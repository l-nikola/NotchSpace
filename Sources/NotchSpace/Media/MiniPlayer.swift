import SwiftUI

/// Transport de lecture permanent, en bas du panneau déplié.
///
/// Il vit **hors des onglets**, à la place qu'occupaient les sliders volume et
/// luminosité : ceux-ci doublaient des touches que le clavier porte déjà, alors que
/// passer un morceau demandait de changer d'onglet. C'est le geste qu'on veut faire
/// d'un seul survol.
///
/// L'onglet Lecture garde ce que cette bande d'une ligne ne peut pas montrer :
/// pochette, position dans le morceau, durée.
struct MiniPlayer: View {
    /// Faux sur l'onglet Lecture, qui affiche déjà le morceau en grand : le titre
    /// répété deux fois à quarante points d'écart était le doublon le plus voyant du
    /// panneau. Les boutons, eux, ne bougent pas d'un onglet à l'autre — ils sont
    /// calés à droite, et c'est l'espaceur qui absorbe la différence.
    var showsNowPlaying = true

    @ObservedObject private var media: MediaController
    @ObservedObject private var settings: AppSettings

    init(services: Services, showsNowPlaying: Bool = true) {
        self.media = services.media
        self.settings = services.settings
        self.showsNowPlaying = showsNowPlaying
    }

    var body: some View {
        if !settings.mediaEnabled {
            EmptyView()
        } else if let track = media.nowPlaying {
            HStack(spacing: 10) {
                if showsNowPlaying {
                    EqualizerBars(isAnimating: track.isPlaying, tint: track.source.tint)
                    label(for: track)
                }
                controls(for: track)
            }
        } else if showsNowPlaying {
            idle
        }
    }

    // MARK: Libellé

    /// Titre et artiste sont concaténés en un seul `Text` plutôt que posés dans un
    /// `HStack` : la troncature porte alors sur l'ensemble, au lieu de laisser le
    /// titre chasser l'artiste hors du cadre.
    ///
    /// Le poids se dégrade avec l'opacité, pas seulement elle : un titre et un
    /// artiste au même corps et au même poids ne se distinguaient qu'à la couleur,
    /// le seul endroit de l'app où la hiérarchie reposait sur un seul repère au lieu
    /// de deux qui se renforcent.
    private func label(for track: NowPlaying) -> some View {
        let title = Text(track.title)
            .font(.notchCompactLabel)
            .foregroundStyle(.white.opacity(0.85))
        let subtitle = track.artist.isEmpty ? track.source.displayName : track.artist
        let trailing = Text("  ·  \(subtitle)")
            .font(.notchSecondary)
            .foregroundStyle(.white.opacity(0.4))

        return (title + trailing)
            .lineLimit(1)
            .truncationMode(.tail)
            // Plafonnée : un titre à rallonge repousserait les boutons hors du panneau.
            .frame(maxWidth: 210, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Commandes

    private func controls(for track: NowPlaying) -> some View {
        let playPauseLabel = track.isPlaying ? "Mettre en pause" : "Reprendre"

        return HStack(spacing: 7) {
            CircleButton(symbol: "backward.fill", size: 22) { media.previous() }
                .help("Morceau précédent")
                .accessibilityLabel("Morceau précédent")

            CircleButton(symbol: track.isPlaying ? "pause.fill" : "play.fill",
                         size: 26,
                         prominent: true) { media.playPause() }
                .help(playPauseLabel)
                .accessibilityLabel(playPauseLabel)

            CircleButton(symbol: "forward.fill", size: 22) { media.next() }
                .help("Morceau suivant")
                .accessibilityLabel("Morceau suivant")
        }
    }

    /// Rien ne joue : la bande reste occupée par un libellé éteint plutôt que de
    /// disparaître, sinon la barre d'onglets sauterait à chaque début de lecture.
    private var idle: some View {
        HStack(spacing: 6) {
            Image(systemName: "music.note")
                .font(.notchCaption)
            Text("Rien en lecture")
                .font(.notchSecondary)
        }
        .foregroundStyle(.white.opacity(0.3))
        .frame(height: 26)
    }
}
