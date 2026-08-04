import SwiftUI

/// Ce qui reste visible quand le panneau est fermé.
///
/// Le parti pris est celui du silence : la coquille repliée ne montre que ce qui
/// avance tout seul et qu'on ne peut pas voir autrement. Le minuteur y a droit — sa
/// progression est le sujet même de l'app —, l'étagère se contente d'une pastille
/// parce qu'un fichier oublié là ne se rappelle à personne. La lecture en cours, elle,
/// n'y figure plus : la pochette occupait une large bande à côté de l'encoche pour
/// répéter ce que le lecteur affiche déjà.
struct CollapsedContent: View {
    let services: Services
    @ObservedObject var state: NotchState
    @ObservedObject private var pomodoro: PomodoroEngine
    @ObservedObject private var shelf: ShelfStore

    init(services: Services, state: NotchState) {
        self.services = services
        self.state = state
        self.pomodoro = services.pomodoro
        self.shelf = services.shelf
    }

    var body: some View {
        ZStack {
            if !shelf.items.isEmpty {
                ShelfBadge(count: shelf.items.count, sideInset: state.activeSideInset)
            }

            if pomodoro.isActive {
                PomodoroRing(progress: pomodoro.progress,
                             phase: pomodoro.phase,
                             isRunning: pomodoro.isRunning)
            }

            if state.isDropTarget {
                DropHighlight()
            }
        }
    }
}

/// Pastille discrète rappelant que des fichiers attendent dans l'étagère.
struct ShelfBadge: View {
    let count: Int
    let sideInset: CGFloat

    /// Largeur approchée de la pastille, pour la centrer dans sa bande.
    private let width: CGFloat = 20

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "tray.full.fill")
                .font(.system(size: 8))
            Text("\(count)")
                .font(.system(size: 9, weight: .semibold))
                .monospacedDigit()
        }
        .foregroundStyle(.white.opacity(0.7))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, leading)
    }

    /// Centrée dans la bande de gauche, mais après le trait de l'anneau : la bande
    /// utile commence au côté de la forme, pas au bord de la coquille.
    private var leading: CGFloat {
        let start = NotchMetrics.topRadius + 2
        return start + max(0, (sideInset - start - width) / 2)
    }
}

/// Liseré affiché pendant qu'un glisser survole l'encoche.
struct DropHighlight: View {
    var body: some View {
        NotchOutlineShape(bottomRadius: NotchMetrics.bottomRadius,
                          topRadius: NotchMetrics.topRadius,
                          closed: false)
            .stroke(Color.accentColor.opacity(0.9),
                    style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [5, 4]))
            .allowsHitTesting(false)
    }
}
