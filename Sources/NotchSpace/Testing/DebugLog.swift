import Foundation

/// Journal de mise au point écrit dans un fichier.
///
/// `NSLog` s'est révélé peu fiable pour observer une app accessoire depuis
/// `log stream` (messages absents ou masqués). Un fichier, lui, est sans ambiguïté.
/// Inactif tant que `NOTCHSPACE_DEBUG_LOG` n'est pas défini, donc sans effet en
/// usage normal.
enum DebugLog {

    private static let path = ProcessInfo.processInfo.environment["NOTCHSPACE_DEBUG_LOG"]
    private static let queue = DispatchQueue(label: "app.notchspace.debuglog")

    static var isEnabled: Bool { path != nil }

    static func write(_ message: @autoclosure () -> String) {
        guard let path else { return }
        let line = "\(Date().formatted(date: .omitted, time: .standard)) \(message())\n"
        queue.async {
            guard let data = line.data(using: .utf8) else { return }
            if let handle = FileHandle(forWritingAtPath: path) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            } else {
                try? data.write(to: URL(fileURLWithPath: path))
            }
        }
    }
}
