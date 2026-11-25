import Foundation

/// Files made only to be shared (PDF, Excel, JSON, text, card image) — audit stage 2.
///
/// Each export gets its own folder under one root in the temporary directory, so cleaning up removes exactly that
/// export and nothing else. Removal refuses any path outside the root: the database and the backups (in Documents
/// and iCloud) can never be touched by it.
public enum TempExports {
    public static var defaultRoot: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("exports", isDirectory: true)
    }

    /// Writes `data` as `name` in a fresh folder under `root` and returns the file's URL.
    public static func write(_ data: Data, name: String, root: URL = defaultRoot,
                             options: Data.WritingOptions = [.atomic]) throws -> URL {
        let folder = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let safe = name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        let url = folder.appendingPathComponent(safe.isEmpty ? "export" : safe)
        try data.write(to: url, options: options)
        return url
    }

    /// whether `url` is an export made by `write` (inside its own folder under `root`)
    public static func isExport(_ url: URL, root: URL = defaultRoot) -> Bool {
        let r = root.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        let p = url.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        return p.count == r.count + 2 && Array(p.prefix(r.count)) == r
    }

    /// Removes one export (its folder). Anything that is not an export is left alone and `false` returned.
    @discardableResult
    public static func remove(_ url: URL, root: URL = defaultRoot) -> Bool {
        guard isExport(url, root: root) else { return false }
        do { try FileManager.default.removeItem(at: url.deletingLastPathComponent()); return true } catch { return false }
    }

    /// Removes every export left behind (e.g. after the app was closed during a share). Only the root is touched.
    public static func purgeAll(root: URL = defaultRoot) {
        try? FileManager.default.removeItem(at: root)
    }

    /// what is still waiting to be cleaned up (tests)
    public static func pending(root: URL = defaultRoot) -> [URL] {
        let fm = FileManager.default
        let folders = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        return folders.flatMap { (try? fm.contentsOfDirectory(at: $0, includingPropertiesForKeys: nil)) ?? [] }
    }
}
