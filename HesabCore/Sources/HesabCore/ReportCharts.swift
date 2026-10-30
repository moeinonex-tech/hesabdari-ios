import Foundation

// Report chart data — web: trendMonthlyData / trendDailyData / trendYearlyData, cashFlowMonthlyData /
// cashFlowYearlyData, renderAccountsCompareChart, renderCommissionCompareChart, getFinancialComparison.

public struct ChartPoint: Equatable, Sendable {
    public let jy: Int
    public let jm: Int          // 0 for yearly points
    public let jd: Int          // 0 unless daily
    public let label: String
    public let value: Int
}

public struct FlowPoint: Equatable, Sendable {
    public let label: String
    public let income: Int
    public let expense: Int
}

public struct Comparison: Equatable, Sendable {
    public let income: Int
    public let expense: Int
    public var net: Int { income - expense }
    /// web: Math.round(expense / income * 100), 0 without income
    public var pct: Int { income > 0 ? Money.jsRound(Double(expense) / Double(income) * 100) : 0 }
}

public enum ReportCharts {
    public typealias Item = (date: JalaliDate, toman: Int)

    static func items(_ list: [JSONValue]) -> [Item] { list.map { (ImportAnalyzer.date($0["date"]), ImportAnalyzer.toman($0)) } }

    public static func ledgerExpenses(_ st: [String: JSONValue], accountId: String) -> [Item] {
        items((st["expenses"]?.arrayValue ?? []).filter { $0["accountId"]?.idString == accountId && $0["type"]?.stringValue != "tankhah" })
    }
    public static func ledgerIncomes(_ st: [String: JSONValue], accountId: String) -> [Item] {
        items((st["incomes"]?.arrayValue ?? []).filter { $0["accountId"]?.idString == accountId })
    }
    public static func allIncomes(_ st: [String: JSONValue]) -> [Item] { items(st["incomes"]?.arrayValue ?? []) }
    public static func personalExpenses(_ st: [String: JSONValue]) -> [Item] { items(st["personalExpenses"]?.arrayValue ?? []) }
    /// web incomeScopeOf === 'personal'
    public static func personalIncomes(_ st: [String: JSONValue]) -> [Item] {
        items((st["incomes"]?.arrayValue ?? []).filter { let a = $0["accountId"]?.idString ?? ""; return a.isEmpty || a == "personal" })
    }

    static func shortMonth(_ m: Int) -> String { String(BackupExporter.months[m - 1].prefix(3)) }

    public static func monthly(_ list: [Item]) -> [ChartPoint] {
        var sums: [Int: Int] = [:]
        for e in list { sums[e.date.jy * 100 + e.date.jm, default: 0] += e.toman }
        return sums.keys.sorted().map { k in ChartPoint(jy: k / 100, jm: k % 100, jd: 0, label: shortMonth(k % 100), value: sums[k]!) }
    }

    public static func daily(_ list: [Item], jy: Int, jm: Int) -> [ChartPoint] {
        var sums: [Int: Int] = [:]
        for e in list where e.date.jy == jy && e.date.jm == jm { sums[e.date.jd, default: 0] += e.toman }
        return (1...Jalali.monthLength(jy, jm)).map { d in
            ChartPoint(jy: jy, jm: jm, jd: d, label: Money.persianDigits(String(d)), value: sums[d] ?? 0)
        }
    }

    public static func yearly(_ list: [Item]) -> [ChartPoint] {
        var sums: [Int: Int] = [:]
        for e in list { sums[e.date.jy, default: 0] += e.toman }
        return sums.keys.sorted().map { ChartPoint(jy: $0, jm: 0, jd: 0, label: Money.persianDigits(String($0)), value: sums[$0]!) }
    }

    public static func cashFlow(income: [Item], expense: [Item], yearly: Bool) -> [FlowPoint] {
        var inc: [Int: Int] = [:], exp: [Int: Int] = [:]
        let key = { (d: JalaliDate) in yearly ? d.jy : d.jy * 100 + d.jm }
        for e in expense { exp[key(e.date), default: 0] += e.toman }
        for e in income { inc[key(e.date), default: 0] += e.toman }
        return Set(inc.keys).union(exp.keys).sorted().map { k in
            FlowPoint(label: yearly ? Money.persianDigits(String(k)) : shortMonth(k % 100), income: inc[k] ?? 0, expense: exp[k] ?? 0)
        }
    }

    /// web renderAccountsCompareChart: accounts with spending, biggest first (shown only for 2+).
    public static func accountsCompare(_ accounts: [AccountImportSummary]) -> [(name: String, value: Int)] {
        accounts.map { ($0.name, $0.expenseTotal) }.filter { $0.1 > 0 }
            .enumerated().sorted { $0.element.1 != $1.element.1 ? $0.element.1 > $1.element.1 : $0.offset < $1.offset }
            .map { (name: $0.element.0, value: $0.element.1) }
    }

    /// web renderCommissionCompareChart: accrued-to-date per commission-enabled account.
    public static func commissionCompare(_ accounts: [AccountImportSummary]) -> [(name: String, value: Int)] {
        accounts.filter { $0.commissionEnabled && $0.percent > 0 }.map { ($0.name, $0.accrued) }.filter { $0.1 > 0 }
            .enumerated().sorted { $0.element.1 != $1.element.1 ? $0.element.1 > $1.element.1 : $0.offset < $1.offset }
            .map { (name: $0.element.0, value: $0.element.1) }
    }

    public static func comparisonLedger(_ st: [String: JSONValue], accountId: String) -> Comparison {
        Comparison(income: ledgerIncomes(st, accountId: accountId).reduce(0) { $0 + $1.toman },
                   expense: ledgerExpenses(st, accountId: accountId).reduce(0) { $0 + $1.toman })
    }
    public static func comparisonPersonal(_ st: [String: JSONValue]) -> Comparison {
        Comparison(income: personalIncomes(st).reduce(0) { $0 + $1.toman }, expense: personalExpenses(st).reduce(0) { $0 + $1.toman })
    }
}
