import AppKit
import ImageIO

/// Taille d'affichage réelle de la pochette dans l'onglet Lecture (68 pt, à
/// l'échelle @2x) : la seule taille à laquelle l'app la montre jamais.
///
/// Hors du type isolé à l'acteur principal : lu depuis `decodeThumbnail`, appelée
/// hors thread principal par la completion de `URLSession`.
private let artworkMaxPixelSize: CGFloat = 136

/// Télécharge et conserve les pochettes.
///
/// Le cache mémoire évite de retélécharger à chaque changement d'état (pause, reprise),
/// et l'`URLCache` de la session assure la persistance sur disque sans code dédié.
@MainActor
final class ArtworkCache {

    private let memory = NSCache<NSString, NSImage>()
    private let session: URLSession
    private var inFlight: URL?

    init() {
        memory.countLimit = 24

        let configuration = URLSessionConfiguration.default
        configuration.urlCache = URLCache(memoryCapacity: 4 << 20,
                                          diskCapacity: 64 << 20,
                                          directory: Self.cacheDirectory)
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        configuration.timeoutIntervalForRequest = 10
        session = URLSession(configuration: configuration)
    }

    private static var cacheDirectory: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("NotchSpace/Artwork", isDirectory: true)
    }

    func cached(for url: URL) -> NSImage? {
        memory.object(forKey: url.absoluteString as NSString)
    }

    /// Charge la pochette et la restitue sur le thread principal.
    ///
    /// Une seule requête à la fois : les changements d'état s'enchaînent vite (pause,
    /// reprise, avance), inutile d'empiler des téléchargements pour la même image.
    func load(_ url: URL, completion: @escaping (NSImage?) -> Void) {
        if let image = cached(for: url) {
            completion(image)
            return
        }
        guard inFlight != url else { return }
        inFlight = url

        session.dataTask(with: url) { [weak self] data, _, _ in
            let image = data.flatMap(Self.decodeThumbnail)
            Task { @MainActor in
                guard let self else { return }
                self.inFlight = nil
                if let image {
                    self.memory.setObject(image, forKey: url.absoluteString as NSString)
                }
                completion(image)
            }
        }.resume()
    }

    /// Décode directement une miniature à la taille d'affichage plutôt que l'image
    /// pleine résolution que servent Spotify (640×640) ou YouTube.
    ///
    /// `CGImageSourceCreateThumbnailAtIndex` s'appuie sur la mise à l'échelle native
    /// du décodeur JPEG/PNG : la pochette pleine résolution n'est jamais matérialisée
    /// en mémoire, contrairement à un décodage complet suivi d'un redimensionnement.
    /// `nonisolated` : appelé depuis la completion de `URLSession`, hors thread
    /// principal — la fonction ne touche à aucun état de l'acteur.
    nonisolated private static func decodeThumbnail(from data: Data) -> NSImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: artworkMaxPixelSize,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }
}
