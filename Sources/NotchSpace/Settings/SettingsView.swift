import SwiftUI

struct SettingsView: View {
    let services: Services

    var body: some View {
        TabView {
            PomodoroSettingsTab(settings: services.settings, effects: services.effects)
                .tabItem { Label("Pomodoro", systemImage: "timer") }

            MediaSettingsTab(settings: services.settings, media: services.media)
                .tabItem { Label("Lecture", systemImage: "music.note") }

            GeneralSettingsTab(settings: services.settings, shelf: services.shelf)
                .tabItem { Label("Général", systemImage: "gearshape") }
        }
        .frame(width: 560, height: 440)
    }
}

// MARK: - Pomodoro

private struct PomodoroSettingsTab: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var effects: SessionEffects

    var body: some View {
        Form {
            Section("Durées") {
                Stepper("Travail : \(settings.workMinutes) min",
                        value: $settings.workMinutes, in: 1...180)
                Stepper("Pause courte : \(settings.shortBreakMinutes) min",
                        value: $settings.shortBreakMinutes, in: 1...60)
                Stepper("Grande pause : \(settings.longBreakMinutes) min",
                        value: $settings.longBreakMinutes, in: 1...120)
                Stepper("Grande pause tous les \(settings.pomodorosBeforeLongBreak) pomodoros",
                        value: $settings.pomodorosBeforeLongBreak, in: 2...12)
            }

            Section("Enchaînement") {
                Toggle("Démarrer la phase suivante automatiquement",
                       isOn: $settings.autoStartNextSession)
            }

            Section("Fin de session") {
                Toggle("Jouer un son", isOn: $settings.playSoundOnSessionEnd)
                Picker("Son", selection: $settings.endSoundName) {
                    ForEach(Self.systemSounds, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                .disabled(!settings.playSoundOnSessionEnd)
                .onChange(of: settings.endSoundName) { _, name in
                    NSSound(named: name)?.play()
                }

                Toggle("Envoyer une notification", isOn: $settings.postNotificationOnSessionEnd)
                if settings.postNotificationOnSessionEnd, effects.notificationsDenied {
                    Label("Notifications refusées pour NotchSpace", systemImage: "bell.slash.fill")
                        .foregroundStyle(NotchColor.warning)
                    Button("Ouvrir Réglages Système") { SystemSettings.openNotifications() }
                }
                Text("Un mode de concentration actif peut retenir la notification : le son reste le signal fiable.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        // Un refus affiché ici a pu être corrigé depuis Réglages Système pendant que
        // NotchSpace tournait déjà : la relecture évite d'afficher un état périmé.
        .onAppear { effects.refreshAuthorizationStatus() }
    }

    /// Sons livrés avec macOS ; on les lit depuis le disque plutôt que d'en coder
    /// une liste qui pourrait ne plus correspondre.
    private static let systemSounds: [String] = {
        let directory = URL(fileURLWithPath: "/System/Library/Sounds")
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path))?
            .filter { $0.hasSuffix(".aiff") }
            .map { String($0.dropLast(5)) }
            .sorted() ?? []
        return names.isEmpty ? ["Submarine"] : names
    }()
}

// MARK: - Lecture

private struct MediaSettingsTab: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var media: MediaController

    var body: some View {
        Form {
            Section("Sources") {
                Toggle("Afficher la lecture en cours", isOn: $settings.mediaEnabled)
                Toggle("Inclure YouTube dans Google Chrome", isOn: $settings.chromeEnabled)
                    .disabled(!settings.mediaEnabled)
            }

            if media.needsAutomationPermission {
                Section {
                    Label("Autorisation d'automatisation refusée", systemImage: "lock.fill")
                        .foregroundStyle(NotchColor.warning)
                    Text("Réglages Système → Confidentialité et sécurité → Automatisation → NotchSpace")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Ouvrir Réglages Système") { SystemSettings.openAutomationPrivacy() }
                }
            }

            if media.chromeNeedsJavaScript {
                Section {
                    // Même libellé que dans l'onglet Lecture de l'encoche, pour le
                    // même état.
                    Label("Chrome bloque le contrôle de YouTube", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(NotchColor.warning)
                    Text("Dans Chrome : menu Affichage → Développeur → Autoriser JavaScript dans les événements AppleScript.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Text("""
                Spotify est lu via son dictionnaire AppleScript et se met à jour \
                à chaque changement, sans interrogation périodique. YouTube demande \
                d'interroger la page, d'où l'option distincte.
                """)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Général

private struct GeneralSettingsTab: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var shelf: ShelfStore
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var launchError: String?

    var body: some View {
        Form {
            Section("Démarrage") {
                Toggle("Lancer NotchSpace à l'ouverture de session", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        launchError = LaunchAtLogin.set(enabled)
                        launchAtLogin = LaunchAtLogin.isEnabled
                    }
                if let launchError {
                    Text(launchError)
                        .font(.caption)
                        .foregroundStyle(NotchColor.warning)
                }
            }

            Section("Barre des menus") {
                Toggle("Afficher l'icône dans la barre des menus", isOn: $settings.showStatusItem)
                Text("L'encoche reste accessible sans elle, mais c'est le seul autre moyen d'ouvrir ces réglages.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Étagère") {
                Stepper(settings.shelfRetentionDays == 0
                        ? "Conserver indéfiniment"
                        : "Vider après \(settings.shelfRetentionDays) jour\(settings.shelfRetentionDays > 1 ? "s" : "")",
                        value: $settings.shelfRetentionDays, in: 0...90)
                HStack {
                    // Même terme et même accord que dans l'onglet Étagère : ce sont
                    // des fichiers, pas des « éléments » génériques, et l'ancien
                    // « élément(s) » n'était pas un pluriel français correct.
                    Text("\(shelf.items.count) fichier\(shelf.items.count > 1 ? "s" : "")")
                        .foregroundStyle(.secondary)
                    Spacer()
                    ClearShelfButton(shelf: shelf) { Text("Tout vider") }
                        .disabled(shelf.items.isEmpty)
                }
                Text("Les fichiers déposés restent à leur place : l'étagère n'en garde qu'une référence.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
