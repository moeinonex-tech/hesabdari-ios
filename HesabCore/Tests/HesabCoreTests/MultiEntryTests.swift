import XCTest
@testable import HesabCore

/// web «فاکتور چندقلمی» (one row with items[]), multi-check group stamps, bank name → logo lookup
final class MultiEntryTests: XCTestCase {
    private let ids = IdSource(nowMs: { 1_770_000_000_000 }, random5: { "abcde" })
    private let d = JalaliDate(jy: 1405, jm: 8, jd: 9)

    private func base() -> [String: JSONValue] {
        ["accounts": .array([.object(["id": .string("a1"), "name": .string("پروژه")])]), "expenses": .array([]),
         "personalExpenses": .array([]), "reminderChecks": .array([]), "ledgerCategories": .array([])]
    }

    func testLedgerInvoice() throws {
        var input = ExpenseInput(accountId: "a1", isTankhah: false, desc: "خرید کارگاه", category: "", subcategory: "", toman: 0,
                                 date: d, payMethod: .cash, cardId: nil, partyId: nil)
        input.items = [ExpenseItem(category: "مصالح", subcategory: "سیمان", toman: 1_000),
                       ExpenseItem(category: " مصالح ", subcategory: "بلوک", toman: 2_500, desc: "بلوک ۱۵")]
        let r = try LedgerOps.addExpense(base(), input, ids: ids)
        let row = r.state["expenses"]!.arrayValue![0]
        XCTAssertEqual(row["toman"]?.intValue, 3_500)
        XCTAssertEqual(row["category"]?.stringValue, "مصالح")       // every item shares it
        XCTAssertNil(row["subcategory"])                               // two different ones
        XCTAssertEqual(row["items"]?.arrayValue?.count, 2)
        XCTAssertEqual(row["items"]?.arrayValue?[1]["category"]?.stringValue, "مصالح")
        XCTAssertEqual(row["items"]?.arrayValue?[1]["desc"]?.stringValue, "بلوک ۱۵")
        XCTAssertEqual(MultiItem.items(of: row).map(\.toman), [1_000, 2_500])
        XCTAssertEqual(r.state["ledgerCategories"]?.arrayValue?.compactMap(\.stringValue), ["مصالح"])

        // edited as multi → keeps items; edited through the single fields → a plain row again
        var e2 = input; e2.items[0].toman = 4_000
        var st = try LedgerOps.editExpense(r.state, id: r.id, e2)
        XCTAssertEqual(st["expenses"]!.arrayValue![0]["toman"]?.intValue, 6_500)
        var single = input; single.items = []; single.category = "مصالح"; single.subcategory = "سیمان"; single.toman = 900
        st = try LedgerOps.editExpense(st, id: r.id, single)
        XCTAssertNil(st["expenses"]!.arrayValue![0]["items"])
        XCTAssertEqual(st["expenses"]!.arrayValue![0]["toman"]?.intValue, 900)
    }

    func testInvoiceValidation() {
        var input = ExpenseInput(accountId: "a1", isTankhah: false, desc: "", category: "", subcategory: "", toman: 0,
                                 date: d, payMethod: .cash, cardId: nil, partyId: nil)
        input.items = [ExpenseItem(category: "a", subcategory: "b", toman: 1), ExpenseItem()]
        XCTAssertEqual(input.missingFields, ["شرح", "نوع هزینه قلم ۲", "زیردسته قلم ۲", "مبلغ قلم ۲"])
        // tankhah never is an invoice
        input.isTankhah = true
        XCTAssertFalse(input.isMulti)
    }

    func testPersonalInvoice() throws {
        var p = PersonalInput(desc: "خرید", category: "", subcategory: "", toman: 0, date: d, payMethod: "cash", cardId: nil)
        p.items = [ExpenseItem(category: "خوراک", subcategory: "نان", toman: 50), ExpenseItem(category: "خانه", subcategory: "نان", toman: 70)]
        let r = try RecordOps.addPersonal(base(), p, ids: ids)
        let row = r.state["personalExpenses"]!.arrayValue![0]
        XCTAssertEqual(row["toman"]?.intValue, 120)
        XCTAssertNil(row["category"])
        XCTAssertEqual(row["subcategory"]?.stringValue, "نان")
        XCTAssertEqual(row["items"]?.arrayValue?.count, 2)
    }

