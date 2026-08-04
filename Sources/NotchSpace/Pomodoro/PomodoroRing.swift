import SwiftUI

/// Anneau de progression tracé sur le contour de la coquille.
///
/// C'est le cœur visuel de l'app : le trait suit la silhouette de l'encoche au lieu
/// d'être un cercle posé à côté. Il n'est visible que parce que la coquille déborde
/// de l'encoche physique — le trait tombe sur de vrais pixels, dans la marge
/// `NotchMetrics.ringMargin`.
struct PomodoroRing: View {
    let progress: Double
    let phase: PomodoroPhase
    let isRunning: Bool
    var bottomRadius: CGFloat = NotchMetrics.bottomRadius
    var topRadius: CGFloat = NotchMetrics.topRadius
    /// Trait fin : la coquille repliée ne déborde que de quelques points de l'encoche,
    /// et un trait épais y transformerait la progression en bandeau.
    var lineWidth: CGFloat = 1.5

    /// Tracé **ouvert** : le bord supérieur, collé au haut de l'écran, est exclu.
    /// Sinon il absorberait près de la moitié de la progression sans rien montrer.
    private var shape: NotchOutlineShape {
        NotchOutlineShape(bottomRadius: bottomRadius, topRadius: topRadius, closed: false)
    }

    private var tint: LinearGradient {
        let colors: [Color]
        switch phase {
        case .work:
            colors = [Color(red: 1.0, green: 0.42, blue: 0.36),
                      Color(red: 1.0, green: 0.62, blue: 0.32)]
        case .shortBreak:
            colors = [Color(red: 0.33, green: 0.80, blue: 0.65),
                      Color(red: 0.36, green: 0.72, blue: 0.92)]
        case .longBreak:
            colors = [Color(red: 0.45, green: 0.65, blue: 0.98),
                      Color(red: 0.65, green: 0.55, blue: 0.98)]
        case .idle:
            colors = [.gray, .gray]
        }
        return LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)
    }

    var body: some View {
        ZStack {
            // Rail : rappelle le parcours restant sans écraser la progression.
            // Un peu plus clair qu'avant, le trait ayant maigri.
            shape
                .stroke(.white.opacity(0.18), lineWidth: lineWidth)

            shape
                .trim(from: 0, to: progress)
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                // Le moteur ne tique qu'une fois par seconde : l'interpolation
                // linéaire sur exactement une seconde donne un trait qui avance en
                // continu au lieu de sauter. Volontairement pas soumis à « Réduire
                // le mouvement » : comme les indicateurs de progression système,
                // c'est de l'information (le temps passe), pas une transition
                // décorative — la couleur et l'atténuation ci-dessous, elles, le sont.
                .animation(.linear(duration: isRunning ? 1 : 0.25), value: progress)
                // Passer du travail à une pause change la teinte du dégradé : un
                // fondu la distingue du tic de chaque seconde, sans quoi la couleur
                // sauterait alors même que la progression, elle, glisse.
                .animation(.reduced(.easeInOut(duration: 0.3)), value: phase)
                .opacity(isRunning ? 1 : 0.55)
                // Même logique pour la mise en pause : le trait s'éteint au lieu de
                // s'assombrir d'un coup.
                .animation(.reduced(.easeInOut(duration: 0.25)), value: isRunning)
        }
        .allowsHitTesting(false)
    }
}
