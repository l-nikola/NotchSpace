import AppKit
import SwiftUI

/// Fenêtre de réglages, créée et gardée en vie explicitement.
///
/// On n'utilise pas la `Settings` scene de SwiftUI : dans une app accessoire sans
/// fenêtre principale, `showSettingsWindow:` n'atteint aucun répondeur et l'action
/// est simplement ignorée — sans erreur, ce qui rend le problème difficile à voir.
/// Une `NSWindow` gérée à la main s'ouvre toujours, et l'app pilote déjà son panneau
/// de la même façon.
@MainActor
final class SettingsWindowController {

    private var window: NSWindow?
    private unowned let services: Services

    /// Réglé par l'`AppDelegate` : ouvrir les réglages doit refermer l'encoche.
    weak var notch: NotchController?

    init(services: Services) {
        self.services = services
    }

    func show() {
        if window == nil {
            window = makeWindow()
        }
        guard let window else { return }

        // Le panneau de l'encoche est au niveau 25 : déplié, il recouvre le haut de
        // l'écran et intercepterait les clics destinés aux réglages.
        notch?.collapse()

        // Sans activation, la fenêtre s'ouvrirait derrière l'app en cours : les
        // réglages sont le seul moment où NotchSpace a légitimement le premier plan.
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }

        if !window.isVisible { position(window) }
        window.makeKeyAndOrderFront(nil)
    }

    /// Centrée horizontalement, mais jamais sous l'encoche dépliée : un simple
    /// `center()` place la fenêtre trop haut sur un écran de portable.
    private func position(_ window: NSWindow) {
        guard let screen = window.screen ?? NSScreen.main else {
            window.center()
            return
        }
        let visible = screen.visibleFrame
        let size = window.frame.size
        let minimumTopGap = NotchMetrics.expandedSize.height + NotchMetrics.windowPadding + 24

        let x = visible.midX - size.width / 2
        let highestTop = visible.maxY - minimumTopGap
        let y = min(visible.midY - size.height / 2, highestTop - size.height)

        window.setFrameOrigin(CGPoint(x: x, y: max(visible.minY + 20, y)))
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 440),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false)

        window.title = "Réglages de NotchSpace"
        window.contentView = NSHostingView(rootView: SettingsView(services: services))
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }
}
