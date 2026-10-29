import Foundation

// Ledger changes on the stored JSON state. Every function returns a NEW state; the caller saves it in one
// transaction (or discards it). Records have exactly the shape the web app writes, so backups stay
// compatible in both directions.
//
// Web sources (app.html): form submit (new/edit expense), commSettleBtn (commission payment),
// list delete (+ undo), addIncomeFromCommissionSettlement, syncIncomeForCommissionSettlement,
// addCategoryIfNew / addSubcategoryIfNew / addIncomeSubcategoryIfNew, applyPayMethodToExpense,
// withEditUnlock / isDateEditLocked.

public struct IdSource: Sendable {
    public var nowMs: @Sendable () -> Int
    public var random5: @Sendable () -> String

    public init(nowMs: @escaping @Sendable () -> Int, random5: @escaping @Sendable () -> String) {
        self.nowMs = nowMs; self.random5 = random5
    }

    /// Same scheme as the web app: prefix + Date.now() + 5 random base-36 chars.
    public static let system = IdSource(
        nowMs: { Int(Date().timeIntervalSince1970 * 1000) },
        random5: {
            let chars = Array("0123456789abcdefghijklmnopqrstuvwxyz")
            return String((0..<5).map { _ in chars[Int.random(in: 0..<chars.count)] })
        })

    func make(_ prefix: String, _ now: Int) -> String { prefix + String(now) + random5() }
}

public enum PayMethod: String, CaseIterable, Sendable {
    case hamrahbank, pos, cash, transfer, check, nasiyeh, branch

    public var title: String {
        switch self {
        case .hamrahbank: return "همراه‌بانک"
        case .pos: return "پوز"
        case .cash: return "نقدی"
        case .transfer: return "حواله به حساب"
        case .check: return "چک"
        case .nasiyeh: return "نسیه"
        case .branch: return "شعبه بانک"
        }
    }

    /// Methods available in this version. Check, nasiyeh and branch create linked records in the web app
    /// (checks / debts / bank details); they come with the checks & debts step.
    public static func available(forTankhah: Bool) -> [PayMethod] {
        forTankhah ? [.transfer, .cash] : [.hamrahbank, .pos, .cash]
    }

    public static func defaultFor(tankhah: Bool) -> PayMethod { tankhah ? .transfer : .hamrahbank }

    public var usesCard: Bool { self == .hamrahbank || self == .pos || self == .transfer }
}

public struct ExpenseInput: Sendable {
    public var accountId: String
    public var isTankhah: Bool
    public var desc: String
    public var category: String
    public var subcategory: String
    public var toman: Int
    public var date: JalaliDate
    public var payMethod: PayMethod
    public var cardId: String?
    public var partyId: String?

    public init(accountId: String, isTankhah: Bool, desc: String, category: String, subcategory: String,
                toman: Int, date: JalaliDate, payMethod: PayMethod, cardId: String?, partyId: String?) {
        self.accountId = accountId; self.isTankhah = isTankhah; self.desc = desc; self.category = category
        self.subcategory = subcategory; self.toman = toman; self.date = date; self.payMethod = payMethod
        self.cardId = cardId; self.partyId = partyId
    }

    /// Web required fields: tankhah → party + amount; expense → desc, category, subcategory, amount.
    public var missingFields: [String] {
        var m: [String] = []
        if isTankhah {
            if (partyId ?? "").isEmpty { m.append("طرف حساب") }
        } else {
            if desc.trimmingCharacters(in: .whitespaces).isEmpty { m.append("شرح") }
            if category.trimmingCharacters(in: .whitespaces).isEmpty { m.append("نوع هزینه") }
            if subcategory.trimmingCharacters(in: .whitespaces).isEmpty { m.append("زیردسته") }
        }
        if toman <= 0 { m.append("مبلغ") }
        return m
    }
}

public enum LedgerError: Error, Equatable, Sendable {
    case notFound
    case linkedRow(String)
    case invalid([String])
    case noAmount

