import Foundation

/// Diagnostic: whether the screen-broadcast extension is actually present
/// in the installed app, for the Screen mirror section's warning.
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
}
