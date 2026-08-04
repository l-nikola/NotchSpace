import AppKit
import Combine
import SwiftUI

enum NotchAnimation {
    static let duration: TimeInterval = 0.34
    static var spring: Animation? { .reduced(.spring(response: 0.34, dampingFraction: 0.78)) }
}

/// Pilote la fenêtre de l'encoche : géométrie, dépliage, survol.
@MainActor
final class NotchController {

    let state = NotchState()

    private var panel: NotchPanel?
    private var hostingView: NotchHostingView<NotchRootView>?
    private var hoverMonitor: HoverMonitor?
    private var shrinkWork: DispatchWorkItem?
    private var cancellables = Set<AnyCancellable>()

    private let services: Services

    init(services: Services) {
        self.services = services
    }

    // MARK: Cycle de vie

    func start() {
        rebuildGeometry()
        installPanel()
        installHoverMonitor()
        observeActivity()
        bindActivitySources()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil)
    }

    func stop() {
        hoverMonitor?.stop()
        hoverMonitor = nil
        shrinkWork?.cancel()
        cancellables.removeAll()
        panel?.orderOut(nil)
        panel = nil
        hostingView = nil
    }

    // MARK: Construction

    private func rebuildGeometry() {
        state.metrics = NotchGeometry.currentMetrics()
    }

    private func installPanel() {
        guard let metrics = state.metrics else { return }

        let frame = metrics.windowFrame(for: state.presentation, activeSideInset: state.activeSideInset)
        let panel = NotchPanel(contentRect: frame)

        // L'état passe par une propriété plutôt que par `environmentObject` : un
        // modificateur changerait le type générique de la vue et `NSHostingView`
        // exige un type concret.
        let hosting = NotchHostingView(rootView: NotchRootView(services: services, state: state))
        hosting.shellSizeProvider = { [weak self] in
            guard let self, !self.state.isShellHidden else { return .zero }
            return self.state.shellSize
        }
        hosting.dropHandler = self
        hosting.enableDrops()

        panel.contentView = hosting
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()

        self.panel = panel
        self.hostingView = hosting
    }

    private func installHoverMonitor() {
        let monitor = HoverMonitor { [weak self] inside in
            guard let self else { return }
            inside ? self.expand() : self.collapse()
        }
        monitor.zoneProvider = { [weak self] in
            guard let self, let metrics = self.state.metrics else { return .zero }
            // Une fois déplié, toute la fenêtre devient zone chaude : sans ça, le
            // curseur qui descend vers les contrôles sortirait de la zone et
            // replierait le panneau sous lui.
            return self.state.isExpanded
                ? metrics.windowFrame(for: .expanded)
                : metrics.hoverZone
        }
        monitor.start()
        hoverMonitor = monitor
    }

    /// La coquille change aussi de taille hors dépliage : quand une activité démarre
    /// ou s'arrête, et quand elle réclame plus de largeur (arrivée d'une pochette).
    private func observeActivity() {
        let activity = state.$hasActivity.map { _ in () }
        let inset = state.$activeSideInset.removeDuplicates().map { _ in () }

        activity.merge(with: inset)
            .dropFirst()
            // Les deux peuvent changer dans le même tour de boucle ; on ne redimensionne
            // qu'une fois, avec l'état déjà à jour.
            .debounce(for: .milliseconds(10), scheduler: RunLoop.main)
            .sink { [weak self] in
                guard let self, !self.state.isExpanded else { return }
                self.applyFrame(for: self.state.presentation, animateContent: true)
            }
            .store(in: &cancellables)
    }

    /// Ce qui justifie que la coquille se montre au repos.
    ///
    /// La lecture en cours n'en fait **pas** partie : elle n'a rien à afficher au
    /// repos, et faire grandir l'encoche pendant toute une playlist reviendrait à la
    /// laisser grandie en permanence.
    ///
    /// On s'abonne aux propriétés publiées plutôt qu'à `objectWillChange` : ce dernier
    /// est émis *avant* la mutation, on lirait donc l'ancienne valeur, et il se
    /// déclencherait à chaque tic de seconde pour rien.
    private func bindActivitySources() {
        let timerActive = services.pomodoro.$phase.map { $0 != .idle }
        let shelfFilled = services.shelf.$items.map { !$0.isEmpty }

        timerActive.combineLatest(shelfFilled)
            .removeDuplicates { $0 == $1 }
            .receive(on: RunLoop.main)
            .sink { [weak self] timer, hasFiles in
                guard let self else { return }
                // Même ressort que le dépliage : l'anneau ou la pastille qui
                // apparaissent tout seuls méritent la même ouverture en douceur que
                // celle qu'on obtient au survol, pas un saut sec.
                withAnimation(NotchAnimation.spring) {
                    self.state.hasActivity = timer || hasFiles
                    // Seule la pastille de fichiers réclame plus que le trait de l'anneau.
                    self.state.activeSideInset = hasFiles
                        ? NotchMetrics.badgeSideInset
                        : NotchMetrics.horizontalExpand
                }
            }
            .store(in: &cancellables)
    }

    // MARK: Dépliage

    func expand() {
        guard !state.isExpanded else { return }
        services.media.setExpanded(true)
        applyFrame(for: .expanded, animateContent: true) { self.state.isExpanded = true }
    }

    func collapse() {
        guard state.isExpanded else { return }
        services.media.setExpanded(false)
        let target: NotchPresentation = state.hasActivity ? .active : .resting
        applyFrame(for: target, animateContent: true) { self.state.isExpanded = false }
    }

    func toggle() {
        state.isExpanded ? collapse() : expand()
    }

    /// Ouvre le panneau sur un onglet donné (depuis le menu de la barre d'état).
    func reveal(tab: NotchTab) {
        state.tab = tab
        expand()
        hoverMonitor?.forceInside()
    }

    /// Ajuste la fenêtre puis le contenu, ou l'inverse selon le sens.
    ///
    /// En agrandissement, la fenêtre grandit **avant** l'animation : le surplus est
    /// transparent, rien ne saute à l'écran, et SwiftUI anime le contenu dans une
    /// fenêtre déjà à la bonne taille. En rétrécissement, l'ordre s'inverse — sinon
    /// la fin de l'animation serait rognée par les bords de la fenêtre. Animer le
    /// cadre de la fenêtre lui-même produirait des à-coups.
    private func applyFrame(for presentation: NotchPresentation,
                            animateContent: Bool,
                            mutate: (() -> Void)? = nil) {
        guard let metrics = state.metrics, let panel else { return }

        shrinkWork?.cancel()
        shrinkWork = nil

        let target = metrics.windowFrame(for: presentation, activeSideInset: state.activeSideInset)
        let grows = target.height > panel.frame.height || target.width > panel.frame.width

        if grows {
            panel.setFrame(target, display: true)
        }

        if animateContent {
            withAnimation(NotchAnimation.spring) { mutate?() }
        } else {
            mutate?()
        }

        if !grows {
            let work = DispatchWorkItem { [weak self] in
                guard let self, let panel = self.panel, let metrics = self.state.metrics else { return }
                // La présentation a pu changer entre-temps : on recalcule au lieu de
                // réutiliser un cadre périmé.
                panel.setFrame(metrics.windowFrame(for: self.state.presentation, activeSideInset: self.state.activeSideInset), display: true)
            }
            shrinkWork = work
            // Sans animation de contenu, rien ne justifie d'attendre : le cadre doit
            // rétrécir tout de suite, pas après le délai prévu pour un ressort qui
            // n'a pas eu lieu.
            let delay = NotchMotion.isReduced ? 0 : NotchAnimation.duration + 0.05
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        }
    }

    // MARK: Changements d'écran

    @objc private func screenParametersChanged() {
        rebuildGeometry()
        guard let metrics = state.metrics else { return }
        panel?.setFrame(metrics.windowFrame(for: state.presentation, activeSideInset: state.activeSideInset), display: true)
    }
}

