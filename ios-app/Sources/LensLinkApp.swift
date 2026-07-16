import SwiftUI

@main
struct LensLinkApp: App {
    @StateObject private var streamer = Streamer.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(streamer)
                // lenslink://start and lenslink://stop, for Shortcuts
                // automations on iOS 15 (16+ also gets App Intents).
                .onOpenURL { url in
                    handle(url)
                }
        }
        .onChange(of: scenePhase) { phase in
            switch phase {
            case .active:
                // Foreground: enter remote-start standby (if enabled) so
                // OBS can start the camera without the phone being touched.
                streamer.sceneDidActivate()
            case .background:
                // The camera can't capture in the background; stop cleanly
                // so OBS shows a blank source instead of a frozen frame.
                streamer.sceneDidEnterBackground()
            default:
                break
            }
        }
    }

    private func handle(_ url: URL) {
        guard url.scheme?.lowercased() == "lenslink" else { return }
        switch url.host?.lowercased() {
        case "start":
            Task { await streamer.start() }
        case "stop":
            streamer.stop()
        default:
            break
        }
    }
}
