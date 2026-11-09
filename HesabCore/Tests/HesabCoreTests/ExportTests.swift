import Foundation
import XCTest
@testable import HesabCore

/// Export rows against the REAL web functions (phase1 tools/make_export_oracle.js on the rich_clean backup).
final class ExportTests: XCTestCase {

    private func json(_ name: String) throws -> JSONValue {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Goldens/import"))
        return try JSONCoding.decode(try Data(contentsOf: url))
    }

    private func cells(_ v: JSONValue?) -> [[ExportCell]] {
        (v?.arrayValue ?? []).map { row in
            (row.arrayValue ?? []).map { c in
                if let n = c.intValue, c.stringValue == nil { return .number(n) }
                return .text(c.stringValue ?? "")
            }
        }
    }

    func testRowsMatchWebApp() throws {
        let o = try json("export_oracle")
        let backup = try json("rich_clean")
        guard case .success(let parsed) = BackupParser.parse(try JSONCoding.encode(backup)) else { return XCTFail("parse") }
        // compare on the web state as exported (no generated ids needed for rows)
        let st = parsed.state
        let acc = try XCTUnwrap(st["accounts"]?.arrayValue?.first?["id"]?.idString)
        let r = DateRange(from: JalaliDate(jy: 1405, jm: 7, jd: 1), to: JalaliDate(jy: 1405, jm: 7, jd: 5))
        XCTAssertEqual(ExportBuilder.ledger(st, accountId: acc, range: nil), cells(o["ledger"]))
        XCTAssertEqual(ExportBuilder.ledger(st, accountId: acc, range: r), cells(o["ledgerRange"]))
        XCTAssertEqual(ExportBuilder.ledger(st, accountId: acc, range: nil, includeLinked: false), cells(o["ledgerNoLinked"]))
        XCTAssertEqual(ExportBuilder.personal(st, range: nil), cells(o["personal"]))
        XCTAssertEqual(ExportBuilder.income(st, range: nil), cells(o["income"]))
        XCTAssertEqual(ExportBuilder.income(st, range: r), cells(o["incomeRange"]))
        XCTAssertEqual(ExportBuilder.checks(st, range: nil), cells(o["checks"]))
        XCTAssertEqual(ExportBuilder.persons(st, range: nil), cells(o["persons"]))
        XCTAssertEqual(ExportBuilder.sheetName(st["accounts"]?.arrayValue?.first?["name"]?.stringValue ?? ""), o["sheetName"]?.stringValue)
    }

    /// Excel: the totals sit right under the last record, toman and rial as real (bold) numbers in their own columns
    func testExcelTotalsUnderLastRow() throws {
        let st: [String: JSONValue] = [
            "accounts": .array([.object(["id": .string("a"), "name": .string("x")])]),
            "expenses": .array([
                .object(["id": .string("1"), "accountId": .string("a"), "desc": .string("d"), "toman": .int(1_500_000),
                         "date": .object(["jy": .int(1405), "jm": .int(8), "jd": .int(1)])]),
                .object(["id": .string("2"), "accountId": .string("a"), "type": .string("tankhah"), "toman": .int(4_000_000),
                         "date": .object(["jy": .int(1405), "jm": .int(8), "jd": .int(2)])]),
            ]),
            "personalExpenses": .array([.object(["id": .string("p"), "toman": .int(20_000), "date": .object(["jy": .int(1405), "jm": .int(8), "jd": .int(3)])])]),
        ]
        let raw = ExportBuilder.ledger(st, accountId: "a", range: nil)
        let x = ExportBuilder.excel(raw, extra: [("جمع کل تنخواه دریافتی", ExportBuilder.tankhahTotal(st, accountId: "a", range: nil))])
        XCTAssertEqual(x.count, raw.count + 1)
        XCTAssertEqual(Array(x.prefix(raw.count - 1)), Array(raw.dropLast()))          // records untouched
        XCTAssertEqual(x[raw.count - 1][3...5], [.bold("جمع کل هزینه‌ها"), .boldNumber(1_500_000), .boldNumber(15_000_000)])
        XCTAssertEqual(x[raw.count][3...5], [.bold("جمع کل تنخواه دریافتی"), .boldNumber(4_000_000), .boldNumber(40_000_000)])
        // every sheet ends with its total in the toman / rial columns
        let p = ExportBuilder.excel(ExportBuilder.personal(st, range: nil))
        XCTAssertEqual(p.last?[2...4], [.bold("جمع کل هزینه‌ها"), .boldNumber(20_000), .boldNumber(200_000)])
        for rows in [ExportBuilder.income(st, range: nil), ExportBuilder.checks(st, range: nil), ExportBuilder.persons(st, range: nil)] {
            let e = ExportBuilder.excel(rows)
            XCTAssertTrue(e.last?.contains(.boldNumber(0)) ?? false, "empty sheet still has its total line")
        }
        let sheet = XLSXWriter.sheetXML(x)
        XCTAssertTrue(sheet.contains(#"s="3"><v>15000000</v>"#))
    }

    func testXLSXIsAValidZip() throws {
        let data = XLSXWriter.make(sheets: [("دفتر: آزمون/۱", [[.text("تاریخ"), .text("مبلغ")], [.text("۱۴۰۵/۸/۸"), .number(1_000_000)]]),
                                            ("چک‌ها", [[.text("x & <y>")]])])
        XCTAssertEqual(Array(data.prefix(4)), [0x50, 0x4B, 0x03, 0x04])
        XCTAssertEqual(Zip.crc32(Data("123456789".utf8)), 0xCBF43926)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("hesab-test.xlsx")
        try data.write(to: url)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        p.arguments = ["-tq", url.path]
        let pipe = Pipe()
        p.standardOutput = pipe
        try p.run()
        p.waitUntilExit()
        XCTAssertEqual(p.terminationStatus, 0, String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self))
    }
}
