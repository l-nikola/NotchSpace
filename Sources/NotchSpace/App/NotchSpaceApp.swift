import AppKit

/// Point d'entrée.
///
/// Le fichier ne doit surtout pas s'appeler `main.swift` : SwiftPM le traiterait
/// comme du code au niveau racine et `@main` deviendrait illégal.
///
/// L'app est montée en AppKit plutôt qu'avec `SwiftUI.App`. Une app accessoire n'a
/// aucune fenêtre principale : la seule `Scene` possible aurait été `Settings`, dont
/// l'ouverture programmatique ne fonctionne pas dans ce contexte. Tout le reste
/// (encoche, réglages) est de toute façon composé en SwiftUI dans des vues hôtes.
///
/// Ce détour permet aussi d'intercepter `--self-test` et `--diagnose` avant de lancer
/// quoi que ce soit : les Command Line Tools ne fournissent ni XCTest ni
/// swift-testing, la suite de tests vit donc dans le binaire lui-même.
@main
enum NotchSpaceMain {

    @MainActor private static let retainedDelegate = AppDelegate()

    @MainActor
    static func main() {
        if CommandLine.arguments.contains("--self-test") {
            SelfTest.runAndExit()
        }
        if CommandLine.arguments.contains("--diagnose") {
            Diagnostics.runAndExit()
        }

        let app = NSApplication.shared
        // `NSApplication.delegate` est une référence faible : le delegate est retenu
        // ici pour toute la durée de vie du processus.
        app.delegate = retainedDelegate
        app.run()
    }
}
