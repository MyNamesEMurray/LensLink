import Foundation
import CoreMedia
import SwiftUI

#if canImport(ScreenCaptureKit)
@_weakLinked import ScreenCaptureKit
#endif

@MainActor
final class ScreenMirrorController: ObservableObject {
    nonisolated static var isAvailable: Bool {
        #if canImport(ScreenCaptureKit)
        if #available(iOS 27.0, *) {
            return true
        }
        #endif
        return false
    }

    @Published private(set) var isActive = false
    @Published private(set) var obsConnected = false
    @Published private(set) var lastError: String?

    private var session: AnyObject?

    func start() {
        guard !isActive else { return }
        #if canImport(ScreenCaptureKit)
        if #available(iOS 27.0, *) {
            lastError = nil
            obsConnected = false
            isActive = true
            Streamer.shared.setScreenMirrorActive(true)
            let session = ScreenMirrorSession()
            session.onConnectionChange = { [weak self, weak session] connected in
                guard let self, let session, self.session === session else { return }
                self.obsConnected = connected
            }
            session.onEnded = { [weak self, weak session] error in
                guard let self, let session else { return }
                self.sessionEnded(session, error: error)
            }
            self.session = session
            session.begin()
        }
        #endif
    }

    func stop() {
        #if canImport(ScreenCaptureKit)
        if #available(iOS 27.0, *), let session = session as? ScreenMirrorSession {
            session.finish(nil)
        }
        #endif
    }

    private func sessionEnded(_ ended: AnyObject, error: String?) {
        guard ended === session else { return }
        session = nil
        isActive = false
        obsConnected = false
        if let error {
            lastError = error
        }
        Streamer.shared.setScreenMirrorActive(false)
    }
}

#if canImport(ScreenCaptureKit)
@available(iOS 27.0, *)
final class ScreenMirrorSession: NSObject, SCContentSharingPickerObserver,
                                 SCStreamDelegate, SCStreamOutput, @unchecked Sendable {
    var onConnectionChange: (@MainActor (Bool) -> Void)?
    var onEnded: (@MainActor (String?) -> Void)?

    private let sampleQueue = DispatchQueue(
        label: "com.exaltedpixels.LensLinkCamera.screen.samples", qos: .userInitiated)
    private let lock = NSLock()
    private var stream: SCStream?
    private var pipeline: ScreenStreamPipeline?
    private var ended = false

    @MainActor
    func begin() {
        let picker = SCContentSharingPicker.shared
        var configuration = SCContentSharingPickerConfiguration()
        configuration.showsMicrophoneControl = false
        configuration.showsCameraControl = false
        picker.defaultConfiguration = configuration
        picker.add(self)
        picker.isActive = true
        picker.present()
    }

    func finish(_ error: String?) {
        lock.lock()
        guard !ended else {
            lock.unlock()
            return
        }
        ended = true
        let stream = self.stream
        let pipeline = self.pipeline
        self.stream = nil
        self.pipeline = nil
        lock.unlock()

        if let stream {
            stream.stopCapture { [self] _ in
                try? stream.removeStreamOutput(self, type: .screen)
                try? stream.removeStreamOutput(self, type: .audio)
            }
        }
        if let pipeline {
            sampleQueue.async {
                pipeline.stop()
            }
        }
        Task { @MainActor [self] in
            let picker = SCContentSharingPicker.shared
            picker.remove(self)
            picker.isActive = false
            self.onEnded?(error)
        }
    }

    private var isEnded: Bool {
        lock.lock()
        defer { lock.unlock() }
        return ended
    }

    private var currentPipeline: ScreenStreamPipeline? {
        lock.lock()
        defer { lock.unlock() }
        return pipeline
    }

    @MainActor
    private func startCapture(with filter: SCContentFilter) {
        lock.lock()
        let alreadyStarted = ended || stream != nil
        lock.unlock()
        guard !alreadyStarted else { return }

        let configuration = SCStreamConfiguration()
        let scale = CGFloat(filter.pointPixelScale)
        let width = Int((filter.contentRect.width * scale).rounded()) & ~1
        let height = Int((filter.contentRect.height * scale).rounded()) & ~1
        if width > 0 && height > 0 {
            configuration.width = width
            configuration.height = height
        }
        configuration.capturesAudio = true
        configuration.excludesCurrentProcessAudio = true
        configuration.sampleRate = OBSCProtocol.screenAudioSampleRate
        configuration.channelCount = OBSCProtocol.screenAudioChannels

        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        do {
            try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: sampleQueue)
            try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: sampleQueue)
        } catch {
            finish(error.localizedDescription)
            return
        }

        let pipeline = ScreenStreamPipeline(logSubsystem: "com.exaltedpixels.LensLinkCamera.screen")
        pipeline.onFatalError = { [weak self] message in
            self?.finish(message)
        }
        pipeline.onConnectionChange = { [weak self] connected in
            Task { @MainActor [weak self] in
                guard let self, !self.isEnded else { return }
                self.onConnectionChange?(connected)
            }
        }

        lock.lock()
        let cancelled = ended
        if !cancelled {
            self.stream = stream
            self.pipeline = pipeline
        }
        lock.unlock()
        guard !cancelled else { return }

        pipeline.start()
        stream.startCapture { [weak self] error in
            if let error {
                self?.finish(Self.failureMessage(error))
            }
        }
    }

    private static func failureMessage(_ error: any Error) -> String? {
        let code = (error as? SCStreamError)?.code
        if code == .userStopped || code == .userDeclined {
            return nil
        }
        return error.localizedDescription
    }

    private static func isComplete(_ sampleBuffer: CMSampleBuffer) -> Bool {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(
                  sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let rawStatus = attachments.first?[SCStreamFrameInfo.status] as? Int
        else { return true }
        return SCFrameStatus(rawValue: rawStatus) == .complete
    }

    // MARK: - SCContentSharingPickerObserver

    func contentSharingPicker(_ picker: SCContentSharingPicker,
                              didUpdateWith filter: SCContentFilter,
                              for stream: SCStream?) {
        Task { @MainActor [weak self] in
            self?.startCapture(with: filter)
        }
    }

    func contentSharingPicker(_ picker: SCContentSharingPicker,
                              didCancelFor stream: SCStream?) {
        lock.lock()
        let capturing = self.stream != nil
        lock.unlock()
        if !capturing {
            finish(nil)
        }
    }

    func contentSharingPickerStartDidFailWithError(_ error: any Error) {
        finish(error.localizedDescription)
    }

    // MARK: - SCStreamDelegate

    func stream(_ stream: SCStream, didStopWithError error: any Error) {
        finish(Self.failureMessage(error))
    }

    // MARK: - SCStreamOutput

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                of type: SCStreamOutputType) {
        guard let pipeline = currentPipeline else { return }
        switch type {
        case .screen:
            guard CMSampleBufferGetImageBuffer(sampleBuffer) != nil,
                  Self.isComplete(sampleBuffer) else { return }
            pipeline.handleVideo(sampleBuffer)
        case .audio:
            pipeline.handleAudio(sampleBuffer)
        default:
            break
        }
    }
}
#endif
