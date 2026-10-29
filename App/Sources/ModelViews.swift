import SwiftUI
import UIKit
import HesabCore

struct AttentionItem: Identifiable {
    let id: String
    let icon: String
    let level: Level
    let text: String
    enum Level { case danger, warning, info }
}

struct RecentItem: Identifiable {
    var id: String { row.id }
    let row: LedgerRowVM
    let account: String
}

struct CategorySlice: Identifiable {
    var id: String { name }
    let name: String
    let total: Int
    let color: Color
}

struct MonthGroup: Identifiable {
    var id: String { "\(year)-\(month)" }
    let year: Int
    let month: Int
    let rows: [LedgerRowVM]
    var total: Int { rows.filter { $0.kind != .tankhah }.reduce(0) { $0 + $1.toman } }
    var title: String { (BackupExporter.months.indices.contains(month - 1) ? BackupExporter.months[month - 1] : "?") + " " + Money.persianDigits(year) }
}

struct WalletCard: Identifiable {
    let id: String
    let bankName: String
    let number: String
    let iban: String
    let holder: String
    let expiry: String
    let accountType: String
    let archived: Bool
    let image: UIImage?
    let color: Color?
}

extension AppModel {

    static let weekdays = ["شنبه", "یکشنبه", "دوشنبه", "سه‌شنبه", "چهارشنبه", "پنجشنبه", "جمعه"]
    static let ownerName = "معین"     // web: HOME_USER_NAME

    /// web homeGreetingByHour
    static func greeting(hour: Int) -> (text: String, icon: String) {
        switch hour {
        case 0..<6: return ("بامداد بخیر", "moon.stars.fill")
        case 6..<11: return ("روز بخیر", "sunrise.fill")
        case 11..<14: return ("ظهر بخیر", "sun.max.fill")
        case 14..<19: return ("عصر بخیر", "sunset.fill")
        default: return ("شب بخیر", "moon.fill")
        }
    }

    var todayTitle: (weekday: String, date: String) {
        let c = Fmt.gregorian.dateComponents([.year, .month, .day], from: Date())
        let w = Jalali.weekdaySat0(c.year ?? 2000, c.month ?? 1, c.day ?? 1)
        return (Self.weekdays[max(0, min(6, w))], BackupExporter.formatJalali(Self.today))
    }

    var activeAccountId: String? {
        let ids = accounts.map(\.id)
        if let a = state["activeAccountId"]?.idString, ids.contains(a) { return a }
        return ids.first
    }

    func categoryColor(_ name: String) -> Color? {
        Color.web(state["categoryColors"]?[name]?.stringValue)
    }

    /// Attention box (simplified port of the web home: budget, checks, installments).
    var attentionItems: [AttentionItem] {
        var items: [AttentionItem] = []
        let today = Self.today
        let todayN = Jalali.j2d(today.jy, today.jm, today.jd)
        func days(_ v: JSONValue?) -> Int? {
            guard ImportAnalyzer.isValidDate(v) else { return nil }
            let d = ImportAnalyzer.date(v)
            return Jalali.j2d(d.jy, d.jm, d.jd) - todayN
        }
        var dueDebts = 0, overdueDebts = 0
        for p in state["reminderPersons"]?.arrayValue ?? [] {
            for i in p["installments"]?.arrayValue ?? [] where !(i["paid"]?.isTruthy ?? false) {
                if let d = days(i["dueDate"]) { if d < 0 { overdueDebts += 1 } else if d <= 3 { dueDebts += 1 } }
            }
        }
        var dueChecks = 0, overdueChecks = 0
        for c in state["reminderChecks"]?.arrayValue ?? [] where c["status"]?.stringValue == "pending" {
            if let d = days(c["dueDate"]) { if d < 0 { overdueChecks += 1 } else if d <= 3 { dueChecks += 1 } }
        }
        if overdueDebts + overdueChecks > 0 {
            items.append(AttentionItem(id: "overdue", icon: "exclamationmark.octagon.fill", level: .danger,
                                       text: Money.persianDigits(overdueDebts + overdueChecks) + " قسط یا چک از سررسیدش گذشته"))
        }
        if dueDebts > 0 {
            items.append(AttentionItem(id: "debts", icon: "arrow.up.forward.circle.fill", level: .danger,
                                       text: Money.persianDigits(dueDebts) + " بدهی نزدیک به سررسید"))
        }
        if dueChecks > 0 {
            items.append(AttentionItem(id: "checks", icon: "doc.text.fill", level: .warning,
                                       text: Money.persianDigits(dueChecks) + " چک نزدیک به سررسید"))
        }
        for a in state["accounts"]?.arrayValue ?? [] {
            let budget = a["budget"]?.intValue ?? 0
            guard budget > 0 else { continue }
            let s = ImportAnalyzer.accountSummary(a, expenses: state["expenses"]?.arrayValue ?? [])
            let pct = Double(s.expenseTotal) / Double(budget) * 100
            if pct >= 80 {
                items.append(AttentionItem(id: "budget-" + s.id, icon: "exclamationmark.triangle.fill", level: .warning,
                                           text: "حساب «\(s.name)» به \(Money.persianDigits(Money.jsRound(pct)))٪ بودجه رسیده"))
            }
        }
        return items
    }

