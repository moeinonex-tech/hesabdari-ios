import Foundation

// Port of the web runSearch (scope "all"): same domains, fields, order and 60-result limit.
// Matching: Persian/Arabic digits → Latin, lowercase, "contains".

public struct SearchResult: Equatable, Identifiable, Sendable {
    public enum Kind: String, Sendable { case expense, personal, check, person, income, appointment }
    public var id: String { kind.rawValue + "-" + recordId }
    public var kind: Kind
    public var recordId: String
    public var accountId: String?
    public var tag: String
    public var title: String
    public var sub: String
    public var amount: Int
    /// scoped search: which group the result belongs to (one per ledger, so ledgers never mix) and its date
    public var group: String = ""
    public var groupOrder: Int = 0
    public var date: JalaliDate? = nil
    public var isTankhah = false
}

/// where to search (home search: «کلی»، «دفترها» (all or one ledger)، «شخصی»، «درآمد»، «یادآوری‌ها»)
public enum SearchScope: Equatable, Sendable {
    case all
    case ledgers(accountId: String?)      // nil = every ledger (each still its own group)
    case personal
    case income
    case reminders

    var ledger: Bool { if case .ledgers = self { return true }; return self == .all }
    var personal: Bool { self == .all || self == .personal }
    var income: Bool { self == .all || self == .income }
    var reminders: Bool { self == .all || self == .reminders }
    var accountId: String? { if case .ledgers(let id) = self { return id }; return nil }
}

public enum SearchEngine {

    /// web toEnglishDigits
    public static func latinDigits(_ s: String) -> String {
        String(s.unicodeScalars.map { u -> Character in
            switch u.value {
            case 0x6F0...0x6F9: return Character(Unicode.Scalar(u.value - 0x6F0 + 0x30)!)
            case 0x660...0x669: return Character(Unicode.Scalar(u.value - 0x660 + 0x30)!)
            default: return Character(u)
            }
        })
    }

    public static func search(_ st: [String: JSONValue], query: String, limit: Int = 60) -> [SearchResult] {
        let q = latinDigits(query.trimmingCharacters(in: .whitespacesAndNewlines)).lowercased()
        func m(_ v: JSONValue?) -> Bool {
            if q.isEmpty { return true }
            let s = v?.stringValue ?? v?.idString ?? ""
            return latinDigits(s).lowercased().contains(q)
        }
        func date(_ v: JSONValue?) -> String {
            let d = ImportAnalyzer.date(v)
            return Money.persianDigits("\(d.jy)/\(d.jm)/\(d.jd)")
        }
        var out: [SearchResult] = []
        let accounts = st["accounts"]?.arrayValue ?? []
        for e in st["expenses"]?.arrayValue ?? [] {
            let acc = accounts.first { $0["id"]?.idString == e["accountId"]?.idString }
            if m(e["desc"]) || m(e["category"]) || (acc != nil && m(acc?["name"])) {
                let title = nonEmpty(e["desc"]) ?? nonEmpty(e["category"]) ?? "(بدون توضیح)"
                let accName = acc?["name"]?.stringValue
                out.append(SearchResult(kind: .expense, recordId: e["id"]?.idString ?? "", accountId: e["accountId"]?.idString,
                                        tag: "دفتر حساب", title: title, sub: (accName.map { $0 + " · " } ?? "") + date(e["date"]),
                                        amount: ImportAnalyzer.toman(e)))
            }
        }
        for e in st["personalExpenses"]?.arrayValue ?? [] where m(e["desc"]) || m(e["category"]) {
            out.append(SearchResult(kind: .personal, recordId: e["id"]?.idString ?? "", accountId: nil, tag: "کیف",
                                    title: nonEmpty(e["desc"]) ?? nonEmpty(e["category"]) ?? "(بدون توضیح)", sub: date(e["date"]),
                                    amount: ImportAnalyzer.toman(e)))
        }
        for c in st["reminderChecks"]?.arrayValue ?? [] where m(c["party"]) || m(c["checkNumber"]) || m(c["bankName"]) || m(c["description"]) {
            let num = c["checkNumber"]?.idString ?? ""
            out.append(SearchResult(kind: .check, recordId: c["id"]?.idString ?? "", accountId: nil, tag: "چک",
                                    title: (nonEmpty(c["party"]) ?? "چک بدون طرف") + (num.isEmpty ? "" : " · " + Money.persianDigits(num)),
                                    sub: date(c["dueDate"]), amount: c["amount"]?.intValue ?? 0))
        }
        for p in st["reminderPersons"]?.arrayValue ?? [] {
            let insts = p["installments"]?.arrayValue ?? []
            guard m(p["name"]) || insts.contains(where: { m($0["description"]) || m($0["category"]) }) else { continue }
            let remaining = insts.filter { !($0["paid"]?.isTruthy ?? false) }.reduce(0) { $0 + ($1["amount"]?.intValue ?? 0) }
            out.append(SearchResult(kind: .person, recordId: p["id"]?.idString ?? "", accountId: nil,
                                    tag: p["type"]?.stringValue == "creditor" ? "طلبکار" : "بدهکار", title: p["name"]?.stringValue ?? "",
                                    sub: Money.persianDigits(insts.count) + " قسط", amount: remaining))
        }
        for i in st["incomes"]?.arrayValue ?? [] where m(i["desc"]) || m(i["category"]) || m(i["subcategory"]) || m(i["accountName"]) {
            let accName = nonEmpty(i["accountName"])
            out.append(SearchResult(kind: .income, recordId: i["id"]?.idString ?? "", accountId: nil, tag: "درآمد",
                                    title: nonEmpty(i["desc"]) ?? nonEmpty(i["category"]) ?? "(بدون توضیح)",
                                    sub: (accName.map { $0 + " · " } ?? "") + date(i["date"]), amount: ImportAnalyzer.toman(i)))
        }
        return Array(out.prefix(limit))
    }

