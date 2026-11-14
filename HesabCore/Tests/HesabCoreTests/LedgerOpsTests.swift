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
                       "پرداخت کمیسیون تا ردیف هزینه \"۶\" (چک آهن) — مبلغ ۵۷.۰۰۰ از تسویه این مرحله از کمیسیون باقی مانده است")
        XCTAssertEqual(row(st, settlement: r1.settlementId)?["category"]?.stringValue, "کمیسیون")
        XCTAssertEqual(s2["expenseId"]?.idString, row(st, settlement: r1.settlementId)?["id"]?.idString)
        let inc = st["incomes"]!.arrayValue!.last!
        XCTAssertEqual(inc["desc"]?.stringValue, "دریافت کمیسیون از پروژه آزمون")
        XCTAssertEqual(inc["toman"]?.intValue, 150_000)
        XCTAssertEqual(inc["accountId"]?.stringValue, "personal")
        XCTAssertEqual(inc["commissionSettlementId"]?.idString, r1.settlementId)
        XCTAssertEqual(inc["category"]?.stringValue, "مدیریت پیمان ساختمان")
        XCTAssertTrue(st["incomeSubcategories"]?["مدیریت پیمان ساختمان"]?.arrayValue?.contains(.string("پروژه آزمون")) ?? false)
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
                       "پرداخت کمیسیون تا ردیف هزینه \"۷\" (سیمان اضافه) تسویه کامل — مبلغ ۱۹۳.۰۰۰ اضافه پرداخت، از کمیسیون بعدی کم می‌شود")
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
                       "پرداخت کمیسیون تا ردیف هزینه \"۶\" (چک آهن) — مبلغ ۱۰۷.۰۰۰ از تسویه این مرحله از کمیسیون باقی مانده است")
        XCTAssertEqual(row(st, settlement: r2.settlementId)?["desc"]?.stringValue,
                       "پرداخت کمیسیون تا ردیف هزینه \"۷\" (سیمان اضافه) تسویه کامل — مبلغ ۱۴۳.۰۰۰ اضافه پرداخت، از کمیسیون بعدی کم می‌شود")
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

final class CategoryOpsTests: XCTestCase {
    func state() -> [String: JSONValue] {
        [
            "ledgerCategories": .array([.string("مصالح"), .string("خوراک"), .string("کمیسیون")]),
            "ledgerSubcategories": .object(["مصالح": .array([.string("سیمان"), .string("آهن")]), "خوراک": .array([.string("نهار")])]),
            "expenses": .array([
                .object(["id": .string("e1"), "category": .string("خوراک"), "subcategory": .string("نهار"), "toman": .int(100)]),
                .object(["id": .string("e2"), "category": .string("مصالح"), "subcategory": .string("سیمان"), "toman": .int(900)]),
                .object(["id": .string("e3"), "toman": .int(300), "items": .array([
                    .object(["category": .string("خوراک"), "subcategory": .string("نهار"), "toman": .int(100), "desc": .string("")]),
                    .object(["category": .string("مصالح"), "subcategory": .string("آهن"), "toman": .int(200), "desc": .string("")]),
                ])]),
            ]),
            "ledgerDescMap": .object(["نهار کارگر": .string("خوراک")]),
        ]
    }

    func testUsageAndGuard() throws {
        let st = state()
        XCTAssertEqual(CategoryOps.usage(st, .ledger, category: "خوراک"), 2)
        XCTAssertEqual(CategoryOps.usage(st, .ledger, category: "مصالح", sub: "آهن"), 1)
        XCTAssertThrowsError(try CategoryOps.removeCategory(st, .ledger, "خوراک", replaceWith: nil))   // used → needs a replacement
        XCTAssertThrowsError(try CategoryOps.removeCategory(st, .ledger, "کمیسیون", replaceWith: "مصالح"))  // built-in
    }

