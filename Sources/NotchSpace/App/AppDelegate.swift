import AppKit
import SwiftUI

/// Les rappels d'`NSApplicationDelegate` et les notifications d'espace de travail
/// arrivent toutes sur le thread principal : on l'affirme au compilateur plutôt que
/// de disperser des `Task { @MainActor in … }`.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private(set) var services: Services!
    private(set) var notch: NotchController!
    private var statusItem: StatusItemController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // `LSUIElement` place déjà l'app en accessoire ; on le réaffirme pour le cas
        // où le binaire serait lancé hors de son bundle (pendant un test).
        NSApp.setActivationPolicy(.accessory)

        let services = Services()
        self.services = services

        let notch = NotchController(services: services)
        self.notch = notch
        notch.start()
        services.settingsWindow.notch = notch

        statusItem = StatusItemController(services: services, notch: notch)

        observeSleepWake()
    }

    func applicationWillTerminate(_ notification: Notification) {
        notch?.stop()
    }

    // MARK: Veille

    private func observeSleepWake() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self,
                           selector: #selector(didWake),
                           name: NSWorkspace.didWakeNotification,
                           object: nil)
        center.addObserver(self,
                           selector: #selector(didWake),
                           name: NSWorkspace.screensDidWakeNotification,
                           object: nil)
    }

    /// Le minuteur repose sur une date d'échéance, donc le temps restant est déjà
    /// juste au réveil. Il reste à relancer le tic, qui ne s'exécute pas pendant la
    /// veille, et à rattraper une échéance franchie entre-temps.
    @objc private func didWake() {
        services?.pomodoro.synchronizeAfterWake()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
}
