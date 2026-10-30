import Foundation
import XCTest
@testable import HesabCore

/// Replays phase1 tools/make_reminder_oracle.js (REAL web functions run inside app.html) with ReminderOps,
/// and compares the linked ledger rows and the reminder records after every step.
final class ReminderOpsTests: XCTestCase {

    private func oracle() throws -> JSONValue {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "reminder_oracle", withExtension: "json", subdirectory: "Goldens/import"))
        return try JSONCoding.decode(try Data(contentsOf: url))
    }

    private func rowKey(_ r: JSONValue) -> String {
        let d = ImportAnalyzer.date(r["date"])
        return [r["desc"]?.stringValue ?? "", String(r["toman"]?.intValue ?? 0), "\(d.jy)/\(d.jm)/\(d.jd)",
                r["accountId"]?.idString ?? "-", r["category"]?.stringValue ?? "", r["subcategory"]?.stringValue ?? "",
                r["type"]?.stringValue ?? "", r["payMethod"]?.stringValue ?? "-",
                r["linked"]?["kind"]?.stringValue ?? "-", r["linked"]?["status"]?.stringValue ?? "-"].joined(separator: "|")
    }

    private func compare(_ st: [String: JSONValue], _ step: JSONValue, file: StaticString = #filePath, line: UInt = #line) {
        let label = step["label"]?.stringValue ?? "?"
        for key in ["expenses", "personalExpenses"] {
            XCTAssertEqual((st[key]?.arrayValue ?? []).map(rowKey), (step[key]?.arrayValue ?? []).map(rowKey), "\(label) \(key)", file: file, line: line)
        }
        let checks = (st["reminderChecks"]?.arrayValue ?? []).map { c in
            (c["status"]?.stringValue ?? "") + "|" + (c["linkedExpenseId"]?.idString == nil ? "unlinked" : "linked") + "|" + (c["accountId"]?.idString ?? "-")
        }
        let webChecks = (step["reminderChecks"]?.arrayValue ?? []).map { c in
            (c["status"]?.stringValue ?? "") + "|" + (c["linkedExpenseId"]?.idString == nil ? "unlinked" : "linked") + "|" + (c["accountId"]?.idString ?? "-")
        }
        XCTAssertEqual(checks, webChecks, "\(label) checks", file: file, line: line)
        func inst(_ ps: [JSONValue]) -> [String] {
            ps.flatMap { p in (p["installments"]?.arrayValue ?? []).map { i in
                (p["name"]?.stringValue ?? "") + "|" + String(i["amount"]?.intValue ?? 0) + "|" + ((i["paid"]?.isTruthy ?? false) ? "paid" : "open")
                    + "|" + (i["linkedExpenseId"]?.idString == nil ? "unlinked" : "linked") + "|" + (i["description"]?.stringValue ?? "")
            } }
        }
        XCTAssertEqual(inst(st["reminderPersons"]?.arrayValue ?? []), inst(step["reminderPersons"]?.arrayValue ?? []), "\(label) installments", file: file, line: line)
    }

    func testLinkedRowsMatchWebApp() throws {
        let o = try oracle()
        let steps = try XCTUnwrap(o["steps"]?.arrayValue)
        XCTAssertEqual(steps.count, 9)
        let today = JalaliDate(jy: 1405, jm: 8, jd: 8)
        let J = { (m: Int, d: Int) in JalaliDate(jy: 1405, jm: m, jd: d) }
        var st: [String: JSONValue] = [
            "accounts": .array([.object(["id": .string("aT"), "name": .string("پروژه آزمون")])]),
            "expenses": .array([]), "personalExpenses": .array([]), "reminderChecks": .array([]), "reminderPersons": .array([]),
            "appointments": .array([]), "parties": .array([]), "ledgerCategories": .array([]), "ledgerSubcategories": .object([:])
        ]
        let check = CheckInput(amount: 2_000_000, party: "آهن‌فروشی", bankName: "ملت", checkNumber: "123", sayadId: "", checkSeries: "",
                               desc: "میلگرد", category: "مصالح", subcategory: "آهن", dueDate: J(8, 20), accountId: "aT")
        let r1 = try ReminderOps.saveCheck(st, editingId: nil, check, today: today); st = r1.state
        compare(st, steps[0])
        st = try ReminderOps.setCheckStatus(st, id: r1.id, status: "cashed", today: today); compare(st, steps[1])
        st = try ReminderOps.setCheckStatus(st, id: r1.id, status: "bounced", today: today); compare(st, steps[2])
        st = try ReminderOps.setCheckStatus(st, id: r1.id, status: "pending", today: today); compare(st, steps[3])
        var moved = check; moved.accountId = "personal"
        st = try ReminderOps.saveCheck(st, editingId: r1.id, moved, today: today).state; compare(st, steps[4])

        let p1 = try ReminderOps.addPerson(st, name: "بنا", creditor: true, partyId: nil); st = p1.state
        st = try ReminderOps.saveInstallment(st, personId: p1.id, editingId: nil,
            InstallmentInput(amount: 500_000, desc: "قسط اول", category: "دستمزد", subcategory: "بنایی", dueDate: J(8, 25), accountId: "aT"), today: today)
        compare(st, steps[5])
        let instId = try XCTUnwrap(st["reminderPersons"]?.arrayValue?.first?["installments"]?.arrayValue?.first?["id"]?.idString)
        st = try ReminderOps.toggleInstallmentPaid(st, personId: p1.id, installmentId: instId, today: today); compare(st, steps[6])

        let p2 = try ReminderOps.addPerson(st, name: "کارفرما", creditor: false, partyId: nil); st = p2.state
        st = try ReminderOps.saveInstallment(st, personId: p2.id, editingId: nil,
            InstallmentInput(amount: 900_000, desc: "", category: "", subcategory: "", dueDate: J(9, 1), accountId: "aT"), today: today)
        compare(st, steps[7])

        let exp: [String: JSONValue] = ["id": .string("eN"), "accountId": .string("aT"), "desc": .string("کاشی"), "toman": .int(750_000),
                                        "date": LedgerOps.date(J(8, 8)), "ts": .int(1), "type": .string("expense"), "category": .string("مصالح"),
                                        "subcategory": .string("کاشی"), "payMethod": .string("nasiyeh")]
        st = try ReminderOps.addNasiyehRow(st, listKey: "expenses", row: exp, partyName: "کاشی‌فروشی", dueDate: J(9, 10))
        compare(st, steps[8])

        // deleting the check removes its linked row; deleting the person removes the installment rows
        st = try ReminderOps.deleteCheck(st, id: r1.id)
        XCTAssertTrue(st["personalExpenses"]?.arrayValue?.isEmpty ?? false)
        st = try ReminderOps.deletePerson(st, id: p1.id)
        XCTAssertEqual(st["expenses"]?.arrayValue?.count, 1, "only the nasiyeh row is left")
    }
}
