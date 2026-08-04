import AppKit

/// Lecture et pilotage d'une vidéo YouTube ouverte dans Google Chrome.
///
/// Chrome n'expose ni état de lecture ni métadonnées : il faut interroger la page
/// elle-même via `execute … javascript`. Cette commande est **désactivée par défaut**
/// (Affichage → Développeur → Autoriser JavaScript dans les événements AppleScript) et
/// renvoie alors l'erreur 12 ; on la reconnaît pour guider l'utilisateur au lieu
/// d'échouer en silence.
@MainActor
final class ChromeSource {

    enum Status: Equatable {
        case idle
        case playing
        /// Un onglet YouTube existe mais Chrome refuse d'exécuter du JavaScript.
        case javaScriptDisabled
    }

    private static let bundleID = "com.google.Chrome"

    /// Sonde exécutée dans la page.
    ///
    /// Écrite **sans aucun guillemet double** : le script s'insère dans une chaîne
    /// AppleScript, et le moindre `"` imposerait un échappement fragile. Les champs
    /// sont séparés par le caractère 31 (séparateur d'unité), qui n'apparaît jamais
    /// dans un titre.
    private static let probeJS = "(function(){var v=document.querySelector('video');if(!v){return '';}var og={},m=document.getElementsByTagName('meta');for(var i=0;i<m.length;i++){var p=m[i].getAttribute('property');if(p){og[p]=m[i].getAttribute('content');}}var t=og['og:title']||document.title;var a=og['og:image']||'';var c='';var e=document.querySelector('ytd-channel-name a');if(e){c=e.textContent;}var s=String.fromCharCode(31);return (v.paused?'0':'1')+s+v.currentTime+s+(v.duration||0)+s+t+s+c+s+a+s+location.href;})()"

    private static func playPauseJS() -> String {
        "(function(){var v=document.querySelector('video');if(v){if(v.paused){v.play();}else{v.pause();}}return '';})()"
    }

    private static func clickJS(_ selector: String) -> String {
        "(function(){var b=document.querySelector('\(selector)');if(b){b.click();}return '';})()"
    }

    /// Enveloppe AppleScript : trouve un onglet YouTube et y exécute `js`.
    ///
    /// Les URL sont récupérées d'un coup par fenêtre (`URL of every tab`) plutôt
    /// qu'onglet par onglet : chaque accès à une propriété est un événement Apple, et
    /// une fenêtre à trente onglets coûterait trente allers-retours.
    private static func script(js: String, stopOnPlaying: Bool) -> String {
        """
        with timeout of 5 seconds
          if application "Google Chrome" is running then
            tell application "Google Chrome"
              set fallbackResult to ""
              repeat with w in windows
                set urlList to URL of every tab of w
                repeat with i from 1 to count of urlList
                  if (item i of urlList) contains "youtube.com/watch" then
                    try
                      set r to (execute (tab i of w) javascript "\(js)")
                    on error errMsg number errNum
                      return {"error", "", errNum}
                    end try
                    if r is not missing value and r is not "" then
                      \(stopOnPlaying
                        ? #"if r starts with "1" then return {"ok", r, 0}"#
                        : #"return {"ok", r, 0}"#)
                      if fallbackResult is "" then set fallbackResult to r
                    end if
                  end if
                end repeat
              end repeat
              if fallbackResult is not "" then return {"ok", fallbackResult, 0}
              return {"notab", "", 0}
            end tell
          else
            return {"notrunning", "", 0}
          end if
        end timeout
        """
    }

    private lazy var query = AppleScriptRunner<Outcome>(
        label: "chrome",
        source: Self.script(js: Self.probeJS, stopOnPlaying: true),
        parse: Self.parse)

    private lazy var playPauseScript = AppleScriptRunner<Bool>(
        label: "chrome.playpause",
        source: Self.script(js: Self.playPauseJS(), stopOnPlaying: false),
        parse: { _ in true })

    private lazy var nextScript = AppleScriptRunner<Bool>(
        label: "chrome.next",
        source: Self.script(js: Self.clickJS(".ytp-next-button"), stopOnPlaying: false),
        parse: { _ in true })

    private lazy var previousScript = AppleScriptRunner<Bool>(
        label: "chrome.previous",
        source: Self.script(js: Self.clickJS(".ytp-prev-button"), stopOnPlaying: false),
        parse: { _ in true })

    enum Outcome {
        case track(NowPlaying)
        case noTab
        case javaScriptDisabled
        /// Autorisation Automation refusée pour Chrome.
        case notAuthorized
    }

    var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID).isEmpty
    }

    // MARK: Interrogation

    func refresh(completion: @escaping (Outcome) -> Void) {
        guard isRunning else {
            completion(.noTab)
            return
        }
        query.run { result in
            switch result {
            case .success(let outcome):
                completion(outcome)
            case .failure(let failure):
                completion(failure.isAuthorizationDenial ? .notAuthorized : .noTab)
            }
        }
    }

    private static func parse(_ descriptor: NSAppleEventDescriptor) -> Outcome? {
        switch descriptor.string(at: 0) {
        case "error":
            return Int(descriptor.double(at: 2)) == ScriptFailure.chromeJavaScriptDisabled
                ? .javaScriptDisabled
                : .noTab
        case "ok":
            return parseProbe(descriptor.string(at: 1)).map(Outcome.track) ?? .noTab
        default:
            return .noTab
        }
    }

    private static func parseProbe(_ payload: String) -> NowPlaying? {
        let fields = payload.components(separatedBy: "\u{1F}")
        guard fields.count >= 7 else { return nil }

        let href = fields[6]
        let videoID = URLComponents(string: href)?
            .queryItems?.first(where: { $0.name == "v" })?.value ?? href

        // La miniature d'`og:image` est parfois absente en navigation interne : on
        // retombe sur l'URL déterministe construite depuis l'identifiant.
        let artwork = fields[5].isEmpty
            ? "https://i.ytimg.com/vi/\(videoID)/hqdefault.jpg"
            : fields[5]

        return NowPlaying(
            source: .chrome,
            trackID: videoID,
            title: fields[3],
            artist: fields[4].trimmingCharacters(in: .whitespacesAndNewlines),
            album: "",
            isPlaying: fields[0] == "1",
            duration: Double(fields[2]) ?? 0,
            position: Double(fields[1]) ?? 0,
            capturedAt: Date(),
            artworkURL: URL(string: artwork))
    }

    // MARK: Commandes

    func playPause() { playPauseScript.run() }
    func next() { nextScript.run() }
    func previous() { previousScript.run() }
}
