import Foundation
import CryptoKit

/// One folder of backups (on the phone, or the app's iCloud Drive folder) — writing with a SHA-256 sidecar,
/// health checks, retention by `BackupRetention` and the soft-delete trash.
///
/// • A backup is written first (atomically); its «.sha256» sidecar only after that succeeded. A backup without a
///   sidecar, or whose sidecar does not match, is not healthy.
/// • Removal is never a delete: the file (and its sidecar) moves into «_حذف‌شده», renamed «حذف ۱۴۰۵-۹-۴ - <name>»;
///   files there are deleted for good only 30 days later.
/// • With `coordinated` (iCloud), every write / move goes through NSFileCoordinator.
public struct BackupFolder: Sendable {
    public let url: URL
    public let coordinated: Bool
    public static let trashName = "_حذف‌شده"
    public static let trashPrefix = "حذف "

    public init(url: URL, coordinated: Bool = false) {
        self.url = url
        self.coordinated = coordinated
    }

    public var trashURL: URL { url.appendingPathComponent(Self.trashName, isDirectory: true) }

    public static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    public static func sidecarName(_ name: String) -> String { name + "." + BackupNames.sidecarExtension }

    static func sidecarText(_ data: Data) -> String {
        "sha256: " + sha256Hex(data) + "\nsize: " + String(data.count) + "\n"
    }

    // MARK: writing

    /// Writes the backup, then — only if that worked — its sidecar.
    @discardableResult
    public func write(_ data: Data, name: String, options: Data.WritingOptions = [.atomic]) throws -> URL {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let dest = url.appendingPathComponent(name)
        try coordinatedWrite(data, to: dest, options: options)
        try coordinatedWrite(Data(Self.sidecarText(data).utf8), to: url.appendingPathComponent(Self.sidecarName(name)), options: options)
        return dest
    }

    /// The sidecar for a file that was written some other way (the raw database copy).
    public func writeSidecar(for name: String, options: Data.WritingOptions = [.atomic]) throws {
        let data = try Data(contentsOf: url.appendingPathComponent(name))
        try coordinatedWrite(Data(Self.sidecarText(data).utf8), to: url.appendingPathComponent(Self.sidecarName(name)), options: options)
    }

    public func exists(_ name: String) -> Bool {
        FileManager.default.fileExists(atPath: url.appendingPathComponent(name).path)
    }

    // MARK: health

    public enum Health: Equatable, Sendable {
        case healthy
        case noSidecar          // older backup, or the sidecar was never written
        case mismatch           // the file changed / was cut short after its sidecar was written
        case unreadable
    }

    public func health(_ name: String) -> Health {
        guard let data = try? Data(contentsOf: url.appendingPathComponent(name)) else { return .unreadable }
        guard let side = try? String(contentsOf: url.appendingPathComponent(Self.sidecarName(name)), encoding: .utf8) else { return .noSidecar }
        var sha: String?, size: Int?
        for line in side.split(separator: "\n") {
            let parts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2 else { continue }
            if parts[0] == "sha256" { sha = parts[1].lowercased() }
            if parts[0] == "size" { size = Int(parts[1]) }
        }
        guard let sha, let size else { return .mismatch }
        return size == data.count && sha == Self.sha256Hex(data) ? .healthy : .mismatch
    }

    public func isHealthy(_ name: String) -> Bool { health(name) == .healthy }

    // MARK: listing, retention, trash

