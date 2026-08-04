import AppKit
import UserNotifications

/// Vérifie, depuis l'identité du bundle, la géométrie de l'encoche et les sources
/// média — tout ce qui dépend de l'extérieur.
///
///     ./NotchSpace.app/Contents/MacOS/NotchSpace --diagnose
///
/// Le passage par le binaire du bundle est important : les autorisations (Automation
/// notamment) sont attribuées à la signature de l'app, pas au terminal. Lancer le
/// diagnostic depuis le bundle déclenche donc exactement les mêmes demandes que
/// l'usage normal, et affiche les erreurs au lieu de les avaler.
@MainActor
enum Diagnostics {

    static func runAndExit() -> Never {
        print("NotchSpace — diagnostic\n")

        checkGeometry()

        // Les interrogations sont asynchrones : on laisse tourner la boucle jusqu'à
        // ce que toutes aient répondu.
        let group = DispatchGroup()
        group.enter()
        group.enter()
        group.enter()

        checkSpotify { group.leave() }
        checkChrome { group.leave() }
        checkNotifications { group.leave() }

        // Le chemin réellement emprunté par l'app, et pas seulement les sources
        // prises isolément : c'est là que se logent les erreurs de câblage.
        group.enter()
        checkMediaController { group.leave() }

        var finished = false
        group.notify(queue: .main) {
            print("\nDiagnostic terminé.")
            finished = true
        }

        let deadline = Date().addingTimeInterval(20)
        while !finished, Date() < deadline {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.1))
        }
        exit(finished ? 0 : 1)
    }

    // MARK: Sections

    private static func checkGeometry() {
        print("— Écran et encoche")
        guard let metrics = NotchGeometry.currentMetrics() else {
            print("  ✗ aucun écran détecté")
            return
        }
        print("  écran         : \(fmt(metrics.screenFrame))")
        print("  encoche       : \(fmt(metrics.notchRect))" +
              (metrics.hasRealNotch ? "" : "  (pilule virtuelle : pas d'encoche physique)"))
        let shell = metrics.shellSize(for: .active)
        let margin = (shell.width - metrics.notchRect.width) / 2 - NotchMetrics.topRadius
        print("  marge anneau  : \(String(format: "%.1f", margin)) pt " +
              (margin > 0 ? "✓ visible" : "✗ l'anneau tomberait dans la zone sans pixels"))
        print("")
    }

    private static func checkSpotify(_ done: @escaping () -> Void) {
        print("— Spotify")
        let source = SpotifySource()
        guard source.isRunning else {
            print("  Spotify n'est pas lancé — impossible de tester.\n")
            done()
            return
        }
        source.refresh { result in
            switch result {
            case .success(.some(let track)):
                print("  ✓ \(track.isPlaying ? "lecture" : "pause") : \(track.title) — \(track.artist)")
                print("    durée \(track.duration.mmss), position \(track.position.mmss)")
                print("    pochette : \(track.artworkURL?.absoluteString ?? "aucune")")
            case .success(.none):
                print("  Spotify répond mais ne lit rien.")
            case .failure(let failure):
                print("  ✗ erreur \(failure.code) : \(failure.message)")
                if failure.isAuthorizationDenial {
                    print("    Autorisation Automation refusée.")
                    print("    Réglages Système → Confidentialité et sécurité → Automatisation → NotchSpace")
                }
            }
            print("")
            done()
        }
    }

    private static func checkChrome(_ done: @escaping () -> Void) {
        print("— Google Chrome / YouTube")
        let source = ChromeSource()
        guard source.isRunning else {
            print("  Chrome n'est pas lancé — impossible de tester.\n")
            done()
            return
        }
        source.refresh { outcome in
            switch outcome {
            case .track(let track):
                print("  ✓ \(track.isPlaying ? "lecture" : "pause") : \(track.title)")
                print("    chaîne \(track.artist), durée \(track.duration.mmss)")
            case .javaScriptDisabled:
                print("  ✗ JavaScript depuis les Apple Events est désactivé dans Chrome.")
                print("    Chrome → Affichage → Développeur → Autoriser JavaScript dans les événements AppleScript")
            case .notAuthorized:
                print("  ✗ autorisation Automation refusée pour Chrome.")
                print("    Réglages Système → Confidentialité et sécurité → Automatisation → NotchSpace")
            case .noTab:
                print("  aucun onglet youtube.com/watch ouvert.")
            }
            print("")
            done()
        }
    }

    /// Dépendance externe au même titre que Spotify ou Chrome : une notification de
    /// fin de session refusée échoue silencieusement, sans qu'aucun écran de l'app
    /// ne l'affiche en dehors des Réglages.
    ///
    /// `UNUserNotificationCenter` exige l'identité d'un bundle .app signé : hors
    /// bundle (le binaire nu lancé directement), il lève une exception non
    /// rattrapable et fait planter tout le diagnostic. La garde évite ce plantage —
    /// le même principe que « lancer le diagnostic depuis le bundle » déjà documenté
    /// pour l'autorisation Automation, ici rendu obligatoire plutôt qu'utile.
    private static func checkNotifications(_ done: @escaping () -> Void) {
        print("— Notifications")
        guard Bundle.main.bundleIdentifier != nil else {
            print("  hors d'un bundle .app — ce contrôle exige l'identité du bundle.")
            print("  Relancer depuis NotchSpace.app pour l'inclure.\n")
            done()
            return
        }
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                switch settings.authorizationStatus {
                case .authorized: print("  ✓ autorisées")
                case .provisional: print("  ✓ autorisées en mode discret")
                case .ephemeral: print("  ✓ autorisées temporairement")
                case .denied:
                    print("  ✗ refusées")
                    print("    Réglages Système → Notifications → NotchSpace")
                case .notDetermined:
                    print("  jamais demandées — le réglage « Envoyer une notification » n'a encore jamais été activé")
                @unknown default:
                    print("  état inconnu")
                }
                print("")
                done()
            }
        }
    }

    private static var controller: MediaController?

    private static func checkMediaController(_ done: @escaping () -> Void) {
        let suite = UserDefaults(suiteName: "NotchSpaceDiagnostics")!
        let controller = MediaController(settings: AppSettings(defaults: suite))
        Self.controller = controller
        controller.start()

        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            print("— MediaController (chemin de l'app)")
            if let track = controller.nowPlaying {
                print("  ✓ source retenue : \(track.source.displayName) — \(track.title)")
                print("    pochette chargée : \(controller.artwork != nil ? "oui" : "pas encore")")
            } else {
                print("  ✗ nowPlaying est nil")
                print("    autorisation manquante : \(controller.needsAutomationPermission)")
                print("    JavaScript Chrome bloqué : \(controller.chromeNeedsJavaScript)")
            }
            print("")
            controller.stop()
            done()
        }
    }

    private static func fmt(_ rect: CGRect) -> String {
        String(format: "x %.0f  y %.0f  %.0f × %.0f",
               rect.minX, rect.minY, rect.width, rect.height)
    }
}
