import Foundation

/// Harnais de test minimal, embarqué dans le binaire.
///
/// Les Command Line Tools ne fournissent ni `XCTest` ni `Testing` : sans Xcode, un
/// `swift test` classique est impossible. Plutôt que de renoncer à toute couverture
/// sur la logique d'échéance du Pomodoro — la seule partie qu'on ne peut pas valider
/// à la souris — on la teste depuis l'app elle-même :
///
///     swift run NotchSpace --self-test
///
@MainActor
enum SelfTest {

    private static var failures: [String] = []
    private static var assertions = 0
    private static var currentCase = ""

    static func runAndExit() -> Never {
        let cases: [(String, () -> Void)] = [
            ("démarrage en phase de travail", testStartBeginsWork),
            ("la pause gèle le temps restant", testPauseFreezesRemaining),
            ("grande pause après 4 pomodoros", testLongBreakAfterFourPomodoros),
            ("phase armée sans enchaînement auto", testArmedWithoutAutoStart),
            ("veille plus longue que la session", testSleepLongerThanSession),
            ("veille courte : temps restant juste", testShortSleep),
            ("réinitialisation du cycle", testReset),
            ("format au-delà de l'heure", testHourFormatting),
            ("géométrie : l'anneau tombe sur des pixels visibles", testRingLandsOnVisiblePixels),
            ("étagère : ajout, doublon, retrait", testShelfAddAndRemove),
            ("étagère : un fichier de l'utilisateur n'est jamais supprimé", testShelfNeverDeletesUserFiles),
            ("étagère : purge des éléments disparus", testShelfPurgesMissingFiles),
        ]

        for (name, body) in cases {
            currentCase = name
            body()
        }

        let failed = failures.count
        print("\n\(assertions) assertions, \(cases.count) cas, \(failed) échec\(failed > 1 ? "s" : "")")
        if failed > 0 {
            failures.forEach { print("  ✗ \($0)") }
            exit(1)
        }
        print("✓ tout passe")
        exit(0)
    }

    // MARK: Assertions

    private static func expect(_ condition: Bool, _ message: @autoclosure () -> String) {
        assertions += 1
        if !condition { failures.append("[\(currentCase)] \(message())") }
    }

    private static func expect(_ actual: Double, _ expected: Double, accuracy: Double,
                               _ label: String) {
        assertions += 1
        if abs(actual - expected) > accuracy {
            failures.append("[\(currentCase)] \(label) : attendu \(expected), obtenu \(actual)")
        }
    }

    private static func expect<T: Equatable>(_ actual: T, _ expected: T, _ label: String) {
        assertions += 1
        if actual != expected {
            failures.append("[\(currentCase)] \(label) : attendu \(expected), obtenu \(actual)")
        }
    }

    // MARK: Fixtures

    /// Horloge pilotée à la main : permet de franchir une échéance instantanément et
    /// surtout de simuler une veille — un saut de plusieurs minutes sans aucun tic.
    private final class FakeClock: PomodoroClock {
        var now = Date(timeIntervalSince1970: 1_000_000)
        func advance(_ interval: TimeInterval) { now += interval }
    }

    /// Suite `UserDefaults` jetable : les tests ne doivent pas écraser les vrais réglages.
    private static func makeSettings(autoStart: Bool = false) -> AppSettings {
        let suite = UserDefaults(suiteName: "NotchSpaceSelfTest.\(UUID().uuidString)")!
        let settings = AppSettings(defaults: suite)
        settings.workMinutes = 25
        settings.shortBreakMinutes = 5
        settings.longBreakMinutes = 15
        settings.pomodorosBeforeLongBreak = 4
        settings.autoStartNextSession = autoStart
        return settings
    }

    // MARK: Cas

    private static func testStartBeginsWork() {
        let engine = PomodoroEngine(settings: makeSettings(), clock: FakeClock())
        expect(engine.phase, .idle, "phase initiale")

        engine.start()

        expect(engine.phase, .work, "phase après démarrage")
        expect(engine.isRunning, "le minuteur doit tourner")
        expect(engine.remaining, 25 * 60, accuracy: 0.01, "temps restant")
        expect(engine.progress, 0, accuracy: 0.001, "progression")
    }

