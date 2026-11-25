import XCTest
@testable import HesabCore

/// The live «مانده تنخواه» on the ledger's main card and the «تنخواه (کل دفتر)» card of the ledger PDF come from one
/// function (AccountOps.tankhahRemaining). These tests pin it to the PDF code as it was before (copied verbatim below)
/// and check that it follows every change at once.
final class TankhahRemainingTests: XCTestCase {

    /// verbatim copy of the ledger PDF's tankhah card maths before this change (PDFReport.ledgerPDF)
    private func pdfReference(_ state: [String: JSONValue], accountId: String) -> (tk: Int, spent: Int, left: Int)? {
        let all = (state["expenses"]?.arrayValue ?? []).filter { $0["accountId"]?.idString == accountId }
        if all.contains(where: { $0["type"]?.stringValue == "tankhah" }) {
            let tk = all.filter { $0["type"]?.stringValue == "tankhah" }.reduce(0) { $0 + ImportAnalyzer.toman($1) }
            let spent = all.filter { $0["type"]?.stringValue != "tankhah" }.reduce(0) { $0 + ImportAnalyzer.toman($1) }
            return (tk, spent, tk - spent)
        }
        return nil
    }

    private func assertSameAsPDF(_ st: [String: JSONValue], _ accountId: String, _ msg: String = "",
                                 file: StaticString = #filePath, line: UInt = #line) {
        let ref = pdfReference(st, accountId: accountId)
        let got = AccountOps.tankhahRemaining(st, accountId: accountId)
        XCTAssertEqual(got == nil, ref == nil, "shown only when the PDF shows it \(msg)", file: file, line: line)
        if let r = ref, let g = got {
            XCTAssertEqual(g.tankhah, r.tk, msg, file: file, line: line)
            XCTAssertEqual(g.spent, r.spent, msg, file: file, line: line)
            XCTAssertEqual(g.remaining, r.left, msg, file: file, line: line)
        }
    }

