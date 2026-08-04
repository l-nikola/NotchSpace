import SwiftUI

/// Trois barres qui montent et descendent pendant la lecture.
///
/// Purement décoratif : Chrome comme Spotify ne donnent aucun niveau audio réel.
/// L'animation s'arrête en pause, ce qui suffit à distinguer les deux états d'un
/// coup d'œil — moins encombrant qu'un second symbole lecture/pause à côté du bouton
/// qui en porte déjà un.
struct EqualizerBars: View {
    let isAnimating: Bool
    /// Couleur de la source en lecture : les barres empruntent son identité plutôt
    /// que de rester un simple témoin d'activité anonyme.
    var tint: Color = .white

    private let heights: [CGFloat] = [7, 12, 9]
    private let delays: [Double] = [0, 0.18, 0.36]

    @State private var phase = false

    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(0..<3, id: \.self) { index in
                Capsule()
                    .fill(tint.opacity(isAnimating ? 0.75 : 0.35))
                    .frame(width: 2.5,
                           height: barHeight(index))
                    // La boucle perpétuelle est le cas d'école de « Réduire le
                    // mouvement » : elle s'arrête, et les barres retombent sur la
                    // hauteur statique qui distingue déjà lecture et pause.
                    .animation(.reduced(isAnimating
                               ? .easeInOut(duration: 0.5).repeatForever().delay(delays[index])
                               : .easeOut(duration: 0.25)),
                               value: phase)
            }
        }
        .frame(height: 14)
        .onAppear { phase = isAnimating }
        .onChange(of: isAnimating) { _, running in
            phase = running
        }
    }

    /// En pause, les barres gardent leur silhouette en réduction plutôt que de
    /// s'écraser à l'identique : trois points de même taille alignés se lisaient comme
    /// des points de suspension, surtout posés juste avant un titre.
    private func barHeight(_ index: Int) -> CGFloat {
        guard isAnimating else { return heights[index] * 0.55 }
        return phase ? heights[index] : 3
    }
}
