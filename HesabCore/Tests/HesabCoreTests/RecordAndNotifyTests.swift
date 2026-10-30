import Foundation
import XCTest
@testable import HesabCore

final class RecordAndNotifyTests: XCTestCase {

    private func json(_ name: String) throws -> JSONValue {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Goldens/import"))
        return try JSONCoding.decode(try Data(contentsOf: url))
    }

    private let fixed = IdSource(nowMs: { 1_770_000_000_000 }, random5: { "abcde" })
    private let d = JalaliDate(jy: 1405, jm: 8, jd: 8)

    /// Same rule and texts as phase1 model/notify_ios_model.js (approved), on the phase1 a7 fixture.
    func testNotificationPlanMatchesPhase1Model() throws {
        let f = try json("notify_fixture")
        let st = try XCTUnwrap(f["state"]?.objectValue)
        let tz = try XCTUnwrap(TimeZone(identifier: f["timeZone"]?.stringValue ?? ""))
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        let isoMs = ISO8601DateFormatter()
        isoMs.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        for c in try XCTUnwrap(f["cases"]?.arrayValue) {
            let nowText = try XCTUnwrap(c["now"]?.stringValue)
            let now = try XCTUnwrap(iso.date(from: nowText))
            let plan = NotificationPlanner.plan(st, now: now, timeZone: tz)
            let expImm = c["schedule"]?["immediate"]?.arrayValue ?? []
            let expSch = c["schedule"]?["scheduled"]?.arrayValue ?? []
            XCTAssertEqual(plan.immediate.map(\.id), expImm.compactMap { $0["id"]?.stringValue }, nowText)
            XCTAssertEqual(plan.immediate.map(\.body), expImm.compactMap { $0["body"]?.stringValue }, nowText)
            XCTAssertEqual(plan.scheduled.map(\.id), expSch.compactMap { $0["id"]?.stringValue }, nowText)
            XCTAssertEqual(plan.scheduled.map(\.title), expSch.compactMap { $0["title"]?.stringValue }, nowText)
            XCTAssertEqual(plan.scheduled.map(\.body), expSch.compactMap { $0["body"]?.stringValue }, nowText)
            XCTAssertEqual(plan.scheduled.compactMap(\.fireAt), expSch.compactMap { $0["fireAt"]?.stringValue }.compactMap { isoMs.date(from: $0) }, nowText)
        }
    }

    func testCapKeepsNearestSixty() {
        var checks: [JSONValue] = []
        for k in 0..<75 {
            checks.append(.object(["id": .string("cap\(k)"), "amount": .int(1000), "party": .string(""), "status": .string("pending"),
                                   "muted": .bool(false), "dueDate": LedgerOps.date(JalaliDate(jy: 1406, jm: 1 + k % 12, jd: 1 + k / 12))]))
        }
        let plan = NotificationPlanner.plan(["reminderChecks": .array(checks)], now: Date(timeIntervalSince1970: 1_792_000_000),
                                            timeZone: TimeZone(identifier: "Asia/Tehran")!)
        XCTAssertEqual(plan.scheduled.count, 60)
        XCTAssertEqual(plan.scheduled.first?.id, "chk-cap0")
    }

    func testPersonalAndIncomeRecordsLikeWeb() throws {
        let st: [String: JSONValue] = ["personalExpenses": .array([]), "incomes": .array([]), "personalCategories": .array([]),
                                       "personalSubcategories": .object([:]), "incomeCategories": .array([]), "incomeSubcategories": .object([:]),
                                       "accounts": .array([.object(["id": .string("a1"), "name": .string("پروژه")])])]
        let p = try RecordOps.addPersonal(st, PersonalInput(desc: "نان", category: "خانه", subcategory: "خوراک", toman: 50_000,
                                                             date: d, payMethod: "hamrahbank", cardId: "c1"), ids: fixed)
        let row = try XCTUnwrap(p.state["personalExpenses"]?.arrayValue?.first?.objectValue)
        XCTAssertEqual(Set(row.keys), ["id", "desc", "toman", "date", "ts", "category", "subcategory", "payMethod", "cardId"])
        XCTAssertEqual(row["id"]?.stringValue, "p1770000000000abcde")
        XCTAssertEqual(p.state["personalSubcategories"]?["خانه"]?.arrayValue, [.string("خوراک")])

        let i = try RecordOps.addIncome(st, IncomeInput(desc: "حقوق", category: "حقوق", subcategory: "", toman: 9_000_000,
                                                         date: d, accountLink: "a1"), ids: fixed)
        let inc = try XCTUnwrap(i.state["incomes"]?.arrayValue?.first?.objectValue)
        XCTAssertEqual(Set(inc.keys), ["id", "desc", "toman", "date", "ts", "category", "subcategory", "accountId", "accountName", "source", "commissionSettlementId"])
        XCTAssertEqual(inc["accountName"]?.stringValue, "پروژه")
        XCTAssertEqual(inc["source"]?.stringValue, "manual")
        XCTAssertEqual(inc["commissionSettlementId"], .null)

        // commission incomes are managed from the ledger
        let withCommission: [String: JSONValue] = ["incomes": .array([.object(["id": .string("i1"), "commissionSettlementId": .string("s1")])])]
        XCTAssertThrowsError(try RecordOps.deleteIncome(withCommission, id: "i1")) { e in
            XCTAssertEqual(e as? LedgerError, .commissionIncome)
        }
    }
}

