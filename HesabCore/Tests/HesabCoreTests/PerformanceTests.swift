import XCTest
import Foundation
@testable import HesabCore
@testable import HesabStore

/// Stage 3 measurements with 20,000 synthetic rows. Run in CI in release mode (`-c release`); each line is printed
/// as «PERF|<operation>|<milliseconds>» and turned into a notice. The limits are deliberately loose: they only catch
/// a real slowdown; the numbers themselves are the result.
final class PerformanceTests: XCTestCase {
    static let rows = 20_000

    @discardableResult
    private func ms(_ name: String, runs: Int = 3, _ block: () throws -> Void) rethrows -> Double {
        var best = Double.infinity
        for _ in 0..<runs {
            let t = DispatchTime.now().uptimeNanoseconds
            try block()
            best = min(best, Double(DispatchTime.now().uptimeNanoseconds - t) / 1_000_000)
        }
        print(String(format: "PERF|%@|%.1f", name, best))
        return best
    }

    func testTwentyThousandRows() throws {
        let st = SyntheticLedger.make(rows: Self.rows)
        let total = st.values.reduce(0) { $0 + ($1.arrayValue?.count ?? 0) }
        XCTAssertGreaterThanOrEqual(total, Self.rows)
        print("PERF|rows|\(total)")

        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("perf-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = try HesabStore(path: dir.appendingPathComponent("perf.sqlite").path)

        // database
        XCTAssertLessThan(try ms("db.save (full)") { try store.save(st) }, 20_000)
        var loaded: [String: JSONValue] = [:]
        XCTAssertLessThan(try ms("db.load") { loaded = try store.loadState() }, 20_000)
        XCTAssertEqual(loaded, st, "what is saved is exactly what is read back")

        // balances, commission, settlement
        let accounts = st["accounts"]!.arrayValue!
        let expenses = st["expenses"]!.arrayValue!
        ms("balances (5 ledgers)") { for a in accounts { _ = ImportAnalyzer.accountSummary(a, expenses: expenses) } }
        ms("commission open rows (5 ledgers)") { for i in 1...5 { _ = LedgerOps.openCommissionRows(st, accountId: "acc\(i)") } }
        try ms("commission settle (1 ledger)") {
            _ = try LedgerOps.settleCommission(st, accountId: "acc1", amount: 1_000_000, date: JalaliDate(jy: 1405, jm: 9, jd: 4),
                                               payMethod: .cash, cardId: nil)
        }
        ms("range sum (1 ledger, all rows)") { _ = LedgerOps.rangeSum(st, accountId: "acc1", from: 1, to: 99_999) }

        // search
        ms("search text (all)") { _ = SearchEngine.find(st, query: "سیمان", scope: .all) }
        ms("search two words") { _ = SearchEngine.find(st, query: "پمپ هوایی", scope: .all) }
        ms("search amount") { _ = SearchEngine.find(st, query: "۱۲۰,۰۰۰", scope: .all) }
        var index: SearchIndex!
        ms("search index build (once per change)") { index = SearchIndex(st) }
        ms("search with index: text") { _ = index.find(query: "سیمان") }
        ms("search with index: two words") { _ = index.find(query: "پمپ هوایی") }
        ms("search with index: amount") { _ = index.find(query: "۱۲۰,۰۰۰") }

        // backup, excel, import
        let today = JalaliDate(jy: 1405, jm: 9, jd: 4)
        var backup = Data()
        try ms("backup JSON (from database)") { backup = try store.exportBackup(today: today) }
        print("PERF|backup size KB|\(backup.count / 1024)")
        var snap = Data()
        try ms("backup JSON (from the saved snapshot, background)") { snap = try BackupExporter.encode(state: st, now: Date(), today: today) }
        XCTAssertEqual(snap.count, backup.count)
        ms("backup SHA-256") { _ = BackupFolder.sha256Hex(backup) }
        ms("excel (5 ledgers)") {
            _ = XLSXWriter.make(sheets: (1...5).map { (name: "پروژه \($0)", rows: ExportBuilder.excel(ExportBuilder.ledger(st, accountId: "acc\($0)", range: nil))) })
        }
        ms("import analysis of the backup", runs: 1) {
            guard case .success(let p) = BackupParser.parse(backup) else { return XCTFail("backup does not parse") }
            _ = ImportAnalyzer.analyze(p)
        }
    }
}