    private static func testPauseFreezesRemaining() {
        let clock = FakeClock()
        let engine = PomodoroEngine(settings: makeSettings(), clock: clock)
        engine.start()

        clock.advance(60)
        engine.pause()
        expect(engine.remaining, 24 * 60, accuracy: 0.01, "restant à la pause")
        expect(!engine.isRunning, "le minuteur doit être arrêté")

        // Dix minutes s'écoulent en pause : elles ne doivent pas être décomptées.
        clock.advance(600)
        expect(engine.remaining, 24 * 60, accuracy: 0.01, "restant après attente en pause")

        engine.resume()
        expect(engine.isRunning, "reprise")
        clock.advance(120)
        expect(engine.remaining, 24 * 60, accuracy: 0.01,
               "le restant ne change qu'au tic, pas à la lecture")
    }

    private static func testLongBreakAfterFourPomodoros() {
        let engine = PomodoroEngine(settings: makeSettings(autoStart: true), clock: FakeClock())

        engine.start()
        expect(engine.phase, .work, "1re phase")

        engine.skip()
        expect(engine.phase, .shortBreak, "après le 1er pomodoro")

        for expected in [PomodoroPhase.shortBreak, .shortBreak, .longBreak] {
            engine.skip()                       // fin de pause -> travail
            expect(engine.phase, .work, "retour au travail")
            engine.skip()                       // fin du travail -> pause
            expect(engine.phase, expected, "pause attendue")
        }
        expect(engine.completedPomodoros, 4, "pomodoros terminés")
    }

    private static func testArmedWithoutAutoStart() {
        let engine = PomodoroEngine(settings: makeSettings(autoStart: false), clock: FakeClock())
        engine.start()
        engine.skip()

        expect(engine.phase, .shortBreak, "phase suivante armée")
        expect(!engine.isRunning, "elle doit attendre un démarrage explicite")
        expect(engine.remaining, 5 * 60, accuracy: 0.01, "durée de la pause")
    }

    /// Le cas qui justifie toute l'architecture par date d'échéance : la machine dort
    /// plus longtemps que la session, sans qu'aucun tic ne se produise.
    private static func testSleepLongerThanSession() {
        let clock = FakeClock()
        let engine = PomodoroEngine(settings: makeSettings(), clock: clock)

        engine.start()
        clock.advance(40 * 60)          // 40 min de veille pour une session de 25
        engine.synchronizeAfterWake()

        expect(engine.completedPomodoros, 1, "la session doit avoir été comptée")
        expect(engine.phase, .shortBreak, "phase après réveil")
    }

    private static func testShortSleep() {
        let clock = FakeClock()
        let engine = PomodoroEngine(settings: makeSettings(), clock: clock)

        engine.start()
        clock.advance(10 * 60)
        engine.synchronizeAfterWake()

        expect(engine.phase, .work, "toujours au travail")
        expect(engine.isRunning, "toujours en cours")
        expect(engine.remaining, 15 * 60, accuracy: 1, "temps restant après veille")
        expect(engine.progress, 10.0 / 25.0, accuracy: 0.01, "progression")
    }

    private static func testReset() {
        let engine = PomodoroEngine(settings: makeSettings(autoStart: true), clock: FakeClock())
        engine.start()
        engine.skip()
        expect(engine.completedPomodoros, 1, "avant réinitialisation")

        engine.reset()

        expect(engine.phase, .idle, "phase")
        expect(!engine.isRunning, "arrêté")
        expect(engine.completedPomodoros, 0, "compteur remis à zéro")
        expect(engine.progress, 0, accuracy: 0.0001, "progression")
    }

