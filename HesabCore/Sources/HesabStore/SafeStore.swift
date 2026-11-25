import Foundation
import GRDB
import HesabCore

public enum SafeStoreError: Error, Equatable, CustomStringConvertible {
    /// the stored data could not be read, so nothing may be written over it
    case readOnly(String)

    public var description: String {
        switch self { case .readOnly(let why): return "read-only after a failed read: " + why }
    }
}

/// The app reaches the database only through this (audit 2026-11, critical #1).
///
/// If reading the stored data fails, the app must not show "nothing" and then save that "nothing" over the real data.
/// So a failed `load()` switches the store to read-only: `save` refuses until a later load succeeds. Replacing
/// everything on purpose (restore from a backup, factory reset) stays possible — that is how the person recovers —
/// and the caller first copies the raw database file aside with `copyDatabase(to:)`.
public final class SafeStore {
    public let base: HesabStore
    public private(set) var readFailure: String?

    public init(_ base: HesabStore) { self.base = base }

    public var isReadOnly: Bool { readFailure != nil }

    /// The stored state, or nil when it cannot be read (the store is then read-only).
    public func load() -> [String: JSONValue]? {
        do {
            let s = try base.loadState()
            readFailure = nil
            return s
        } catch {
            readFailure = String(describing: error)
            return nil
        }
    }

    public func save(_ state: [String: JSONValue]) throws {
        if let why = readFailure { throw SafeStoreError.readOnly(why) }
        try base.save(state)
    }

    /// whether anything at all is stored (works even when the rows cannot be decoded)
    public var isEmpty: Bool { base.isEmpty }

    public func replaceAll(with state: [String: JSONValue], sourceExportedAtJalali: String?, reportLines: [String]) throws {
        try base.replaceAll(with: state, sourceExportedAtJalali: sourceExportedAtJalali, reportLines: reportLines)
    }

    public func wipe() throws { try base.wipe() }

    public func lastImport() throws -> (importedAt: String, sourceExportedAtJalali: String?)? { try base.lastImport() }

    public func exportBackup(now: Date = Date(), today: JalaliDate) throws -> Data {
        if let why = readFailure { throw SafeStoreError.readOnly(why) }
        return try base.exportBackup(now: now, today: today)
    }

    /// A byte-for-byte copy of the database as it is (readable or not), e.g. before a restore replaces it.
    public func copyDatabase(to url: URL) throws {
        try? FileManager.default.removeItem(at: url)
        let dest = try DatabaseQueue(path: url.path)
        try base.dbQueue.backup(to: dest)
    }
}

#if DEBUG
extension HesabStore {
    /// tests only: makes one stored record unreadable, as a damaged file would be
    public func corruptOneRecordForTesting() throws {
        try dbQueue.write { db in
            try db.execute(sql: "UPDATE record SET json = '{broken' WHERE rowid = (SELECT MIN(rowid) FROM record)")
        }
    }

    public func recordCountForTesting() throws -> Int {
        try dbQueue.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM record") ?? 0 }
    }
}
#endif
