import AppKit
import Combine

/// Agrège les sources média et décide laquelle afficher.
@MainActor
final class MediaController: ObservableObject {

    @Published private(set) var nowPlaying: NowPlaying?
    @Published private(set) var artwork: NSImage?
    /// Un onglet YouTube est ouvert mais Chrome refuse d'exécuter du JavaScript.
    @Published private(set) var chromeNeedsJavaScript = false
    /// L'autorisation Automation n'a pas été accordée : sans elle, aucune source ne
    /// peut répondre, et il faut le dire plutôt que d'afficher « rien en lecture ».
    @Published private(set) var needsAutomationPermission = false

    private let settings: AppSettings
    private let spotify = SpotifySource()
    private let chrome = ChromeSource()
    private let artworkCache = ArtworkCache()

    private var timer: Timer?
    private var currentInterval: TimeInterval = 0
    private var isExpanded = false
    private var pendingSpotifyRefresh: DispatchWorkItem?
    private var cancellables = Set<AnyCancellable>()

    init(settings: AppSettings) {
        self.settings = settings
    }

    // MARK: Cycle de vie

    func start() {
        spotify.startObserving { [weak self] in
            self?.scheduleSpotifyRefresh()
        }

        settings.$mediaEnabled
            .removeDuplicates()
            .sink { [weak self] enabled in
                guard let self else { return }
                if enabled {
                    self.refreshAll()
                    self.rescheduleTimer()
                } else {
                    self.clear()
                    self.stopTimer()
                }
            }
            .store(in: &cancellables)

        refreshAll()
        rescheduleTimer()
    }

    func stop() {
        spotify.stopObserving()
        stopTimer()
        pendingSpotifyRefresh?.cancel()
        cancellables.removeAll()
    }

    /// La cadence suit l'attention portée à l'app : serrée panneau ouvert, lâche
    /// quand rien n'est visible.
    func setExpanded(_ expanded: Bool) {
        guard isExpanded != expanded else { return }
        isExpanded = expanded
        if expanded { refreshAll() }
        rescheduleTimer()
    }

    // MARK: Cadence

    private var desiredInterval: TimeInterval {
        if isExpanded { return 2 }
        if nowPlaying?.isPlaying == true { return 5 }
        return 12
    }

    private func rescheduleTimer() {
        guard settings.mediaEnabled else { return }
        let interval = desiredInterval
        guard interval != currentInterval else { return }

        stopTimer()
        currentInterval = interval
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshAll() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
        currentInterval = 0
    }

    /// Spotify émet plusieurs notifications d'affilée sur un changement de piste ;
    /// on regroupe pour n'interroger qu'une fois.
    private func scheduleSpotifyRefresh() {
        pendingSpotifyRefresh?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.refreshAll() }
        pendingSpotifyRefresh = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    // MARK: Interrogation

    private func refreshAll() {
        guard settings.mediaEnabled else { return }

        var spotifyResult: NowPlaying?
        var chromeResult: NowPlaying?
        var chromeBlocked = false
        var denied = false
        let group = DispatchGroup()

        group.enter()
        spotify.refresh { result in
            switch result {
            case .success(let track): spotifyResult = track
            case .failure(let failure): denied = denied || failure.isAuthorizationDenial
            }
            group.leave()
        }

        if settings.chromeEnabled {
            group.enter()
            chrome.refresh { outcome in
                switch outcome {
                case .track(let track): chromeResult = track
                case .javaScriptDisabled: chromeBlocked = true
                case .notAuthorized: denied = true
                case .noTab: break
                }
                group.leave()
            }
        }

        group.notify(queue: .main) { [weak self] in
            guard let self else { return }
            self.chromeNeedsJavaScript = chromeBlocked
            self.needsAutomationPermission = denied
            self.apply(candidates: [spotifyResult, chromeResult].compactMap { $0 })
        }
    }

    /// Choisit la source à afficher.
    ///
    /// Ce qui joue l'emporte sur ce qui est en pause. À égalité, on garde la source
    /// déjà affichée : sans cette préférence, deux lecteurs en pause feraient
    /// clignoter l'encoche d'une source à l'autre à chaque cycle.
    private func apply(candidates: [NowPlaying]) {
        let playing = candidates.filter(\.isPlaying)
        let pool = playing.isEmpty ? candidates : playing

        let chosen = pool.first(where: { $0.source == nowPlaying?.source })
            ?? pool.first(where: { $0.source == .spotify })
            ?? pool.first

        guard let chosen else {
            clear()
            rescheduleTimer()
            return
        }

        let changed = !chosen.isSameContent(as: nowPlaying)
        nowPlaying = chosen

        if changed { loadArtwork(for: chosen) }
        rescheduleTimer()
    }

    private func loadArtwork(for track: NowPlaying) {
        guard let url = track.artworkURL else {
            artwork = nil
            return
        }
        if let cached = artworkCache.cached(for: url) {
            artwork = cached
            return
        }
        // On efface tout de suite : garder la pochette précédente sous un nouveau
        // titre est plus trompeur qu'un carré vide le temps du téléchargement.
        artwork = nil
        artworkCache.load(url) { [weak self] image in
            guard let self, self.nowPlaying?.artworkURL == url else { return }
            self.artwork = image
        }
    }

    private func clear() {
        nowPlaying = nil
        artwork = nil
    }

    // MARK: Commandes

    func playPause() { withActiveSource { $0.playPause() } }
    func next() { withActiveSource { $0.next() } }
    func previous() { withActiveSource { $0.previous() } }

    private func withActiveSource(_ action: (MediaCommandTarget) -> Void) {
        guard let source = nowPlaying?.source else { return }
        switch source {
        case .spotify: action(spotify)
        case .chrome: action(chrome)
        }
        // La commande met un instant à prendre effet côté app : on relit juste après
        // plutôt que d'attendre le prochain tic.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.refreshAll()
        }
    }
}

/// Dénominateur commun des sources pilotables.
@MainActor
protocol MediaCommandTarget {
    func playPause()
    func next()
    func previous()
}

extension SpotifySource: MediaCommandTarget {}
extension ChromeSource: MediaCommandTarget {}