    func testReplaceCategoryMovesRowsItemsAndLearning() throws {
        let out = try CategoryOps.removeCategory(state(), .ledger, "خوراک", replaceWith: "هزینه‌های کارگاهی")
        XCTAssertFalse(CategoryOps.categories(out, .ledger).contains("خوراک"))
        XCTAssertEqual(CategoryOps.usage(out, .ledger, category: "هزینه‌های کارگاهی"), 2)
        let rows = out["expenses"]!.arrayValue!
        XCTAssertEqual(rows[0]["category"]?.stringValue, "هزینه‌های کارگاهی")
        XCTAssertEqual(rows[0]["subcategory"]?.stringValue, "نهار")
        XCTAssertEqual(rows[2]["toman"]?.intValue, 300)                          // amount untouched
        XCTAssertEqual(rows[2]["items"]?.arrayValue?[0]["category"]?.stringValue, "هزینه‌های کارگاهی")
        XCTAssertEqual(out["ledgerDescMap"]?["نهار کارگر"]?.stringValue, "هزینه‌های کارگاهی")
        XCTAssertEqual(CategoryOps.subcategories(out, .ledger, category: "هزینه‌های کارگاهی"), ["نهار"])
        // the fixed keyword table («خوراک» for «نهار») is redirected, never suggests the removed name
        XCTAssertFalse(Learning.categoryCandidates(out, .ledger, desc: "تهیه نهار تیم").contains("خوراک"))
    }

    func testColoursFollowTheRightMap() throws {
        var st = state()
        st["categoryColors"] = .object(["خوراک": .string("#FF3366")])
        st["personalCategories"] = .array([.string("خوراک")])          // same name used in the personal part too
        st["incomeCategories"] = .array([.string("حقوق"), .string("اجاره")])
        st["incomes"] = .array([.object(["id": .string("i1"), "category": .string("حقوق"), "toman": .int(5)])])
        st["categoryColorsIncome"] = .object(["حقوق": .string("#22C55E")])

        let a = try CategoryOps.removeCategory(st, .ledger, "خوراک", replaceWith: "غذا")
        XCTAssertEqual(a["categoryColors"]?["غذا"]?.stringValue, "#FF3366")      // replacement inherits
        XCTAssertEqual(a["categoryColors"]?["خوراک"]?.stringValue, "#FF3366")    // personal still uses «خوراک»: kept

        let b = try CategoryOps.removeCategory(st, .income, "حقوق", replaceWith: "اجاره")
        XCTAssertEqual(b["categoryColorsIncome"]?["اجاره"]?.stringValue, "#22C55E")
        XCTAssertNil(b["categoryColorsIncome"]?["حقوق"])
        XCTAssertEqual(b["categoryColors"]?["خوراک"]?.stringValue, "#FF3366")    // ledger/personal map untouched
    }

    func testRemoveUnusedAndReplaceSub() throws {
        var st = state()
        st = try CategoryOps.removeSubcategory(st, .ledger, category: "مصالح", "آهن", replaceWith: "سیمان")
        XCTAssertEqual(CategoryOps.usage(st, .ledger, category: "مصالح", sub: "سیمان"), 2)
        XCTAssertEqual(CategoryOps.subcategories(st, .ledger, category: "مصالح"), ["سیمان"])
        let st2 = try CategoryOps.removeCategory(state(), .ledger, "کمیسیون2", replaceWith: nil)   // unknown + unused → just gone
        XCTAssertEqual(CategoryOps.categories(st2, .ledger).count, 3)
    }
}

final class FuzzyAndChecksTests: XCTestCase {
    func testFuzzyDuplicates() {
        let list = ["مصالح ساختمانی", "حمل و نقل", "خوراک"]
        XCTAssertEqual(Fuzzy.matches(list, "مصالح ساختمانى"), ["مصالح ساختمانی"])     // Arabic ى
        XCTAssertEqual(Fuzzy.matches(list, "مصالح‌ساختمانی"), ["مصالح ساختمانی"])     // half-space
        XCTAssertEqual(Fuzzy.matches(list, "مصالح ساختمان"), ["مصالح ساختمانی"])      // a typo / letter less
        XCTAssertEqual(Fuzzy.matches(list, "مصالح ساختمانی"), [])                      // exact → nothing to ask
        XCTAssertEqual(Fuzzy.matches(list, "بیمه کارگران"), [])                        // really new
        XCTAssertEqual(Fuzzy.matches(list, "حم"), [])                                  // too short
    }

