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
