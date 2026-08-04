import SwiftUI
import UniformTypeIdentifiers

/// Onglet Étagère du panneau déplié.
struct ShelfPanel: View {
    let services: Services
    @ObservedObject private var shelf: ShelfStore

    init(services: Services) {
        self.services = services
        self.shelf = services.shelf
    }

    var body: some View {
        Group {
            if shelf.items.isEmpty {
                PlaceholderPanel(symbol: "tray",
                                 text: "Déposez des fichiers sur l'encoche pour les garder sous la main")
            } else {
                content
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(shelf.items.count) fichier\(shelf.items.count > 1 ? "s" : "")")
                    .font(.notchCaption)
                    .foregroundStyle(.white.opacity(0.4))
                Spacer()
                ClearShelfButton(shelf: shelf) {
                    Text("Tout vider")
                        .font(.notchCaption)
                        .foregroundStyle(.white.opacity(0.45))
                }
                .buttonStyle(.plain)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(shelf.items) { item in
                        ShelfTile(item: item,
                                  onRemove: { shelf.remove(item) },
                                  onReveal: { shelf.revealInFinder(item) })
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }
}

/// Vide l'étagère — sans interruption si elle ne contient que des références, avec
/// confirmation nommant la conséquence si elle contient des copies.
///
/// « Tout vider » supprimait ces copies pour de bon (pas même une Corbeille) sans
/// jamais le dire : le libellé se lisait comme un simple oubli de la liste. Les
/// références vers des fichiers de l'utilisateur, elles, ne risquent rien — leur
/// retrait ne mérite pas une interruption.
struct ClearShelfButton<Label: View>: View {
    @ObservedObject var shelf: ShelfStore
    @ViewBuilder var label: () -> Label

    @State private var isConfirmingDeletion = false

    var body: some View {
        Button {
            if shelf.items.contains(where: \.isCopy) {
                isConfirmingDeletion = true
            } else {
                shelf.removeAll()
            }
        } label: {
            label()
        }
        .confirmationDialog("Vider l'étagère ?",
                             isPresented: $isConfirmingDeletion,
                             titleVisibility: .visible) {
            Button("Vider et supprimer les fichiers copiés", role: .destructive) {
                shelf.removeAll()
            }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("""
            Les fichiers glissés depuis un navigateur ont été copiés dans l'étagère : \
            les retirer les supprime pour de bon. Les fichiers déposés depuis le \
            Finder ne sont que des références et restent à leur emplacement d'origine.
            """)
        }
    }
}

/// Une vignette de l'étagère, que l'on peut glisser vers le Finder ou une autre app.
struct ShelfTile: View {
    let item: ShelfItem
    let onRemove: () -> Void
    let onReveal: () -> Void

    @State private var isHovered = false

    var body: some View {
        VStack(spacing: 4) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                .resizable()
                .frame(width: 32, height: 32)

            Text(item.name)
                .font(.notchMicro)
                .foregroundStyle(.white.opacity(0.65))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 66)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 6)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.white.opacity(isHovered ? 0.12 : 0.05))
        }
        .overlay(alignment: .topTrailing) {
            if isHovered {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.7), .black.opacity(0.5))
                }
                .buttonStyle(.plain)
                .offset(x: 2, y: -2)
            }
        }
        .onHover { isHovered = $0 }
        .onTapGesture(count: 2) { onReveal() }
        // Glisser une vignette vers le Finder ressort le fichier : c'est tout
        // l'intérêt de l'étagère comme relais.
        .onDrag {
            NSItemProvider(contentsOf: item.url) ?? NSItemProvider()
        }
        .help(item.url.path)
        // Le bouton de retrait n'existe qu'au survol : sans ce menu, personne au
        // clavier ou en VoiceOver ne pourrait retirer un seul élément sans tout vider.
        .contextMenu {
            Button("Afficher dans le Finder", action: onReveal)
            Button("Retirer de l'étagère", action: onRemove)
        }
    }
}