    func testCheckGroup() throws {
        let input = CheckInput(amount: 100, party: "علی", bankName: "ملت", checkNumber: "1", sayadId: "", checkSeries: "",
                               desc: "اقساط", category: "مصالح", subcategory: "سیمان", dueDate: d, accountId: "a1")
        var st = base()
        for i in 1...3 {
            st = try ReminderOps.saveCheck(st, editingId: nil, input, group: CheckGroup(groupId: "cg1", index: i, count: 3, total: 300),
                                           ids: ids, today: d).state
        }
        let checks = st["reminderChecks"]!.arrayValue!
        XCTAssertEqual(checks.count, 3)
        XCTAssertEqual(checks.map { $0["groupIndex"]?.intValue }, [1, 2, 3])
        XCTAssertEqual(checks[2]["groupCount"]?.intValue, 3)
        XCTAssertEqual(checks[0]["groupTotal"]?.intValue, 300)
        XCTAssertEqual(checks[0]["groupId"]?.stringValue, "cg1")
        XCTAssertEqual(st["expenses"]!.arrayValue!.count, 3)      // every check its own linked row
        // a single check keeps the web defaults
        let one = try ReminderOps.saveCheck(base(), editingId: nil, input, ids: ids, today: d).state["reminderChecks"]!.arrayValue![0]
        XCTAssertEqual(one["groupCount"]?.intValue, 1)
        XCTAssertEqual(one["groupId"], .null)
    }

    func testBankByName() {
        XCTAssertEqual(SettingsOps.bank(named: "ملت")?.key, "mellat")
        XCTAssertEqual(SettingsOps.bank(named: "بانک  ملی")?.key, "melli")
        XCTAssertEqual(SettingsOps.bank(named: "صادرات")?.key, "saderat")
        XCTAssertEqual(SettingsOps.bank(named: "توسعه صادرات")?.key, "tosesaderat")
        XCTAssertNil(SettingsOps.bank(named: "  "))
        XCTAssertEqual(SettingsOps.banks.count, 29)
    }
}

final class NotesImportTests: XCTestCase {
    func testParseAnyOrderAndProblems() {
        let text = """
        یادداشت قدیمی بی‌تاریخ
        1405/6/19
        8.520.000
        بابت خرید ۲۰۰ عدد بلوک
        از فروشگاه

        ۱۴۰۵/۸/۷

        خرید قند و چای خشک برای کارگران (آرماتور بند)

        ۵۱۸.۱۰۰
        1405/8/8
        کرایه وانت
        1405/8/9
        12.000 ریال
        1405/8/10
        100.000
        200.000
        دو عدد
        1405/8/11
        950.000
        1405/13/1
        """
        let r = NotesImport.parse(text)
        XCTAssertEqual(r.orphans, ["یادداشت قدیمی بی‌تاریخ"])
        XCTAssertEqual(r.entries.count, 6)
        XCTAssertEqual(r.entries[0].toman, 8_520_000)
        XCTAssertEqual(r.entries[0].desc, "بابت خرید ۲۰۰ عدد بلوک از فروشگاه")
        XCTAssertTrue(r.entries[0].problems.isEmpty)
        // description before the amount: still read right
        XCTAssertEqual(r.entries[1].toman, 518_100)
        XCTAssertEqual(r.entries[1].desc, "خرید قند و چای خشک برای کارگران (آرماتور بند)")
        XCTAssertTrue(r.entries[1].problems.isEmpty)
        // no amount → kept and flagged, never dropped
        XCTAssertEqual(r.entries[2].problems, ["مبلغ پیدا نشد"])
        // a row with only an amount: flagged for its missing description (12.000 rial = 1.200 toman)
        XCTAssertEqual(r.entries[3].toman, 1_200)
        XCTAssertTrue(r.entries[3].problems.contains("شرح پیدا نشد"))
        // two numbers → amount left empty, the person picks
        XCTAssertEqual(r.entries[4].toman, 0)
        XCTAssertTrue(r.entries[4].problems.first?.hasPrefix("چند عدد پیدا شد") ?? false)
        // an impossible date inside a row is reported on that row
        XCTAssertTrue(r.entries[5].problems.contains { $0.hasPrefix("تاریخ نامعتبر") })
        XCTAssertEqual(r.problemCount, 4)
    }

