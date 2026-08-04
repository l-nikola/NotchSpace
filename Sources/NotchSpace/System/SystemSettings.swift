import AppKit

/// Raccourcis vers les panneaux de Réglages Système pertinents pour NotchSpace.
///
/// Sans ce lien, chaque écran d'autorisation refusée ne pouvait que décrire le
/// chemin à suivre à la main — un détail de plus qui sépare l'explication du geste
/// qui la résout.
enum SystemSettings {

    /// Confidentialité et sécurité → Automatisation.
    static func openAutomationPrivacy() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")
    }

    /// Notifications.
    static func openNotifications() {
        open("x-apple.systempreferences:com.apple.preference.notifications")
    }

    private static func open(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }
}
