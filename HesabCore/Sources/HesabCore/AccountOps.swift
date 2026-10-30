import Foundation

// Ledger accounts and parties — web: ledgerSelAddBtn, saveLedgerRename, removeLedgerAccountWithDependents,
// commToggleBtn / commDisableBtn / commPercentInput, partyForm (central registry), tankhah party picker,
// tankhahPartyReportData.

public struct PartyInput: Sendable {
    public var fullName, nationalCode, mobile, cardNumber, accountNumber, iban, bankName: String
    public init(fullName: String, nationalCode: String = "", mobile: String = "", cardNumber: String = "",
                accountNumber: String = "", iban: String = "", bankName: String = "") {
        self.fullName = fullName; self.nationalCode = nationalCode; self.mobile = mobile; self.cardNumber = cardNumber
        self.accountNumber = accountNumber; self.iban = iban; self.bankName = bankName
    }
}

public struct TankhahPartyGroup: Sendable {
    public let name: String
    public let type: String?          // person / company / nil (no party)
    public let total: Int
    public let rows: [[String: JSONValue]]
}

public enum AccountOps {
    public typealias State = [String: JSONValue]

    /// web Math.random().toString(36).slice(2,6)
    static func rand36(_ n: Int) -> String {
        let chars = Array("0123456789abcdefghijklmnopqrstuvwxyz")
        return String((0..<n).map { _ in chars[Int.random(in: 0..<chars.count)] })
    }

    // MARK: accounts

    public static func addAccount(_ state: State, name: String, ids: IdSource = .system) throws -> (state: State, id: String) {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty else { throw LedgerError.invalid(["نام دفتر"]) }
        var st = state
        let id = "a" + String(ids.nowMs()) + rand36(4)
        var accounts = LedgerOps.array(st, "accounts")
        accounts.append(.object(["id": .string(id), "name": .string(n), "commissionPercent": .int(0),
                                 "commissionSettlements": .array([]), "commissionEnabled": .bool(false), "budget": .int(0)]))
        st["accounts"] = .array(accounts)
        st["activeAccountId"] = .string(id)
        return (st, id)
    }

    static func updateAccount(_ state: State, _ id: String, _ f: (inout [String: JSONValue]) -> Void) throws -> State {
        var st = state
        var accounts = LedgerOps.array(st, "accounts")
        guard let i = accounts.firstIndex(where: { $0["id"]?.idString == id }), var a = accounts[i].objectValue else { throw LedgerError.notFound }
        f(&a)
        accounts[i] = .object(a)
        st["accounts"] = .array(accounts)
        return st
    }

    public static func renameAccount(_ state: State, id: String, name: String) throws -> State {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty else { throw LedgerError.invalid(["نام دفتر"]) }
        return try updateAccount(state, id) { $0["name"] = .string(n) }
    }

    public static func setCommissionEnabled(_ state: State, id: String, _ on: Bool) throws -> State {
        try updateAccount(state, id) { $0["commissionEnabled"] = .bool(on) }
    }

    public static func setCommissionPercent(_ state: State, id: String, _ percent: Int) throws -> State {
        try updateAccount(state, id) { $0["commissionPercent"] = .int(Int64(max(0, percent))) }
    }

    public static func setActiveAccount(_ state: State, id: String) -> State {
        var st = state
        st["activeAccountId"] = .string(id)
        return st
    }

