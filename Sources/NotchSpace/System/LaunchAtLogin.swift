import Foundation
import ServiceManagement

/// Lancement automatique à l'ouverture de session.
///
/// `SMAppService` est la voie officielle depuis macOS 13 : l'app apparaît dans
/// Réglages Système → Général → Ouverture, et l'utilisateur peut la désactiver de là.
/// Elle exige toutefois une app signée et à un emplacement stable ; en développement,
/// avec une signature ad hoc et un bundle dans le dossier du projet, elle échoue
/// régulièrement. D'où le repli sur un `LaunchAgent`, qui n'a aucune de ces exigences.
enum LaunchAtLogin {

    private static let agentLabel = "app.notchspace.NotchSpace"

    private static var agentURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(agentLabel).plist")
    }

    /// Chemin du bundle courant, quel que soit l'endroit d'où l'exécutable tourne.
    private static var appBundleURL: URL? {
        let executable = Bundle.main.bundleURL
        return executable.pathExtension == "app" ? executable : nil
    }

    static var isEnabled: Bool {
        if SMAppService.mainApp.status == .enabled { return true }
        return FileManager.default.fileExists(atPath: agentURL.path)
    }

    /// Renvoie un message d'erreur lisible, ou `nil` si tout s'est bien passé.
    @discardableResult
    static func set(_ enabled: Bool) -> String? {
        enabled ? enable() : disable()
    }

    private static func enable() -> String? {
        do {
            try SMAppService.mainApp.register()
            removeAgent()
            return nil
        } catch {
            // Repli : un LaunchAgent classique, qui se moque de l'emplacement et de
            // l'identité de signature.
            return writeAgent()
        }
    }

    private static func disable() -> String? {
        try? SMAppService.mainApp.unregister()
        removeAgent()
        return nil
    }

    private static func writeAgent() -> String? {
        guard let bundle = appBundleURL else {
            return "Le lancement automatique exige que NotchSpace soit lancé depuis son bundle .app."
        }
        let executable = bundle.appendingPathComponent("Contents/MacOS/NotchSpace").path

        let plist: [String: Any] = [
            "Label": agentLabel,
            "ProgramArguments": [executable],
            "RunAtLoad": true,
            // Pas de `KeepAlive` : l'utilisateur doit pouvoir quitter l'app sans
            // qu'elle ressuscite aussitôt.
            "ProcessType": "Interactive",
        ]

        do {
            try FileManager.default.createDirectory(at: agentURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            let data = try PropertyListSerialization.data(fromPropertyList: plist,
                                                          format: .xml,
                                                          options: 0)
            try data.write(to: agentURL, options: .atomic)
            return nil
        } catch {
            return "Impossible d'écrire l'agent de démarrage : \(error.localizedDescription)"
        }
    }

    private static func removeAgent() {
        try? FileManager.default.removeItem(at: agentURL)
    }
}
