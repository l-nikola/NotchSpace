import AppKit

struct ShelfItem: Identifiable, Codable, Equatable {
    let id: UUID
    var url: URL
    var name: String
    var addedAt: Date
    /// Vrai quand le contenu a été copié dans le dossier de l'étagère (glisser depuis
    /// un navigateur, une pièce jointe…). Ces copies nous appartiennent : on les
    /// supprime en retirant l'élément.
    var isCopy: Bool

    var exists: Bool { FileManager.default.fileExists(atPath: url.path) }
}

/// Étagère de fichiers en transit.
///
/// Les vrais fichiers sont conservés **par référence** : copier ce que l'utilisateur
/// dépose doublerait l'espace disque et créerait deux versions divergentes d'un même
/// document. Seuls les contenus sans fichier source stable (promesses de glisser
/// depuis un navigateur) sont matérialisés dans le dossier de l'étagère.
@MainActor
final class ShelfStore: ObservableObject {

    @Published private(set) var items: [ShelfItem] = []

    private let settings: AppSettings
    private let fileManager = FileManager.default
    private let supportDirectory: URL

    /// `rootDirectory` permet aux tests d'isoler l'étagère : sans lui, l'index et les
    /// copies vivraient dans le vrai dossier de l'utilisateur, et `removeAll()` viderait
    /// sa véritable étagère à chaque exécution de `--self-test`.
    init(settings: AppSettings, rootDirectory: URL? = nil) {
        self.settings = settings
        if let rootDirectory {
            self.supportDirectory = rootDirectory
        } else {
            let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            self.supportDirectory = base.appendingPathComponent("NotchSpace", isDirectory: true)
        }
        load()
        purgeExpired()
    }

    // MARK: Emplacements

    private var indexURL: URL { supportDirectory.appendingPathComponent("shelf.json") }
    var copiesDirectory: URL { supportDirectory.appendingPathComponent("Shelf", isDirectory: true) }

    // MARK: Contenu

    @discardableResult
    func add(url: URL, isCopy: Bool = false) -> Bool {
        // Un même fichier déposé deux fois remonte en tête plutôt que de s'empiler.
        if let index = items.firstIndex(where: { $0.url == url }) {
            items[index].addedAt = Date()
            items.sort { $0.addedAt > $1.addedAt }
            save()
            return true
        }

        let item = ShelfItem(id: UUID(),
                             url: url,
                             name: url.lastPathComponent,
                             addedAt: Date(),
                             isCopy: isCopy)
        items.insert(item, at: 0)
        save()
        return true
    }

    /// Matérialise un contenu sans fichier source dans le dossier de l'étagère.
    func addCopy(data: Data, preferredName: String) -> Bool {
        do {
            try fileManager.createDirectory(at: copiesDirectory, withIntermediateDirectories: true)
            let destination = uniqueURL(for: preferredName, in: copiesDirectory)
            try data.write(to: destination)
            return add(url: destination, isCopy: true)
        } catch {
            return false
        }
    }

    func remove(_ item: ShelfItem) {
        items.removeAll { $0.id == item.id }
        // Seules nos propres copies sont effacées : supprimer un fichier de
        // l'utilisateur parce qu'il quitte l'étagère serait une très mauvaise surprise.
        if item.isCopy {
            try? fileManager.removeItem(at: item.url)
        }
        save()
    }

    func removeAll() {
        items.filter(\.isCopy).forEach { try? fileManager.removeItem(at: $0.url) }
        items.removeAll()
        save()
    }

    func revealInFinder(_ item: ShelfItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    private func uniqueURL(for name: String, in directory: URL) -> URL {
        var candidate = directory.appendingPathComponent(name)
        var index = 2
        let base = candidate.deletingPathExtension().lastPathComponent
        let ext = candidate.pathExtension
        while fileManager.fileExists(atPath: candidate.path) {
            let numbered = ext.isEmpty ? "\(base) \(index)" : "\(base) \(index).\(ext)"
            candidate = directory.appendingPathComponent(numbered)
            index += 1
        }
        return candidate
    }

    // MARK: Entretien

    /// Retire les éléments périmés et ceux dont le fichier a disparu entre-temps
    /// (déplacé, renommé, jeté à la corbeille).
    func purgeExpired() {
        let days = max(0, settings.shelfRetentionDays)
        let cutoff = Date().addingTimeInterval(-Double(days) * 86_400)

        let expired = items.filter { item in
            (days > 0 && item.addedAt < cutoff) || !item.exists
        }
        guard !expired.isEmpty else { return }
        expired.forEach(remove)
    }

    // MARK: Persistance

    private func load() {
        guard let data = try? Data(contentsOf: indexURL),
              let decoded = try? JSONDecoder().decode([ShelfItem].self, from: data) else {
            return
        }
        items = decoded.sorted { $0.addedAt > $1.addedAt }
    }

    private func save() {
        do {
            try fileManager.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(items)
            try data.write(to: indexURL, options: .atomic)
        } catch {
            // L'étagère reste utilisable en mémoire même si l'index ne s'écrit pas ;
            // faire échouer le dépôt pour autant serait disproportionné.
        }
    }
}