    func testDueChecksAndAnswers() throws {
        let today = JalaliDate(jy: 1405, jm: 8, jd: 18)
        let st: [String: JSONValue] = ["reminderChecks": .array([
            .object(["id": .string("a"), "status": .string("pending"), "amount": .int(10), "dueDate": .object(["jy": .int(1405), "jm": .int(8), "jd": .int(18)])]),
            .object(["id": .string("b"), "status": .string("pending"), "amount": .int(10), "dueDate": .object(["jy": .int(1405), "jm": .int(8), "jd": .int(2)])]),
            .object(["id": .string("c"), "status": .string("pending"), "amount": .int(10), "dueDate": .object(["jy": .int(1405), "jm": .int(9), "jd": .int(1)])]),
            .object(["id": .string("d"), "status": .string("cashed"), "amount": .int(10), "dueDate": .object(["jy": .int(1405), "jm": .int(8), "jd": .int(1)])]),
            .object(["id": .string("e"), "status": .string("pending"), "muted": .bool(true), "amount": .int(10), "dueDate": .object(["jy": .int(1405), "jm": .int(8), "jd": .int(1)])]),
        ])]
        XCTAssertEqual(ReminderOps.dueChecksToAsk(st, today: today), ["b", "a"])
        let no = try ReminderOps.answerNotCollected(st, id: "a")
        XCTAssertEqual(no["reminderChecks"]?.arrayValue?[0]["collectAnswer"]?.stringValue, "no")
        XCTAssertEqual(no["reminderChecks"]?.arrayValue?[0]["status"]?.stringValue, "pending")
    }

    func testTankhahPaidByCheck() throws {
        var st: [String: JSONValue] = ["expenses": .array([]), "reminderChecks": .array([])]
        let r = try ReminderOps.addTankhahCheck(st, amount: 5_000_000, party: "کارفرما", bankName: "ملت", checkNumber: "123",
                                                desc: "", dueDate: JalaliDate(jy: 1405, jm: 9, jd: 1), accountId: "a1")
        st = r.state
        var input = ExpenseInput(accountId: "a1", isTankhah: true, desc: "", category: "", subcategory: "", toman: 5_000_000,
                                 date: JalaliDate(jy: 1405, jm: 8, jd: 18), payMethod: .check, cardId: nil, partyId: "p1")
        input.checkIds = [r.id]
        let added = try LedgerOps.addExpense(st, input)
        let row = added.state["expenses"]!.arrayValue![0]
        XCTAssertEqual(row["checkId"]?.stringValue, r.id)
        XCTAssertTrue(ReminderOps.isTankhahCheck(added.state, added.state["reminderChecks"]!.arrayValue![0]))
        XCTAssertEqual(added.state["expenses"]!.arrayValue!.count, 1)              // the check makes no expense row
        // editing the تنخواه (same method, no new check chosen) keeps the link
        input.checkIds = []
        input.desc = "دریافت از کارفرما"
        let edited = try LedgerOps.editExpense(added.state, id: added.id, input)
        XCTAssertEqual(edited["expenses"]!.arrayValue![0]["checkId"]?.stringValue, r.id)
        // cashing the check writes «وصول شد» on the تنخواه row
        let cashed = try ReminderOps.setCheckStatus(edited, id: r.id, status: "cashed", today: JalaliDate(jy: 1405, jm: 9, jd: 1))
        XCTAssertTrue(cashed["expenses"]!.arrayValue![0]["desc"]!.stringValue!.contains("وصول شد"))
    }
}

