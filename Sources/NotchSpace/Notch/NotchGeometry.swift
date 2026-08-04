import AppKit

/// Présentation courante de la coquille.
enum NotchPresentation {
    /// Rien en cours : la coquille épouse exactement l'encoche, donc elle est
    /// invisible (elle tombe dans la zone sans pixels). L'encoche reste l'encoche.
    case resting
    /// Minuteur ou lecture en cours : la coquille déborde pour porter l'anneau.
    case active
    /// Panneau ouvert.
    case expanded
}

/// Mesures de l'encoche pour un écran donné.
///
/// Piège central de tout ce projet : `NSScreen.frame` **inclut** la zone de l'encoche,
/// mais cette zone n'a physiquement aucun pixel. Dessiner exactement sur `notchRect`
/// revient à dessiner dans le vide — rien ne s'affiche.
///
/// On dessine donc une coquille plus large et plus basse que l'encoche physique, sur
/// les pixels visibles qui l'entourent. Le noir de la coquille fusionne avec le noir
/// de l'encoche et donne l'illusion que l'encoche s'est agrandie ; c'est aussi ce qui
/// offre à l'anneau de progression une surface réellement visible.
struct NotchMetrics: Equatable {
    /// L'encoche physique, en coordonnées écran AppKit (origine en bas à gauche).
    let notchRect: CGRect
    /// Cadre de l'écran concerné.
    let screenFrame: CGRect
    /// `false` quand on retombe sur une pilule virtuelle (écran externe, Mac sans encoche).
    let hasRealNotch: Bool

    // MARK: Constantes de dessin

    /// Rayon des raccords concaves supérieurs, à l'état replié.
    static let topRadius: CGFloat = 6
    /// Rayon des coins inférieurs, à l'état replié.
    static let bottomRadius: CGFloat = 9
    /// Marge visible entre le bord de l'encoche et le bord de la coquille.
    ///
    /// C'est la bande de vrais pixels sur laquelle l'anneau de progression est tracé.
    /// Elle doit rester supérieure à la moitié de l'épaisseur du trait — à 4 pt pour un
    /// trait de 1,5, il reste plus de 3 pt de marge, largement de quoi absorber
    /// l'antialiasing.
    static let ringMargin: CGFloat = 4

    /// Débord horizontal total de chaque côté.
    ///
    /// Les côtés de la forme se trouvent à `topRadius` du bord du rect (c'est la
    /// géométrie de `NotchOutlineShape`) : il faut donc ajouter le rayon à la marge,
    /// sinon les côtés retombent **à l'intérieur** de l'encoche et l'anneau disparaît.
    static let horizontalExpand: CGFloat = topRadius + ringMargin
    /// Débord vertical sous l'encoche. Le haut reste collé au bord de l'écran.
    static let verticalExpand: CGFloat = 4
    /// Débord latéral quand une pastille doit tenir dans la bande de gauche.
    ///
    /// Juste assez pour la loger **en dehors** du trait de l'anneau, qui occupe déjà
    /// les premiers points de la bande.
    static let badgeSideInset: CGFloat = 28
    /// Marge intérieure de la fenêtre, pour le trait de l'anneau et sa lueur.
    static let windowPadding: CGFloat = 16
    /// Taille du panneau déplié (hors `windowPadding`).
    ///
    /// La largeur est dictée par la bande du bas — onglets et transport côte à côte —,
    /// la hauteur par le plus haut des trois onglets, l'étagère et ses vignettes.
    static let expandedSize = CGSize(width: 620, height: 178)

    /// `sideInset` est le débord de chaque côté de l'encoche à l'état actif.
    ///
    /// Il varie selon ce qu'on affiche : l'anneau seul se contente de la marge
    /// minimale, une pastille de fichiers réclame une bande un peu plus large.
    func shellSize(for presentation: NotchPresentation,
                   activeSideInset: CGFloat = horizontalExpand) -> CGSize {
        switch presentation {
        case .resting:
            // Exactement l'encoche : dessiné dans la zone sans pixels, donc invisible.
            return notchRect.size
        case .active:
            return CGSize(width: notchRect.width + 2 * max(Self.horizontalExpand, activeSideInset),
                          height: notchRect.height + Self.verticalExpand)
        case .expanded:
            return Self.expandedSize
        }
    }

    /// Cadre de la fenêtre en coordonnées écran, ancré en haut et centré sur l'encoche.
    ///
    /// La fenêtre est dimensionnée à l'état courant plutôt que maintenue en grand :
    /// une grande fenêtre transparente en permanence intercepterait les clics de la
    /// barre de menus et les glisser-déposer vers le bureau.
    func windowFrame(for presentation: NotchPresentation,
                     activeSideInset: CGFloat = horizontalExpand) -> CGRect {
        let shell = shellSize(for: presentation, activeSideInset: activeSideInset)
        let width = shell.width + 2 * Self.windowPadding
        let height = shell.height + Self.windowPadding
        return CGRect(x: notchRect.midX - width / 2,
                      y: screenFrame.maxY - height,
                      width: width,
                      height: height)
    }

    /// Zone qui déclenche le dépliage au survol.
    ///
    /// Volontairement un peu plus généreuse que l'encoche vers le bas, pour ne pas
    /// obliger à viser une bande de 32 pt — mais sans mordre sur les menus voisins.
    var hoverZone: CGRect {
        CGRect(x: notchRect.minX - Self.horizontalExpand,
               y: notchRect.minY - Self.verticalExpand,
               width: notchRect.width + 2 * Self.horizontalExpand,
               height: notchRect.height + Self.verticalExpand)
    }
}

enum NotchGeometry {

    /// Écran à utiliser : celui qui porte une encoche, sinon l'écran principal.
    static func targetScreen() -> NSScreen? {
        NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main
    }

    static func metrics(for screen: NSScreen) -> NotchMetrics {
        let frame = screen.frame

        // Sur un Mac à encoche, `auxiliaryTopLeftArea` et `auxiliaryTopRightArea`
        // décrivent les deux moitiés de barre de menus de part et d'autre de l'encoche.
        // Ce qui reste entre les deux, c'est l'encoche.
        if let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea,
           screen.safeAreaInsets.top > 0 {
            let width = frame.width - left.width - right.width
            if width > 0 {
                let height = screen.safeAreaInsets.top
                let rect = CGRect(x: frame.minX + left.width,
                                  y: frame.maxY - height,
                                  width: width,
                                  height: height)
                return NotchMetrics(notchRect: rect, screenFrame: frame, hasRealNotch: true)
            }
        }

        // Repli : pilule virtuelle centrée en haut, aux proportions d'une vraie encoche.
        let width: CGFloat = 185
        let height: CGFloat = 32
        let rect = CGRect(x: frame.midX - width / 2,
                          y: frame.maxY - height,
                          width: width,
                          height: height)
        return NotchMetrics(notchRect: rect, screenFrame: frame, hasRealNotch: false)
    }

    static func currentMetrics() -> NotchMetrics? {
        targetScreen().map(metrics(for:))
    }
}
