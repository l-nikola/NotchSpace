import AppKit
import Combine

/// Icône dans la barre de menus.
///
/// Elle reste optionnelle : sur une barre déjà chargée, l'encoche se suffit à
/// elle-même. C'est aussi le seul point d'entrée pour ouvrir les réglages, l'app
/// n'ayant pas d'icône dans le Dock.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {

    private var statusItem: NSStatusItem?
    private var cancellables = Set<AnyCancellable>()

    private let services: Services
    private weak var notch: NotchController?

    init(services: Services, notch: NotchController) {
        self.services = services
        self.notch = notch
        super.init()

        services.settings.$showStatusItem
            .removeDuplicates()
            .sink { [weak self] visible in
                visible ? self?.install() : self?.remove()
            }
            .store(in: &cancellables)
    }

    private func install() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "timer", accessibilityDescription: "NotchSpace")
        item.button?.image?.isTemplate = true

        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu

        statusItem = item
    }

    private func remove() {
        guard let statusItem else { return }
        NSStatusBar.system.removeStatusItem(statusItem)
        self.statusItem = nil
    }

    // MARK: Menu

    /// Reconstruit à l'ouverture : les libellés dépendent de l'état du minuteur.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let pomodoro = services.pomodoro
        if pomodoro.isActive {
            let status = NSMenuItem(title: "\(pomodoro.phase.label) — \(pomodoro.formattedRemaining)",
                                    action: nil, keyEquivalent: "")
            status.isEnabled = false
            menu.addItem(status)
            menu.addItem(.separator())
        }

        // « Reprendre » et non « Démarrer » quand une session existe déjà en pause :
        // sinon rien ne distingue, dans ce libellé, continuer le compte à rebours en
        // cours d'en relancer un nouveau.
        let startLabel = pomodoro.isActive ? "Reprendre" : "Démarrer une session"
        menu.addItem(item(pomodoro.isRunning ? "Mettre en pause" : startLabel,
                          #selector(togglePomodoro)))
        if pomodoro.isActive {
            // Même verbe que dans le panneau, pour l'action identique.
            menu.addItem(item("Passer à la phase suivante", #selector(skipPhase)))
            menu.addItem(item("Tout remettre à zéro", #selector(resetPomodoro)))
        }

        menu.addItem(.separator())
        menu.addItem(item("Ouvrir l'encoche", #selector(revealNotch)))
        menu.addItem(item("Réglages…", #selector(openSettings), key: ","))
        menu.addItem(.separator())
        menu.addItem(item("Quitter NotchSpace", #selector(quit), key: "q"))
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    // MARK: Actions

    @objc private func togglePomodoro() { services.pomodoro.toggle() }
    @objc private func skipPhase() { services.pomodoro.skip() }
    @objc private func resetPomodoro() { services.pomodoro.reset() }
    @objc private func revealNotch() { notch?.reveal(tab: .focus) }

    @objc private func openSettings() { services.settingsWindow.show() }

    @objc private func quit() { NSApp.terminate(nil) }
}
