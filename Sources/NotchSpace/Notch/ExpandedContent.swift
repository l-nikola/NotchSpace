import SwiftUI

/// Contenu du panneau déplié.
///
/// Trois bandes, séparées par un filet :
///
/// - **l'en-tête** porte l'état du minuteur, quel que soit l'onglet ouvert ;
/// - **le corps** appartient à l'onglet courant ;
/// - **le pied** réunit la navigation et le transport de lecture, eux aussi
///   permanents.
///
/// Ce qui est permanent encadre donc ce qui change. Sans les filets, les trois bandes
/// se lisaient comme un seul bloc où le contenu flottait ; ils coûtent un demi-point
/// chacun et rendent la composition évidente.
///
/// L'en-tête est le seul endroit contraint : sur sa hauteur, le centre est masqué par
/// l'encoche physique. On n'y place donc rien au milieu, en réservant explicitement la
/// largeur de l'encoche.
struct ExpandedContent: View {
    let services: Services
    @ObservedObject var state: NotchState

    var body: some View {
        VStack(spacing: 0) {
            header
            hairline
            body(for: state.tab)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .padding(.vertical, 10)
            hairline
            footer
                .padding(.top, 10)
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 12)
    }

    /// Un demi-point : sur un écran Retina, c'est le trait d'un pixel. À 1 pt, le filet
    /// devient une barre et attire l'œil au lieu de le guider.
    private var hairline: some View {
        Rectangle()
            .fill(.white.opacity(0.09))
            .frame(height: 0.5)
    }

    // MARK: En-tête

    private var notchWidth: CGFloat { state.metrics?.notchRect.width ?? 185 }
    private var notchHeight: CGFloat { state.metrics?.notchRect.height ?? 32 }

    private var header: some View {
        HStack(spacing: 0) {
            HStack { HeaderPhase(services: services); Spacer(minLength: 0) }
                .frame(maxWidth: .infinity)

            // Réservation de l'encoche : rien ne peut s'afficher ici.
            Color.clear.frame(width: notchWidth)

            HStack { Spacer(minLength: 0); HeaderTime(services: services) }
                .frame(maxWidth: .infinity)
        }
        .frame(height: notchHeight)
    }

    // MARK: Corps

    @ViewBuilder
    private func body(for tab: NotchTab) -> some View {
        switch tab {
        case .focus:
            PomodoroPanel(services: services)
        case .media:
            MediaPanel(services: services)
        case .shelf:
            ShelfPanel(services: services)
        }
    }

    // MARK: Pied

    private var footer: some View {
        HStack(spacing: 6) {
            ForEach(NotchTab.allCases) { tab in
                Button {
                    withAnimation(.reduced(.easeInOut(duration: 0.18))) { state.tab = tab }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: tab.symbol)
                            .font(.system(size: 10, weight: .semibold))
                        Text(tab.title)
                            .font(.notchCompactLabel)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background {
                        Capsule().fill(.white.opacity(state.tab == tab ? 0.16 : 0.06))
                    }
                    .foregroundStyle(.white.opacity(state.tab == tab ? 0.95 : 0.5))
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 12)

            MiniPlayer(services: services, showsNowPlaying: state.tab != .media)
        }
    }
}

/// Coin haut-gauche : la phase Pomodoro en cours.
private struct HeaderPhase: View {
    @ObservedObject private var pomodoro: PomodoroEngine

    init(services: Services) {
        self.pomodoro = services.pomodoro
    }

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(pomodoro.phase.accent)
                .frame(width: 6, height: 6)
                .opacity(pomodoro.isRunning ? 1 : 0.35)
            Text(pomodoro.phase.label)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.75))
        }
    }
}

/// Coin haut-droit : le temps restant.
private struct HeaderTime: View {
    @ObservedObject private var pomodoro: PomodoroEngine
    @ObservedObject private var settings: AppSettings

    init(services: Services) {
        self.pomodoro = services.pomodoro
        self.settings = services.settings
    }

    /// Hors session, la place affichait un tiret cadratin — un signe qui ne dit rien.
    /// La durée qui démarrerait au prochain clic est la seule information utile ici.
    var body: some View {
        Text(pomodoro.isActive
             ? pomodoro.formattedRemaining
             : "\(settings.workMinutes) min")
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.white.opacity(pomodoro.isActive ? 0.95 : 0.3))
            .contentTransition(.numericText())
    }
}

extension PomodoroPhase {
    var accent: Color {
        switch self {
        case .work: return Color(red: 1.0, green: 0.45, blue: 0.36)
        case .shortBreak: return Color(red: 0.33, green: 0.80, blue: 0.65)
        case .longBreak: return Color(red: 0.50, green: 0.62, blue: 0.98)
        case .idle: return .gray
        }
    }
}
