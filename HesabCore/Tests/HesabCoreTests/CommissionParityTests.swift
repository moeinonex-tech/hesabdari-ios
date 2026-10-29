import Foundation
import XCTest
@testable import HesabCore

/// Replays the 21 Phase 1 scenarios (G01–G21) and compares every step with
/// Goldens/commission_corrected.json (generated in Phase 1; the same model reproduces
/// the real web app 1326/1326 in "web" mode, and the approved-rule numbers were checked by hand).
final class CommissionParityTests: XCTestCase {

    private func golden(_ name: String, _ ext: String) throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "Goldens"),
                                "missing golden \(name).\(ext)")
        return try Data(contentsOf: url)
    }

    private func int(_ x: Any?) -> Int? { (x as? NSNumber)?.intValue }
    private func dbl(_ x: Any?) -> Double? { (x as? NSNumber)?.doubleValue }
    private func date(_ x: Any?) -> JalaliDate? {
        guard let d = x as? [String: Any], let y = int(d["jy"]), let m = int(d["jm"]), let dd = int(d["jd"]) else { return nil }
        return JalaliDate(jy: y, jm: m, jd: dd)
    }

    private var checks = 0

    private func eq<T: Equatable>(_ a: T?, _ b: T?, _ what: @autoclosure () -> String) {
        checks += 1
        XCTAssertEqual(a, b, what())
    }

    func testCommissionScenariosMatchGolden() throws {
        let g = try XCTUnwrap(JSONSerialization.jsonObject(with: golden("commission_corrected", "json")) as? [String: Any])
        let sf = try XCTUnwrap(JSONSerialization.jsonObject(with: golden("commission_scenarios", "json")) as? [String: Any])
        let defaults = try XCTUnwrap(sf["defaults"] as? [String: Any])
        let scenarios = try XCTUnwrap(sf["scenarios"] as? [[String: Any]])
        let jy = try XCTUnwrap(int(defaults["jy"])), jm = try XCTUnwrap(int(defaults["jm"]))
        let J = { (d: Int) in JalaliDate(jy: jy, jm: jm, jd: d) }
        let gScen = try XCTUnwrap(g["scenarios"] as? [[String: Any]])
        XCTAssertEqual(gScen.count, 21)

        for gs in gScen {
            let id = try XCTUnwrap(gs["id"] as? String)
            let sc = try XCTUnwrap(scenarios.first { ($0["id"] as? String) == id }, "scenario \(id) missing")
            let steps = try XCTUnwrap(gs["steps"] as? [[String: Any]])

            var L = CommissionLedger(accountId: defaults["accountId"] as? String ?? "",
                                     accountName: defaults["accountName"] as? String ?? "",
                                     percent: try XCTUnwrap(dbl(steps[0]["percent"])))
            for r in (sc["seed"] as? [[String: Any]]) ?? [] {
                L.addExpense(key: r["key"] as! String, desc: r["desc"] as? String ?? "", toman: int(r["toman"])!,
                             date: J(int(r["d"])!), subcategory: nil, type: r["type"] as? String ?? "expense")
            }
            compare(L, steps[0], "\(id) initial")

            for (i, st) in steps.enumerated().dropFirst() {
                let op = try XCTUnwrap(st["step"] as? [String: Any])
                let key = op["key"] as? String ?? ""
                switch (op["op"] as? String) ?? "" {
                case "add":
                    L.addExpense(key: key, desc: op["desc"] as? String ?? "", toman: int(op["toman"])!, date: J(int(op["d"])!))
                case "settle":
                    L.settle(key: key, amount: int(op["amount"])!, date: J(int(op["d"])!))
                case "edit":
                    L.edit(key: key, toman: int(op["toman"]), date: int(op["d"]).map(J))
                case "del":
                    L.delete(key: key)
                case "undo":
                    L.undo()
                case "percent":
                    L.percent = dbl(op["value"])!
                case "linkCheck":
                    // the check row's auto text is not commission logic: taken from the golden (as in Phase 1)
                    let gRows = st["rows"] as? [[String: Any]] ?? []
                    let desc = gRows.first(where: { ($0["key"] as? String) == key })?["desc"] as? String ?? ""
                    L.addExpense(key: key, desc: desc, toman: int(op["amount"])!, date: J(int(op["d"])!),
                                 subcategory: nil, linked: "check:pending")
                case "bounceCheck":
                    L.removeRow(key: key)
                default:
                    XCTFail("\(id): unknown op \(String(describing: op["op"]))")
                }
                let opName = (op["op"] as? String) ?? "?"
                compare(L, st, "\(id) step \(i) \(opName)")
            }
        }
        print("commission parity: \(checks) field checks")
        XCTAssertGreaterThan(checks, 1000)
    }

    private func compare(_ L: CommissionLedger, _ g: [String: Any], _ at: String) {
        let s = L.summary()
        eq(s.openBase, int(g["openBase"]), "\(at): openBase")
        eq(s.accrued, int(g["accrued"]), "\(at): accrued")
        eq(s.pastShortfall, int(g["pastShortfall"]), "\(at): pastShortfall")
        eq(s.remaining, int(g["remaining"]), "\(at): remaining")
        eq(s.settled, int(g["settled"]), "\(at): settled")
        eq(s.nextRowNumber, int(g["nextRowNumber"]), "\(at): nextRowNumber")
        eq(s.ledgerTotal, int(g["ledgerTotal"]), "\(at): ledgerTotal")
        eq(s.percent, dbl(g["percent"]), "\(at): percent")
        if let lr = g["lastRow"] as? [String: Any] {
            eq(s.lastRow, StageRow(num: int(lr["num"]) ?? -1, desc: lr["desc"] as? String ?? ""), "\(at): lastRow")
        } else {
            eq(s.lastRow, nil, "\(at): lastRow should be null")
        }

        let gRows = g["rows"] as? [[String: Any]] ?? []
        eq(L.rows.map(\.key), gRows.map { $0["key"] as? String ?? "" }, "\(at): row order")
        for (r, gr) in zip(L.rows, gRows) {
            eq(r.toman, int(gr["toman"]), "\(at): row \(r.key) toman")
            eq(r.date, date(gr["date"]), "\(at): row \(r.key) date")
            eq(r.subcategory, gr["subcategory"] as? String, "\(at): row \(r.key) subcategory")
            if (gr["kind"] as? String) == "commission" {
                eq(r.desc, gr["desc"] as? String, "\(at): commission row \(r.key) text")
            }
        }

        let gSet = g["settlements"] as? [[String: Any]] ?? []
        eq(L.settlements.map(\.key), gSet.map { $0["key"] as? String ?? "" }, "\(at): settlements")
        for (a, b) in zip(L.settlements, gSet) {
            eq(a.toman, int(b["toman"]), "\(at): \(a.key) toman")
            eq(a.date, date(b["date"]), "\(at): \(a.key) date")
            eq(a.calculatedAmount, int(b["calculatedAmount"]), "\(at): \(a.key) calculatedAmount")
            eq(a.remainingForStage, int(b["remainingForStage"]), "\(at): \(a.key) remainingForStage")
            eq(a.isFull, b["isFull"] as? Bool, "\(at): \(a.key) isFull")
            eq(a.balanceAfter, int(b["balanceAfter"]), "\(at): \(a.key) balanceAfter")
        }

        let gInc = g["commissionIncomes"] as? [[String: Any]] ?? []
        eq(L.incomes.map(\.settlement), gInc.map { $0["settlement"] as? String ?? "" }, "\(at): incomes")
        for (a, b) in zip(L.incomes, gInc) {
            eq(a.toman, int(b["toman"]), "\(at): income \(a.settlement) toman")
            eq(a.desc, b["desc"] as? String, "\(at): income \(a.settlement) desc")
        }
    }

    /// The owner's own example (G04): 40,000 debt carried, then 200,000 paid on 140,000 due → 60,000 credit.
    func testOwnerExampleCreditCarriesForward() {
        let d = { JalaliDate(jy: 1405, jm: 7, jd: $0) }
        var L = CommissionLedger(accountId: "a", accountName: "پروژه", percent: 10)
        L.addExpense(key: "E1", desc: "آجر", toman: 1_000_000, date: d(1))
        let s1 = L.settle(key: "S1", amount: 60_000, date: d(2))
        XCTAssertEqual(s1.balanceAfter, 40_000); XCTAssertFalse(s1.isFull)
        L.addExpense(key: "E2", desc: "ماسه", toman: 1_000_000, date: d(3))
        let s2 = L.settle(key: "S2", amount: 200_000, date: d(4))
        XCTAssertEqual(s2.calculatedAmount, 100_000)
        XCTAssertEqual(s2.balanceAfter, -60_000); XCTAssertTrue(s2.isFull)
        XCTAssertEqual(L.summary().remaining, -60_000)
        // the web formula (sum of remainingForStage) gives the same balance
        XCTAssertEqual(L.settlements.reduce(0) { $0 + $1.remainingForStage }, -60_000)
    }
}
