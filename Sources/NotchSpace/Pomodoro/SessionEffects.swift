import AppKit
import Combine
import UserNotifications

/// Réagit à la fin d'une phase du Pomodoro : son, notification.
///
/// Isolé du moteur pour que celui-ci reste du calcul pur et testable.
@MainActor
final class SessionEffects: ObservableObject {

    /// Refusée alors que le réglage est actif : sans ce signal, la case cochée dans
    /// les préférences ne produit jamais rien, sans qu'aucune explication n'apparaisse
    /// nulle part.
    @Published private(set) var notificationsDenied = false

    private let settings: AppSettings
    private var cancellable: AnyCancellable?

    init(settings: AppSettings) {
        self.settings = settings
    }

    func attach(to engine: PomodoroEngine) {
        engine.onPhaseEnded = { [weak self] finished, next in
            self?.phaseEnded(finished, next: next)
        }
    }

    private func phaseEnded(_ finished: PomodoroPhase, next: PomodoroPhase) {
        // Le son reste le signal le plus fiable : une notification peut être retenue
        // par le mode de concentration du système.
        if settings.playSoundOnSessionEnd {
            NSSound(named: settings.endSoundName)?.play()
        }

        if settings.postNotificationOnSessionEnd, next != .idle, !notificationsDenied {
            postNotification(finished: finished, next: next)
        }
    }

    // MARK: Notifications

    /// Demande l'autorisation si le réglage est déjà actif au lancement, puis à
    /// nouveau à chaque activation depuis les préférences.
    ///
    /// La limiter au seul lancement laissait l'utilisateur cocher la case en cours de
    /// session sans jamais voir la demande système apparaître : la notification
    /// restait silencieusement refusée pour toujours.
    func start() {
        requestAuthorizationIfNeeded(settings.postNotificationOnSessionEnd)
        cancellable = settings.$postNotificationOnSessionEnd
            .removeDuplicates()
            .dropFirst() // valeur initiale déjà couverte par l'appel ci-dessus
            .sink { [weak self] enabled in self?.requestAuthorizationIfNeeded(enabled) }
    }

    private func requestAuthorizationIfNeeded(_ enabled: Bool) {
        guard enabled else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { [weak self] granted, _ in
            Task { @MainActor in self?.notificationsDenied = !granted }
        }
    }

    /// Relit le statut réel, sans redemander : contrairement à l'autorisation
    /// Automation (revérifiée à chaque sondage média), un refus de notification ne
    /// s'auto-corrigeait jamais si l'utilisateur l'accordait depuis Réglages Système
    /// pendant que NotchSpace tournait déjà — la bannière restait affichée à tort.
    /// À rappeler quand la fenêtre de réglages s'affiche.
    func refreshAuthorizationStatus() {
        guard settings.postNotificationOnSessionEnd else { return }
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] notificationSettings in
            Task { @MainActor in
                self?.notificationsDenied = notificationSettings.authorizationStatus == .denied
            }
        }
    }

    private func postNotification(finished: PomodoroPhase, next: PomodoroPhase) {
        let content = UNMutableNotificationContent()
        content.title = finished == .work ? "Session terminée" : "Pause terminée"
        content.body = next == .work ? "Au travail." : "\(next.label) — c'est parti."
        // Silencieux : le son est déjà géré à part, et une notification sonore
        // doublerait le signal.
        content.sound = nil

        let request = UNNotificationRequest(identifier: UUID().uuidString,
                                            content: content,
                                            trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