    func budget(accountId: String) -> Int {
        (state["accounts"]?.arrayValue ?? []).first { $0["id"]?.idString == accountId }?["budget"]?.intValue ?? 0
    }

    /// Latest entries across all ledgers (by entry time).
    var recentRows: [RecentItem] {
        let names = Dictionary(accounts.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        let all = (state["expenses"]?.arrayValue ?? []).sorted { ($0["ts"]?.intValue ?? 0) > ($1["ts"]?.intValue ?? 0) }.prefix(6)
        return all.compactMap { e -> RecentItem? in
            let acc = e["accountId"]?.idString ?? ""
            guard let vm = rows(accountId: acc).first(where: { $0.rowId == e["id"]?.idString }) else { return nil }
            return RecentItem(row: vm, account: names[acc] ?? "")
        }
    }

    func categoryBreakdown(accountId: String) -> [CategorySlice] {
        var sums: [String: Int] = [:]
        for r in rows(accountId: accountId) where r.kind != .tankhah {
            sums[r.category.isEmpty ? "بدون دسته" : r.category, default: 0] += r.toman
        }
        let palette: [Color] = [.blue, .teal, .orange, .pink, .purple, .green, .indigo, .mint, .red, .yellow]
        return sums.sorted { $0.value > $1.value }.enumerated().map { i, kv in
            CategorySlice(name: kv.key, total: kv.value, color: categoryColor(kv.key) ?? palette[i % palette.count])
        }
    }

    func monthGroups(accountId: String) -> [MonthGroup] {
        let rows = rows(accountId: accountId)
        var order: [String] = []
        var groups: [String: [LedgerRowVM]] = [:]
        for r in rows.reversed() {
            let k = "\(r.dateValue.jy)-\(r.dateValue.jm)"
            if groups[k] == nil { order.append(k) }
            groups[k, default: []].append(r)
        }
        return order.compactMap { k in
            guard let g = groups[k], let f = g.first else { return nil }
            return MonthGroup(year: f.dateValue.jy, month: f.dateValue.jm, rows: g)
        }
    }

    var walletCards: [WalletCard] {
        (state["cards"]?.arrayValue ?? []).compactMap { c in
            guard let id = c["id"]?.idString else { return nil }
            var image: UIImage?
            if let s = c["bgImage"]?.stringValue, let comma = s.firstIndex(of: ","), s.hasPrefix("data:"),
               let data = Data(base64Encoded: String(s[s.index(after: comma)...]), options: .ignoreUnknownCharacters) {
                image = UIImage(data: data)
            }
            return WalletCard(id: id, bankName: c["bankName"]?.stringValue ?? "",
                              number: c["cardNumber"]?.idString ?? "", iban: c["iban"]?.stringValue ?? "",
                              holder: c["holderName"]?.stringValue ?? "", expiry: c["expiry"]?.stringValue ?? "",
                              accountType: c["accountType"]?.stringValue ?? "",
                              archived: c["archived"]?.isTruthy ?? false, image: image,
                              color: Color.web(c["bgColor"]?.stringValue))
        }
    }
}
