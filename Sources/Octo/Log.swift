import Foundation

/// A small log at ~/Library/Logs/Octo.log for startup and permission events.
/// Gestures themselves are shown in Test & Tune, not written here.
enum Log {
    static let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/Octo.log")
    private static let queue = DispatchQueue(label: "octo.log")
    private static let formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func write(_ message: String) {
        let line = "\(formatter.string(from: Date())) \(message)\n"
        queue.async {
            guard let data = line.data(using: .utf8) else { return }
            if let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                // Keep the file small: start over past 512 KB.
                if (try? handle.seekToEnd()) ?? 0 > 512_000 {
                    try? handle.truncate(atOffset: 0)
                }
                try? handle.write(contentsOf: data)
            } else {
                try? data.write(to: url)
            }
        }
    }
}
