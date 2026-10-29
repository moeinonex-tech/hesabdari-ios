import Foundation
import XCTest
@testable import HesabCore
@testable import HesabStore

/// Ledger operations on the clean fixture (exported by the real web app). Every expected number is
/// HAND-COMPUTED here (10% commission; open base 2,070,000 → 207,000 due before the first new payment).
final class LedgerOpsTests: XCTestCase {

    private func cleanState() throws -> [String: JSONValue] {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "rich_clean", withExtension: "json", subdirectory: "Goldens/import"))
        guard case .success(let parsed) = BackupParser.parse(try Data(contentsOf: url)) else { throw LedgerError.notFound }
        return ImportAnalyzer.analyze(parsed).cleanedState
    }

    private func ids(_ start: Int) -> IdSource {
        let counter = Counter(start)
        return IdSource(nowMs: { counter.next() }, random5: { "abcde" })
    }

    private func summary(_ st: [String: JSONValue], _ acc: String = "aT") -> AccountImportSummary {
        let a = st["accounts"]!.arrayValue!.first { $0["id"]?.stringValue == acc }!
        return ImportAnalyzer.accountSummary(a, expenses: st["expenses"]?.arrayValue ?? [])
    }

    private func settlements(_ st: [String: JSONValue]) -> [JSONValue] {
        st["accounts"]!.arrayValue!.first { $0["id"]?.stringValue == "aT" }!["commissionSettlements"]!.arrayValue!
    }

    private func row(_ st: [String: JSONValue], settlement sid: String) -> JSONValue? {
        st["expenses"]?.arrayValue?.first { $0["commissionSettlementId"]?.idString == sid }
    }

    func testPartialThenOverpaymentThenEditThenDelete() throws {
        var st = try cleanState()
        XCTAssertEqual(summary(st).remaining, 207_000)

        // 1) partial payment: 150,000 of 207,000 → debt 57,000
        let r1 = try LedgerOps.settleCommission(st, accountId: "aT", amount: 150_000, date: JalaliDate(jy: 1405, jm: 7, jd: 20), ids: ids(1_770_000_000_000))
        st = r1.state
        let s2 = settlements(st).last!
        XCTAssertEqual(s2["calculatedAmount"]?.intValue, 207_000)
        XCTAssertEqual(s2["remainingForStage"]?.intValue, 57_000)
        XCTAssertEqual(s2["balanceAfter"]?.intValue, 57_000)
        XCTAssertEqual(s2["isFull"]?.boolValue, false)
        XCTAssertEqual(s2["id"]?.stringValue, "s1770000000000abcd")
        XCTAssertEqual(row(st, settlement: r1.settlementId)?["desc"]?.stringValue,
                       "پرداخت کمیسیون تا ردیف هزینه \"۵\" (چک آهن) — مبلغ ۵۷.۰۰۰ از تسویه این مرحله از کمیسیون باقی مانده است")
        XCTAssertEqual(row(st, settlement: r1.settlementId)?["category"]?.stringValue, "کمیسیون")
        XCTAssertEqual(s2["expenseId"]?.idString, row(st, settlement: r1.settlementId)?["id"]?.idString)
        let inc = st["incomes"]!.arrayValue!.last!
        XCTAssertEqual(inc["desc"]?.stringValue, "دریافت کمیسیون از پروژه آزمون")
        XCTAssertEqual(inc["toman"]?.intValue, 150_000)
        XCTAssertEqual(inc["accountId"]?.stringValue, "personal")
        XCTAssertEqual(inc["commissionSettlementId"]?.idString, r1.settlementId)
        XCTAssertTrue(st["incomeSubcategories"]?["کمیسیون"]?.arrayValue?.contains(.string("پروژه آزمون")) ?? false)
        XCTAssertEqual(summary(st).remaining, 57_000)

        // 2) new expense 500,000 → +50,000 due; pay 300,000 of 107,000 → credit 193,000
        let add = try LedgerOps.addExpense(st, ExpenseInput(accountId: "aT", isTankhah: false, desc: "سیمان اضافه",
            category: "مصالح", subcategory: "سیمان", toman: 500_000, date: JalaliDate(jy: 1405, jm: 7, jd: 21),
            payMethod: .cash, cardId: nil, partyId: nil), ids: ids(1_770_000_001_000))
        st = add.state
        XCTAssertEqual(summary(st).remaining, 107_000)
        let r2 = try LedgerOps.settleCommission(st, accountId: "aT", amount: 300_000, date: JalaliDate(jy: 1405, jm: 7, jd: 22), ids: ids(1_770_000_002_000))
        st = r2.state
        let s3 = settlements(st).last!
        XCTAssertEqual(s3["calculatedAmount"]?.intValue, 50_000)
        XCTAssertEqual(s3["balanceAfter"]?.intValue, -193_000)
        XCTAssertEqual(s3["remainingForStage"]?.intValue, -250_000)
        XCTAssertEqual(s3["isFull"]?.boolValue, true)
        XCTAssertEqual(row(st, settlement: r2.settlementId)?["desc"]?.stringValue,
                       "پرداخت کمیسیون تا ردیف هزینه \"۶\" (سیمان اضافه) تسویه کامل — مبلغ ۱۹۳.۰۰۰ اضافه پرداخت، از کمیسیون بعدی کم می‌شود")
        XCTAssertEqual(summary(st).remaining, -193_000)
        // web formula (sum of remainingForStage) gives the same balance
        XCTAssertEqual(settlements(st).reduce(0) { $0 + ($1["remainingForStage"]?.intValue ?? 0) }, -193_000)

        // 3) D16: edit the first new payment 150,000 → 100,000: debt 107,000; next payment → credit 143,000
        let s2RowId = try XCTUnwrap(row(st, settlement: r1.settlementId)?["id"]?.idString)
        st = try LedgerOps.editExpense(st, id: s2RowId, ExpenseInput(accountId: "aT", isTankhah: false, desc: "",
            category: "", subcategory: "", toman: 100_000, date: JalaliDate(jy: 1405, jm: 7, jd: 20),
            payMethod: .cash, cardId: nil, partyId: nil))
        let e2 = settlements(st).first { $0["id"]?.idString == r1.settlementId }!
        let e3 = settlements(st).first { $0["id"]?.idString == r2.settlementId }!
        XCTAssertEqual(e2["toman"]?.intValue, 100_000)
        XCTAssertEqual(e2["balanceAfter"]?.intValue, 107_000)
        XCTAssertEqual(e2["isFull"]?.boolValue, false)
        XCTAssertEqual(e3["balanceAfter"]?.intValue, -143_000)
        XCTAssertEqual(e3["calculatedAmount"]?.intValue, 50_000, "calculatedAmount is kept (D16)")
        XCTAssertEqual(summary(st).remaining, -143_000)
        XCTAssertEqual(row(st, settlement: r1.settlementId)?["desc"]?.stringValue,
                       "پرداخت کمیسیون تا ردیف هزینه \"۵\" (چک آهن) — مبلغ ۱۰۷.۰۰۰ از تسویه این مرحله از کمیسیون باقی مانده است")
        XCTAssertEqual(row(st, settlement: r2.settlementId)?["desc"]?.stringValue,
                       "پرداخت کمیسیون تا ردیف هزینه \"۶\" (سیمان اضافه) تسویه کامل — مبلغ ۱۴۳.۰۰۰ اضافه پرداخت، از کمیسیون بعدی کم می‌شود")
        XCTAssertEqual(st["incomes"]!.arrayValue!.first { $0["commissionSettlementId"]?.idString == r1.settlementId }?["toman"]?.intValue, 100_000)

        // 4) delete the overpayment row: settlement and income go too; the 500,000 expense is open again
        let before = st
        let s3RowId = try XCTUnwrap(row(st, settlement: r2.settlementId)?["id"]?.idString)
        st = try LedgerOps.deleteExpense(st, id: s3RowId)
        XCTAssertNil(settlements(st).first { $0["id"]?.idString == r2.settlementId })
        XCTAssertNil(st["incomes"]!.arrayValue!.first { $0["commissionSettlementId"]?.idString == r2.settlementId })
        XCTAssertEqual(summary(st).remaining, 157_000)      // 107,000 debt + 50,000 open

        // saved and loaded through the database, then undo restores exactly
        let store = try HesabStore()
        try store.save(st)
        XCTAssertEqual(try store.loadState(), st)
        try store.save(before)
        XCTAssertEqual(try store.loadState(), before)
    }

    func testNewRowShapeMatchesWeb() throws {
        let st = try cleanState()
        let r = try LedgerOps.addExpense(st, ExpenseInput(accountId: "aT", isTankhah: false, desc: "گچ", category: "مصالح جدید",
            subcategory: "گچ", toman: 120_000, date: JalaliDate(jy: 1405, jm: 8, jd: 8), payMethod: .hamrahbank, cardId: "crd1", partyId: nil),
            ids: ids(1_770_000_009_000))
        let row = try XCTUnwrap(r.state["expenses"]?.arrayValue?.last?.objectValue)
        XCTAssertEqual(Set(row.keys), ["id", "accountId", "desc", "toman", "date", "ts", "type", "category", "subcategory", "payMethod", "cardId"])
        XCTAssertEqual(row["id"]?.stringValue, "e1770000009000abcde")
        XCTAssertEqual(row["ts"]?.intValue, 1_770_000_009_000)
        XCTAssertEqual(r.state["lastCardByAccount"]?["aT"]?.stringValue, "crd1")
        XCTAssertTrue(r.state["ledgerCategories"]?.arrayValue?.contains(.string("مصالح جدید")) ?? false)
        XCTAssertEqual(r.state["ledgerSubcategories"]?["مصالح جدید"]?.arrayValue, [.string("گچ")])

        let t = try LedgerOps.addExpense(st, ExpenseInput(accountId: "aT", isTankhah: true, desc: "", category: "",
            subcategory: "x", toman: 1_000_000, date: JalaliDate(jy: 1405, jm: 8, jd: 8), payMethod: .transfer, cardId: nil, partyId: "tp1"),
            ids: ids(1_770_000_009_500))
        let trow = try XCTUnwrap(t.state["expenses"]?.arrayValue?.last?.objectValue)
        XCTAssertEqual(Set(trow.keys), ["id", "accountId", "desc", "toman", "date", "ts", "type", "partyId", "payMethod"])
        XCTAssertEqual(trow["type"]?.stringValue, "tankhah")

        XCTAssertThrowsError(try LedgerOps.addExpense(st, ExpenseInput(accountId: "aT", isTankhah: false, desc: "", category: "",
            subcategory: "", toman: 0, date: JalaliDate(jy: 1405, jm: 8, jd: 8), payMethod: .cash, cardId: nil, partyId: nil))) { e in
            XCTAssertEqual(e as? LedgerError, .invalid(["شرح", "نوع هزینه", "زیردسته", "مبلغ"]))
        }
    }

    func testLinkedRowsAreProtected() throws {
        let st = try cleanState()
        XCTAssertThrowsError(try LedgerOps.deleteExpense(st, id: "eChk")) { e in
            XCTAssertEqual(e as? LedgerError, .linkedRow("چک"))
        }
    }

    func testEditLockMatchesWeb() {
        let today = JalaliDate(jy: 1405, jm: 8, jd: 8)
        XCTAssertTrue(LedgerOps.isEditLocked(rowDate: JalaliDate(jy: 1405, jm: 7, jd: 30), today: today, password: "۱۲۳۴", sessionUnlocked: false))
        XCTAssertFalse(LedgerOps.isEditLocked(rowDate: JalaliDate(jy: 1405, jm: 8, jd: 1), today: today, password: "۱۲۳۴", sessionUnlocked: false))
        XCTAssertFalse(LedgerOps.isEditLocked(rowDate: JalaliDate(jy: 1405, jm: 7, jd: 1), today: today, password: "۱۲۳۴", sessionUnlocked: true))
        XCTAssertFalse(LedgerOps.isEditLocked(rowDate: JalaliDate(jy: 1405, jm: 7, jd: 1), today: today, password: nil, sessionUnlocked: false))
        XCTAssertFalse(LedgerOps.isEditLocked(rowDate: JalaliDate(jy: 1405, jm: 7, jd: 1), today: today, password: "", sessionUnlocked: false))
    }
}

private final class Counter: @unchecked Sendable {
    private var value: Int
    init(_ start: Int) { value = start }
    func next() -> Int { defer { value += 1 }; return value }
}
