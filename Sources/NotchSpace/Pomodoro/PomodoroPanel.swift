import SwiftUI

/// Onglet Focus du panneau déplié : transport, cycle, presets.
struct PomodoroPanel: View {
    let services: Services
    @ObservedObject private var pomodoro: PomodoroEngine
    @ObservedObject private var settings: AppSettings

    init(services: Services) {
        self.services = services
        self.pomodoro = services.pomodoro
        self.settings = services.settings
    }

    /// Ce qu'on fait à gauche, ce qu'on règle à droite.
    ///
    /// Transport et cycle décrivent la session en cours, les presets la prochaine :
    /// les séparer sur toute la largeur donne deux blocs à lire au lieu d'un empilement
    /// centré qui laissait la moitié du panneau vide.
    var body: some View {
        HStack(spacing: 16) {
            transport

            Rectangle()
                .fill(.white.opacity(0.10))
                .frame(width: 0.5, height: 28)

            cycleDots

            Spacer(minLength: 16)

            presets
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var isCustomPreset: Bool {
        !settings.matchesClassicPreset && !settings.matchesLongPreset
    }

    // MARK: Transport

    private var transport: some View {
        // « Reprendre » quand une session existe déjà en pause, comme le distingue
        // déjà le même bouton côté lecture média (« Reprendre » vs « Mettre en
        // pause ») : sans ça, rien ne dit que cliquer continue le compte à rebours en
        // cours plutôt que d'en relancer un nouveau.
        let playPauseLabel = pomodoro.isRunning ? "Mettre en pause" : (pomodoro.isActive ? "Reprendre" : "Démarrer")

        return HStack(spacing: 10) {
            CircleButton(symbol: pomodoro.isRunning ? "pause.fill" : "play.fill",
                         size: 34,
                         prominent: true,
                         tint: (pomodoro.phase == .idle ? PomodoroPhase.work : pomodoro.phase).accent) {
                pomodoro.toggle()
            }
            .help(playPauseLabel)
            .accessibilityLabel(playPauseLabel)

            CircleButton(symbol: "forward.end.fill", size: 26) { pomodoro.skip() }
                .help("Passer à la phase suivante")
                .accessibilityLabel("Passer à la phase suivante")
                .disabled(!pomodoro.isActive)

            CircleButton(symbol: "arrow.counterclockwise", size: 26) { pomodoro.reset() }
                .help("Tout remettre à zéro")
                .accessibilityLabel("Tout remettre à zéro")
                .disabled(!pomodoro.isActive)
        }
    }

    // MARK: Cycle

    private var cycleDots: some View {
        let total = max(1, settings.pomodorosBeforeLongBreak)
        // Position dans le cycle courant : après une grande pause on repart à zéro.
        let done = pomodoro.completedPomodoros % total
        let filled = (pomodoro.completedPomodoros > 0 && done == 0) ? total : done

        return HStack(spacing: 6) {
            ForEach(0..<total, id: \.self) { index in
                Circle()
                    .fill(index < filled ? PomodoroPhase.work.accent : .white.opacity(0.18))
                    .frame(width: 7, height: 7)
            }
            // Arrondie comme le reste du chrome Pomodoro (l'en-tête, les presets) :
            // c'était la seule légende de cette famille encore en dessin par défaut.
            Text("\(pomodoro.completedPomodoros) terminé\(pomodoro.completedPomodoros > 1 ? "s" : "")")
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(.white.opacity(0.45))
                .padding(.leading, 4)
        }
    }

    // MARK: Presets

    private var presets: some View {
        HStack(spacing: 6) {
            // Même fondu que le changement d'onglet juste à côté : la puce active
            // glisse au lieu de sauter d'une position à l'autre.
            PresetChip(title: "25/5",
                       isActive: settings.matchesClassicPreset) {
                withAnimation(.reduced(.easeInOut(duration: 0.18))) { settings.applyPreset(work: 25, shortBreak: 5) }
            }
            PresetChip(title: "50/10",
                       isActive: settings.matchesLongPreset) {
                withAnimation(.reduced(.easeInOut(duration: 0.18))) { settings.applyPreset(work: 50, shortBreak: 10) }
            }
            // Sur un preset standard, afficher les durées ici ferait doublon avec la
            // puce déjà active : on montre alors simplement l'accès aux réglages.
            PresetChip(title: isCustomPreset
                        ? "\(settings.workMinutes)/\(settings.shortBreakMinutes)"
                        : "Perso…",
                       isActive: isCustomPreset) {
                services.settingsWindow.show()
            }
            .help("Régler des durées personnalisées")
        }
    }

}

// MARK: - Petits composants

struct CircleButton: View {
    let symbol: String
    var size: CGFloat = 28
    var prominent = false
    var tint: Color = .white
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        // L'animation entoure l'action, pas seulement l'icône : c'est ce qui donne
        // au changement d'état qu'elle déclenche (lecture ↔ pause, anneau qui
        // change de phase après un « suivant ») de quoi être animé plutôt que sauter.
        Button(action: { withAnimation(.reduced(.easeInOut(duration: 0.18))) { action() } }) {
            ZStack {
                Circle()
                    .fill(prominent ? AnyShapeStyle(tint) : AnyShapeStyle(Color.white.opacity(0.10)))
                Image(systemName: symbol)
                    .font(.system(size: size * 0.36, weight: .semibold))
                    .foregroundStyle(prominent ? .black : .white)
                    // Lecture ↔ pause se lit comme un seul symbole qui se retourne,
                    // pas deux icônes qui se remplacent au montage suivant.
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(width: size, height: size)
            .opacity(isEnabled ? 1 : 0.35)
            .animation(.reduced(.easeOut(duration: 0.15)), value: isEnabled)
        }
        .buttonStyle(.plain)
    }
}

struct PresetChip: View {
    let title: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background { Capsule().fill(.white.opacity(isActive ? 0.18 : 0.07)) }
                .foregroundStyle(.white.opacity(isActive ? 0.9 : 0.5))
        }
        .buttonStyle(.plain)
    }
}