    public var message: String {
        switch self {
        case .notFound: return "این ردیف پیدا نشد."
        case .linkedRow(let kind): return "این ردیف به \(kind) وصل است و فعلاً از همان بخش مدیریت می‌شود. ویرایش آن در مرحله‌ی چک‌ها و بدهی‌ها اضافه می‌شود."
        case .invalid(let fields): return "این موارد را پر کنید: " + fields.joined(separator: "، ")
        case .noAmount: return "مبلغ پرداخت را وارد کنید."
        }
    }
}

public enum LedgerOps {

    // MARK: JSON helpers

    static func date(_ d: JalaliDate) -> JSONValue {
        .object(["jy": .int(Int64(d.jy)), "jm": .int(Int64(d.jm)), "jd": .int(Int64(d.jd))])
    }

    static func array(_ st: [String: JSONValue], _ key: String) -> [JSONValue] { st[key]?.arrayValue ?? [] }

    /// web addCategoryIfNew (trimmed, compared trimmed)
    static func addCategoryIfNew(_ st: inout [String: JSONValue], list key: String, _ cat: String) {
        let c = cat.trimmingCharacters(in: .whitespaces)
        guard !c.isEmpty else { return }
        var list = array(st, key)
        if !list.contains(where: { ($0.stringValue ?? "").trimmingCharacters(in: .whitespaces) == c }) {
            list.append(.string(c))
            st[key] = .array(list)
        }
    }

    /// web addSubcategoryIfNew / addIncomeSubcategoryIfNew
    static func addSubcategoryIfNew(_ st: inout [String: JSONValue], map key: String, category: String, _ sub: String) {
        let s = sub.trimmingCharacters(in: .whitespaces)
        guard !category.isEmpty, !s.isEmpty else { return }
        var map = st[key]?.objectValue ?? [:]
        var list = map[category]?.arrayValue ?? []
        if !list.contains(where: { ($0.stringValue ?? "").trimmingCharacters(in: .whitespaces) == s }) {
            list.append(.string(s))
            map[category] = .array(list)
            st[key] = .object(map)
        }
    }

    // MARK: add / edit

    /// New ledger row (expense or tankhah) — web form submit, new-row branch.
    public static func addExpense(_ state: [String: JSONValue], _ input: ExpenseInput, ids: IdSource = .system)
        throws -> (state: [String: JSONValue], id: String) {
        let missing = input.missingFields
        guard missing.isEmpty else { throw LedgerError.invalid(missing) }
        var st = state
        if !input.isTankhah { learn(&st, input) }
        let now = ids.nowMs()
        let id = ids.make("e", now)
        var row: [String: JSONValue] = [
            "id": .string(id), "accountId": .string(input.accountId),
            "desc": .string(input.desc), "toman": .int(Int64(input.toman)), "date": date(input.date),
            "ts": .int(Int64(now)), "type": .string(input.isTankhah ? "tankhah" : "expense")
        ]
        let cat = input.category.trimmingCharacters(in: .whitespaces)
        if !cat.isEmpty { row["category"] = .string(input.category) }
        if !input.isTankhah && !input.subcategory.isEmpty { row["subcategory"] = .string(input.subcategory) }
        if input.isTankhah, let p = input.partyId, !p.isEmpty { row["partyId"] = .string(p) }
        applyPayMethod(&row, &st, input)
        var rows = array(st, "expenses")
        rows.append(.object(row))
        st["expenses"] = .array(rows)
        return (st, id)
    }