    /// file names directly in the folder (not the trash, not iCloud placeholders)
    public func names() -> [String] {
        let items = (try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []
        return items.filter { !$0.hasPrefix(".") && $0 != Self.trashName }
    }

    public struct RetentionResult: Equatable, Sendable {
        public var moved: [String]
        public var skipped: String?
        public var purged: [String]
    }

    /// Applies the policy (moving what goes into the trash) and empties trash entries older than `trashDays`.
    @discardableResult
    public func applyRetention(today: JalaliDate, policy: BackupRetentionPolicy, trashDays: Int = 30) -> RetentionResult {
        let plan = BackupRetention.plan(names: names(), today: today, policy: policy, isHealthy: isHealthy)
        var moved: [String] = []
        for name in plan.remove where (try? moveToTrash(name, today: today)) != nil { moved.append(name) }
        return RetentionResult(moved: moved, skipped: plan.skipped, purged: purgeTrash(today: today, days: trashDays))
    }

    /// Moves a backup and its sidecar into the trash folder (never deletes).
    public func moveToTrash(_ name: String, today: JalaliDate) throws {
        try FileManager.default.createDirectory(at: trashURL, withIntermediateDirectories: true)
        let stamp = Self.trashPrefix + BackupNames.day(today) + " - "
        for n in [name, Self.sidecarName(name)] where exists(n) {
            var dest = trashURL.appendingPathComponent(stamp + n)
            var i = 2
            while FileManager.default.fileExists(atPath: dest.path) {
                dest = trashURL.appendingPathComponent(stamp + "(\(i)) " + n); i += 1
            }
            try coordinatedMove(url.appendingPathComponent(n), to: dest)
        }
    }

    /// Deletes trash entries moved there at least `days` days ago (date from the «حذف …» name). Nothing else in
    /// the trash is touched, and nothing at all when an entry is dated after today (wrong clock).
    @discardableResult
    public func purgeTrash(today: JalaliDate, days: Int = 30) -> [String] {
        let items = (try? FileManager.default.contentsOfDirectory(atPath: trashURL.path)) ?? []
        let todayN = Jalali.j2d(today.jy, today.jm, today.jd)
        var dated: [(String, Int)] = []
        for n in items {
            guard let d = Self.trashDate(n) else { continue }
            let dn = Jalali.j2d(d.jy, d.jm, d.jd)
            if dn > todayN { return [] }
            dated.append((n, dn))
        }
        var purged: [String] = []
        for (n, dn) in dated where todayN - dn >= days {
            if (try? coordinatedDelete(trashURL.appendingPathComponent(n))) != nil { purged.append(n) }
        }
        return purged
    }

    static func trashDate(_ name: String) -> JalaliDate? {
        guard name.hasPrefix(trashPrefix) else { return nil }
        let rest = SearchEngine.latinDigits(String(name.dropFirst(trashPrefix.count)))
        let head = rest.components(separatedBy: " - ").first ?? ""
        let p = head.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return nil }
        let d = JalaliDate(jy: p[0], jm: p[1], jd: p[2])
        return BackupNames.isValid(d) ? d : nil
    }

    // MARK: file operations (coordinated for iCloud)

    private func coordinatedWrite(_ data: Data, to dest: URL, options: Data.WritingOptions) throws {
        guard coordinated else { try data.write(to: dest, options: options); return }
        var coordError: NSError?, opError: Error?
        NSFileCoordinator().coordinate(writingItemAt: dest, options: .forReplacing, error: &coordError) { u in
            do { try data.write(to: u, options: options) } catch { opError = error }
        }
        if let e = coordError ?? opError { throw e }
    }

    private func coordinatedMove(_ from: URL, to: URL) throws {
        guard coordinated else { try FileManager.default.moveItem(at: from, to: to); return }
        var coordError: NSError?, opError: Error?
        NSFileCoordinator().coordinate(writingItemAt: from, options: .forMoving, writingItemAt: to, options: .forReplacing,
                                       error: &coordError) { a, b in
            do { try FileManager.default.moveItem(at: a, to: b) } catch { opError = error }
        }
        if let e = coordError ?? opError { throw e }
    }

    private func coordinatedDelete(_ target: URL) throws {
        guard coordinated else { try FileManager.default.removeItem(at: target); return }
        var coordError: NSError?, opError: Error?
        NSFileCoordinator().coordinate(writingItemAt: target, options: .forDeleting, error: &coordError) { u in
            do { try FileManager.default.removeItem(at: u) } catch { opError = error }
        }
        if let e = coordError ?? opError { throw e }
    }
}