    private static func testHourFormatting() {
        let settings = makeSettings()
        settings.workMinutes = 90
        let engine = PomodoroEngine(settings: settings, clock: FakeClock())
        engine.start()
        expect(engine.formattedRemaining, "1:30:00", "format long")
    }

    // MARK: Étagère

    /// Dossier jetable, avec un fichier bidon dedans.
    private static func makeSandbox() -> (URL, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("NotchSpaceSelfTest/\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("document.txt")
        try? Data("contenu".utf8).write(to: file)
        return (directory, file)
    }

    private static func testShelfAddAndRemove() {
        let (directory, file) = makeSandbox()
        defer { try? FileManager.default.removeItem(at: directory) }

        let shelf = ShelfStore(settings: makeSettings(), rootDirectory: directory.appendingPathComponent("ShelfRoot", isDirectory: true))
        shelf.removeAll()

        shelf.add(url: file)
        expect(shelf.items.count, 1, "un élément après ajout")
        expect(shelf.items.first?.name, "document.txt", "nom repris du fichier")

        // Le même fichier déposé deux fois ne doit pas s'empiler.
        shelf.add(url: file)
        expect(shelf.items.count, 1, "pas de doublon")

        shelf.removeAll()
        expect(shelf.items.isEmpty, "étagère vidée")
    }

    /// Retirer un élément de l'étagère ne doit **jamais** effacer le fichier
    /// d'origine : l'étagère référence, elle ne possède pas.
    private static func testShelfNeverDeletesUserFiles() {
        let (directory, file) = makeSandbox()
        defer { try? FileManager.default.removeItem(at: directory) }

        let shelf = ShelfStore(settings: makeSettings(), rootDirectory: directory.appendingPathComponent("ShelfRoot", isDirectory: true))
        shelf.removeAll()
        shelf.add(url: file)

        guard let item = shelf.items.first else {
            expect(false, "élément absent")
            return
        }
        shelf.remove(item)

        expect(shelf.items.isEmpty, "élément retiré de l'étagère")
        expect(FileManager.default.fileExists(atPath: file.path),
               "le fichier de l'utilisateur doit rester sur le disque")
    }

    private static func testShelfPurgesMissingFiles() {
        let (directory, file) = makeSandbox()
        defer { try? FileManager.default.removeItem(at: directory) }

        let shelf = ShelfStore(settings: makeSettings(), rootDirectory: directory.appendingPathComponent("ShelfRoot", isDirectory: true))
        shelf.removeAll()
        shelf.add(url: file)
        expect(shelf.items.count, 1, "avant purge")

        // L'utilisateur déplace ou jette le fichier hors de l'app.
        try? FileManager.default.removeItem(at: file)
        shelf.purgeExpired()

        expect(shelf.items.isEmpty, "l'entrée orpheline doit disparaître")
    }

    /// Garde-fou contre la régression la plus coûteuse du projet : si les côtés de la
    /// coquille retombent à l'intérieur de l'encoche, l'anneau est tracé dans une zone
    /// sans pixels et devient invisible — sans que rien ne plante.
    private static func testRingLandsOnVisiblePixels() {
        let notch = CGRect(x: 663, y: 950, width: 185, height: 32)
        let metrics = NotchMetrics(notchRect: notch,
                                   screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
                                   hasRealNotch: true)

        let shell = metrics.shellSize(for: .active)
        // Les côtés du tracé se trouvent à `topRadius` du bord de la coquille.
        let sideInset = (shell.width - notch.width) / 2 - NotchMetrics.topRadius
        expect(sideInset > 0,
               "les côtés doivent déborder de l'encoche (marge \(sideInset) pt)")
        expect(Double(sideInset), Double(NotchMetrics.ringMargin), accuracy: 0.001,
               "marge latérale de l'anneau")

        let bottomInset = shell.height - notch.height
        expect(bottomInset > 0, "le bas doit déborder sous l'encoche")

        // Au repos, à l'inverse, rien ne doit dépasser : la coquille disparaît.
        expect(metrics.shellSize(for: .resting), notch.size, "coquille au repos")
    }
}
