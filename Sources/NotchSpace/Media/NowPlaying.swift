import Foundation
import SwiftUI

/// Ce qui joue actuellement, quelle que soit la source.
struct NowPlaying: Equatable {

    enum Source: String, Equatable {
        case spotify
        case chrome

        var displayName: String {
            switch self {
            case .spotify: return "Spotify"
            case .chrome: return "YouTube"
            }
        }

        var symbol: String {
            switch self {
            case .spotify: return "music.note"
            case .chrome: return "play.rectangle"
            }
        }

        /// Couleur de marque, réservée à l'icône de source et à l'égaliseur — jamais
        /// au texte ni au fond : elle signale qui joue, sans prendre la place que le
        /// reste du panneau garde en niveaux de gris.
        var tint: Color {
            switch self {
            case .spotify: return Color(red: 0.11, green: 0.73, blue: 0.33)
            case .chrome: return Color(red: 1.0, green: 0.13, blue: 0.13)
            }
        }
    }

    var source: Source
    /// Identifiant stable de la piste, pour ne retélécharger la pochette qu'au changement.
    var trackID: String
    var title: String
    var artist: String
    var album: String = ""
    var isPlaying: Bool
    var duration: TimeInterval
    /// Position à l'instant `capturedAt`.
    var position: TimeInterval
    var capturedAt: Date
    var artworkURL: URL?

    /// Position extrapolée jusqu'à maintenant.
    ///
    /// Évite d'interroger la source chaque seconde juste pour faire avancer une barre :
    /// tant que la lecture continue, le temps passe au même rythme ici.
    func currentPosition(now: Date = Date()) -> TimeInterval {
        guard isPlaying else { return position }
        return min(duration, position + now.timeIntervalSince(capturedAt))
    }

    var progress: Double {
        guard duration > 0 else { return 0 }
        return min(max(currentPosition() / duration, 0), 1)
    }

    /// Ce qui doit déclencher un rafraîchissement de l'affichage, en ignorant la
    /// position qui, elle, avance toute seule.
    func isSameContent(as other: NowPlaying?) -> Bool {
        guard let other else { return false }
        return source == other.source
            && trackID == other.trackID
            && isPlaying == other.isPlaying
            && title == other.title
            && artworkURL == other.artworkURL
    }
}

extension TimeInterval {
    /// `3:07`
    var mmss: String {
        guard isFinite, self >= 0 else { return "0:00" }
        let total = Int(self)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