    private func richClean() throws -> [String: JSONValue] {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "rich_clean", withExtension: "json", subdirectory: "Goldens/import"))
        guard case .success(let p) = BackupParser.parse(try Data(contentsOf: url)) else { throw NSError(domain: "fixture", code: 1) }
        return ImportAnalyzer.analyze(p).cleanedState
    }

    /// the UI smoke-test ledger: tankhah 7,000,000; expenses 900,000 + 2,500,000 + 300,000 + reward 4,000,000
    private func small() throws -> [String: JSONValue] {
        let json = """
        {"accounts": [{"id": "a1", "name": "با تنخواه"}, {"id": "a2", "name": "بدون تنخواه"}, {"id": "a3", "name": "خالی"}],
         "expenses": [
          {"id": "e1", "accountId": "a1", "desc": "سیمان", "category": "مصالح", "subcategory": "سیمان", "toman": 900000, "date": {"jy": 1405, "jm": 8, "jd": 10}, "ts": 1},
          {"id": "e2", "accountId": "a1", "desc": "میلگرد", "category": "مصالح", "subcategory": "آهن", "toman": 2500000, "date": {"jy": 1405, "jm": 8, "jd": 12}, "ts": 2},
          {"id": "e3", "accountId": "a1", "desc": "نهار", "category": "خوراک", "subcategory": "نهار", "toman": 300000, "date": {"jy": 1405, "jm": 8, "jd": 14}, "ts": 3},
          {"id": "e6", "accountId": "a1", "desc": "پاداش", "category": "پاداش", "reward": true, "payMethod": "cash", "toman": 4000000, "date": {"jy": 1405, "jm": 8, "jd": 13}, "ts": 8},
          {"id": "e4", "accountId": "a1", "type": "tankhah", "partyId": "tp1", "desc": "", "payMethod": "cash", "toman": 5000000, "date": {"jy": 1405, "jm": 8, "jd": 2}, "ts": 6},
          {"id": "e5", "accountId": "a1", "type": "tankhah", "partyId": "tp1", "desc": "", "payMethod": "transfer", "toman": 2000000, "date": {"jy": 1405, "jm": 8, "jd": 3}, "ts": 7},
          {"id": "e7", "accountId": "a2", "desc": "گچ", "category": "مصالح", "subcategory": "گچ", "toman": 400000, "date": {"jy": 1405, "jm": 8, "jd": 5}, "ts": 9}
         ],
         "tankhahParties": [{"id": "tp1", "type": "person", "name": "کارفرما"}]}
        """
        return try JSONDecoder().decode([String: JSONValue].self, from: Data(json.utf8))
    }

    func testSameNumbersAsThePDF() throws {
        for (name, st) in [("small", try small()), ("rich_clean", try richClean()), ("synthetic", SyntheticLedger.make(rows: 6_000))] {
            let ids = (st["accounts"]?.arrayValue ?? []).compactMap { $0["id"]?.idString }
            XCTAssertFalse(ids.isEmpty, name)
            for id in ids { assertSameAsPDF(st, id, "\(name) \(id)") }
        }
        let st = try small()
        let r = try XCTUnwrap(AccountOps.tankhahRemaining(st, accountId: "a1"))
        XCTAssertEqual(r, TankhahRemaining(tankhah: 7_000_000, spent: 7_700_000))
        XCTAssertEqual(r.remaining, -700_000)          // overspent: shown negative, as in the PDF
    }

    func testNothingShownWithoutTankhah() throws {
        let st = try small()
        XCTAssertNil(AccountOps.tankhahRemaining(st, accountId: "a2"), "a ledger with expenses but no tankhah")
        XCTAssertNil(AccountOps.tankhahRemaining(st, accountId: "a3"), "an empty ledger")
        XCTAssertNil(AccountOps.tankhahRemaining(st, accountId: "nope"), "an unknown ledger")
        XCTAssertNil(AccountOps.tankhahRemaining([:], accountId: "a1"), "no data at all")
    }

    func testFollowsAddEditAndDeleteAtOnce() throws {
        var st = try small()
        let day = JalaliDate(jy: 1405, jm: 8, jd: 20)
        // add an expense
        let add = try LedgerOps.addExpense(st, ExpenseInput(accountId: "a1", isTankhah: false, desc: "آجر", category: "مصالح",
            subcategory: "آجر", toman: 120_000, date: day, payMethod: .cash, cardId: nil, partyId: nil))
        st = add.state
        XCTAssertEqual(AccountOps.tankhahRemaining(st, accountId: "a1")?.remaining, -820_000)
        assertSameAsPDF(st, "a1", "after add")
        // edit its amount
        st = try LedgerOps.editExpense(st, id: add.id, ExpenseInput(accountId: "a1", isTankhah: false, desc: "آجر", category: "مصالح",
            subcategory: "آجر", toman: 220_000, date: day, payMethod: .cash, cardId: nil, partyId: nil))
        XCTAssertEqual(AccountOps.tankhahRemaining(st, accountId: "a1")?.remaining, -920_000)
        assertSameAsPDF(st, "a1", "after edit")
        // delete it
        st = try LedgerOps.deleteExpense(st, id: add.id)
        XCTAssertEqual(AccountOps.tankhahRemaining(st, accountId: "a1")?.remaining, -700_000)
        assertSameAsPDF(st, "a1", "after delete")
        // a new tankhah row
        let tk = try LedgerOps.addExpense(st, ExpenseInput(accountId: "a1", isTankhah: true, desc: "", category: "", subcategory: "",
            toman: 1_000_000, date: day, payMethod: .transfer, cardId: nil, partyId: "tp1"))
        st = tk.state
        XCTAssertEqual(AccountOps.tankhahRemaining(st, accountId: "a1")?.remaining, 300_000)
        assertSameAsPDF(st, "a1", "after a tankhah row")
        // a ledger without tankhah gets its first one: it appears; removing it hides it again
        XCTAssertNil(AccountOps.tankhahRemaining(st, accountId: "a2"))
        let first = try LedgerOps.addExpense(st, ExpenseInput(accountId: "a2", isTankhah: true, desc: "", category: "", subcategory: "",
            toman: 500_000, date: day, payMethod: .transfer, cardId: nil, partyId: "tp1"))
        XCTAssertEqual(AccountOps.tankhahRemaining(first.state, accountId: "a2")?.remaining, 100_000)
        assertSameAsPDF(first.state, "a2", "first tankhah")
        XCTAssertNil(AccountOps.tankhahRemaining(try LedgerOps.deleteExpense(first.state, id: first.id), accountId: "a2"))
    }
}
