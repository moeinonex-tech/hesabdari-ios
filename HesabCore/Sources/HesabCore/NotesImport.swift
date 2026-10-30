import Foundation

// web «وارد کردن از یادداشت» (parseNotesImportText): pasted text, for each row: Jalali date line → amount line → description
// lines until the next date line. Unlimited rows. Here each row also gets a category / subcategory guess from the
// learning engine (the person can correct it before saving).

public struct NotesEntry: Sendable, Equatable, Identifiable {
    public var id: Int
    public var date: JalaliDate
    public var toman: Int
    public var desc: String
    public var category: String
    public var subcategory: String
    public var guessed: Bool          // the category came from the learning engine
    public init(id: Int, date: JalaliDate, toman: Int, desc: String, category: String = "", subcategory: String = "", guessed: Bool = false) {
        self.id = id; self.date = date; self.toman = toman; self.desc = desc
        self.category = category; self.subcategory = subcategory; self.guessed = guessed
    }
}

public enum NotesImport {
    static func latin(_ s: String) -> String { SearchEngine.latinDigits(s) }

    /// web niIsDateLine / niParseDateLine
    static func parseDate(_ l: String) -> JalaliDate? {
        let s = latin(l).trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ".", with: "/").replacingOccurrences(of: "-", with: "/")
        let parts = s.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 3, parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isASCII) && $0.allSatisfy(\.isNumber) }),
              (2...4).contains(parts[0].count), (1...2).contains(parts[1].count), (1...2).contains(parts[2].count),
              var jy = Int(parts[0]), let jm = Int(parts[1]), let jd = Int(parts[2]),
              (1...12).contains(jm), (1...31).contains(jd) else { return nil }
        if jy < 100 { jy += 1400 }
        return JalaliDate(jy: jy, jm: jm, jd: jd)
    }

    /// web niIsAmountLine / niParseAmountLine
    static func parseAmount(_ l: String) -> Int? {
        var s = latin(l).trimmingCharacters(in: .whitespaces)
        for w in ["تومان", "ریال", "ريال"] { s = s.replacingOccurrences(of: w, with: "") }
        s = s.trimmingCharacters(in: .whitespaces)
        let digits = s.filter { !".,،".contains($0) && !$0.isWhitespace }
        guard !digits.isEmpty, digits.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        return Int(digits) ?? 0
    }

    public static func parse(_ text: String) -> (entries: [NotesEntry], skipped: Int) {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        var out: [NotesEntry] = [], skipped = 0, i = 0
        while i < lines.count {
            if let d = parseDate(lines[i]) {
                i += 1
                if i < lines.count, let n = parseAmount(lines[i]) {
                    i += 1
                    var desc: [String] = []
                    while i < lines.count && parseDate(lines[i]) == nil { desc.append(lines[i]); i += 1 }
                    out.append(NotesEntry(id: out.count, date: d, toman: n, desc: desc.joined(separator: " ").trimmingCharacters(in: .whitespaces)))
                } else {
                    skipped += 1
                }
            } else {
                skipped += 1; i += 1
            }
        }
        return (out, skipped)
    }

    /// the best guess of the learning engine for every row
    public static func classify(_ st: [String: JSONValue], _ entries: [NotesEntry], ctx: LearnContext) -> [NotesEntry] {
        entries.map { e in
            var e = e
            if let c = Learning.categoryCandidates(st, ctx, desc: e.desc).first {
                e.category = c; e.guessed = true
                e.subcategory = Learning.subcategoryCandidates(st, ctx, category: c, desc: e.desc).first ?? ""
            }
            return e
        }
    }

    /// web confirm: plain rows (no pay method), ts = now + i; here with the category/subcategory, learned like a form entry
    public static func add(_ state: [String: JSONValue], _ entries: [NotesEntry], ledgerAccountId: String?,
                           ids: IdSource = .system) -> [String: JSONValue] {
        var st = state
        let key = ledgerAccountId == nil ? "personalExpenses" : "expenses"
        let ctx: LearnContext = ledgerAccountId == nil ? .personal : .ledger
        let catList = ledgerAccountId == nil ? "personalCategories" : "ledgerCategories"
        let subMap = ledgerAccountId == nil ? "personalSubcategories" : "ledgerSubcategories"
        var list = LedgerOps.array(st, key)
        let now = ids.nowMs()
        for (i, e) in entries.enumerated() {
            let c = e.category.trimmingCharacters(in: .whitespaces), s = e.subcategory.trimmingCharacters(in: .whitespaces)
            if !c.isEmpty {
                LedgerOps.addCategoryIfNew(&st, list: catList, c)
                Learning.learnCategory(&st, ctx, desc: e.desc, category: c)
                if !s.isEmpty {
                    LedgerOps.addSubcategoryIfNew(&st, map: subMap, category: c, s)
                    Learning.learnSubcategory(&st, ctx, category: c, desc: e.desc, sub: s)
                }
            }
            var row: [String: JSONValue] = ["id": .string(ids.make(ledgerAccountId == nil ? "p" : "e", now) + String(i)),
                                            "desc": .string(e.desc), "toman": .int(Int64(e.toman)), "date": LedgerOps.date(e.date),
                                            "ts": .int(Int64(now + i))]
            if let a = ledgerAccountId { row["accountId"] = .string(a); row["type"] = .string("expense") }
            if !c.isEmpty { row["category"] = .string(c) }
            if !s.isEmpty { row["subcategory"] = .string(s) }
            list.append(.object(row))
        }
        st[key] = .array(list)
        return st
    }
}