    /// web removeLedgerAccountWithDependents + the caller's active/starred fix-up.
    public static func deleteAccount(_ state: State, id: String) throws -> State {
        var st = state
        let accounts = LedgerOps.array(st, "accounts")
        guard let acc = accounts.first(where: { $0["id"]?.idString == id }) else { throw LedgerError.notFound }
        guard accounts.count > 1 else { throw LedgerError.message("حداقل یک حساب باید باقی بماند") }
        let accName = acc["name"]?.stringValue ?? ""
        let expenses = LedgerOps.array(st, "expenses")
        var expenseIds = Set<String>()
        var settlementIds = Set<String>()
        for s in acc["commissionSettlements"]?.arrayValue ?? [] { if let sid = s["id"]?.idString { settlementIds.insert(sid) } }
        for e in expenses where e["accountId"]?.idString == id {
            if let eid = e["id"]?.idString { expenseIds.insert(eid) }
            if let sid = e["commissionSettlementId"]?.idString { settlementIds.insert(sid) }
        }
        st["accounts"] = .array(accounts.filter { $0["id"]?.idString != id })
        st["expenses"] = .array(expenses.filter { $0["accountId"]?.idString != id })
        st["incomes"] = .array(LedgerOps.array(st, "incomes").filter { inc in
            if inc["accountId"]?.idString == id { return false }
            if let sid = inc["commissionSettlementId"]?.idString, settlementIds.contains(sid) { return false }
            return true
        })
        func unlink(_ o: inout [String: JSONValue], _ key: String, _ matches: (String) -> Bool) {
            if let v = o[key]?.idString, matches(v) { o[key] = .null }
        }
        if let checks = st["reminderChecks"]?.arrayValue {
            st["reminderChecks"] = .array(checks.map { c in
                guard var o = c.objectValue else { return c }
                unlink(&o, "accountId") { $0 == id }
                unlink(&o, "linkedExpenseId") { expenseIds.contains($0) }
                unlink(&o, "tankhahAccountId") { $0 == id }
                unlink(&o, "tankhahExpenseId") { expenseIds.contains($0) }
                return .object(o)
            })
        }
        if let persons = st["reminderPersons"]?.arrayValue {
            st["reminderPersons"] = .array(persons.map { p in
                guard var po = p.objectValue, let inst = po["installments"]?.arrayValue else { return p }
                po["installments"] = .array(inst.map { i in
                    guard var o = i.objectValue else { return i }
                    unlink(&o, "accountId") { $0 == id }
                    unlink(&o, "linkedExpenseId") { expenseIds.contains($0) }
                    return .object(o)
                })
                return .object(po)
            })
        }
        if let appts = st["appointments"]?.arrayValue {
            st["appointments"] = .array(appts.map { a in
                guard var o = a.objectValue, o["projectId"]?.idString == id else { return a }
                o["projectId"] = .null
                if (o["projectManualName"]?.stringValue ?? "").isEmpty { o["projectManualName"] = .string(accName) }
                return .object(o)
            })
        }
        if var last = st["lastCardByAccount"]?.objectValue {
            last.removeValue(forKey: id)
            st["lastCardByAccount"] = .object(last)
        }
        let remaining = LedgerOps.array(st, "accounts")
        if st["activeAccountId"]?.idString == id, let first = remaining.first?["id"] { st["activeAccountId"] = first }
        if st["starredAccountId"]?.idString == id { st["starredAccountId"] = .null }
        return st
    }

    // MARK: central party registry (state.parties)

    public static func saveParty(_ state: State, editingId: String?, _ input: PartyInput, ids: IdSource = .system) throws -> (state: State, id: String) {
        let name = input.fullName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { throw LedgerError.invalid(["نام و نام خانوادگی"]) }
        var st = state
        var parties = LedgerOps.array(st, "parties")
        let digits = { (s: String) in SearchEngine.latinDigits(s).filter(\.isNumber) }
        var fields: [String: JSONValue] = [
            "fullName": .string(name),
            "nationalCode": .string(String(digits(input.nationalCode).prefix(10))),
            "mobile": .string(digits(input.mobile)),
            "cardNumber": .string(String(digits(input.cardNumber).prefix(16))),
            "accountNumber": .string(SearchEngine.latinDigits(input.accountNumber).trimmingCharacters(in: .whitespaces)),
            "iban": .string(SearchEngine.latinDigits(input.iban).trimmingCharacters(in: .whitespaces)),
            "bankName": .string(input.bankName.trimmingCharacters(in: .whitespaces)),
        ]
        if let eid = editingId {
            guard let i = parties.firstIndex(where: { $0["id"]?.idString == eid }), var o = parties[i].objectValue else { throw LedgerError.notFound }
            for (k, v) in fields { o[k] = v }
            parties[i] = .object(o)
            st["parties"] = .array(parties)
            return (st, eid)
        }
        let now = ids.nowMs()
        let id = "party" + String(now) + rand36(4)
        fields["id"] = .string(id)
        fields["createdAt"] = .int(Int64(now))
        parties.append(.object(fields))
        st["parties"] = .array(parties)
        return (st, id)
    }

    /// web: removes the registry entry only (people/checks keep their own name copy).
    public static func deleteParty(_ state: State, id: String) -> State {
        var st = state
        st["parties"] = .array(LedgerOps.array(st, "parties").filter { $0["id"]?.idString != id })
        return st
    }

    // MARK: tankhah parties (state.tankhahParties)

