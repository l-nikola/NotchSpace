import SwiftUI

/// Silhouette d'encoche : deux raccords concaves en haut (qui creusent la barre de
/// menus), deux coins convexes en bas.
///
/// Le tracé démarre en haut à gauche et tourne dans le sens horaire. C'est ce qui
/// rend `.trim(from:to:)` utilisable tel quel pour l'anneau de progression Pomodoro :
/// la progression part du coin supérieur gauche et enrobe la forme.
///
/// La largeur du `rect` englobe les deux raccords supérieurs ; le corps de la forme
/// s'étend donc de `topRadius` à `width - topRadius`.
struct NotchOutlineShape: Shape {
    var bottomRadius: CGFloat = 13
    var topRadius: CGFloat = 8

    /// Referme le tracé par le bord supérieur.
    ///
    /// Indispensable pour remplir la forme, à proscrire pour l'anneau de progression :
    /// ce bord longe le haut de l'écran et n'est pas regardable, alors qu'il pèse près
    /// de la moitié de la longueur du tracé. Fermé, la progression semblerait se figer
    /// à mi-session. Ouvert, les 100 % de l'anneau sont visibles.
    var closed = true

    /// Interpole les rayons pendant l'animation dépliage/repliage.
    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(bottomRadius, topRadius) }
        set {
            bottomRadius = newValue.first
            topRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()

        // Garde-fous : sur une forme très petite (ou pendant une animation qui passe
        // par zéro) des rayons trop grands produisent un tracé replié sur lui-même.
        let tr = max(0, min(topRadius, rect.width / 2))
        let br = max(0, min(bottomRadius, min(rect.height, (rect.width - 2 * tr) / 2)))

        // Haut à gauche : raccord concave, du bord de l'écran vers l'intérieur.
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.minX + tr, y: rect.minY + tr),
                          control: CGPoint(x: rect.minX + tr, y: rect.minY))

        // Côté gauche, puis coin inférieur gauche convexe.
        path.addLine(to: CGPoint(x: rect.minX + tr, y: rect.maxY - br))
        path.addQuadCurve(to: CGPoint(x: rect.minX + tr + br, y: rect.maxY),
                          control: CGPoint(x: rect.minX + tr, y: rect.maxY))

        // Base, puis coin inférieur droit convexe.
        path.addLine(to: CGPoint(x: rect.maxX - tr - br, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - tr, y: rect.maxY - br),
                          control: CGPoint(x: rect.maxX - tr, y: rect.maxY))

        // Côté droit, puis raccord concave supérieur droit.
        path.addLine(to: CGPoint(x: rect.maxX - tr, y: rect.minY + tr))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY),
                          control: CGPoint(x: rect.maxX - tr, y: rect.minY))

        if closed { path.closeSubpath() }
        return path
    }
}
