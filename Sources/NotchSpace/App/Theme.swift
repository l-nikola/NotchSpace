import AppKit
import SwiftUI

/// Rôles de couleur transverses à l'app.
///
/// Le reste de l'interface reste en niveaux de gris à dessein — voir le README sur
/// le parti pris du silence. NotchSpace ne colore que ce qui signale un état ou une
/// identité reconnaissable d'un coup d'œil : la phase du minuteur
/// (`PomodoroPhase.accent`), la source qui joue (`NowPlaying.Source.tint`), et
/// l'avertissement ci-dessous. Tout le reste continue de se fondre dans le noir de
/// la coquille.
enum NotchColor {
    /// Autorisation refusée, réglage en échec : jamais utilisé pour un état normal,
    /// pour qu'il ne se confonde jamais avec le corail de la phase de travail.
    static let warning = Color.orange
}

/// Réglage d'accessibilité système, relu à chaque appel plutôt que mis en cache :
/// un changement en cours de session doit se répercuter tout de suite, sans
/// redémarrage.
enum NotchMotion {
    static var isReduced: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
}

extension Animation {
    /// `nil` quand « Réduire le mouvement » est actif dans Réglages Système →
    /// Accessibilité → Écran : la mutation s'applique alors sans transition, comme
    /// n'importe quel réglage système qui doit primer sur le parti pris de l'app.
    static func reduced(_ animation: Animation) -> Animation? {
        NotchMotion.isReduced ? nil : animation
    }
}

/// Rôles typographiques partagés entre plusieurs vues.
///
/// Nommés par ce qu'ils portent, pas par leur taille : les combinaisons qui
/// n'apparaissent qu'à un seul endroit (le compte à rebours, le nom de la phase, une
/// puce de preset…) restent des littéraux locaux à leur vue — leur donner un nom ici
/// n'empêcherait aucune dérive puisqu'elles ne peuvent diverger que d'elles-mêmes.
extension Font {
    /// Métadonnée la plus fine de l'app : horodatage, icône de source, nom de
    /// fichier dans l'étagère.
    static let notchMicro = Font.system(size: 9)
    /// Texte secondaire accompagnant un titre — artiste sous un morceau, état neutre
    /// d'un mini-lecteur au repos.
    static let notchSecondary = Font.system(size: 11)
    /// Libellé compact mais appuyé : onglet du pied de panneau, titre du mini-lecteur.
    static let notchCompactLabel = Font.system(size: 11, weight: .medium)
    /// Texte utilitaire discret : légende de compteur, corps d'une alerte.
    static let notchCaption = Font.system(size: 10)
    /// En-tête d'un état d'alerte (permission refusée, Chrome bloqué…).
    static let notchAlertHeadline = Font.system(size: 12, weight: .medium)
    /// Icône d'un état d'alerte.
    static let notchAlertIcon = Font.system(size: 14)
}
