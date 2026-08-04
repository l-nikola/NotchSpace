import AppKit

/// Lecture et pilotage de Spotify via son dictionnaire AppleScript.
///
/// Spotify diffuse `com.spotify.client.PlaybackStateChanged` à chaque changement
/// d'état : on n'a donc quasiment jamais besoin d'interroger en boucle. La
/// notification sert de déclencheur, et le script fournit la vérité — notamment
/// l'URL de la pochette, absente de la notification.
@MainActor
final class SpotifySource {

    private static let notificationName = Notification.Name("com.spotify.client.PlaybackStateChanged")
    private static let bundleID = "com.spotify.client"

    /// La garde `is running` est indispensable : sans elle, le simple fait
    /// d'interroger Spotify le **lancerait**.
    private static let querySource = """
    with timeout of 3 seconds
      if application "Spotify" is running then
        tell application "Spotify"
          try
            set trk to current track
            return {player state as text, name of trk, artist of trk, album of trk, ¬
                    duration of trk, player position, artwork url of trk, id of trk}
          on error
            return {"stopped", "", "", "", 0, 0, "", ""}
          end try
        end tell
      else
        return {"notrunning", "", "", "", 0, 0, "", ""}
      end if
    end timeout
    """

    private lazy var query = AppleScriptRunner<NowPlaying?>(
        label: "spotify",
        source: Self.querySource,
        parse: Self.parse)

    private lazy var playPauseScript = command("playpause")
    private lazy var nextScript = command("next track")
    private lazy var previousScript = command("previous track")

    private var onChange: (() -> Void)?

    // MARK: Observation

    func startObserving(onChange: @escaping () -> Void) {
        self.onChange = onChange
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(playbackStateChanged),
            name: Self.notificationName,
            object: nil)
    }

    func stopObserving() {
        DistributedNotificationCenter.default().removeObserver(self)
        onChange = nil
    }

    @objc private func playbackStateChanged() {
        onChange?()
    }

    var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID).isEmpty
    }

    // MARK: Interrogation

    /// Le résultat distingue « rien ne joue » d'un échec : sans cette distinction,
    /// un refus d'autorisation Automation serait indiscernable d'un Spotify à l'arrêt,
    /// et l'utilisateur n'aurait aucun moyen de comprendre pourquoi rien ne s'affiche.
    func refresh(completion: @escaping (Result<NowPlaying?, ScriptFailure>) -> Void) {
        // Inutile de payer un événement Apple si l'app n'est pas lancée.
        guard isRunning else {
            completion(.success(nil))
            return
        }
        query.run { result in
            completion(result.map { $0 })
        }
    }

    private static func parse(_ descriptor: NSAppleEventDescriptor) -> NowPlaying?? {
        let state = descriptor.string(at: 0)
        guard state == "playing" || state == "paused" else { return .some(nil) }

        let title = descriptor.string(at: 1)
        let trackID = descriptor.string(at: 7)
        guard !title.isEmpty || !trackID.isEmpty else { return .some(nil) }

        return NowPlaying(
            source: .spotify,
            trackID: trackID.isEmpty ? title : trackID,
            title: title,
            artist: descriptor.string(at: 2),
            album: descriptor.string(at: 3),
            isPlaying: state == "playing",
            // Spotify exprime la durée en millisecondes, la position en secondes.
            duration: descriptor.double(at: 4) / 1000,
            position: descriptor.double(at: 5),
            capturedAt: Date(),
            artworkURL: URL(string: descriptor.string(at: 6)))
    }

    // MARK: Commandes

    func playPause() { playPauseScript.run() }
    func next() { nextScript.run() }
    func previous() { previousScript.run() }

    private func command(_ verb: String) -> AppleScriptRunner<Bool> {
        AppleScriptRunner<Bool>(
            label: "spotify.\(verb)",
            source: """
            with timeout of 3 seconds
              if application "Spotify" is running then
                tell application "Spotify" to \(verb)
              end if
              return true
            end timeout
            """,
            parse: { _ in true })
    }

    deinit {
        DistributedNotificationCenter.default().removeObserver(self)
    }
}
