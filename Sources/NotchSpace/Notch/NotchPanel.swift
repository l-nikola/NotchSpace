import AppKit
import SwiftUI

/// Fenêtre de l'encoche.
///
/// `.nonactivatingPanel` est le point clé : cliquer dans l'encoche ne fait jamais
/// passer NotchSpace au premier plan. L'app sur laquelle on travaille garde le focus —
/// indispensable pour un outil de concentration.
final class NotchPanel: NSPanel {

    init(contentRect: CGRect) {
        super.init(contentRect: contentRect,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovableByWindowBackground = false
        isMovable = false
        acceptsMouseMovedEvents = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false

        // 25, juste au-dessus de la barre de menus (24) : l'encoche passe par-dessus
        // les menus sans pour autant masquer les alertes système.
        level = .statusBar

        // Présente sur tous les bureaux, y compris par-dessus une app en plein écran,
        // et jamais déplacée par Mission Control.
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
    }

    // Peut devenir key (pour que boutons et sliders réagissent) sans activer l'app.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Ce que la vue hôte demande au contrôleur pendant un glisser-déposer.
@MainActor
protocol NotchDropHandling: AnyObject {
    /// Appelé quand un glisser entre dans l'encoche. Renvoie `false` pour laisser
    /// passer le glisser.
    func notchDragEntered() -> Bool
    func notchDragExited()
    func notchPerformDrop(_ dragging: NSDraggingInfo) -> Bool
}

/// Vue hôte SwiftUI qui laisse passer les clics hors de la coquille visible, et qui
/// sert de cible aux glisser-déposer.
///
/// Sans le filtrage des clics, la fenêtre — rectangulaire et plus grande que la forme
/// dessinée — avalerait ceux qui tombent dans ses coins transparents, y compris ceux
/// destinés à la barre de menus.
final class NotchHostingView<Content: View>: NSHostingView<Content> {

    /// Taille de la coquille effectivement dessinée. Elle est ancrée en haut et
    /// centrée horizontalement dans la vue.
    var shellSizeProvider: () -> CGSize = { .zero }

    weak var dropHandler: (any NotchDropHandling)?

    /// Coquille dans le repère de cette vue, sans supposer son orientation :
    /// `NSHostingView` est normalement flippée, mais on ne s'y fie pas.
    var shellRect: CGRect {
        let shell = shellSizeProvider()
        guard shell.width > 0, shell.height > 0 else { return .zero }
        let x = (bounds.width - shell.width) / 2
        let y = isFlipped ? 0 : bounds.height - shell.height
        return CGRect(x: x, y: y, width: shell.width, height: shell.height)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = superview.map { convert(point, from: $0) } ?? point
        guard shellRect.contains(local) else { return nil }
        return super.hitTest(point)
    }

    // MARK: Glisser-déposer

    /// Types acceptés : les URL de fichiers couvrent le Finder et la plupart des apps,
    /// les promesses couvrent les glissers depuis un navigateur, où le fichier
    /// n'existe pas encore sur le disque au moment du dépôt.
    static var acceptedDragTypes: [NSPasteboard.PasteboardType] {
        [.fileURL, NSPasteboard.PasteboardType(rawValue: "com.apple.pasteboard.promised-file-url")]
    }

    func enableDrops() {
        registerForDraggedTypes(Self.acceptedDragTypes)
        DebugLog.write("types enregistrés : \(registeredDraggedTypes.map(\.rawValue))")
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        DebugLog.write("draggingEntered")
        return dropHandler?.notchDragEntered() == true ? .copy : []
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        // La fenêtre est petite au repos et couvre exactement l'encoche : tout ce qui
        // arrive ici vise bien l'encoche, il n'y a pas de zone morte à écarter.
        // Pas de journalisation ici — cette méthode est appelée en continu.
        .copy
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        DebugLog.write("draggingExited")
        dropHandler?.notchDragExited()
    }

    override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        DebugLog.write("prepareForDragOperation types=\(sender.draggingPasteboard.types?.map(\.rawValue) ?? [])")
        return true
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        let accepted = dropHandler?.notchPerformDrop(sender) ?? false
        DebugLog.write("performDragOperation accepted=\(accepted)")
        return accepted
    }

    override func concludeDragOperation(_ sender: (any NSDraggingInfo)?) {
        dropHandler?.notchDragExited()
    }
}