    /// Edit — web form submit, edit branch. Commission rows keep settlement and income in sync, and an amount
    /// change recomputes the balance of that payment and every later one (D16).
    public static func editExpense(_ state: [String: JSONValue], id: String, _ input: ExpenseInput) throws -> [String: JSONValue] {
        var st = state
        var rows = array(st, "expenses")
        guard let i = rows.firstIndex(where: { $0["id"]?.idString == id }), var row = rows[i].objectValue else {
            throw LedgerError.notFound
        }
        if let kind = linkedKind(rows[i]) { throw LedgerError.linkedRow(kind) }
        let isCommission = row["commissionSettlementId"]?.idString != nil
        // a commission payment row: only amount and date are editable (its text is generated)
        var input = input
        if isCommission {
            input.desc = row["desc"]?.stringValue ?? ""
            input.category = row["category"]?.stringValue ?? "کمیسیون"
            if input.subcategory.isEmpty { input.subcategory = row["subcategory"]?.stringValue ?? "تسویه" }
            input.isTankhah = false
        }
        let missing = input.missingFields
        guard missing.isEmpty else { throw LedgerError.invalid(missing) }
        if !input.isTankhah { learn(&st, input) }

        let oldToman = ImportAnalyzer.toman(rows[i])
        row["desc"] = .string(input.desc)
        row["toman"] = .int(Int64(input.toman))
        row["date"] = date(input.date)
        row["type"] = .string(input.isTankhah ? "tankhah" : "expense")
        let cat = input.category.trimmingCharacters(in: .whitespaces)
        if cat.isEmpty { row.removeValue(forKey: "category") } else { row["category"] = .string(input.category) }
        if !input.isTankhah && !input.subcategory.isEmpty { row["subcategory"] = .string(input.subcategory) } else { row.removeValue(forKey: "subcategory") }
        if input.isTankhah, let p = input.partyId, !p.isEmpty { row["partyId"] = .string(p) } else { row.removeValue(forKey: "partyId") }
        row.removeValue(forKey: "items")          // web: an edited multi-item invoice becomes a single row
        if !isCommission { applyPayMethod(&row, &st, input) }
        rows[i] = .object(row)
        st["expenses"] = .array(rows)

        guard isCommission, let sid = row["commissionSettlementId"]?.idString,
              let accId = row["accountId"]?.idString else { return st }

        // settlement + income sync (web)
        var accounts = array(st, "accounts")
        if let ai = accounts.firstIndex(where: { $0["id"]?.idString == accId }), var acc = accounts[ai].objectValue {
            var sets = acc["commissionSettlements"]?.arrayValue ?? []
            if let si = sets.firstIndex(where: { $0["id"]?.idString == sid }), var s = sets[si].objectValue {
                s["toman"] = .int(Int64(input.toman)); s["date"] = date(input.date)
                sets[si] = .object(s)
                acc["commissionSettlements"] = .array(sets)
                accounts[ai] = .object(acc)
                st["accounts"] = .array(accounts)
            }
        }
        var incomes = array(st, "incomes")
        for j in incomes.indices where incomes[j]["commissionSettlementId"]?.idString == sid {
            if var inc = incomes[j].objectValue {
                inc["toman"] = .int(Int64(input.toman)); inc["date"] = date(input.date)
                incomes[j] = .object(inc)
            }
        }
        st["incomes"] = .array(incomes)

        if oldToman != input.toman { st = recomputeBalances(st, accountId: accId, editedRowId: id, oldState: state, newToman: input.toman, newDate: input.date) }
        return st
    }

