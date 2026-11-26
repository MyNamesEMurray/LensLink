import SwiftUI

/// TestFlight-only performance probe (Settings → Help → Performance
/// debug): switches that turn parts of the Live screen off, and a log of
/// main-thread hangs, redraw counts and pipeline events that can be
/// copied into a bug report. English only: it is a tool for testers, not
/// a feature, and it never shows in App Store builds.
final class PerfProbe: ObservableObject, @unchecked Sendable {
    static let shared = PerfProbe()

    static let available: Bool = {
#if DEBUG
        return true
#else
        return Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
#endif
    }()

    /// Each switch: true = that part runs as normal.
    @Published var micMeter = PerfProbe.flag("micMeter") {
        didSet { micMeterOn.value = micMeter; save("micMeter", micMeter) }
    }
    @Published var liveValues = PerfProbe.flag("liveValues") { didSet { save("liveValues", liveValues) } }
    @Published var linkStats = PerfProbe.flag("linkStats") { didSet { save("linkStats", linkStats) } }
    @Published var pictureFrame = PerfProbe.flag("pictureFrame") { didSet { save("pictureFrame", pictureFrame) } }
    @Published var guides = PerfProbe.flag("guides") { didSet { save("guides", guides) } }
    /// The mic switch for the audio thread.
    let micMeterOn = Locked(PerfProbe.flag("micMeter"))

    private static func flag(_ key: String) -> Bool {
        !available || UserDefaults.standard.object(forKey: "perf." + key) as? Bool ?? true
    }

    private func save(_ key: String, _ on: Bool) {
        UserDefaults.standard.set(on, forKey: "perf." + key)
        log("switch \(key) \(on ? "on" : "off")")
    }

    private let lock = NSLock()
    private var lines: [String] = []
    private var redraws: [String: Int] = [:]
    private let started = CACurrentMediaTime()

    func log(_ line: String) {
        guard Self.available else { return }
        let stamp = String(format: "%8.3f", CACurrentMediaTime() - started)
        lock.lock()
        lines.append("\(stamp) [\(Thread.isMainThread ? "main" : "bg")] \(line)")
        if lines.count > 3000 { lines.removeFirst(lines.count - 3000) }
        lock.unlock()
    }

    /// Call from a view's body: counts how often SwiftUI re-evaluates it.
    func redraw(_ view: String) {
        guard Self.available else { return }
        lock.lock()
        redraws[view, default: 0] += 1
        lock.unlock()
    }

    var text: String {
        lock.lock()
        defer { lock.unlock() }
        return lines.joined(separator: "\n")
    }

    func clear() {
        lock.lock()
        lines.removeAll()
        lock.unlock()
    }

    /// Times a block and logs it when it is slow enough to be felt.
    func timed<T>(_ label: String, _ block: () throws -> T) rethrows -> T {
        let start = CACurrentMediaTime()
        defer {
            let ms = (CACurrentMediaTime() - start) * 1000
            log(String(format: "%@ took %.0f ms", label, ms))
        }
        return try block()
    }

    /// Pings the main thread every 100 ms from a background thread and
    /// logs any stretch over 200 ms where it did not answer; logs redraw
    /// counts every 5 s.
    func startWatchdog() {
        guard Self.available, !watching else { return }
        watching = true
        log("probe started: \(Self.device), iOS \(UIDevice.current.systemVersion)")
        let thread = Thread { [weak self] in
            var lastReport = CACurrentMediaTime()
            while let self = self {
                let answered = DispatchSemaphore(value: 0)
                let sent = CACurrentMediaTime()
                DispatchQueue.main.async { answered.signal() }
                if answered.wait(timeout: .now() + 0.2) == .timedOut {
                    self.log("HANG main thread not answering")
                    answered.wait()
                    let ms = (CACurrentMediaTime() - sent) * 1000
                    self.log(String(format: "HANG ended after %.0f ms", ms))
                }
                let now = CACurrentMediaTime()
                if now - lastReport >= 5 {
                    self.lock.lock()
                    let counts = self.redraws.sorted { $0.key < $1.key }
                        .map { "\($0.key) \(Int(Double($0.value) / (now - lastReport)))/s" }
                    self.redraws.removeAll()
                    self.lock.unlock()
                    if !counts.isEmpty { self.log("redraws " + counts.joined(separator: ", ")) }
                    lastReport = now
                }
                Thread.sleep(forTimeInterval: 0.1)
            }
        }
        thread.name = "perf-watchdog"
        thread.qualityOfService = .utility
        thread.start()
    }

    private var watching = false

    private static let device: String = {
        var sys = utsname()
        uname(&sys)
        return withUnsafePointer(to: &sys.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(validatingUTF8: $0) ?? "unknown"
            }
        }
    }()
}

struct PerfProbeView: View {
    @ObservedObject private var probe = PerfProbe.shared
    @State private var snapshot = ""
    @State private var copied = false

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $probe.micMeter) { Text(verbatim: "Mic meter") }
                Toggle(isOn: $probe.liveValues) { Text(verbatim: "Live auto values (4×/s)") }
                Toggle(isOn: $probe.linkStats) { Text(verbatim: "Link stats in top bar") }
                Toggle(isOn: $probe.pictureFrame) { Text(verbatim: "Inset picture frame") }
                Toggle(isOn: $probe.guides) { Text(verbatim: "Guides overlay") }
            } header: {
                Text(verbatim: "Pro interface parts")
            }
            Section {
                Button {
                    UIPasteboard.general.string = PerfProbe.shared.text
                    copied = true
                } label: {
                    Text(verbatim: copied ? "Copied" : "Copy log")
                }
                Button(role: .destructive) {
                    probe.clear()
                    snapshot = ""
                } label: {
                    Text(verbatim: "Clear log")
                }
                Text(verbatim: snapshot.isEmpty ? "(empty)" : snapshot)
                    .font(.system(.caption2, design: .monospaced))
                    .textSelection(.enabled)
            } header: {
                Text(verbatim: "Log (last 3000 lines)")
            }
        }
        .navigationTitle(Text(verbatim: "Performance debug"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            let lines = PerfProbe.shared.text.split(separator: "\n").suffix(200)
            snapshot = lines.joined(separator: "\n")
        }
    }
}
