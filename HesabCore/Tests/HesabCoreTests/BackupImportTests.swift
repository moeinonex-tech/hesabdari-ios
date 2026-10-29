import Foundation
import XCTest
@testable import HesabCore
@testable import HesabStore

/// Import / storage / export against fixtures produced by the REAL web app (phase1 tools/make_import_fixtures.js):
/// the backup file the web app exports and the numbers the web app itself computes for it.
final class BackupImportTests: XCTestCase {

    private func fixture(_ name: String) throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Goldens/import"),
                                "missing fixture \(name)")
        return try Data(contentsOf: url)
    }

    private func expected(_ name: String) throws -> JSONValue {
        try JSONCoding.decode(try fixture(name + ".expected"))
    }

    private func parseOK(_ data: Data, file: StaticString = #filePath, line: UInt = #line) throws -> ParsedBackup {
        switch BackupParser.parse(data) {
        case .success(let p): return p
        case .failure(let e): XCTFail("parse failed: \(e.message)", file: file, line: line); throw e
        }
    }

    private func parseError(_ s: String) -> BackupFormatError? {
        if case .failure(let e) = BackupParser.parse(Data(s.utf8)) { return e }
        return nil
    }

    // Same inputs as phase1 BK03 (web validation matrix). Web texts must match; D4 rows differ on purpose.
    func testValidationMatrixMatchesWebAndD4() {
        XCTAssertEqual(parseError("{oops"), .notJSON)
        XCTAssertEqual(parseError("{}"), .notFullBackup)
        XCTAssertEqual(parseError("[{\"desc\":\"x\",\"toman\":1}]"), .notFullBackup)
        XCTAssertEqual(parseError("{\"__appBackup\":\"hesabdari-full\",\"version\":1}"), .notFullBackup)
        XCTAssertEqual(parseError("{\"__appBackup\":\"hesabdari-full\",\"version\":1,\"state\":{\"accounts\":{},\"expenses\":[],\"personalExpenses\":[]}}"), .badStructure)
        XCTAssertEqual(parseError("{\"state\":{\"accounts\":[],\"expenses\":[]}}"), .badStructure)
        XCTAssertEqual(parseError("{\"__appBackup\":\"hesabdari-section\",\"section\":\"ledger\",\"version\":1,\"data\":{\"accounts\":[]}}"), .notFullBackup)
        XCTAssertEqual(parseError("42"), .unrecognized)
        // web accepts these two; iOS rejects them (decision D4)
        XCTAssertEqual(parseError("{\"__appBackup\":\"hesabdari-full\",\"version\":2,\"state\":{\"accounts\":[],\"expenses\":[],\"personalExpenses\":[]}}"),
                       .unsupportedFormat(tag: "hesabdari-full", version: "2"))
        XCTAssertEqual(parseError("{\"__appBackup\":\"something-else\",\"state\":{\"accounts\":[],\"expenses\":[],\"personalExpenses\":[]}}"),
                       .unsupportedFormat(tag: "something-else", version: "—"))
        XCTAssertNil(parseError("{\"accounts\":[],\"expenses\":[],\"personalExpenses\":[]}"))   // raw state
        XCTAssertEqual(BackupFormatError.notJSON.message, "فایل انتخاب‌شده یک JSON معتبر نیست.")
        XCTAssertEqual(BackupFormatError.badStructure.message, "ساختار فایل با پشتیبان کامل این اپ مطابقت نداره.")
    }

    func testCleanBackupNumbersMatchWebApp() throws {
        let report = ImportAnalyzer.analyze(try parseOK(try fixture("rich_clean")))
        let exp = try expected("rich_clean")

        XCTAssertEqual(report.summaryLines, exp["summary"]?.arrayValue?.compactMap(\.stringValue))
        XCTAssertEqual(report.personalTotal, exp["personalTotal"]?.intValue)
        XCTAssertEqual(report.incomeTotal, exp["incomeTotal"]?.intValue)
        let expAccounts = try XCTUnwrap(exp["accounts"]?.arrayValue)
        XCTAssertEqual(report.accounts.count, expAccounts.count)
        for (a, e) in zip(report.accounts, expAccounts) {
            XCTAssertEqual(a.id, e["id"]?.stringValue)
            XCTAssertEqual(a.name, e["name"]?.stringValue)
            XCTAssertEqual(a.rows, e["rows"]?.intValue)
            XCTAssertEqual(a.expenseTotal, e["expenseTotal"]?.intValue)
            XCTAssertEqual(a.tankhahTotal, e["tankhahTotal"]?.intValue)
            XCTAssertEqual(a.percent, e["percent"]?.doubleValue)
            XCTAssertEqual(a.openBase, e["openBase"]?.intValue, "open base (same as web for this data)")
            XCTAssertEqual(a.accrued, e["accrued"]?.intValue)
            XCTAssertEqual(a.balance, e["pastShortfall"]?.intValue)
            XCTAssertEqual(a.settled, e["settled"]?.intValue)
        }

        XCTAssertTrue(report.canImport, report.issues.map(\.title).joined(separator: " | "))
        XCTAssertEqual(report.cvvRemoved, 1)
        XCTAssertEqual(report.generatedIds.count, 1, "the legacy row without id (D1)")
        XCTAssertNil(report.cleanedState["cards"]?.arrayValue?.first?["cvv"])
        // D1: deterministic — the same file gives the same id
        let again = ImportAnalyzer.analyze(try parseOK(try fixture("rich_clean")))
        XCTAssertEqual(again.generatedIds, report.generatedIds)
        // unknown fields kept
        XCTAssertNotNil(report.cleanedState["zFutureRootField"])
        let e1 = report.cleanedState["expenses"]?.arrayValue?.first { $0["id"]?.stringValue == "e1" }
        XCTAssertEqual(e1?["xFutureRow"]?.stringValue, "keep-me")
    }

    func testDirtyBackupIsBlockedForOpenDecisions() throws {
        let report = ImportAnalyzer.analyze(try parseOK(try fixture("rich_dirty")))
        let exp = try expected("rich_dirty")
        XCTAssertEqual(report.summaryLines, exp["summary"]?.arrayValue?.compactMap(\.stringValue))
        XCTAssertFalse(report.canImport)
        let blocking = Set(report.issues.filter { $0.level == .blocking }.map(\.id))
        XCTAssertEqual(blocking, ["d2", "d3"])
    }

    func testStoreRoundTripIsLossless() throws {
        let report = ImportAnalyzer.analyze(try parseOK(try fixture("rich_clean")))
        let store = try HesabStore()
        XCTAssertTrue(store.isEmpty)
        try store.replaceAll(with: report.cleanedState, sourceExportedAtJalali: report.exportedAtJalali, reportLines: report.summaryLines)
        XCTAssertFalse(store.isEmpty)
        XCTAssertEqual(try store.loadState(), report.cleanedState)

        // export → import again gives the same state; no CVV anywhere in the file
        let exported = try store.exportBackup(now: Date(timeIntervalSince1970: 1_793_000_000), today: JalaliDate(jy: 1405, jm: 8, jd: 8))
        let text = String(decoding: exported, as: UTF8.self)
        XCTAssertFalse(text.contains("\"cvv\""))
        XCTAssertTrue(text.contains("\"exportedAtJalali\" : \"۸ آبان ۱۴۰۵\""))
        let reparsed = try parseOK(exported)
        XCTAssertTrue(reparsed.isEnvelope)
        let report2 = ImportAnalyzer.analyze(reparsed)
        XCTAssertEqual(report2.cleanedState, report.cleanedState)
        XCTAssertTrue(report2.generatedIds.isEmpty)
        XCTAssertEqual(report2.accounts, report.accounts)

        // replacing is all-or-nothing and leaves exactly the new state
        try store.replaceAll(with: report2.cleanedState, sourceExportedAtJalali: nil, reportLines: [])
        XCTAssertEqual(try store.loadState(), report.cleanedState)
        XCTAssertNotNil(try store.lastImport())
    }

    func testFormatJalaliMatchesWeb() {
        XCTAssertEqual(BackupExporter.formatJalali(JalaliDate(jy: 1405, jm: 7, jd: 28)), "۲۸ مهر ۱۴۰۵")
        XCTAssertEqual(BackupExporter.formatJalali(JalaliDate(jy: 1405, jm: 8, jd: 7)), "۷ آبان ۱۴۰۵")
    }
}