    /// D16: recompute with the engine, then write the balance fields and the row texts back to JSON.
    static func recomputeBalances(_ st: [String: JSONValue], accountId: String, editedRowId: String,
                                  oldState: [String: JSONValue], newToman: Int, newDate: JalaliDate) -> [String: JSONValue] {
        var st = st
        guard let accBefore = array(oldState, "accounts").first(where: { $0["id"]?.idString == accountId }) else { return st }
        var L = ImportAnalyzer.ledger(account: accBefore, expenses: array(oldState, "expenses"))
        L.edit(key: editedRowId, toman: newToman, date: newDate)
        let byKey = Dictionary(L.settlements.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        let descByRow = Dictionary(L.rows.map { ($0.key, $0.desc) }, uniquingKeysWith: { a, _ in a })

        var accounts = array(st, "accounts")
        if let ai = accounts.firstIndex(where: { $0["id"]?.idString == accountId }), var acc = accounts[ai].objectValue {
            var sets = acc["commissionSettlements"]?.arrayValue ?? []
            for k in sets.indices {
                guard var s = sets[k].objectValue, let sid = s["id"]?.idString, let n = byKey[sid], let ba = n.balanceAfter else { continue }
                let changed = s["remainingForStage"]?.intValue != n.remainingForStage || s["isFull"]?.boolValue != n.isFull
                    || s["balanceAfter"]?.intValue != ba
                if changed {
                    s["remainingForStage"] = .int(Int64(n.remainingForStage))
                    s["isFull"] = .bool(n.isFull)
                    s["balanceAfter"] = .int(Int64(ba))
                    sets[k] = .object(s)
                }
            }
            acc["commissionSettlements"] = .array(sets)
            accounts[ai] = .object(acc)
            st["accounts"] = .array(accounts)
        }
        var rows = array(st, "expenses")
        for k in rows.indices {
            guard rows[k]["accountId"]?.idString == accountId, rows[k]["commissionSettlementId"]?.idString != nil,
                  let rid = rows[k]["id"]?.idString, let d = descByRow[rid], var o = rows[k].objectValue else { continue }
            if o["desc"]?.stringValue != d { o["desc"] = .string(d); rows[k] = .object(o) }
        }
        st["expenses"] = .array(rows)
        return st
    }

    // MARK: delete

    /// Web list delete: removes the row; a commission row also removes its settlement and the linked income.
    /// Undo = keep the previous state and save it again (exact restore).
    public static func deleteExpense(_ state: [String: JSONValue], id: String) throws -> [String: JSONValue] {
        var st = state
        var rows = array(st, "expenses")
        guard let i = rows.firstIndex(where: { $0["id"]?.idString == id }) else { throw LedgerError.notFound }
        if let kind = linkedKind(rows[i]) { throw LedgerError.linkedRow(kind) }
        let item = rows[i]
        rows = rows.filter { $0["id"]?.idString != id }
        st["expenses"] = .array(rows)
        if let sid = item["commissionSettlementId"]?.idString {
            let accId = item["accountId"]?.idString
            st["accounts"] = .array(array(st, "accounts").map { a in
                guard a["id"]?.idString == accId, var o = a.objectValue else { return a }
                o["commissionSettlements"] = .array((o["commissionSettlements"]?.arrayValue ?? []).filter { $0["id"]?.idString != sid })
                return .object(o)
            })
            st["incomes"] = .array(array(st, "incomes").filter { $0["commissionSettlementId"]?.idString != sid })
        }
        return st
    }

    // MARK: commission payment

    /// Web commSettleBtn with the approved rules (coverage by entry order, running balance).
    public static func settleCommission(_ state: [String: JSONValue], accountId: String, amount: Int, date: JalaliDate,
                                        ids: IdSource = .system) throws -> (state: [String: JSONValue], settlementId: String) {
        guard amount > 0 else { throw LedgerError.noAmount }
        var st = state
        var accounts = array(st, "accounts")
        guard let ai = accounts.firstIndex(where: { $0["id"]?.idString == accountId }), var acc = accounts[ai].objectValue else {
            throw LedgerError.notFound
        }
        let now = ids.nowMs()
        let settleId = ids.make("s", now).dropLast(1).description      // web: 4 random chars for settlements
        let expenseId = ids.make("e", now)

        var L = ImportAnalyzer.ledger(account: accounts[ai], expenses: array(st, "expenses"))
        let s = L.settle(key: settleId, amount: amount, date: date, ts: now)
        let desc = L.rows.last?.desc ?? ""

        var sets = acc["commissionSettlements"]?.arrayValue ?? []
        sets.append(.object([
            "id": .string(settleId), "toman": .int(Int64(amount)), "date": self.date(date), "ts": .int(Int64(now)),
            "expenseId": .string(expenseId), "calculatedAmount": .int(Int64(s.calculatedAmount)),
            "remainingForStage": .int(Int64(s.remainingForStage)), "isFull": .bool(s.isFull),
            "balanceAfter": .int(Int64(s.balanceAfter ?? 0))
        ]))
        acc["commissionSettlements"] = .array(sets)
        accounts[ai] = .object(acc)
        st["accounts"] = .array(accounts)

        addCategoryIfNew(&st, list: "ledgerCategories", "کمیسیون")
        var rows = array(st, "expenses")
        rows.append(.object([
            "id": .string(expenseId), "accountId": .string(accountId), "type": .string("expense"),
            "desc": .string(desc), "category": .string("کمیسیون"), "toman": .int(Int64(amount)),
            "date": self.date(date), "ts": .int(Int64(now)), "commissionSettlementId": .string(settleId)
        ]))
        st["expenses"] = .array(rows)

        // income (web addIncomeFromCommissionSettlement)
        let name = acc["name"]?.stringValue ?? ""
        addCategoryIfNew(&st, list: "incomeCategories", "کمیسیون")
        addSubcategoryIfNew(&st, map: "incomeSubcategories", category: "کمیسیون", name)
        var incomes = array(st, "incomes")
        incomes.append(.object([
            "id": .string(ids.make("i", now)), "desc": .string("دریافت کمیسیون از " + name), "toman": .int(Int64(amount)),
            "date": self.date(date), "ts": .int(Int64(now)), "category": .string("کمیسیون"), "subcategory": .string(name),
            "accountId": .string("personal"), "accountName": .string(name), "source": .string("commission"),
            "commissionSettlementId": .string(settleId)
        ]))
        st["incomes"] = .array(incomes)
        return (st, settleId)
    }

    // MARK: edit lock (web withEditUnlock)

    /// Locked when a password is set, the session is not unlocked, and the row's own date is 8+ days ago.
    public static func isEditLocked(rowDate: JalaliDate, today: JalaliDate, password: String?, sessionUnlocked: Bool) -> Bool {
        guard let p = password, !p.isEmpty, !sessionUnlocked else { return false }
        let diff = Jalali.j2d(today.jy, today.jm, today.jd) - Jalali.j2d(rowDate.jy, rowDate.jm, rowDate.jd)
        return diff >= 8
    }

    /// Unlock lasts 15 minutes (web).
    public static let unlockSeconds: TimeInterval = 15 * 60

    // MARK: private

    static func linkedKind(_ row: JSONValue) -> String? {
        guard let kind = row["linked"]?["kind"]?.stringValue else { return nil }
        switch kind {
        case "check": return "چک"
        case "debt": return "بدهی/نسیه"
        default: return "بخش دیگری"
        }
    }

    static func learn(_ st: inout [String: JSONValue], _ input: ExpenseInput) {
        addCategoryIfNew(&st, list: "ledgerCategories", input.category)
        if !input.category.isEmpty && !input.subcategory.isEmpty {
            addSubcategoryIfNew(&st, map: "ledgerSubcategories", category: input.category, input.subcategory)
        }
    }

    /// web applyPayMethodToExpense (methods available in this version)
    static func applyPayMethod(_ row: inout [String: JSONValue], _ st: inout [String: JSONValue], _ input: ExpenseInput) {
        row["payMethod"] = .string(input.payMethod.rawValue)
        for k in ["cardId", "bankName", "branchName", "checkId", "checkIds"] { row.removeValue(forKey: k) }
        if input.payMethod.usesCard, let c = input.cardId, !c.isEmpty {
            row["cardId"] = .string(c)
            if input.payMethod == .hamrahbank {
                var m = st["lastCardByAccount"]?.objectValue ?? [:]
                m[input.accountId] = .string(c)
                st["lastCardByAccount"] = .object(m)
            }
        }
    }
}