    static func nonEmpty(_ v: JSONValue?) -> String? {
        guard let s = v?.stringValue, !s.isEmpty else { return nil }
        return s
    }

    // MARK: - scoped search (home search screen)

    /// web normalizeFa-like: digits → Latin, ی/ي/ى, ک/ك, half-space and punctuation as space, lowercase
    public static func norm(_ s: String) -> String {
        var t = latinDigits(s).lowercased()
        t = t.replacingOccurrences(of: "ي", with: "ی").replacingOccurrences(of: "ى", with: "ی").replacingOccurrences(of: "ك", with: "ک")
            .replacingOccurrences(of: "ة", with: "ه").replacingOccurrences(of: "\u{200C}", with: " ")
        for p in ["،", "؛", ".", "-", "_", "/", "«", "»", "(", ")", ":"] { t = t.replacingOccurrences(of: p, with: " ") }
        return t.split(separator: " ").joined(separator: " ")
    }

    /// a number typed in the query (thousand separators allowed) — matched against amounts too
    static func digits(_ s: String) -> String? {
        let d = latinDigits(s).filter { $0.isNumber || $0 == "," || $0 == "٬" }
        let only = d.filter(\.isNumber)
        return only.count >= 3 && only.count == latinDigits(s).filter({ !$0.isWhitespace }).filter({ $0 != "," && $0 != "٬" }).count ? String(only) : nil
    }

