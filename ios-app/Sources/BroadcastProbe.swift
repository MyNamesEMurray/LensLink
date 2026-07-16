import Foundation
import Network

/// Diagnostic: checks whether the screen-broadcast extension's listener is
/// reachable on this device, without involving OBS or USB. usbmuxd delivers
/// USB connections to a local port the same way, so a passing probe means
/// the extension side is healthy and any remaining failure is on the
/// OBS/transport side; a failing probe means the listener never opened.
enum BroadcastProbe {
    /// Whether the broadcast extension actually made it into the installed
    /// app. Sideloading tools commonly strip PlugIns when re-signing, and
    /// iOS's broadcast picker can keep showing a stale entry from an older
    /// install — so "it's in the picker" does not mean it's installed.
    static func installedExtensionDescription() -> String {
        guard let plugins = Bundle.main.builtInPlugInsURL,
              let items = try? FileManager.default.contentsOfDirectory(
                  at: plugins, includingPropertiesForKeys: nil)
        else {
            return "✗ No PlugIns folder — the sideloader stripped the extension"
        }
        let appexes = items.filter { $0.pathExtension == "appex" }
        guard !appexes.isEmpty else {
            return "✗ Extension missing from app bundle — re-sideload with app extensions enabled"
        }
        return "✓ Extension installed: "
            + appexes.map { $0.lastPathComponent }.joined(separator: ", ")
    }

    /// Who answered on the port. The app's remote-start standby listener
    /// shares port 9979 with the extension, so "something accepted" isn't
    /// proof the extension is up — the HELLO's `kind` field says which
    /// listener this really is.
    enum Result {
        case screenListener /* the broadcast extension — healthy */
        case appListener    /* the app's own (standby) listener */
        case none           /* nothing listening */
    }

    static func run(completion: @escaping (Result) -> Void) {
        guard let port = NWEndpoint.Port(rawValue: OBSCProtocol.usbPort) else {
            completion(.none)
            return
        }
        let connection = NWConnection(host: "127.0.0.1", port: port, using: .tcp)
        let queue = DispatchQueue(label: "lenslink.probe")
        var finished = false
        var received = Data()
        func finish(_ result: Result) {
            guard !finished else { return }
            finished = true
            connection.cancel()
            DispatchQueue.main.async { completion(result) }
        }
        // Reads until the HELLO packet (header + JSON payload) is complete,
        // then reports which peer sent it.
        func readHello() {
            connection.receive(minimumIncompleteLength: 1,
                               maximumLength: 4096) { content, _, isComplete, error in
                if let content {
                    received.append(content)
                }
                let headerSize = OBSCProtocol.headerSize
                if received.count >= headerSize {
                    let header = [UInt8](received.prefix(headerSize))
                    let payloadSize = header[16..<20].reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
                    guard Array(header[0..<4]) == OBSCProtocol.magic,
                          header[5] == OBSCProtocol.PacketType.hello.rawValue,
                          payloadSize < 4096 else {
                        finish(.none)
                        return
                    }
                    if received.count >= headerSize + Int(payloadSize) {
                        let payload = received.subdata(
                            in: headerSize..<headerSize + Int(payloadSize))
                        let object = try? JSONSerialization.jsonObject(with: payload)
                        let kind = (object as? [String: Any])?["kind"] as? String
                        finish(kind == OBSCProtocol.SourceKind.screen.rawValue
                               ? .screenListener : .appListener)
                        return
                    }
                }
                if isComplete || error != nil {
                    finish(.none)
                    return
                }
                readHello()
            }
        }
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                readHello()
            case .failed, .waiting:
                finish(.none)
            default:
                break
            }
        }
        connection.start(queue: queue)
        queue.asyncAfter(deadline: .now() + 3) { finish(.none) }
    }
}
