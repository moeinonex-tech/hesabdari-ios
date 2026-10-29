import Foundation

// Commission engine with the two rules the owner approved (2026-10-28/29).
//
// (1) Coverage: a payment covers every expense entered before it (by entry order `ts`).
//     Each expense is counted once; its financial date never moves it between stages.
// (2) Running balance: due = commission of newly covered expenses + previous balance.
//     balanceAfter = due − paid. Debt (> 0) carries to the next payment; overpayment
//     (< 0) is credit that reduces the next commission. A full settlement leaves 0.
//     The balance is stored as a delta in `remainingForStage`, so the web app (which
//     sums remainingForStage) shows the same balance when it restores an iOS backup.
//
// D16 (approved): editing the amount of a payment recomputes the balance of that payment
// and every later one; calculatedAmount is kept.
//
// The golden reference is phase1/expected/commission_corrected.json.

public struct LedgerRow: Codable, Equatable, Sendable {
    public var key: String
    public var type: String            // "expense" | "tankhah" | …
    public var desc: String
    public var toman: Int
    public var date: JalaliDate
    public var ts: Int                 // entry order
    public var subcategory: String?
    public var commission: String?     // settlement key when this row is a commission payment
    public var linked: String?         // e.g. "check:pending"

    public init(key: String, type: String = "expense", desc: String, toman: Int, date: JalaliDate, ts: Int,
                subcategory: String? = nil, commission: String? = nil, linked: String? = nil) {
        self.key = key; self.type = type; self.desc = desc; self.toman = toman; self.date = date; self.ts = ts
        self.subcategory = subcategory; self.commission = commission; self.linked = linked
    }
}

public struct Settlement: Codable, Equatable, Sendable {
    public var key: String
    public var toman: Int
    public var date: JalaliDate
    public var ts: Int
    public var calculatedAmount: Int
    public var remainingForStage: Int
    public var isFull: Bool
    public var balanceAfter: Int?
}

public struct CommissionIncome: Codable, Equatable, Sendable {
    public var settlement: String
    public var desc: String
    public var toman: Int
    public var date: JalaliDate
    public var category: String
    public var subcategory: String
    public var accountId: String
    public var accountName: String
}

public struct StageRow: Equatable, Sendable {
    public var num: Int
    public var desc: String
}

public struct Stage: Equatable, Sendable {
    public var openBase: Int
    public var nextRowNumber: Int
    public var lastRow: StageRow?
    public var pastShortfall: Int   // = running balance (debt > 0, credit < 0)
}

public struct CommissionSummary: Equatable, Sendable {
    public var percent: Double
    public var openBase: Int
    public var accrued: Int
    public var pastShortfall: Int
    public var remaining: Int        // negative = credit
    public var settled: Int
    public var nextRowNumber: Int
    public var lastRow: StageRow?
    public var ledgerTotal: Int
}

/// One project ledger (حساب پروژه) with its commission state. Value type; the app layer
/// persists it inside a database transaction.
public struct CommissionLedger: Sendable {
    public var accountId: String
    public var accountName: String
    public var percent: Double
    public private(set) var rows: [LedgerRow] = []
    public private(set) var settlements: [Settlement] = []
    public private(set) var incomes: [CommissionIncome] = []
    private var clock: Int = 0
    private var undoState: (rows: [LedgerRow], settlements: [Settlement], incomes: [CommissionIncome])?

    public init(accountId: String, accountName: String, percent: Double, rows: [LedgerRow] = [],
                settlements: [Settlement] = []) {
        self.accountId = accountId; self.accountName = accountName; self.percent = percent
        self.rows = rows; self.settlements = settlements
        self.clock = max(rows.map(\.ts).max() ?? 0, settlements.map(\.ts).max() ?? 0)
    }

    private mutating func nextTs() -> Int { clock += 1; return clock }

    // MARK: stage

