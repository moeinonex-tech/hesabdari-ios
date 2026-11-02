import Foundation

// web «وارد کردن از یادداشت»: pasted text, unlimited rows. Every Jalali date line starts a row; the lines up to the
// next date belong to it, in ANY order: the line that is only a number is the amount, the rest is the description
// (web needed date → amount → description). A row that cannot be read for sure is never dropped silently: it is kept
// with its problem written on it, and text before the first date is reported as unassigned. Each row also gets a
// category / subcategory guess from the learning engine and, after the preview, a pay method chosen by the person.

public struct NotesEntry: Sendable, Equatable, Identifiable {
    public var id: Int
    public var date: JalaliDate
    public var toman: Int
    public var desc: String
    public var category: String
    public var subcategory: String
    public var guessed: Bool          // the category came from the learning engine
    public var payMethod: String?     // chosen after the preview (nil = none)
    /// why this row could not be read for sure (shown on the row; empty = fine)
    public var problems: [String] = []
    /// the original lines of this row, to show next to a problem
    public var raw: String = ""
    public init(id: Int, date: JalaliDate, toman: Int, desc: String, category: String = "", subcategory: String = "", guessed: Bool = false) {
        self.id = id; self.date = date; self.toman = toman; self.desc = desc
        self.category = category; self.subcategory = subcategory; self.guessed = guessed
    }
    /// still missing something that must be filled before saving
    public var blocking: Bool {
        toman <= 0 || desc.trimmingCharacters(in: .whitespaces).isEmpty
            || category.trimmingCharacters(in: .whitespaces).isEmpty || subcategory.trimmingCharacters(in: .whitespaces).isEmpty
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

    /// a line that looks like a date but is not a valid one (e.g. 1405/13/1)
    static func looksLikeDate(_ l: String) -> Bool {
        let s = latin(l).trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ".", with: "/").replacingOccurrences(of: "-", with: "/")
        let parts = s.split(separator: "/", omittingEmptySubsequences: false)
        // shaped like y/m/d (2–4, 1–2, 1–2 digits) — an amount like 8.520.000 has 3-digit groups and is not a date
        guard parts.count == 3, parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0.isASCII && $0.isNumber } }) else { return false }
        return (2...4).contains(parts[0].count) && (1...2).contains(parts[1].count) && (1...2).contains(parts[2].count)
    }

    /// web niIsAmountLine / niParseAmountLine (an amount in rials is turned into toman)
    static func parseAmount(_ l: String) -> Int? {
        var s = latin(l).trimmingCharacters(in: .whitespaces)
        let rial = s.contains("ریال") || s.contains("ريال")
        for w in ["تومان", "ریال", "ريال"] { s = s.replacingOccurrences(of: w, with: "") }
        s = s.trimmingCharacters(in: .whitespaces)
        let digits = s.filter { !".,،٬".contains($0) && !$0.isWhitespace }
        guard !digits.isEmpty, digits.allSatisfy({ $0.isASCII && $0.isNumber }), let n = Int(digits) else { return nil }
        return rial ? n / 10 : n
    }

    static func legacyAmount(_ l: String) -> Int? {
        var s = latin(l).trimmingCharacters(in: .whitespaces)
        for w in ["تومان", "ریال", "ريال"] { s = s.replacingOccurrences(of: w, with: "") }
        s = s.trimmingCharacters(in: .whitespaces)
        let digits = s.filter { !".,،".contains($0) && !$0.isWhitespace }
        guard !digits.isEmpty, digits.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        return Int(digits) ?? 0
    }

    public struct Result: Sendable {
        public var entries: [NotesEntry]
        /// text before the first date: it belongs to no row
        public var orphans: [String]
        public var problemCount: Int { entries.filter { !$0.problems.isEmpty }.count }
    }

    /// order-insensitive reading (see the top of the file)
    public static func parse(_ text: String) -> Result {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        var entries: [NotesEntry] = []
        var orphans: [String] = []
        var i = 0
        while i < lines.count, parseDate(lines[i]) == nil { orphans.append(lines[i]); i += 1 }
        while i < lines.count {
            guard let d = parseDate(lines[i]) else { i += 1; continue }
            var block: [String] = []
            i += 1
            while i < lines.count, parseDate(lines[i]) == nil { block.append(lines[i]); i += 1 }
            var amounts: [Int] = [], text: [String] = [], problems: [String] = []
            for l in block {
                if looksLikeDate(l) {
                    problems.append("تاریخ نامعتبر: «" + l + "»")
                } else if let n = parseAmount(l) {
                    amounts.append(n)
                } else {
                    text.append(l)
                }
            }
            var e = NotesEntry(id: entries.count, date: d, toman: 0, desc: text.joined(separator: " ").trimmingCharacters(in: .whitespaces))
            switch amounts.count {
            case 0: problems.append("مبلغ پیدا نشد")
            case 1:
                e.toman = amounts[0]
                if amounts[0] <= 0 { problems.append("مبلغ صفر است") }
            default:
                problems.append("چند عدد پیدا شد (" + amounts.map { Money.persianDigits(Money.format($0)) }.joined(separator: "، ") + ") — مبلغ درست را وارد کنید")
            }
            if e.desc.isEmpty { problems.append("شرح پیدا نشد") }
            e.problems = problems
            e.raw = ([BackupExporter.formatJalali(d)] + block).joined(separator: "\n")
            entries.append(e)
        }
        return Result(entries: entries, orphans: orphans)
    }

    /// the old web reading (date → amount → description, strict order) — kept for reference / tests
    public static func parseStrict(_ text: String) -> (entries: [NotesEntry], skipped: Int) {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        var out: [NotesEntry] = [], skipped = 0, i = 0
        while i < lines.count {
            if let d = parseDate(lines[i]) {
                i += 1
                if i < lines.count, let n = legacyAmount(lines[i]) {
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
                           cardId: String? = nil, ids: IdSource = .system) -> [String: JSONValue] {
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
            if let m = e.payMethod, !m.isEmpty {
                row["payMethod"] = .string(m)
                // card methods get the card this ledger uses most
                if ["hamrahbank", "pos", "card"].contains(m), let card = cardId { row["cardId"] = .string(card) }
            }
            list.append(.object(row))
        }
        st[key] = .array(list)
        return st
    }
}
