import SwiftUI

/// Racine SwiftUI affichée dans la fenêtre de l'encoche.
///
/// La coquille est ancrée en haut et centrée : la fenêtre est plus grande que la
/// forme dessinée pour laisser la place au trait de l'anneau.
struct NotchRootView: View {
    let services: Services
    @ObservedObject var state: NotchState

    var body: some View {
        VStack(spacing: 0) {
            NotchShell(state: state) {
                if state.isExpanded {
                    ExpandedContent(services: services, state: state)
                        .transition(.opacity)
                } else {
                    CollapsedContent(services: services, state: state)
                        .transition(.opacity)
                }
            }
            .frame(width: state.shellSize.width, height: state.shellSize.height)
            .opacity(state.isShellHidden ? 0 : 1)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, NotchMetrics.windowPadding)
        .padding(.bottom, NotchMetrics.windowPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

/// La forme noire elle-même : fond opaque qui fusionne avec l'encoche, plus le contenu.
///
/// Le contenu n'est pas rembourré ici — l'anneau doit pouvoir se tracer exactement
/// sur le contour, tandis que le panneau déplié applique ses propres marges.
struct NotchShell<Content: View>: View {
    @ObservedObject var state: NotchState
    @ViewBuilder var content: Content

    private var shape: NotchOutlineShape {
        NotchOutlineShape(bottomRadius: state.isExpanded ? 24 : NotchMetrics.bottomRadius,
                          topRadius: state.isExpanded ? 10 : NotchMetrics.topRadius)
    }

    var body: some View {
        ZStack {
            // Noir plein : c'est ce qui donne l'illusion que l'encoche s'agrandit.
            shape.fill(.black)

            // Liseré discret quand le panneau est ouvert, pour décoller la forme du
            // fond sur un fond d'écran sombre.
            if state.isExpanded {
                shape.insetStroke(.white.opacity(0.09), lineWidth: 1)
            }

            content
        }
    }
}

extension NotchOutlineShape {
    /// `Shape` ne fournit pas `strokeBorder` : on rentre le tracé d'une demi-épaisseur
    /// pour que le trait reste à l'intérieur de la forme.
    func insetStroke(_ color: Color, lineWidth: CGFloat) -> some View {
        GeometryReader { proxy in
            path(in: CGRect(origin: .zero, size: proxy.size)
                .insetBy(dx: lineWidth / 2, dy: lineWidth / 2))
                .stroke(color, lineWidth: lineWidth)
        }
    }
}
