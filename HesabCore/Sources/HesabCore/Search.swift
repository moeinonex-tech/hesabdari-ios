import Foundation

// Port of the web runSearch (scope "all"): same domains, fields, order and 60-result limit.
// Matching: Persian/Arabic digits → Latin, lowercase, "contains".

public struct SearchResult: Equatable, Identifiable, Sendable {
    public enum Kind: String, Sendable { case expense, personal, check, person, income }
    public var id: String { kind.rawValue + "-" + recordId }
    public var kind: Kind
    public var recordId: String
    public var accountId: String?
    public var tag: String
    public var title: String
    public var sub: String
    public var amount: Int
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
}
