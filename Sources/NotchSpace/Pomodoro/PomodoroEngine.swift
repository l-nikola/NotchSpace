import Foundation

enum PomodoroPhase: String, Equatable {
    case idle
    case work
    case shortBreak
    case longBreak

    var isBreak: Bool { self == .shortBreak || self == .longBreak }

    var label: String {
        switch self {
        case .idle: return "Prêt"
        case .work: return "Concentration"
        case .shortBreak: return "Pause"
        case .longBreak: return "Grande pause"
        }
    }
}

/// Source de temps injectable, pour tester le comportement autour de la veille sans
/// attendre réellement.
protocol PomodoroClock {
    var now: Date { get }
}

struct SystemClock: PomodoroClock {
    var now: Date { Date() }
}

/// Minuteur Pomodoro.
///
/// Le compte à rebours repose sur une **date d'échéance**, jamais sur un compteur
/// décrémenté à chaque tic. Un minuteur ne se déclenche pas pendant la veille : avec
/// un compteur, fermer le capot dix minutes « gèlerait » la session. En comparant à
/// l'horloge, le temps restant est toujours juste, et il suffit de relire à la sortie
/// de veille.
final class PomodoroEngine: ObservableObject {

    @Published private(set) var phase: PomodoroPhase = .idle
    @Published private(set) var isRunning = false
    /// Temps restant dans la phase courante.
    @Published private(set) var remaining: TimeInterval = 0
    /// Durée totale de la phase courante, pour calculer la progression.
    @Published private(set) var phaseDuration: TimeInterval = 0
    /// Pomodoros de travail terminés depuis le début du cycle.
    @Published private(set) var completedPomodoros = 0

    /// Appelé quand une phase se termine — pour le son et la notification.
    var onPhaseEnded: ((PomodoroPhase, PomodoroPhase) -> Void)?

    private let settings: AppSettings
    private let clock: PomodoroClock
    private var endDate: Date?
    private var ticker: Timer?

    init(settings: AppSettings, clock: PomodoroClock = SystemClock()) {
        self.settings = settings
        self.clock = clock
    }

    // MARK: Progression

    /// De 0 à 1 sur la phase courante. Vaut 0 hors session.
    var progress: Double {
        guard phaseDuration > 0 else { return 0 }
        return min(max(1 - remaining / phaseDuration, 0), 1)
    }

    var isActive: Bool { phase != .idle }

    /// `25:00`, ou `1:05:00` au-delà de l'heure.
    var formattedRemaining: String {
        let total = Int(remaining.rounded(.up))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%d:%02d", minutes, seconds)
    }

    // MARK: Commandes

    func start() {
        if phase == .idle {
            begin(.work)
        } else {
            resume()
        }
    }

    func pause() {
        guard isRunning, let endDate else { return }
        remaining = max(0, endDate.timeIntervalSince(clock.now))
        isRunning = false
        self.endDate = nil
        stopTicker()
    }

    func resume() {
        guard !isRunning, phase != .idle, remaining > 0 else { return }
        endDate = clock.now.addingTimeInterval(remaining)
        isRunning = true
        startTicker()
    }

    func toggle() {
        isRunning ? pause() : start()
    }

    /// Arrête tout et remet le compteur de cycles à zéro.
    func reset() {
        let previous = phase
        stopTicker()
        endDate = nil
        isRunning = false
        phase = .idle
        remaining = 0
        phaseDuration = 0
        completedPomodoros = 0
        if previous != .idle {
            onPhaseEnded?(previous, .idle)
        }
    }

    /// Termine la phase courante immédiatement et enchaîne sur la suivante.
    func skip() {
        guard phase != .idle else { return }
        finishCurrentPhase()
    }

    // MARK: Enchaînement

    private func begin(_ next: PomodoroPhase) {
        let duration = duration(for: next)
        phase = next
        phaseDuration = duration
        remaining = duration
        endDate = clock.now.addingTimeInterval(duration)
        isRunning = true
        startTicker()
    }

    private func duration(for phase: PomodoroPhase) -> TimeInterval {
        switch phase {
        case .idle: return 0
        case .work: return TimeInterval(settings.workMinutes * 60)
        case .shortBreak: return TimeInterval(settings.shortBreakMinutes * 60)
        case .longBreak: return TimeInterval(settings.longBreakMinutes * 60)
        }
    }

    /// Phase qui suit celle qui vient de finir.
    private func phaseAfter(_ finished: PomodoroPhase, completed: Int) -> PomodoroPhase {
        guard finished == .work else { return .work }
        let every = max(1, settings.pomodorosBeforeLongBreak)
        return completed % every == 0 ? .longBreak : .shortBreak
    }

    private func finishCurrentPhase() {
        let finished = phase
        guard finished != .idle else { return }

        if finished == .work {
            completedPomodoros += 1
        }

        let next = phaseAfter(finished, completed: completedPomodoros)
        stopTicker()
        endDate = nil

        onPhaseEnded?(finished, next)

        if settings.autoStartNextSession {
            begin(next)
        } else {
            // La phase suivante est armée mais en attente d'un démarrage explicite.
            phase = next
            phaseDuration = duration(for: next)
            remaining = phaseDuration
            isRunning = false
        }
    }

    // MARK: Tic

    private func startTicker() {
        stopTicker()
        // Un tic par seconde suffit : l'anneau interpole entre deux valeurs, et la
        // justesse vient de la date d'échéance, pas de la régularité du minuteur.
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
        tick()
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }

    private func tick() {
        guard isRunning, let endDate else { return }
        let left = endDate.timeIntervalSince(clock.now)
        if left <= 0 {
            remaining = 0
            finishCurrentPhase()
        } else {
            remaining = left
        }
    }

    /// À appeler à la sortie de veille : relit l'horloge et rattrape une échéance
    /// franchie pendant que la machine dormait.
    func synchronizeAfterWake() {
        guard isRunning else { return }
        tick()
        // Le minuteur a pu être suspendu pendant la veille ; on le relance.
        if isRunning { startTicker() }
    }

    deinit { ticker?.invalidate() }
}