final class SectionBackupTests: XCTestCase {
    func testRoundTripOnlyTouchesItsSection() throws {
        let st: [String: JSONValue] = [
            "incomes": .array([.object(["id": .string("i1"), "toman": .int(5)])]), "incomeCategories": .array([.string("حقوق")]),
            "expenses": .array([.object(["id": .string("e1"), "toman": .int(9)])]),
        ]
        let file = try SectionBackup.build(st, .income, todayText: "۱۸ آبان ۱۴۰۵")
        // another section's file is refused
        if case .success = SectionBackup.parse(file, .personal) { XCTFail("wrong section accepted") }
        guard case .success(let data) = SectionBackup.parse(file, .income) else { return XCTFail("own section refused") }
        var changed = st
        changed["incomes"] = .array([])
        changed["expenses"] = .array([])                         // not part of «درآمد»
        let restored = SectionBackup.apply(changed, .income, data)
        XCTAssertEqual(restored["incomes"]?.arrayValue?.count, 1)
        XCTAssertEqual(restored["expenses"]?.arrayValue?.count, 0)  // untouched
        XCTAssertEqual(BackupSection.income.summary(st), ["درآمدها: ۱"])
    }
}

final class ScopedSearchTests: XCTestCase {
    let st: [String: JSONValue] = [
        "accounts": .array([.object(["id": .string("a1"), "name": .string("کوچه وصال")]), .object(["id": .string("a2"), "name": .string("پروژه دو")])]),
        "tankhahParties": .array([.object(["id": .string("tp"), "name": .string("کارفرما")])]),
        "expenses": .array([
            .object(["id": .string("e1"), "accountId": .string("a1"), "desc": .string("خرید سيمان"), "category": .string("مصالح"),
                     "toman": .int(1_200_000), "date": .object(["jy": .int(1405), "jm": .int(8), "jd": .int(1)])]),
            .object(["id": .string("e2"), "accountId": .string("a2"), "desc": .string("سیمان تیپ ۲"), "category": .string("مصالح"),
                     "toman": .int(900_000), "date": .object(["jy": .int(1405), "jm": .int(8), "jd": .int(5)])]),
            .object(["id": .string("e3"), "accountId": .string("a1"), "type": .string("tankhah"), "partyId": .string("tp"),
                     "toman": .int(50_000_000), "date": .object(["jy": .int(1405), "jm": .int(8), "jd": .int(2)])]),
        ]),
        "personalExpenses": .array([.object(["id": .string("p1"), "desc": .string("سیمان باغچه"), "toman": .int(10_000),
                                             "date": .object(["jy": .int(1405), "jm": .int(8), "jd": .int(3)])])]),
    ]

    func testScopesNeverMix() {
        // «کلی»: every ledger is its own group, then personal
        let all = SearchEngine.find(st, query: "سیمان", scope: .all)
        XCTAssertEqual(all.map(\.recordId), ["e1", "e2", "p1"])                          // ي == ی
        XCTAssertEqual(Set(all.map(\.group)).count, 3)
        // one ledger only
        XCTAssertEqual(SearchEngine.find(st, query: "سیمان", scope: .ledgers(accountId: "a2")).map(\.recordId), ["e2"])
        // personal only
        XCTAssertEqual(SearchEngine.find(st, query: "سیمان", scope: .personal).map(\.recordId), ["p1"])
        // several words, any order; an amount; a tankhah found by its party
        XCTAssertEqual(SearchEngine.find(st, query: "مصالح سیمان", scope: .all).count, 2)
        XCTAssertEqual(SearchEngine.find(st, query: "۹۰۰,۰۰۰", scope: .all).map(\.recordId), ["e2"])
        XCTAssertEqual(SearchEngine.find(st, query: "کارفرما", scope: .ledgers(accountId: nil)).first?.isTankhah, true)
    }
}

