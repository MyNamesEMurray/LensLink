import Foundation
import AVFoundation
import Metal
import Vision

/// Virtual green screen: keeps the person (Vision segmentation, optionally
/// gated by a depth-based max-subject-distance cutoff) and paints
/// everything else chroma green in one Metal compute pass, so the wire
/// carries ordinary video and OBS chroma-keys it exactly like a physical
/// green screen.
///
/// App target ONLY — deliberately absent from `LensLinkBroadcast.sources`
/// (ios-app/project.yml is an explicit list), so the broadcast extension
/// never links Vision or Metal.
///
/// THREADING: `composite(sampleBuffer:)`, `updateDepth(_:)` and
/// `maxDistance` are all called from CameraManager's capture queue
/// ("obscam.video") only — no locking needed. Segmentation runs
/// synchronously on that queue by design: when a frame takes too long the
/// capture output sheds the next one (alwaysDiscardsLateVideoFrames)
/// instead of building a queue — docs/PERFORMANCE.md's drop-don't-queue
/// rule.
final class FrameCompositor {

    /// Person segmentation exists on every OS this app runs on
    /// (VNGeneratePersonSegmentationRequest is iOS 15.0+, the deployment
    /// floor). Kept as an explicit gate for symmetry with
    /// `hdrAvailable` / `appleLogCaptureAvailable`, so a future
    /// capability split or floor change has one place to land.
    static var supportsSegmentation: Bool { true }

    /// Max subject distance in meters: anything farther is treated as
    /// background even where the person mask disagrees (iOS 15's
    /// segmentation is ONE mask covering all people, so this is the only
    /// tool against a passer-by behind the subject). 0 disables the
    /// cutoff. Capture queue only.
    var maxDistance: Float = 0

    // MARK: - Members (all capture-queue confined after init)

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipeline: MTLComputePipelineState
    private let textureCache: CVMetalTextureCache
    /// Metal validation requires every declared texture argument bound
    /// even when the kernel's runtime branch never samples it; this 1×1
    /// NaN texel stands in when no depth map exists (NaN reads as "no
    /// depth opinion" → gate 1 in the kernel, so even a stray sample is
    /// harmless).
    private let dummyDepthTexture: MTLTexture

    /// ONE stateful request for the stream's life: Vision smooths
    /// temporal changes between frames only when the same request
    /// instance sees the sequence in order (it is a VNStatefulRequest).
    private let request: VNGeneratePersonSegmentationRequest
    private let sequenceHandler = VNSequenceRequestHandler()

    /// App-owned output pool — the capture buffer must never be written
    /// in place (the hardware encoder still reads the previous frame
    /// asynchronously), so the composite pass IS the one copy.
    private var pool: CVPixelBufferPool?
    private var poolWidth = 0
    private var poolHeight = 0
    /// Buffers from one pool share a format description; recreated only
    /// when CMVideoFormatDescriptionMatchesImageBuffer says otherwise.
    private var cachedFormatDescription: CMVideoFormatDescription?

    /// Depth runs slower than video (~15 Hz vs 30/60), so the newest map
    /// is kept and reused until the next one lands.
    private var latestDepthPixelBuffer: CVPixelBuffer?

    private var loggedStages = Set<String>()
    private var loggedMaskDims = false

    // MARK: - Init

    /// - Parameter targetFps: the stream's configured frame rate. It
    ///   picks the segmentation model once — the request is stateful and
    ///   lives for the whole stream: `.fast` is Apple's "streaming"
    ///   model (the only safe choice above 30 fps), `.balanced` the
    ///   30 fps video model (WWDC21 session 10040).
    /// - Returns: nil when Metal is unavailable or the kernel fails to
    ///   compile — the caller then streams uncomposited frames.
    /// The Metal objects are process-wide constants (the shader source
    /// never varies — only the Vision request depends on init
    /// parameters), so they compile ONCE per process: a fresh compositor
    /// is created on every (re)configure while armed, and recompiling
    /// tens of milliseconds of MSL on the main thread per lens switch
    /// was a per-reconfigure UI hitch for nothing.
    private struct SharedMetal {
        let device: MTLDevice
        let queue: MTLCommandQueue
        let pipeline: MTLComputePipelineState
    }

