import Foundation

/// Racine de composition : construit et détient les services partagés.
///
/// Un conteneur unique évite les singletons éparpillés et rend l'ordre de création
/// explicite (les réglages d'abord, tout le reste s'appuie dessus).
@MainActor
final class Services {
    let settings: AppSettings
    let pomodoro: PomodoroEngine
    let effects: SessionEffects
    let media: MediaController
    let shelf: ShelfStore
    /// Créée à la demande : la fenêtre n'existe que si l'utilisateur l'ouvre.
    private(set) lazy var settingsWindow = SettingsWindowController(services: self)

    init(settings: AppSettings = AppSettings()) {
        self.settings = settings
        self.pomodoro = PomodoroEngine(settings: settings)
        self.effects = SessionEffects(settings: settings)
        self.media = MediaController(settings: settings)
        self.shelf = ShelfStore(settings: settings)

        effects.attach(to: pomodoro)
        effects.start()
        media.start()
    }

    func shutdown() {
        media.stop()
    }
}
