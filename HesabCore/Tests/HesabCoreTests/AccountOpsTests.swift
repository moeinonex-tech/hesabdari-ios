import Foundation
import XCTest
@testable import HesabCore

/// Replays phase1 tools/make_account_oracle.js (real web removeLedgerAccountWithDependents + tankhahPartyReportData).
final class AccountOpsTests: XCTestCase {

    private func oracle() throws -> JSONValue {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "account_oracle", withExtension: "json", subdirectory: "Goldens/import"))
        return try JSONCoding.decode(try Data(contentsOf: url))
    }

    private func ids(_ v: JSONValue?) -> [String] { (v?.arrayValue ?? []).map { $0["id"]?.idString ?? "?" } }
    private func f(_ v: JSONValue?, _ keys: [String]) -> [String] {
        (v?.arrayValue ?? []).map { o in keys.map { o[$0]?.idString ?? o[$0]?.stringValue ?? "null" }.joined(separator: "|") }
    }

    func testDeleteAccountMatchesWeb() throws {
        let o = try oracle()
        let seed = try XCTUnwrap(o["seed"]?.objectValue)
        let after = try XCTUnwrap(o["after"])
        let st = try AccountOps.deleteAccount(seed, id: "aA")
        XCTAssertEqual(ids(st["accounts"]), ids(after["accounts"]))
        XCTAssertEqual(ids(st["expenses"]), ids(after["expenses"]))
        XCTAssertEqual(ids(st["incomes"]), ids(after["incomes"]))
        let ck = ["id", "accountId", "linkedExpenseId", "tankhahAccountId", "tankhahExpenseId"]
        XCTAssertEqual(f(st["reminderChecks"], ck), f(after["reminderChecks"], ck))
        let inst = { (v: JSONValue?) in (v?.arrayValue ?? []).flatMap { p in self.f(p["installments"], ["id", "accountId", "linkedExpenseId"]) } }
        XCTAssertEqual(inst(st["reminderPersons"]), inst(after["reminderPersons"]))
        XCTAssertEqual(f(st["appointments"], ["id", "projectId", "projectManualName"]), f(after["appointments"], ["id", "projectId", "projectManualName"]))
        XCTAssertEqual(st["lastCardByAccount"], after["lastCardByAccount"])
        XCTAssertEqual(st["activeAccountId"]?.idString, after["activeAccountId"]?.idString)
        XCTAssertEqual(st["starredAccountId"]?.idString, after["starredAccountId"]?.idString)
    }

    func testLastAccountCannotBeDeleted() throws {
        let st: [String: JSONValue] = ["accounts": .array([.object(["id": .string("a1"), "name": .string("x")])])]
        XCTAssertThrowsError(try AccountOps.deleteAccount(st, id: "a1"))
    }

    func testTankhahPartyReportMatchesWeb() throws {
        let o = try oracle()
        let seed = try XCTUnwrap(o["seed"]?.objectValue)
        let rep = AccountOps.tankhahPartyReport(seed, accountId: "aA")
        let web = try XCTUnwrap(o["report"])
        XCTAssertEqual(rep.groups.map(\.name), (web["order"]?.arrayValue ?? []).compactMap(\.stringValue))
        XCTAssertEqual(rep.groups.map(\.total), (web["totals"]?.arrayValue ?? []).compactMap(\.intValue))
        XCTAssertEqual(rep.groups.map { $0.rows.map { $0["id"]?.idString ?? "" } },
                       (web["ids"]?.arrayValue ?? []).map { ($0.arrayValue ?? []).compactMap(\.idString) })
        XCTAssertEqual(rep.total, web["grandTotal"]?.intValue)
    }

    func testAddAccountAndParties() throws {
        var st: [String: JSONValue] = ["accounts": .array([])]
        let r = try AccountOps.addAccount(st, name: "  پروژه نو ")
        st = r.state
        XCTAssertTrue(r.id.hasPrefix("a"))
        XCTAssertEqual(st["activeAccountId"]?.idString, r.id)
        XCTAssertEqual(st["accounts"]?.arrayValue?.first?["name"]?.stringValue, "پروژه نو")
        XCTAssertEqual(st["accounts"]?.arrayValue?.first?["commissionEnabled"]?.boolValue, false)

        let t1 = try AccountOps.addTankhahParty(st, name: "حامد", company: false)
        XCTAssertEqual(t1.result, .created)
        XCTAssertEqual(t1.state["parties"]?.arrayValue?.count, 1)          // person also registered centrally
        let t2 = try AccountOps.addTankhahParty(t1.state, name: " حامد  ", company: true)
        XCTAssertEqual(t2.result, .existing)
        XCTAssertEqual(t2.id, t1.id)
        let t3 = try AccountOps.addTankhahParty(t1.state, name: "شرکت آریا", company: true)
        XCTAssertEqual(t3.state["parties"]?.arrayValue?.count, 1)          // companies are not
    }
}