    private var sortedBaseRows: [LedgerRow] {
        rows.filter { $0.type != "tankhah" }
            .enumerated()
            .sorted { a, b in
                if a.element.date != b.element.date { return a.element.date < b.element.date }
                if a.element.ts != b.element.ts { return a.element.ts < b.element.ts }
                return a.offset < b.offset
            }
            .map(\.element)
    }

    public func stage() -> Stage {
        let sorted = sortedBaseRows
        var byKey: [String: Settlement] = [:]
        for s in settlements where byKey[s.key] == nil { byKey[s.key] = s }
        // a settlement counts only while its own commission row exists
        let coverTs = sorted.compactMap { r in r.commission.flatMap { byKey[$0] }?.ts }.max() ?? Int.min
        var base = 0, past = 0
        var last: StageRow?
        for (i, r) in sorted.enumerated() {
            if let c = r.commission {
                past += byKey[c]?.remainingForStage ?? 0
                continue
            }
            if r.ts > coverTs {
                base += r.toman
                last = StageRow(num: i + 1, desc: r.desc)
            }
        }
        return Stage(openBase: base, nextRowNumber: sorted.count + 1, lastRow: last, pastShortfall: past)
    }

    public func accrued(for openBase: Int) -> Int {
        Money.jsRound(Double(openBase) * percent / 100)
    }

    public func summary() -> CommissionSummary {
        let st = stage()
        let acc = accrued(for: st.openBase)
        return CommissionSummary(
            percent: percent, openBase: st.openBase, accrued: acc, pastShortfall: st.pastShortfall,
            remaining: acc + st.pastShortfall, settled: settlements.reduce(0) { $0 + $1.toman },
            nextRowNumber: st.nextRowNumber, lastRow: st.lastRow,
            ledgerTotal: rows.filter { $0.type != "tankhah" }.reduce(0) { $0 + $1.toman })
    }

    // MARK: operations

    public mutating func addExpense(key: String, desc: String, toman: Int, date: JalaliDate,
                                    subcategory: String? = "عمومی", type: String = "expense", linked: String? = nil) {
        rows.append(LedgerRow(key: key, type: type, desc: desc, toman: toman, date: date, ts: nextTs(),
                              subcategory: subcategory, linked: linked))
    }

    /// Records a commission payment and returns the settlement.
    @discardableResult
    public mutating func settle(key: String, amount: Int, date: JalaliDate) -> Settlement {
        let ts = nextTs()
        let st = stage()
        let calc = accrued(for: st.openBase)
        let before = st.pastShortfall
        let due = calc + before
        let balanceAfter = due - amount
        let isFull = amount >= due
        let rem = balanceAfter - before

        let descBase: String
        if let lr = st.lastRow {
            let rowNum = Money.persianDigits(lr.num)
            let rowDesc = lr.desc.isEmpty ? "—" : lr.desc
            descBase = "پرداخت کمیسیون تا ردیف هزینه \"\(rowNum)\" (\(rowDesc))"
        } else {
            let pct = Money.persianDigits(Money.jsNumberString(percent))
            descBase = percent != 0 ? "پرداخت کمیسیون (\(pct)٪)" : "پرداخت کمیسیون"
        }
        let desc = Self.balanceText(descBase, balanceAfter)

        let s = Settlement(key: key, toman: amount, date: date, ts: ts, calculatedAmount: calc,
                           remainingForStage: rem, isFull: isFull, balanceAfter: balanceAfter)
        settlements.append(s)
        rows.append(LedgerRow(key: key, desc: desc, toman: amount, date: date, ts: ts, subcategory: nil, commission: key))
        incomes.append(CommissionIncome(settlement: key, desc: "دریافت کمیسیون از \(accountName)", toman: amount, date: date,
                                        category: "کمیسیون", subcategory: accountName, accountId: "personal",
                                        accountName: accountName))
        return s
    }