    /// Every word of the query must appear somewhere in the record (description, categories, the items of an invoice,
    /// the party, the ledger, check number, bank…); a number also matches the amount. Results are grouped (each ledger
    /// is its own group, so ledgers never mix), newest first inside a group.
    public static func find(_ st: [String: JSONValue], query: String, scope: SearchScope, limit: Int = 300) -> [SearchResult] {
        let words = norm(query).split(separator: " ").map(String.init)
        guard !words.isEmpty else { return [] }
        let number = digits(query)
        func s(_ v: JSONValue?) -> String { v?.stringValue ?? v?.idString ?? "" }
        func hit(_ fields: [String], amount: Int?) -> Bool {
            if let n = number, let a = amount, String(a).contains(n) { return true }
            let hay = norm(fields.joined(separator: " "))
            return words.allSatisfy { hay.contains($0) }
        }
        func items(_ e: JSONValue) -> [String] {
            (e["items"]?.arrayValue ?? []).flatMap { [s($0["desc"]), s($0["category"]), s($0["subcategory"])] }
        }
        func cat(_ e: JSONValue) -> String {
            [s(e["category"]), s(e["subcategory"])].filter { !$0.isEmpty }.joined(separator: " / ")
        }
        func dateText(_ d: JalaliDate) -> String { Money.persianDigits("\(d.jy)/\(d.jm)/\(d.jd)") }
        var out: [SearchResult] = []

        if scope.ledger {
            let accounts = (st["accounts"]?.arrayValue ?? []).filter { scope.accountId == nil || $0["id"]?.idString == scope.accountId }
            let tkParties = st["tankhahParties"]?.arrayValue ?? []
            for (ai, acc) in accounts.enumerated() {
                let aid = acc["id"]?.idString
                let name = s(acc["name"])
                for e in st["expenses"]?.arrayValue ?? [] where e["accountId"]?.idString == aid {
                    let tankhah = e["type"]?.stringValue == "tankhah"
                    let party = tkParties.first { $0["id"]?.idString == e["partyId"]?.idString && e["partyId"]?.idString != nil }.map { s($0["name"]) } ?? ""
                    let amount = ImportAnalyzer.toman(e)
                    guard hit([s(e["desc"]), s(e["category"]), s(e["subcategory"]), party, tankhah ? "تنخواه" : ""] + items(e), amount: amount) else { continue }
                    let d = ImportAnalyzer.date(e["date"])
                    let title = nonEmpty(e["desc"]) ?? (tankhah && !party.isEmpty ? "تنخواه از " + party : nil) ?? nonEmpty(e["category"]) ?? "(بدون توضیح)"
                    let sub = [dateText(d), tankhah ? party : cat(e)].filter { !$0.isEmpty }.joined(separator: " · ")
                    out.append(SearchResult(kind: .expense, recordId: s(e["id"]), accountId: aid, tag: tankhah ? "تنخواه" : "هزینه",
                                            title: title, sub: sub, amount: amount, group: "دفتر «" + name + "»", groupOrder: 10 + ai,
                                            date: d, isTankhah: tankhah))
                }
            }
        }
        if scope.personal {
            for e in st["personalExpenses"]?.arrayValue ?? [] {
                let amount = ImportAnalyzer.toman(e)
                guard hit([s(e["desc"]), s(e["category"]), s(e["subcategory"])] + items(e), amount: amount) else { continue }
                let d = ImportAnalyzer.date(e["date"])
                out.append(SearchResult(kind: .personal, recordId: s(e["id"]), accountId: nil, tag: "شخصی",
                                        title: nonEmpty(e["desc"]) ?? nonEmpty(e["category"]) ?? "(بدون توضیح)",
                                        sub: [dateText(d), cat(e)].filter { !$0.isEmpty }.joined(separator: " · "), amount: amount,
                                        group: "هزینه‌های شخصی", groupOrder: 1000, date: d))
            }
        }
        if scope.income {
            for i in st["incomes"]?.arrayValue ?? [] {
                let amount = ImportAnalyzer.toman(i)
                guard hit([s(i["desc"]), s(i["category"]), s(i["subcategory"]), s(i["accountName"])], amount: amount) else { continue }
                let d = ImportAnalyzer.date(i["date"])
                out.append(SearchResult(kind: .income, recordId: s(i["id"]), accountId: nil, tag: "درآمد",
                                        title: nonEmpty(i["desc"]) ?? nonEmpty(i["category"]) ?? "(بدون توضیح)",
                                        sub: [dateText(d), cat(i)].filter { !$0.isEmpty }.joined(separator: " · "), amount: amount,
                                        group: "درآمدها", groupOrder: 1001, date: d))
            }
        }
        if scope.reminders {
            let status = ["pending": "در انتظار وصول", "cashed": "وصول شد", "bounced": "برگشت خورد", "cancelled": "باطل شد"]
            for c in st["reminderChecks"]?.arrayValue ?? [] {
                let amount = c["amount"]?.intValue ?? 0
                guard hit([s(c["party"]), s(c["checkNumber"]), s(c["sayadId"]), s(c["bankName"]), s(c["description"]),
                           s(c["category"]), s(c["subcategory"]), "چک"], amount: amount) else { continue }
                let d = ImportAnalyzer.date(c["dueDate"])
                let num = s(c["checkNumber"])
                out.append(SearchResult(kind: .check, recordId: s(c["id"]), accountId: nil, tag: "چک",
                                        title: (nonEmpty(c["party"]) ?? "چک بدون طرف") + (num.isEmpty ? "" : " · " + Money.persianDigits(num)),
                                        sub: ["سررسید " + dateText(d), s(c["bankName"]), status[s(c["status"])] ?? ""].filter { !$0.isEmpty }.joined(separator: " · "),
                                        amount: amount, group: "چک‌ها", groupOrder: 1002, date: d))
            }
            for p in st["reminderPersons"]?.arrayValue ?? [] {
                let insts = p["installments"]?.arrayValue ?? []
                let remaining = insts.filter { !($0["paid"]?.isTruthy ?? false) }.reduce(0) { $0 + ($1["amount"]?.intValue ?? 0) }
                guard hit([s(p["name"])] + insts.flatMap { [s($0["description"]), s($0["category"])] }, amount: remaining) else { continue }
                let creditor = p["type"]?.stringValue == "creditor"
                out.append(SearchResult(kind: .person, recordId: s(p["id"]), accountId: nil, tag: creditor ? "طلبکار" : "بدهکار",
                                        title: s(p["name"]), sub: Money.persianDigits(insts.count) + " قسط · مانده", amount: remaining,
                                        group: "بدهکاران و طلبکاران", groupOrder: 1003))
            }
            for a in st["appointments"]?.arrayValue ?? [] {
                guard hit([s(a["title"]), s(a["note"]), s(a["location"]?["label"]), "قرار"], amount: nil) else { continue }
                let d = ImportAnalyzer.date(a["date"])
                out.append(SearchResult(kind: .appointment, recordId: s(a["id"]), accountId: nil, tag: "قرار", title: s(a["title"]),
                                        sub: [dateText(d), s(a["time"])].filter { !$0.isEmpty }.joined(separator: " · "), amount: 0,
                                        group: "قرارها", groupOrder: 1004, date: d))
            }
        }
        return Array(out.enumerated().sorted { x, y in
            let a = x.element, b = y.element
            if a.groupOrder != b.groupOrder { return a.groupOrder < b.groupOrder }
            if let da = a.date, let db = b.date, da != db { return da > db }
            return x.offset > y.offset
        }.map(\.element).prefix(limit))
    }
}