    private static let sharedMetal: SharedMetal? = {
        guard let metalDevice = MTLCreateSystemDefaultDevice(),
              let queue = metalDevice.makeCommandQueue() else {
            print("FrameCompositor: Metal unavailable — green screen disabled")
            return nil
        }
        // The kernel ships as Swift-embedded MSL compiled here once per
        // process via makeLibrary(source:) — keeping the shader next to
        // the code that dispatches it and avoiding .metal/metallib build
        // plumbing in project.yml.
        guard let library = try? metalDevice.makeLibrary(
                source: shaderSource, options: nil),
              let function = library.makeFunction(name: "greenScreenComposite"),
              let pipeline = try? metalDevice.makeComputePipelineState(
                function: function) else {
            print("FrameCompositor: shader compile failed — green screen disabled")
            return nil
        }
        return SharedMetal(device: metalDevice, queue: queue,
                           pipeline: pipeline)
    }()

    init?(targetFps: Int32) {
        guard let shared = Self.sharedMetal else { return nil }
        let metalDevice = shared.device
        let queue = shared.queue
        let pipeline = shared.pipeline
        var cache: CVMetalTextureCache?
        CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, metalDevice,
                                  nil, &cache)
        guard let cache else {
            print("FrameCompositor: texture cache creation failed — green screen disabled")
            return nil
        }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r16Float, width: 1, height: 1, mipmapped: false)
        descriptor.usage = .shaderRead
        guard let dummy = metalDevice.makeTexture(descriptor: descriptor) else {
            print("FrameCompositor: dummy texture creation failed — green screen disabled")
            return nil
        }
        var nan: UInt16 = 0x7E00 // IEEE 754 half-precision NaN
        dummy.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0,
                      withBytes: &nan,
                      bytesPerRow: MemoryLayout<UInt16>.size)

        let request = VNGeneratePersonSegmentationRequest()
        request.qualityLevel = targetFps > 30 ? .fast : .balanced
        // OneComponent8 maps straight onto an r8Unorm texture.
        request.outputPixelFormat = kCVPixelFormatType_OneComponent8

        self.device = metalDevice
        self.commandQueue = queue
        self.pipeline = pipeline
        self.textureCache = cache
        self.dummyDepthTexture = dummy
        self.request = request
    }

    // MARK: - Depth

    /// Store the newest depth frame (capture queue only). Converts to
    /// DepthFloat16 defensively — CameraManager pins that format, so the
    /// conversion is normally a no-op — because the kernel samples the
    /// map as r16Float meters.
    func updateDepth(_ depth: AVDepthData) {
        let wanted = kCVPixelFormatType_DepthFloat16
        let data = depth.depthDataType == wanted
            ? depth : depth.converting(toDepthDataType: wanted)
        latestDepthPixelBuffer = data.depthDataMap
    }

    // MARK: - Composite

    /// Capture queue only. Returns:
    ///  - a NEW sample buffer with the person kept and everything else
    ///    painted chroma green (source pts/duration/attachments carried
    ///    over verbatim, so timesync/lip-sync never notice), or
    ///  - the ORIGINAL buffer when any stage fails — fail-open: a Vision
    ///    or Metal hiccup must never blank the stream, or
    ///  - nil when the output pool is exhausted (every in-flight buffer
    ///    is still referenced downstream): the caller drops the frame,
    ///    per the repo-wide drop-don't-queue rule.
    func composite(sampleBuffer: CMSampleBuffer) -> CMSampleBuffer? {
        guard let source = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return sampleBuffer
        }
        // Green screen is SDR-only; the composite green constants are
        // BT.709 video-range and the kernel reads 8-bit biplanar 420v.
        guard CVPixelBufferGetPixelFormatType(source)
                == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange else {
            logOnce("pixel-format",
                    "FrameCompositor: non-420v input — green screen is SDR-only; passing frames through")
            return sampleBuffer
        }

        // 1. Person mask. Synchronous on the capture queue: overload
        // sheds the NEXT frame via alwaysDiscardsLateVideoFrames rather
        // than queueing work. Buffers are upright sensor-native
        // landscape (the connection sets .landscapeRight and mirrors the
        // front camera), so .up keeps the mask in buffer coordinates.
        do {
            try sequenceHandler.perform([request], on: source,
                                        orientation: .up)
        } catch {
            logOnce("vision",
                    "FrameCompositor: segmentation failed (\(error.localizedDescription)) — passing frames through")
            return sampleBuffer
        }
        guard let maskBuffer = request.results?.first?.pixelBuffer else {
            logOnce("vision-results",
                    "FrameCompositor: segmentation returned no mask — passing frames through")
            return sampleBuffer
        }

        let width = CVPixelBufferGetWidth(source)
        let height = CVPixelBufferGetHeight(source)
        if !loggedMaskDims {
            loggedMaskDims = true
            // Mask resolution per quality level is undocumented — log the
            // observed value once (it feeds the feather-quality picture).
            print("FrameCompositor: mask "
                  + "\(CVPixelBufferGetWidth(maskBuffer))x\(CVPixelBufferGetHeight(maskBuffer))"
                  + " for \(width)x\(height) input")
        }

        // 2. Output buffer from our pool (rebuilt on dimension change).
        if pool == nil || width != poolWidth || height != poolHeight {
            rebuildPool(width: width, height: height)
        }
        guard let pool else { return sampleBuffer } // rebuild already logged
        var allocated: CVPixelBuffer?
        let aux = [kCVPixelBufferPoolAllocationThresholdKey as String: 6]
        let poolStatus = CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(
            kCFAllocatorDefault, pool, aux as CFDictionary, &allocated)
        if poolStatus == kCVReturnWouldExceedAllocationThreshold {
            // All in-flight buffers still referenced downstream — the
            // GPU/encoder is behind. Drop, don't queue.
            return nil
        }
        guard poolStatus == kCVReturnSuccess, let output = allocated else {
            logOnce("pool-alloc",
                    "FrameCompositor: pool allocation failed (\(poolStatus)) — passing frames through")
            return sampleBuffer
        }

        // 3. GPU composite.
        guard runKernel(source: source, mask: maskBuffer, output: output) else {
            logOnce("metal",
                    "FrameCompositor: Metal composite failed — passing frames through")
            return sampleBuffer
        }

        // 4. Wrap for the encoder. Attachments (colour primaries /
        // transfer / matrix — the BT.709 tags) must travel with the new
        // buffer or colours shift on the wire.
        CVBufferPropagateAttachments(source, output)
        if let cached = cachedFormatDescription,
           !CMVideoFormatDescriptionMatchesImageBuffer(cached,
                                                       imageBuffer: output) {
            cachedFormatDescription = nil
        }
        if cachedFormatDescription == nil {
            var created: CMVideoFormatDescription?
            CMVideoFormatDescriptionCreateForImageBuffer(
                allocator: kCFAllocatorDefault, imageBuffer: output,
                formatDescriptionOut: &created)
            cachedFormatDescription = created
        }
        guard let formatDescription = cachedFormatDescription else {
            logOnce("format-description",
                    "FrameCompositor: format description creation failed — passing frames through")
            return sampleBuffer
        }
        // Source timing verbatim: pts drives the wire timestamps.
        var timing = CMSampleTimingInfo(
            duration: CMSampleBufferGetDuration(sampleBuffer),
            presentationTimeStamp:
                CMSampleBufferGetPresentationTimeStamp(sampleBuffer),
            decodeTimeStamp: .invalid)
        var wrapped: CMSampleBuffer?
        let status = CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: output,
            formatDescription: formatDescription,
            sampleTiming: &timing,
            sampleBufferOut: &wrapped)
        guard status == noErr, let wrapped else {
            logOnce("sample-buffer",
                    "FrameCompositor: sample buffer wrap failed (\(status)) — passing frames through")
            return sampleBuffer
        }
        return wrapped
    }

    // MARK: - Metal pass

    private func runKernel(source: CVPixelBuffer, mask: CVPixelBuffer,
                           output: CVPixelBuffer) -> Bool {
        // The CVMetalTextures must outlive the GPU pass (releasing one
        // recycles its backing); collected here and held past the wait.
        var retained: [CVMetalTexture] = []
        guard let srcY = makeTexture(from: source, pixelFormat: .r8Unorm,
                                     planeIndex: 0, retaining: &retained),
              let srcCbCr = makeTexture(from: source, pixelFormat: .rg8Unorm,
                                        planeIndex: 1, retaining: &retained),
              let maskTexture = makeTexture(from: mask, pixelFormat: .r8Unorm,
                                            planeIndex: 0, retaining: &retained),
              let outY = makeTexture(from: output, pixelFormat: .r8Unorm,
                                     planeIndex: 0, retaining: &retained),
              let outCbCr = makeTexture(from: output, pixelFormat: .rg8Unorm,
                                        planeIndex: 1, retaining: &retained)
        else { return false }

        // Depth is optional per frame: no map yet, no cutoff configured,
        // or a failed wrap all degrade to segmentation-only (gate = 1).
        var depthTexture = dummyDepthTexture
        var hasDepth: Float = 0
        if maxDistance > 0, let depthBuffer = latestDepthPixelBuffer {
            if let wrappedDepth = makeTexture(from: depthBuffer,
                                              pixelFormat: .r16Float,
                                              planeIndex: 0,
                                              retaining: &retained) {
                depthTexture = wrappedDepth
                hasDepth = 1
            } else {
                logOnce("depth-wrap",
                        "FrameCompositor: depth texture wrap failed — segmentation-only")
            }
        }

        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else {
            return false
        }
        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(srcY, index: 0)
        encoder.setTexture(srcCbCr, index: 1)
        encoder.setTexture(maskTexture, index: 2)
        encoder.setTexture(depthTexture, index: 3)
        encoder.setTexture(outY, index: 4)
        encoder.setTexture(outCbCr, index: 5)
        var params = SIMD2<Float>(maxDistance, hasDepth)
        encoder.setBytes(&params, length: MemoryLayout<SIMD2<Float>>.size,
                         index: 0)

        // One thread per 2×2 luma quad. Plain dispatchThreadgroups with
        // an in-kernel bounds check — non-uniform threadgroups need
        // A11+, and iOS 15 still runs on A9/A10.
        let chromaWidth = CVPixelBufferGetWidthOfPlane(output, 1)
        let chromaHeight = CVPixelBufferGetHeightOfPlane(output, 1)
        let threadsPerGroup = MTLSize(width: 16, height: 16, depth: 1)
        let groups = MTLSize(width: (chromaWidth + 15) / 16,
                             height: (chromaHeight + 15) / 16,
                             depth: 1)
        encoder.dispatchThreadgroups(groups,
                                     threadsPerThreadgroup: threadsPerGroup)
        encoder.endEncoding()
        commandBuffer.commit()
        // Blocking (~0.5 ms) is the simplest correct ordering before the
        // encoder reads the buffer; overload sheds upstream via
        // alwaysDiscardsLateVideoFrames. An MTLSharedEvent pipeline is a
        // later optimization only if measurements demand it.
        commandBuffer.waitUntilCompleted()
        withExtendedLifetime(retained) {}
        return commandBuffer.error == nil
    }

    private func makeTexture(from buffer: CVPixelBuffer,
                             pixelFormat: MTLPixelFormat,
                             planeIndex: Int,
                             retaining retained: inout [CVMetalTexture])
        -> MTLTexture? {
        let planar = CVPixelBufferIsPlanar(buffer)
        let width = planar
            ? CVPixelBufferGetWidthOfPlane(buffer, planeIndex)
            : CVPixelBufferGetWidth(buffer)
        let height = planar
            ? CVPixelBufferGetHeightOfPlane(buffer, planeIndex)
            : CVPixelBufferGetHeight(buffer)
        var cvTexture: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault, textureCache, buffer, nil, pixelFormat,
            width, height, planeIndex, &cvTexture)
        guard status == kCVReturnSuccess, let cvTexture,
              let texture = CVMetalTextureGetTexture(cvTexture) else {
            return nil
        }
        retained.append(cvTexture)
        return texture
    }

    // MARK: - Pool

    private func rebuildPool(width: Int, height: Int) {
        let attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String:
                kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            // IOSurface backing keeps the VideoToolbox handoff zero-copy
            // and lets the texture cache wrap the planes for writing.
            kCVPixelBufferIOSurfacePropertiesKey as String: [:],
            kCVPixelBufferMetalCompatibilityKey as String: true,
        ]
        var created: CVPixelBufferPool?
        let status = CVPixelBufferPoolCreate(kCFAllocatorDefault, nil,
                                             attributes as CFDictionary,
                                             &created)
        pool = status == kCVReturnSuccess ? created : nil
        poolWidth = width
        poolHeight = height
        cachedFormatDescription = nil
        if pool == nil {
            logOnce("pool-create",
                    "FrameCompositor: pool creation failed (\(status)) — passing frames through")
        }
    }

    // MARK: - Logging

    /// Capture queue only. Each distinct failure stage logs once — a
    /// per-frame print at 60 fps would itself be a performance bug.
    private func logOnce(_ stage: String, _ message: String) {
        guard loggedStages.insert(stage).inserted else { return }
        print(message)
    }

    // MARK: - Kernel source

    private static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    // Chroma green, BT.709 limited (video) range — THE single tunable
    // set of green constants for the whole feature.
    // sRGB #00B140 (0, 177, 64) is the industry chroma-key green; it
    // survives 4:2:0 subsampling + H.264/HEVC quantization better than
    // primary green (0, 255, 0). Derivation with BT.709 coefficients
    // (Kr = 0.2126, Kg = 0.7152, Kb = 0.0722):
    //   Y' = 0.5146, Cb' = -0.1420, Cr' = -0.3267
    //   Y  = 16 + 219 * Y'  = 129
    //   Cb = 128 + 224 * Cb' = 96
    //   Cr = 128 + 224 * Cr' = 55
    // Normalized for r8Unorm / rg8Unorm writes:
    constant float GREEN_Y  = 129.0 / 255.0;
    constant float GREEN_CB =  96.0 / 255.0;
    constant float GREEN_CR =  55.0 / 255.0;

    // Depth gate feather, meters: alpha ramps 1 -> 0 over
    // [maxDistance - FEATHER, maxDistance].
    constant float DEPTH_FEATHER_M = 0.15;

    struct Params {
        float maxDistance; // meters; <= 0 disables the depth cutoff
        float hasDepth;    // > 0.5 when the depth texture is real
    };

    // One thread per 2x2 luma quad (grid = chroma-plane dimensions).
    kernel void greenScreenComposite(
        texture2d<float, access::read>   srcY    [[texture(0)]],
        texture2d<float, access::read>   srcCbCr [[texture(1)]],
        texture2d<float, access::sample> mask    [[texture(2)]],
        texture2d<float, access::sample> depth   [[texture(3)]],
        texture2d<float, access::write>  outY    [[texture(4)]],
        texture2d<float, access::write>  outCbCr [[texture(5)]],
        constant Params &params [[buffer(0)]],
        uint2 gid [[thread_position_in_grid]])
    {
        const uint chromaW = outCbCr.get_width();
        const uint chromaH = outCbCr.get_height();
        if (gid.x >= chromaW || gid.y >= chromaH)
            return;

        constexpr sampler bilinear(coord::normalized,
                                   address::clamp_to_edge,
                                   filter::linear);

        const uint lumaW = outY.get_width();
        const uint lumaH = outY.get_height();
        const float2 lumaSize = float2(lumaW, lumaH);

        float alphaSum = 0.0;
        for (uint i = 0; i < 4; ++i) {
            const uint2 px = uint2(min(2 * gid.x + (i & 1u), lumaW - 1),
                                   min(2 * gid.y + (i >> 1), lumaH - 1));
            // The mask is far smaller than the frame (~256 wide): this
            // bilinear upsample IS the edge feather.
            const float2 uv = (float2(px) + 0.5) / lumaSize;
            float alpha = mask.sample(bilinear, uv).r;

            // Depth gate: 1 inside the cutoff, ramping to 0 at it.
            // NaN (depth holes / no reading) must NEVER classify as
            // background — every comparison against NaN is false, so
            // test isnan() FIRST and fall through to "no depth
            // opinion" (gate stays 1).
            if (params.hasDepth > 0.5 && params.maxDistance > 0.0) {
                const float d = depth.sample(bilinear, uv).r;
                if (!isnan(d)) {
                    alpha *= 1.0 - smoothstep(
                        params.maxDistance - DEPTH_FEATHER_M,
                        params.maxDistance, d);
                }
            }

            const float y = srcY.read(px).r;
            outY.write(float4(mix(GREEN_Y, y, alpha)), px);
            alphaSum += alpha;
        }

        const float alphaMean = alphaSum * 0.25;
        const float2 cbcr = srcCbCr.read(gid).rg;
        const float2 outC = mix(float2(GREEN_CB, GREEN_CR), cbcr, alphaMean);
        outCbCr.write(float4(outC, 0.0, 0.0), gid);
    }
    """
}