/// Owner's request 2026-11: reward rows never carry commission; a payment can cover the open rows only up to a chosen row.
final class RewardAndPartialCommissionTests: XCTestCase {
    private let J = { (d: Int) in JalaliDate(jy: 1405, jm: 8, jd: d) }

    private func ledger() -> CommissionLedger {
        var L = CommissionLedger(accountId: "a", accountName: "پروژه", percent: 10)
        L.visibleNumbers = true
        L.addExpense(key: "e1", desc: "یک", toman: 1_000_000, date: J(1))
        L.addExpense(key: "t1", desc: "تنخواه", toman: 9_000_000, date: J(2), type: "tankhah")
        L.addExpense(key: "e2", desc: "دو", toman: 2_000_000, date: J(3))
        L.addExpense(key: "r1", desc: "پاداش", toman: 5_000_000, date: J(4), reward: true)
        L.addExpense(key: "e3", desc: "سه", toman: 3_000_000, date: J(5))
        L.addExpense(key: "e4", desc: "چهار", toman: 4_000_000, date: J(6))
        return L
    }

    func testRewardNeverInCommission() {
        let L = ledger()
        XCTAssertEqual(L.summary().openBase, 10_000_000)             // 1+2+3+4, no reward, no tankhah
        XCTAssertEqual(L.summary().accrued, 1_000_000)
        XCTAssertEqual(L.summary().ledgerTotal, 15_000_000)          // still an expense of the ledger
        XCTAssertFalse(L.openRows().contains { $0.key == "r1" })
    }

    func testPartialPaymentLeavesLaterRowsOpen() {
        var L = ledger()
        let open = L.openRows()
        XCTAssertEqual(open.map(\.num), [1, 3, 5, 6])                // ledger numbers (تنخواه and reward counted)
        XCTAssertEqual(open.map(\.cumulativeCommission), [100_000, 300_000, 600_000, 1_000_000])
        // pay up to row 5 («سه»): 600,000
        let s = L.settle(key: "s1", amount: 600_000, date: J(7), upTo: "e3")
        XCTAssertEqual(s.calculatedAmount, 600_000)
        XCTAssertEqual(s.covered, ["e1", "e2", "e3"])
        XCTAssertEqual(s.balanceAfter, 0)
        XCTAssertEqual(L.rows.last?.desc, "پرداخت کمیسیون ردیف‌های هزینه \"۱\" تا \"۵\" (سه) تسویه کامل")
        // the live commission now shows only row 6
        XCTAssertEqual(L.summary().openBase, 4_000_000)
        XCTAssertEqual(L.summary().remaining, 400_000)
        XCTAssertEqual(L.openRows().map(\.key), ["e4"])
        // a new row entered later is open too; a full payment then covers everything
        L.addExpense(key: "e5", desc: "پنج", toman: 1_000_000, date: J(2))
        XCTAssertEqual(L.summary().openBase, 5_000_000)
        let f = L.settle(key: "s2", amount: 500_000, date: J(8))
        XCTAssertNil(f.covered)
        XCTAssertEqual(f.calculatedAmount, 500_000)
        XCTAssertEqual(L.summary().openBase, 0)
        XCTAssertEqual(L.summary().remaining, 0)
    }

    func testPartialWithDebtCarriesBalance() {
        var L = ledger()
        L.settle(key: "s1", amount: 200_000, date: J(7), upTo: "e2")      // due 300,000 → debt 100,000
        XCTAssertEqual(L.summary().pastShortfall, 100_000)
        XCTAssertEqual(L.summary().remaining, 700_000 + 100_000)       // rows 5 & 6 + debt
        // deleting the payment reopens its rows
        let row = L.rows.first { $0.commission == "s1" }!
        L.delete(key: row.key)
        XCTAssertEqual(L.summary().openBase, 10_000_000)
        XCTAssertEqual(L.summary().pastShortfall, 0)
    }

