import Foundation

/// Réglages persistés dans `UserDefaults`.
///
/// On n'utilise pas `@AppStorage` : dans un `ObservableObject`, il ne déclenche pas
/// `objectWillChange`, donc les vues qui observent l'objet ne se rafraîchissent pas.
/// Un `@Published` avec `didSet` fait le travail sans surprise.
final class AppSettings: ObservableObject {

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        workMinutes = defaults.value(forKey: Key.workMinutes) as? Int ?? 25
        shortBreakMinutes = defaults.value(forKey: Key.shortBreakMinutes) as? Int ?? 5
        longBreakMinutes = defaults.value(forKey: Key.longBreakMinutes) as? Int ?? 15
        pomodorosBeforeLongBreak = defaults.value(forKey: Key.pomodorosBeforeLongBreak) as? Int ?? 4
        autoStartNextSession = defaults.value(forKey: Key.autoStartNextSession) as? Bool ?? true
        playSoundOnSessionEnd = defaults.value(forKey: Key.playSoundOnSessionEnd) as? Bool ?? true
        endSoundName = defaults.string(forKey: Key.endSoundName) ?? "Submarine"
        postNotificationOnSessionEnd = defaults.value(forKey: Key.postNotificationOnSessionEnd) as? Bool ?? false

        mediaEnabled = defaults.value(forKey: Key.mediaEnabled) as? Bool ?? true
        chromeEnabled = defaults.value(forKey: Key.chromeEnabled) as? Bool ?? true

        showStatusItem = defaults.value(forKey: Key.showStatusItem) as? Bool ?? true
        shelfRetentionDays = defaults.value(forKey: Key.shelfRetentionDays) as? Int ?? 7
    }

    // MARK: Pomodoro

    @Published var workMinutes: Int { didSet { defaults.set(workMinutes, forKey: Key.workMinutes) } }
    @Published var shortBreakMinutes: Int { didSet { defaults.set(shortBreakMinutes, forKey: Key.shortBreakMinutes) } }
    @Published var longBreakMinutes: Int { didSet { defaults.set(longBreakMinutes, forKey: Key.longBreakMinutes) } }
    @Published var pomodorosBeforeLongBreak: Int { didSet { defaults.set(pomodorosBeforeLongBreak, forKey: Key.pomodorosBeforeLongBreak) } }
    @Published var autoStartNextSession: Bool { didSet { defaults.set(autoStartNextSession, forKey: Key.autoStartNextSession) } }
    @Published var playSoundOnSessionEnd: Bool { didSet { defaults.set(playSoundOnSessionEnd, forKey: Key.playSoundOnSessionEnd) } }
    @Published var endSoundName: String { didSet { defaults.set(endSoundName, forKey: Key.endSoundName) } }
    @Published var postNotificationOnSessionEnd: Bool { didSet { defaults.set(postNotificationOnSessionEnd, forKey: Key.postNotificationOnSessionEnd) } }

    // MARK: Média

    @Published var mediaEnabled: Bool { didSet { defaults.set(mediaEnabled, forKey: Key.mediaEnabled) } }
    @Published var chromeEnabled: Bool { didSet { defaults.set(chromeEnabled, forKey: Key.chromeEnabled) } }

    // MARK: Divers

    @Published var showStatusItem: Bool { didSet { defaults.set(showStatusItem, forKey: Key.showStatusItem) } }
    @Published var shelfRetentionDays: Int { didSet { defaults.set(shelfRetentionDays, forKey: Key.shelfRetentionDays) } }

    // MARK: Presets

    /// Applique un cycle courant. `nil` pour les durées laissées telles quelles.
    func applyPreset(work: Int, shortBreak: Int) {
        workMinutes = work
        shortBreakMinutes = shortBreak
    }

    var matchesClassicPreset: Bool { workMinutes == 25 && shortBreakMinutes == 5 }
    var matchesLongPreset: Bool { workMinutes == 50 && shortBreakMinutes == 10 }

    private enum Key {
        static let workMinutes = "pomodoro.workMinutes"
        static let shortBreakMinutes = "pomodoro.shortBreakMinutes"
        static let longBreakMinutes = "pomodoro.longBreakMinutes"
        static let pomodorosBeforeLongBreak = "pomodoro.pomodorosBeforeLongBreak"
        static let autoStartNextSession = "pomodoro.autoStartNextSession"
        static let playSoundOnSessionEnd = "pomodoro.playSoundOnSessionEnd"
        static let endSoundName = "pomodoro.endSoundName"
        static let postNotificationOnSessionEnd = "pomodoro.postNotificationOnSessionEnd"
        static let mediaEnabled = "media.enabled"
        static let chromeEnabled = "media.chromeEnabled"
        static let showStatusItem = "ui.showStatusItem"
        static let shelfRetentionDays = "shelf.retentionDays"
    }
}