    public static func normalizeName(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: { $0.isWhitespace }).joined(separator: " ").lowercased()
    }

    public enum AddResult: Equatable, Sendable { case created, existing }

    /// web tkNewPartySaveBtn: same name → reuse; a new "person" is also registered in state.parties.
    public static func addTankhahParty(_ state: State, name: String, company: Bool, ids: IdSource = .system) throws
        -> (state: State, id: String, result: AddResult) {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { throw LedgerError.invalid(["نام"]) }
        var st = state
        var list = LedgerOps.array(st, "tankhahParties")
        if let found = list.first(where: { normalizeName($0["name"]?.stringValue ?? "") == normalizeName(n) }), let fid = found["id"]?.idString {
            return (st, fid, .existing)
        }
        let now = ids.nowMs()
        let id = "tp" + String(now) + rand36(4)
        list.append(.object(["id": .string(id), "type": .string(company ? "company" : "person"), "name": .string(n)]))
        st["tankhahParties"] = .array(list)
        if !company {
            var parties = LedgerOps.array(st, "parties")
            if !parties.contains(where: { normalizeName($0["fullName"]?.stringValue ?? "") == normalizeName(n) }) {
                parties.append(.object(["id": .string("party" + String(now) + rand36(4)), "fullName": .string(n), "nationalCode": .string(""),
                                        "mobile": .string(""), "cardNumber": .string(""), "accountNumber": .string(""), "iban": .string(""),
                                        "bankName": .string(""), "createdAt": .int(Int64(now))]))
                st["parties"] = .array(parties)
            }
        }
        return (st, id, .created)
    }

    /// web: picking a registry person ("cp:<id>") creates/links a same-name tankhah party.
    public static func tankhahPartyFromRegistry(_ state: State, partyId: String, ids: IdSource = .system) throws -> (state: State, id: String) {
        guard let cp = LedgerOps.array(state, "parties").first(where: { $0["id"]?.idString == partyId }),
              let name = cp["fullName"]?.stringValue else { throw LedgerError.notFound }
        var st = state
        var list = LedgerOps.array(st, "tankhahParties")
        if let found = list.first(where: { normalizeName($0["name"]?.stringValue ?? "") == normalizeName(name) }), let fid = found["id"]?.idString {
            return (st, fid)
        }
        let id = "tp" + String(ids.nowMs()) + rand36(4)
        list.append(.object(["id": .string(id), "type": .string("person"), "name": .string(name)]))
        st["tankhahParties"] = .array(list)
        return (st, id)
    }

    /// web tankhahPartyReportData: tankhah rows of one account grouped by party, biggest total first.
    public static func tankhahPartyReport(_ st: State, accountId: String) -> (groups: [TankhahPartyGroup], total: Int) {
        let parties = LedgerOps.array(st, "tankhahParties")
        let rows = LedgerOps.array(st, "expenses").enumerated()
            .filter { $0.element["accountId"]?.idString == accountId && $0.element["type"]?.stringValue == "tankhah" }
            .sorted { a, b in
                let da = ImportAnalyzer.date(a.element["date"]), db = ImportAnalyzer.date(b.element["date"])
                if da != db { return da < db }
                let ta = a.element["ts"]?.intValue ?? 0, tb = b.element["ts"]?.intValue ?? 0
                if ta != tb { return ta < tb }
                return a.offset < b.offset
            }
            .compactMap { $0.element.objectValue }
        var order: [String] = []
        var groups: [String: [[String: JSONValue]]] = [:]
        var types: [String: String] = [:]
        for r in rows {
            let p = parties.first { $0["id"]?.idString == r["partyId"]?.idString && r["partyId"]?.idString != nil }
            let name = p?["name"]?.stringValue ?? "بدون طرف حساب"
            if groups[name] == nil { order.append(name); groups[name] = [] }
            groups[name]!.append(r)
            if let t = p?["type"]?.stringValue { types[name] = t }
        }
        func sum(_ rs: [[String: JSONValue]]) -> Int { rs.reduce(0) { $0 + ImportAnalyzer.toman(.object($1)) } }
        // JS sort is stable: equal totals keep first-seen order
        let sorted = order.enumerated().sorted { a, b in
            let sa = sum(groups[a.element]!), sb = sum(groups[b.element]!)
            return sa != sb ? sa > sb : a.offset < b.offset
        }.map(\.element)
        let out = sorted.map { TankhahPartyGroup(name: $0, type: types[$0], total: sum(groups[$0]!), rows: groups[$0]!) }
        return (out, rows.reduce(0) { $0 + ImportAnalyzer.toman(.object($1)) })
    }
}