    func testOpsRewardRowAndPartialSettle() throws {
        var st: [String: JSONValue] = [
            "accounts": .array([.object(["id": .string("a"), "name": .string("پروژه"), "commissionPercent": .int(10),
                                         "commissionEnabled": .bool(true), "commissionSettlements": .array([])])]),
            "expenses": .array([]), "incomes": .array([]),
        ]
        var n = 1_780_000_000_000
        func ids() -> IdSource { n += 1000; let v = n; return IdSource(nowMs: { v }, random5: { "abcde" }) }
        func add(_ desc: String, _ t: Int, reward: Bool = false) throws {
            var i = ExpenseInput(accountId: "a", isTankhah: false, desc: desc, category: reward ? "" : "مصالح", subcategory: reward ? "" : "سیمان",
                                 toman: t, date: JalaliDate(jy: 1405, jm: 8, jd: 1), payMethod: .cash, cardId: nil, partyId: nil)
            i.isReward = reward
            st = try LedgerOps.addExpense(st, i, ids: ids()).state
        }
        try add("الف", 1_000_000); try add("", 3_000_000, reward: true); try add("ب", 2_000_000)
        let rw = st["expenses"]!.arrayValue![1]
        XCTAssertEqual(rw["reward"]?.boolValue, true)
        XCTAssertEqual(rw["category"]?.stringValue, "پاداش")
        XCTAssertEqual(rw["desc"]?.stringValue, "پاداش کارفرما")
        let open = LedgerOps.openCommissionRows(st, accountId: "a")
        XCTAssertEqual(open.map(\.num), [1, 3])
        let r = try LedgerOps.settleCommission(st, accountId: "a", amount: 100_000, date: JalaliDate(jy: 1405, jm: 8, jd: 2),
                                               upTo: open[0].key, ids: ids())
        let s = r.state["accounts"]!.arrayValue![0]["commissionSettlements"]!.arrayValue![0]
        XCTAssertEqual(s["coveredExpenseIds"]?.arrayValue?.compactMap(\.idString), [open[0].key])
        XCTAssertEqual(LedgerOps.openCommissionRows(r.state, accountId: "a").map(\.num), [3])
        let a = r.state["accounts"]!.arrayValue![0]
        XCTAssertEqual(ImportAnalyzer.accountSummary(a, expenses: r.state["expenses"]!.arrayValue!).remaining, 200_000)
    }
}

/// pasted from Telegram: the «Name, [date at time]» header of each message never becomes part of a row
final class NotesTelegramPasteTests: XCTestCase {
    func testTelegramHeadersAreDropped() {
        let text = """
        Moein, [Nov 9, 2026 at 20:27]
        1405/8/17
        640.000
        خرید ۴ جفت دستکش کار
         Moein, [Nov 9, 2026 at 20:28]
        1405/8/17
        1.595.000
        خوراک نهار بتن ریزی
         Moein, [Nov 9, 2026 at 20:29]
        1405/8/17
        500.000
        انعام راننده پمپ بتن هوایی
         Moein, [Nov 9, 2026 at 20:31]
        1405/8/18
        17.000.000
        بابت پمپ بتن هوایی 
        (فاکتور رسمی فردا در این آیتم ادیت میشود)
        [09.11.26 20:35] معین:
        ۱۴۰۵/۸/۱۸
        ۲۵۰.۰۰۰
        کرایه وانت
        """
        let r = NotesImport.parse(text)
        XCTAssertTrue(r.orphans.isEmpty, "\(r.orphans)")
        XCTAssertEqual(r.entries.count, 5)
        XCTAssertEqual(r.entries.map(\.toman), [640_000, 1_595_000, 500_000, 17_000_000, 250_000])
        XCTAssertEqual(r.entries[0].desc, "خرید ۴ جفت دستکش کار")
        XCTAssertEqual(r.entries[2].desc, "انعام راننده پمپ بتن هوایی")
        XCTAssertEqual(r.entries[3].desc, "بابت پمپ بتن هوایی (فاکتور رسمی فردا در این آیتم ادیت میشود)")
        XCTAssertEqual(r.entries[3].date, JalaliDate(jy: 1405, jm: 8, jd: 18))
        XCTAssertEqual(r.entries[4].desc, "کرایه وانت")
        XCTAssertFalse(r.entries.contains { $0.desc.contains("Moein") || $0.desc.contains("[") || $0.desc.contains("معین") })
        XCTAssertTrue(r.entries.allSatisfy { $0.problems.isEmpty }, "\(r.entries.map(\.problems))")
        // a description with a time in brackets later in the line is kept
        XCTAssertEqual(NotesImport.stripChatHeader("جلسه با کارفرما [ساعت 10:30]"), "جلسه با کارفرما [ساعت 10:30]")
    }
}

