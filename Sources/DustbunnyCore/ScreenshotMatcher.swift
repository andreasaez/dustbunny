import Foundation

/// Decides whether a file is a macOS screenshot by looking at its *name only*.
///
/// macOS names screenshots like `Screenshot 2026-10-11 at 18.04.12.png`
/// (older versions: `Screen Shot 2020-01-02 at 9.41.03 PM.png`).
/// The capture day is taken from the name, so no file metadata or contents are ever read.
public enum ScreenshotMatcher {
    static let prefixes = ["Screenshot ", "Screen Shot "]
    /// Every format macOS can save screenshots in.
    static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "tiff", "tif", "gif", "pdf", "bmp"]

    /// Returns the capture day as `YYYY-MM-DD` if `name` is a macOS screenshot name, otherwise `nil`.
    public static func captureDay(forFileName name: String) -> String? {
        guard !name.hasPrefix("."), !name.contains("/") else { return nil }

        let ext = (name as NSString).pathExtension.lowercased()
        guard imageExtensions.contains(ext), let prefix = prefixes.first(where: name.hasPrefix) else { return nil }

        // Expect exactly "YYYY-MM-DD at " right after the prefix, followed by a time and the extension.
        let rest = Array(name.utf8.dropFirst(prefix.utf8.count))
        let header = 14 // "YYYY-MM-DD at "
        guard rest.count > header + 1 + ext.utf8.count else { return nil }

        let digitIndices = [0, 1, 2, 3, 5, 6, 8, 9]
        guard digitIndices.allSatisfy({ (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(rest[$0]) }),
              rest[4] == UInt8(ascii: "-"), rest[7] == UInt8(ascii: "-"),
              Array(rest[10..<14]) == Array(" at ".utf8)
        else { return nil }

        let day = String(decoding: rest[0..<10], as: UTF8.self)
        guard let month = Int(day.dropFirst(5).prefix(2)), (1...12).contains(month),
              let dayOfMonth = Int(day.suffix(2)), (1...31).contains(dayOfMonth)
        else { return nil }

        return day
    }
}