final class SearchTests: XCTestCase {
    func testSearchLikeWeb() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "rich_clean", withExtension: "json", subdirectory: "Goldens/import"))
        guard case .success(let p) = BackupParser.parse(try Data(contentsOf: url)) else { return XCTFail("parse") }
        let st = p.state
        XCTAssertEqual(SearchEngine.latinDigits("۱۲۳٤٥"), "12345")
        // "سیمان" matches the ledger row by description and the keyword is not in other domains
        let r = SearchEngine.search(st, query: "سیمان")
        XCTAssertEqual(r.map(\.kind), [.expense])
        XCTAssertEqual(r.first?.sub, "پروژه آزمون · ۱۴۰۵/۷/۱")
        // account name matches every row of that account (web behaviour)
        XCTAssertEqual(SearchEngine.search(st, query: "پروژه آزمون").filter { $0.kind == .expense }.count,
                       st["expenses"]?.arrayValue?.count)
        // Persian digits in the query find Latin digits in the data (check number 987)
        XCTAssertEqual(SearchEngine.search(st, query: "۹۸۷").map(\.kind), [.check])
        XCTAssertTrue(SearchEngine.search(st, query: "zzz-nothing").isEmpty)
    }
}

final class SettingsOpsTests: XCTestCase {
    func testQuoteHashMatchesWeb() {
        // values from the web quoteHash32 (node)
        XCTAssertEqual(SettingsOps.quoteHash32("custom-q1|0"), 2169972479)
        XCTAssertEqual(SettingsOps.quoteHash32("custom-1700000000000-12|977"), 367492988)
        XCTAssertEqual(SettingsOps.quoteHash32("جمله|3"), 2776771398)
    }

    func testEveryQuoteOncePerLap() {
        var st: [String: JSONValue] = ["customQuotes": .array([])]
        for i in 0..<5 { st = try! SettingsOps.addQuote(st, text: "جمله \(i)", author: "") }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/London")!
        let start = cal.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: 0))!   // slot divisible by 5? not needed
        var seen: [String] = []
        for k in 0..<10 { seen.append(SettingsOps.quoteOfNow(st, now: start.addingTimeInterval(Double(k) * 12 * 3600), calendar: cal)!.id) }
        // within any 5 consecutive half days of one lap every quote appears exactly once
        let days = Int((cal.startOfDay(for: start).timeIntervalSince1970 / 86400).rounded(.down))
        let first = (5 - (days * 2) % 5) % 5
        XCTAssertEqual(Set(seen[first..<first + 5]).count, 5)
    }

    func testCardSaveDropsCVVAndDetectsBank() throws {
        XCTAssertEqual(SettingsOps.bank(forCardNumber: "۶۰۳۷۹۹۱۲۳۴۵۶۷۸۹۰")?.key, "melli")
        let st: [String: JSONValue] = ["cards": .array([.object(["id": .string("c1"), "bankName": .string("ملت"), "cvv": .string("123")])])]
        let out = try SettingsOps.saveCard(st, editingId: "c1", CardInput(bankName: "ملت", bankKey: "mellat", cardNumber: "6104 3378 1234 5678",
            accountNumber: "", iban: "ir12", accountType: "جاری", expiryYear: 1409, expiryMonth: 5, holderName: "معین", bgColor: nil, bgImage: nil, archived: false))
        let c = try XCTUnwrap(out["cards"]?.arrayValue?.first)
        XCTAssertNil(c["cvv"])
        XCTAssertEqual(c["cardNumber"]?.stringValue, "6104337812345678")
        XCTAssertEqual(c["last4"]?.stringValue, "5678")
        XCTAssertEqual(c["iban"]?.stringValue, "IR12")
        XCTAssertEqual(SettingsOps.expiryText(c["expiry"]), "۱۴۰۹/۰۵")
    }
}
