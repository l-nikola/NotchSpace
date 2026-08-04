import SwiftUI

/// Onglet Lecture du panneau déplié.
struct MediaPanel: View {
    let services: Services
    @ObservedObject private var media: MediaController

    init(services: Services) {
        self.services = services
        self.media = services.media
    }

    var body: some View {
        Group {
            if let track = media.nowPlaying {
                player(track)
            } else if media.needsAutomationPermission {
                automationHint
            } else if media.chromeNeedsJavaScript {
                chromeHint
            } else {
                empty
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Lecteur

    /// Pas de boutons ici : le transport vit en permanence dans la bande du bas, et
    /// deux jeux de commandes identiques visibles en même temps étaient le doublon le
    /// plus voyant du panneau. Cet onglet montre donc ce que la bande d'une ligne ne
    /// peut pas montrer — la pochette, et où l'on en est dans le morceau.
    private func player(_ track: NowPlaying) -> some View {
        HStack(spacing: 14) {
            artwork(track)

            VStack(alignment: .leading, spacing: 7) {
                Text(track.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.95))
                    .lineLimit(1)

                HStack(spacing: 5) {
                    // Seule l'icône porte la couleur de la source : le texte reste
                    // en gris, pour que l'identité se lise sans jamais crier.
                    Image(systemName: track.source.symbol)
                        .font(.notchMicro)
                        .foregroundStyle(track.source.tint)
                    Text(track.artist.isEmpty ? track.source.displayName : track.artist)
                        .font(.notchSecondary)
                        .lineLimit(1)
                        .foregroundStyle(.white.opacity(0.55))
                }

                progress(track)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func artwork(_ track: NowPlaying) -> some View {
        Group {
            if let image = media.artwork {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    Color.white.opacity(0.07)
                    Image(systemName: track.source.symbol)
                        .font(.system(size: 18))
                        .foregroundStyle(.white.opacity(0.35))
                }
            }
        }
        .frame(width: 68, height: 68)
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
    }

    /// La position est extrapolée localement : `TimelineView` fait avancer la barre
    /// chaque seconde sans qu'on ait à interroger Spotify ou Chrome pour autant.
    private func progress(_ track: NowPlaying) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let elapsed = track.currentPosition(now: context.date)
            let ratio = track.duration > 0 ? min(max(elapsed / track.duration, 0), 1) : 0

            VStack(spacing: 3) {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.13))
                        Capsule()
                            .fill(.white.opacity(0.75))
                            .frame(width: proxy.size.width * ratio)
                    }
                }
                .frame(height: 3)

                HStack {
                    Text(elapsed.mmss)
                    Spacer()
                    Text(track.duration.mmss)
                }
                .font(.notchMicro)
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.4))
            }
        }
    }

    // MARK: États sans lecture

    private var empty: some View {
        PlaceholderPanel(symbol: "music.note", text: "Rien en lecture")
    }

    /// Chrome bloque `execute … javascript` tant que l'option n'est pas cochée. Le
    /// message reprend le chemin exact du menu pour éviter la chasse au réglage.
    private var chromeHint: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.notchAlertIcon)
                .foregroundStyle(NotchColor.warning.opacity(0.8))

            VStack(alignment: .leading, spacing: 2) {
                Text("Chrome bloque le contrôle de YouTube")
                    .font(.notchAlertHeadline)
                    .foregroundStyle(.white.opacity(0.9))
                Text("Menu Affichage → Développeur → Autoriser JavaScript dans les événements AppleScript")
                    .font(.notchCaption)
                    .foregroundStyle(.white.opacity(0.5))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    /// Sans autorisation Automation, aucune source ne peut répondre : le dire ici
    /// plutôt que de laisser croire, dans l'onglet même où l'on vient chercher la
    /// lecture en cours, que rien ne joue nulle part.
    private var automationHint: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.fill")
                .font(.notchAlertIcon)
                .foregroundStyle(NotchColor.warning.opacity(0.8))

            VStack(alignment: .leading, spacing: 4) {
                Text("Autorisation d'automatisation refusée")
                    .font(.notchAlertHeadline)
                    .foregroundStyle(.white.opacity(0.9))
                Text("NotchSpace ne peut lire ni Spotify ni Chrome tant qu'elle n'est pas accordée.")
                    .font(.notchCaption)
                    .foregroundStyle(.white.opacity(0.5))
                    .fixedSize(horizontal: false, vertical: true)

                Button("Ouvrir Réglages Système") { SystemSettings.openAutomationPrivacy() }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background { Capsule().fill(.white.opacity(0.12)) }
                    .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
    }
}
