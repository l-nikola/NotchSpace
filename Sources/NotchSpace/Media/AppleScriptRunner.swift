import Foundation

struct ScriptFailure: Error, Equatable {
    let code: Int
    let message: String

    /// Chrome refuse `execute … javascript` tant que « Autoriser JavaScript dans les
    /// événements AppleScript » n'est pas coché dans le menu Développeur.
    static let chromeJavaScriptDisabled = 12

    /// `errAEEventNotPermitted` : l'utilisateur n'a pas accordé l'autorisation
    /// Automation, ou l'a refusée.
    static let notAuthorized = -1743

    /// `procNotFound` : l'application ciblée n'est pas lancée.
    static let applicationNotRunning = -600

    var isAuthorizationDenial: Bool { code == Self.notAuthorized }
}

/// Exécute un script AppleScript précompilé, hors du thread principal.
///
/// Trois choix comptent ici :
///
/// - **Précompilation** : la compilation coûte ~30 ms, l'exécution ~80 ms. Compiler
///   une seule fois évite de payer les deux à chaque interrogation.
/// - **File série unique, partagée par tous les scripts** : `NSAppleScript` n'est pas
///   thread-safe, et pas seulement instance par instance — le composant AppleScript
///   sous-jacent est commun au processus. Donner une file à chaque script laissait
///   les requêtes Spotify et Chrome s'exécuter en parallèle, ce qui produisait des
///   erreurs intermittentes (-1751) et faisait échouer la lecture une fois sur deux.
///   Une file unique hors du thread principal règle les deux problèmes : la sérialisation
///   et les 80 ms qui feraient sauter l'animation de l'anneau.
/// - **Analyse sur place** : `NSAppleEventDescriptor` ne traverse pas les threads
///   sereinement, donc on le convertit en valeur simple avant de revenir au principal.
///
/// Les scripts englobent leur corps dans un `with timeout` : sans ça, une app figée
/// bloquerait l'événement pendant les deux minutes du délai par défaut.
final class AppleScriptRunner<Output> {

    /// Partagée par tous les scripts du processus — voir la note ci-dessus.
    private static var executionQueue: DispatchQueue { SharedScriptQueue.queue }

    private let source: String
    private let parse: (NSAppleEventDescriptor) -> Output?
    private var compiled: NSAppleScript?
    private var compilationFailed = false

    init(label: String,
         source: String,
         parse: @escaping (NSAppleEventDescriptor) -> Output?) {
        self.source = source
        self.parse = parse
    }

    /// Résultat livré sur le thread principal.
    func run(completion: ((Result<Output, ScriptFailure>) -> Void)? = nil) {
        Self.executionQueue.async { [self] in
            let outcome = executeOnQueue()
            guard let completion else { return }
            DispatchQueue.main.async { completion(outcome) }
        }
    }

    private func executeOnQueue() -> Result<Output, ScriptFailure> {
        guard let script = compiledScript() else {
            return .failure(ScriptFailure(code: -1, message: "script non compilable"))
        }

        var errorInfo: NSDictionary?
        let descriptor = script.executeAndReturnError(&errorInfo)

        if let errorInfo {
            let code = errorInfo[NSAppleScript.errorNumber] as? Int ?? -1
            let message = errorInfo[NSAppleScript.errorMessage] as? String ?? "erreur inconnue"
            return .failure(ScriptFailure(code: code, message: message))
        }

        guard let output = parse(descriptor) else {
            return .failure(ScriptFailure(code: -2, message: "résultat inattendu"))
        }
        return .success(output)
    }

    private func compiledScript() -> NSAppleScript? {
        if let compiled { return compiled }
        guard !compilationFailed else { return nil }

        var errorInfo: NSDictionary?
        guard let script = NSAppleScript(source: source),
              script.compileAndReturnError(&errorInfo) else {
            compilationFailed = true
            return nil
        }
        compiled = script
        return script
    }
}

/// Porteur de la file d'exécution commune.
///
/// Un type à part plutôt qu'une propriété statique sur `AppleScriptRunner` : une
/// statique dans un générique donnerait **une file par spécialisation** de `Output`,
/// ce qui rétablirait exactement le parallélisme qu'on cherche à supprimer.
private enum SharedScriptQueue {
    static let queue = DispatchQueue(label: "app.notchspace.applescript", qos: .utility)
}

extension NSAppleEventDescriptor {
    /// Éléments d'une liste AppleScript, indexés à partir de 1.
    var listItems: [NSAppleEventDescriptor] {
        guard numberOfItems > 0 else { return [] }
        return (1...numberOfItems).compactMap { atIndex($0) }
    }

    func string(at index: Int) -> String {
        listItems.indices.contains(index) ? (listItems[index].stringValue ?? "") : ""
    }

    /// Lit un nombre via `doubleValue` plutôt que via le texte : la coercition
    /// AppleScript en texte suit la locale et produirait « 101,0 » en français.
    func double(at index: Int) -> Double {
        listItems.indices.contains(index) ? listItems[index].doubleValue : 0
    }
}
