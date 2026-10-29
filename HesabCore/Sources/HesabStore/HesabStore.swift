import Foundation
import GRDB
import HesabCore

/// Local database (SQLite via GRDB).
///
/// Step 1 stores the imported state losslessly:
///  - `record`: one row per item of every array-of-objects collection (expenses, accounts, cards, …), in the
///    original order, with its original id and its full JSON (unknown fields included);
///  - `root`: every other top-level value (settings, category lists, maps …) as JSON.
/// Later steps add typed tables through new migrations; the original JSON stays the source of truth.
public final class HesabStore {
    public let dbQueue: DatabaseQueue

    public init(path: String) throws {
        var config = Configuration()
        config.foreignKeysEnabled = true
        dbQueue = try DatabaseQueue(path: path, configuration: config)
        try Self.migrator.migrate(dbQueue)
    }

    /// In-memory database (tests).
    public init() throws {
        dbQueue = try DatabaseQueue()
        try Self.migrator.migrate(dbQueue)
    }

    static var migrator: DatabaseMigrator {
        var m = DatabaseMigrator()
        m.registerMigration("v1-document-store") { db in
            try db.create(table: "root") { t in
                t.column("key", .text).notNull().primaryKey()
                t.column("json", .text).notNull()
            }
            try db.create(table: "record") { t in
                t.column("collection", .text).notNull()
                t.column("ord", .integer).notNull()
                t.column("id", .text)
                t.column("json", .text).notNull()
                t.primaryKey(["collection", "ord"])
            }
            try db.create(index: "record_by_id", on: "record", columns: ["collection", "id"])
            try db.create(table: "import_log") { t in
                t.autoIncrementedPrimaryKey("seq")
                t.column("importedAt", .text).notNull()
                t.column("sourceExportedAtJalali", .text)
                t.column("report", .text).notNull()
            }
        }
        return m
    }

    // MARK: write

    /// Replaces everything with `state` in ONE transaction: either all of it is stored or nothing changes.
    public func replaceAll(with state: [String: JSONValue], sourceExportedAtJalali: String?, reportLines: [String]) throws {
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM record")
            try db.execute(sql: "DELETE FROM root")
            for key in state.keys.sorted() {
                let value = state[key] ?? .null
                if case .array(let items) = value, !items.isEmpty, items.allSatisfy({ $0.objectValue != nil }) {
                    for (i, item) in items.enumerated() {
                        try db.execute(sql: "INSERT INTO record(collection, ord, id, json) VALUES (?, ?, ?, ?)",
                                       arguments: [key, i, item["id"]?.idString, try JSONCoding.string(item)])
                    }
                } else {
                    try db.execute(sql: "INSERT INTO root(key, json) VALUES (?, ?)",
                                   arguments: [key, try JSONCoding.string(value)])
                }
            }
            let iso = ISO8601DateFormatter().string(from: Date())
            try db.execute(sql: "INSERT INTO import_log(importedAt, sourceExportedAtJalali, report) VALUES (?, ?, ?)",
                           arguments: [iso, sourceExportedAtJalali, reportLines.joined(separator: "\n")])
        }
    }

    // MARK: read

    public var isEmpty: Bool {
        (try? dbQueue.read { db in
            let r = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM record") ?? 0
            let k = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM root") ?? 0
            return r + k == 0
        }) ?? true
    }

    public func loadState() throws -> [String: JSONValue] {
        try dbQueue.read { db in
            var state: [String: JSONValue] = [:]
            for row in try Row.fetchAll(db, sql: "SELECT key, json FROM root") {
                let key: String = row["key"]
                let json: String = row["json"]
                state[key] = try JSONCoding.decode(Data(json.utf8))
            }
            var collections: [String: [JSONValue]] = [:]
            for row in try Row.fetchAll(db, sql: "SELECT collection, json FROM record ORDER BY collection, ord") {
                let c: String = row["collection"]
                let json: String = row["json"]
                collections[c, default: []].append(try JSONCoding.decode(Data(json.utf8)))
            }
            for (c, items) in collections { state[c] = .array(items) }
            return state
        }
    }

    public func lastImport() throws -> (importedAt: String, sourceExportedAtJalali: String?)? {
        try dbQueue.read { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT importedAt, sourceExportedAtJalali FROM import_log ORDER BY seq DESC LIMIT 1") else { return nil }
            let at: String = row["importedAt"]
            let src: String? = row["sourceExportedAtJalali"]
            return (at, src)
        }
    }

    // MARK: export

    /// Full backup in the web format (version 1). CVV is never present because it is never stored.
    public func exportBackup(now: Date = Date(), today: JalaliDate) throws -> Data {
        let env = BackupExporter.envelope(state: try loadState(), now: now, today: today)
        return try JSONCoding.encode(env, pretty: true)
    }
}
