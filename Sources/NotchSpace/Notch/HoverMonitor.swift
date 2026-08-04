import AppKit

/// Détecte l'entrée et la sortie du curseur sur une zone de l'écran.
///
/// On n'utilise pas de `NSTrackingArea` : la fenêtre change de taille selon l'état et
/// n'est pas systématiquement key, ce qui rend le suivi peu fiable. Deux moniteurs
/// `NSEvent` couvrent tous les cas — le moniteur global ne se déclenche pas quand
/// NotchSpace est l'app active, d'où le moniteur local en complément.
///
/// À noter : surveiller les mouvements de souris **ne demande pas** la permission
/// Accessibilité (contrairement aux événements clavier).
final class HoverMonitor {

    /// Zone chaude courante, en coordonnées écran. Recalculée à chaque événement pour
    /// suivre le dépliage : une fois le panneau ouvert, la zone couvre tout le panneau.
    var zoneProvider: () -> CGRect = { .zero }

    /// Délai avant repli, pour éviter un clignotement quand le curseur frôle un bord.
    var exitDelay: TimeInterval = 0.18

    private(set) var isInside = false
    private var onChange: (Bool) -> Void
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var pendingExit: DispatchWorkItem?
    private var watchdog: Timer?

    init(onChange: @escaping (Bool) -> Void) {
        self.onChange = onChange
    }

    func start() {
        guard globalMonitor == nil else { return }
        let events: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged]

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: events) { [weak self] _ in
            self?.evaluate()
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: events) { [weak self] event in
            self?.evaluate()
            return event
        }
    }

    func stop() {
        [globalMonitor, localMonitor].compactMap { $0 }.forEach(NSEvent.removeMonitor)
        globalMonitor = nil
        localMonitor = nil
        pendingExit?.cancel()
        pendingExit = nil
        stopWatchdog()
    }

    /// Force l'état « à l'intérieur » sans attendre un mouvement de souris.
    /// Utile quand un glisser-déposer entre dans l'encoche.
    func forceInside() {
        pendingExit?.cancel()
        pendingExit = nil
        guard !isInside else { return }
        isInside = true
        startWatchdog()
        onChange(true)
    }

    /// Filet de sécurité contre un événement de sortie manqué.
    ///
    /// Les moniteurs `NSEvent` ne voient pas tout : une app qui consomme les événements,
    /// un changement de bureau ou un déplacement programmatique du curseur peuvent
    /// laisser le panneau ouvert en travers de la barre de menus. Ce minuteur relit
    /// directement la position réelle du curseur — et ne tourne que panneau ouvert,
    /// donc il ne coûte rien au repos.
    private func startWatchdog() {
        guard watchdog == nil else { return }
        let timer = Timer(timeInterval: 0.4, repeats: true) { [weak self] _ in
            DispatchQueue.main.async { self?.evaluate() }
        }
        // `.common` pour continuer à tourner pendant qu'un menu est ouvert.
        RunLoop.main.add(timer, forMode: .common)
        watchdog = timer
    }

    private func stopWatchdog() {
        watchdog?.invalidate()
        watchdog = nil
    }

    private func evaluate() {
        let inside = zoneProvider().contains(NSEvent.mouseLocation)
        guard inside != isInside else { return }

        if inside {
            pendingExit?.cancel()
            pendingExit = nil
            isInside = true
            startWatchdog()
            onChange(true)
        } else {
            // Sortie différée : on ne replie que si le curseur est toujours dehors
            // à l'échéance.
            pendingExit?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard let self, !self.zoneProvider().contains(NSEvent.mouseLocation) else { return }
                self.isInside = false
                self.stopWatchdog()
                self.onChange(false)
            }
            pendingExit = work
            DispatchQueue.main.asyncAfter(deadline: .now() + exitDelay, execute: work)
        }
    }

    deinit { stop() }
}