// MARK: - Dépôt de fichiers

extension NotchController: NotchDropHandling {

    func notchDragEntered() -> Bool {
        state.isDropTarget = true
        // Le panneau s'ouvre de lui-même : le moniteur de survol observe aussi les
        // événements de glisser. On se contente d'amener l'étagère au premier plan
        // pour que l'utilisateur voie où son fichier va atterrir.
        state.tab = .shelf
        hoverMonitor?.forceInside()
        return true
    }

    func notchDragExited() {
        state.isDropTarget = false
    }

    func notchPerformDrop(_ dragging: NSDraggingInfo) -> Bool {
        state.isDropTarget = false
        let pasteboard = dragging.draggingPasteboard

        // Cas courant : le fichier existe déjà sur le disque (Finder, éditeurs…).
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL],
           !urls.isEmpty {
            urls.forEach { services.shelf.add(url: $0) }
            return true
        }

        // Cas des promesses : le contenu n'existe pas encore (glisser depuis un
        // navigateur, une pièce jointe). Il faut le matérialiser nous-mêmes.
        return receivePromises(from: pasteboard)
    }

    private func receivePromises(from pasteboard: NSPasteboard) -> Bool {
        guard let receivers = pasteboard.readObjects(forClasses: [NSFilePromiseReceiver.self],
                                                     options: nil) as? [NSFilePromiseReceiver],
              !receivers.isEmpty else {
            return false
        }

        let destination = services.shelf.copiesDirectory
        try? FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

        let queue = OperationQueue()
        for receiver in receivers {
            receiver.receivePromisedFiles(atDestination: destination,
                                          options: [:],
                                          operationQueue: queue) { url, error in
                guard error == nil else { return }
                Task { @MainActor [weak self] in
                    self?.services.shelf.add(url: url, isCopy: true)
                }
            }
        }
        return true
    }
}
