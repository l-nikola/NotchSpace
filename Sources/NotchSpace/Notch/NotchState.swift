import SwiftUI

/// Onglets du panneau déplié.
enum NotchTab: String, CaseIterable, Identifiable {
    case focus
    case media
    case shelf

    var id: String { rawValue }

    var title: String {
        switch self {
        case .focus: return "Focus"
        case .media: return "Lecture"
        case .shelf: return "Étagère"
        }
    }

    var symbol: String {
        switch self {
        case .focus: return "timer"
        case .media: return "music.note"
        case .shelf: return "tray.full"
        }
    }
}

/// État d'affichage de l'encoche, partagé avec les vues SwiftUI.
final class NotchState: ObservableObject {
    @Published var isExpanded = false
    @Published var metrics: NotchMetrics?
    @Published var tab: NotchTab = .focus

    /// Vrai pendant qu'un glisser-déposer survole l'encoche.
    @Published var isDropTarget = false

    /// Quelque chose mérite d'être montré au repos : minuteur en cours, lecture en
    /// cours, fichiers en attente. Sinon la coquille se fait oublier.
    @Published var hasActivity = false

    /// Débord de chaque côté de l'encoche à l'état actif. Élargi quand une pochette
    /// d'album doit tenir à côté de l'encoche.
    @Published var activeSideInset: CGFloat = NotchMetrics.horizontalExpand

    var presentation: NotchPresentation {
        if isExpanded { return .expanded }
        return hasActivity ? .active : .resting
    }

    /// Taille de la coquille pour l'état courant, ou `.zero` tant que la géométrie
    /// n'est pas connue.
    var shellSize: CGSize {
        metrics?.shellSize(for: presentation, activeSideInset: activeSideInset) ?? .zero
    }

    func windowFrame(for presentation: NotchPresentation) -> CGRect? {
        metrics?.windowFrame(for: presentation, activeSideInset: activeSideInset)
    }

    /// Au repos sur un écran sans encoche, il n'y a pas de trou noir dans lequel se
    /// fondre : on masque complètement la coquille plutôt que d'afficher un rectangle.
    var isShellHidden: Bool {
        presentation == .resting && !(metrics?.hasRealNotch ?? true)
    }
}
