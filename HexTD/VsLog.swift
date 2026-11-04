import Foundation

/// Logger mínimo de arquivo pra debug do fim de partida. Grava em Documents/vslog.txt.
enum VsLog {
    static let url: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("vslog.txt")
    private static let q = DispatchQueue(label: "vslog.queue")
    private static var started = false

    static func write(_ s: String) {
        q.async {
            if !started { started = true; try? "=== VS LOG \(Date()) ===\n".data(using: .utf8)?.write(to: url) }
            guard let h = try? FileHandle(forWritingTo: url) else { return }
            h.seekToEndOfFile()
            if let d = ("\(Date().timeIntervalSince1970.rounded()) \(s)\n").data(using: .utf8) { h.write(d); try? h.synchronize() }
            try? h.close()
        }
    }
}