    func testRial() {
        let r = NotesImport.parse("1405/8/9\n12.000 ریال\nخرید")
        XCTAssertEqual(r.entries[0].toman, 1_200)
    }

    func testTopPayMethods() {
        let st: [String: JSONValue] = ["expenses": .array([
            .object(["accountId": .string("a"), "payMethod": .string("cash")]),
            .object(["accountId": .string("a"), "payMethod": .string("cash")]),
            .object(["accountId": .string("a"), "payMethod": .string("pos")]),
            .object(["accountId": .string("b"), "payMethod": .string("transfer")])])]
        XCTAssertEqual(SmartDefaults.topPayMethods(st, listKey: "expenses", accountId: "a"), ["cash", "pos"])
        XCTAssertEqual(SmartDefaults.topPayMethods(st, listKey: "expenses", accountId: "z"), ["hamrahbank", "pos"])
    }

    func testMostUsedCard() {
        let st: [String: JSONValue] = [
            "cards": .array([.object(["id": .string("c1")]), .object(["id": .string("c2")]), .object(["id": .string("c3"), "archived": .bool(true)])]),
            "expenses": .array([
                .object(["accountId": .string("a"), "cardId": .string("c2"), "ts": .int(1)]),
                .object(["accountId": .string("a"), "cardId": .string("c2"), "ts": .int(2)]),
                .object(["accountId": .string("a"), "cardId": .string("c1"), "ts": .int(3)]),
                .object(["accountId": .string("a"), "cardId": .string("c3"), "ts": .int(4)]),
                .object(["accountId": .string("a"), "cardId": .string("c3"), "ts": .int(5)]),
                .object(["accountId": .string("a"), "cardId": .string("c3"), "ts": .int(6)])])]
        XCTAssertEqual(SmartDefaults.mostUsedCard(st, listKey: "expenses", accountId: "a"), "c2")   // c3 is archived
        XCTAssertNil(SmartDefaults.mostUsedCard(st, listKey: "expenses", accountId: "b"))
    }

    func testAdd() {
        let ids = IdSource(nowMs: { 1_000 }, random5: { "abcde" })
        var e = [NotesEntry(id: 0, date: JalaliDate(jy: 1405, jm: 1, jd: 1), toman: 10, desc: "سیمان", category: "مصالح", subcategory: "سیمان"),
                 NotesEntry(id: 1, date: JalaliDate(jy: 1405, jm: 1, jd: 2), toman: 20, desc: "x")]
        e[0].payMethod = "pos"; e[1].payMethod = "cash"
        let st = NotesImport.add(["expenses": .array([])], e, ledgerAccountId: "a1", cardId: "c9", ids: ids)
        let rows = st["expenses"]!.arrayValue!
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0]["category"]?.stringValue, "مصالح")
        XCTAssertEqual(rows[0]["accountId"]?.stringValue, "a1")
        XCTAssertEqual(rows[1]["ts"]?.intValue, 1_001)
        XCTAssertNil(rows[1]["category"])
        XCTAssertEqual(st["ledgerCategories"]?.arrayValue?.count, 1)
        XCTAssertEqual(rows[0]["payMethod"]?.stringValue, "pos")
        XCTAssertEqual(rows[0]["cardId"]?.stringValue, "c9")
        XCTAssertEqual(rows[1]["payMethod"]?.stringValue, "cash")
        XCTAssertNil(rows[1]["cardId"])
    }
}