final class RowRangeSumTests: XCTestCase {
    func testRangeSumByLedgerNumbers() {
        func row(_ id: String, _ d: Int, _ t: Int, _ extra: [String: JSONValue] = [:]) -> JSONValue {
            .object(["id": .string(id), "accountId": .string("a"), "desc": .string(id), "toman": .int(Int64(t)),
                     "date": .object(["jy": .int(1405), "jm": .int(8), "jd": .int(Int64(d))]), "ts": .int(Int64(d))].merging(extra) { _, b in b })
        }
        let st: [String: JSONValue] = ["expenses": .array([
            row("e1", 1, 100), row("t1", 2, 5_000, ["type": .string("tankhah")]), row("e2", 3, 200),
            row("r1", 4, 1_000, ["reward": .bool(true)]), row("c1", 5, 30, ["commissionSettlementId": .string("s")]),
            row("e3", 6, 400), row("x", 7, 9_999, ["accountId": .string("other")]),
        ])]
        XCTAssertEqual(LedgerOps.rowCount(st, accountId: "a"), 6)
        let s = LedgerOps.rangeSum(st, accountId: "a", from: 2, to: 6)
        XCTAssertEqual(s.rowCount, 5)
        XCTAssertEqual(s.expenses, 600)          // e2 + e3
        XCTAssertEqual(s.rewards, 1_000)
        XCTAssertEqual(s.commissionPaid, 30)
        XCTAssertEqual(s.tankhah, 5_000)
        XCTAssertEqual(s.firstDesc, "t1"); XCTAssertEqual(s.lastDesc, "e3")
        // reversed and out of range are clamped
        let w = LedgerOps.rangeSum(st, accountId: "a", from: 99, to: 3)
        XCTAssertEqual(w.from, 3); XCTAssertEqual(w.to, 6); XCTAssertEqual(w.expenses, 600)
    }
}

final class CommissionTextTests: XCTestCase {
    func testShortWording() {
        XCTAssertEqual(CommissionText.short(desc: "پرداخت کمیسیون تا ردیف هزینه \"۲۵\" (خرید میلگرد) تسویه کامل", balanceAfter: 0),
                       "تا ردیف ۲۵ تسویه شد")
        XCTAssertEqual(CommissionText.short(desc: "پرداخت کمیسیون ردیف‌های هزینه \"۲۶\" تا \"۴۰\" (سیمان) — مبلغ ۱۰۰ باقی", balanceAfter: 100_000),
                       "ردیف ۲۶ تا ۴۰ تسویه شد — باقی‌مانده ۱۰۰.۰۰۰")
        XCTAssertEqual(CommissionText.short(desc: "پرداخت کمیسیون ردیف هزینه \"۷\" (x)", balanceAfter: -50_000),
                       "ردیف ۷ تسویه شد — اضافه پرداخت ۵۰.۰۰۰")
        XCTAssertEqual(CommissionText.short(desc: "پرداخت کمیسیون (۱۰٪)", balanceAfter: nil), "پرداخت کمیسیون")
        // a number inside the description of the expense itself is not taken for a row
        XCTAssertEqual(CommissionText.rows(in: "پرداخت کمیسیون تا ردیف هزینه \"۱۲\" (خرید \"۴\" جفت دستکش)"), "تا ردیف ۱۲")
    }
}
