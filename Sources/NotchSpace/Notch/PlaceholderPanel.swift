import SwiftUI

/// État vide d'un onglet du panneau.
struct PlaceholderPanel: View {
    let symbol: String
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 13))
            Text(text)
                .font(.system(size: 12))
        }
        .foregroundStyle(.white.opacity(0.35))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