    public mutating func edit(key: String, toman: Int? = nil, date: JalaliDate? = nil) {
        guard let i = rows.firstIndex(where: { $0.key == key }) else { return }
        if let t = toman { rows[i].toman = t }
        if let d = date { rows[i].date = d }
        if rows[i].subcategory == nil { rows[i].subcategory = "تسویه" }   // the web form forces a subcategory
        if let c = rows[i].commission {
            let r = rows[i]
            if let si = settlements.firstIndex(where: { $0.key == c }) {
                settlements[si].toman = r.toman
                settlements[si].date = r.date
            }
            for j in incomes.indices where incomes[j].settlement == c {
                incomes[j].toman = r.toman
                incomes[j].date = r.date
            }
            if toman != nil, let edited = settlements.first(where: { $0.key == c }) {
                recomputeBalance(from: edited)
            }
        }
    }

    // MARK: D16 (approved 2026-10-29)

    /// Row text for a payment: base + balance suffix (debt / full / credit).
    static func balanceText(_ base: String, _ balanceAfter: Int) -> String {
        if balanceAfter > 0 {
            let amountText = Money.persianDigits(Money.format(balanceAfter))
            return "\(base) — مبلغ \(amountText) از تسویه این مرحله از کمیسیون باقی مانده است"
        } else if balanceAfter < 0 {
            // wording PROPOSED, not yet approved by the owner
            let amountText = Money.persianDigits(Money.format(-balanceAfter))
            return "\(base) تسویه کامل — مبلغ \(amountText) اضافه پرداخت، از کمیسیون بعدی کم می‌شود"
        }
        return "\(base) تسویه کامل"
    }

    static let balanceSuffix = " — مبلغ [۰-۹.]+ از تسویه این مرحله از کمیسیون باقی مانده است$| تسویه کامل — مبلغ [۰-۹.]+ اضافه پرداخت، از کمیسیون بعدی کم می‌شود$| تسویه کامل$"

    /// Editing a payment amount recomputes the balance of that payment and of every later payment
    /// (entry order). calculatedAmount is kept (the percent at that time is not stored); earlier payments
    /// are untouched; the balance suffix of each affected row text is rewritten.
    private mutating func recomputeBalance(from edited: Settlement) {
        let liveKeys = Set(rows.compactMap(\.commission))
        let order = settlements.indices.filter { liveKeys.contains(settlements[$0].key) }
            .sorted { settlements[$0].ts < settlements[$1].ts }
        var before = order.filter { settlements[$0].ts < edited.ts }.reduce(0) { $0 + settlements[$1].remainingForStage }
        for si in order where settlements[si].ts >= edited.ts {
            let due = settlements[si].calculatedAmount + before
            let ba = due - settlements[si].toman
            settlements[si].balanceAfter = ba
            settlements[si].isFull = settlements[si].toman >= due
            settlements[si].remainingForStage = ba - before
            before = ba
            if let ri = rows.firstIndex(where: { $0.commission == settlements[si].key }),
               let range = rows[ri].desc.range(of: Self.balanceSuffix, options: .regularExpression) {
                let base = String(rows[ri].desc[..<range.lowerBound])
                rows[ri].desc = Self.balanceText(base, ba)
            }
        }
    }

    public mutating func delete(key: String) {
        guard let i = rows.firstIndex(where: { $0.key == key }) else { return }
        undoState = (rows: rows, settlements: settlements, incomes: incomes)
        let item = rows.remove(at: i)
        if let c = item.commission {
            settlements.removeAll { $0.key == c }
            incomes.removeAll { $0.settlement == c }
        }
    }

    public mutating func undo() {
        guard let u = undoState else { return }
        rows = u.rows; settlements = u.settlements; incomes = u.incomes
        undoState = nil
    }

    /// Removes a row without an undo point (e.g. a bounced check's linked expense).
    public mutating func removeRow(key: String) {
        rows.removeAll { $0.key == key }
    }
}
