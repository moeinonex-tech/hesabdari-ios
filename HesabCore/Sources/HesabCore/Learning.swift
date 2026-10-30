import Foundation

// Smart category / subcategory suggestion — a port of the web app's learning engine:
// STOPWORDS, isNumericToken, descSignature, descWords, normalizeFa, wordOverlapScore, learnCategory,
// learnSubcategory / learnPersonalSubcategory / learnIncomeSubcategory, suggestCategory, ledgerBaseCategoryScores
// (LEDGER_BASE_KEYWORDS / LEDGER_BASE_PHRASES), learnedCategoryScores, rankScoreMap, suggestCategoryCandidates,
// suggest*SubcategoryCandidates. Everything is stored in the same state fields as the web app.

public enum LearnContext: Sendable {
    case ledger, personal, income

    var descMap: String { self == .ledger ? "ledgerDescMap" : (self == .income ? "incomeDescMap" : "personalDescMap") }
    var keywordMap: String { self == .ledger ? "ledgerKeywordMap" : (self == .income ? "incomeKeywordMap" : "personalKeywordMap") }
    var subDescMap: String { self == .ledger ? "ledgerSubDescMap" : (self == .income ? "incomeSubDescMap" : "personalSubDescMap") }
    var subKeywordMap: String { self == .ledger ? "ledgerSubKeywordMap" : (self == .income ? "incomeSubKeywordMap" : "personalSubKeywordMap") }
}

public enum Learning {
    static let stopwords: Set<String> = ["خرید", "خریدن", "خریداری", "فروش", "بابت", "برای", "از", "به", "با", "در", "این", "آن", "یک", "دو", "سه",
        "تا", "که", "هم", "نیز", "یا", "و", "های", "ها", "است", "شد", "شدن", "کرد", "کردن", "رفت", "آمد", "بود", "باشد", "پرداخت", "پرداختن",
        "دریافت", "مبلغ", "پول", "هزینه", "امروز", "دیروز", "ماه", "هفته", "بیعانه", "تسویه", "نهایی", "اول", "دوم", "واریز", "انتقال", "شریک",
        "تامین", "تأمین", "تعداد", "عدد", "عد", "شماره", "ردیف", "تراکنش", "آقای", "آقایان", "خانم"]

    static let baseKeywords: [(String, [String])] = [
        ("هزینه های بیمه", ["بیمه", "تمدید", "ثابت", "قدم", "نوین"]),
        ("هزینه های تحریر و فوتوکپی", ["آرماتوربند", "ارائه", "استفاده", "اصلی", "بررسی", "جلوگیری", "جیبی", "رنگی", "روی", "زدگی", "زنگ", "سازه", "سوزن", "عکس", "فعلی", "فوتوکپی", "قفل", "مدارک", "مربوطه", "منگنه", "ناظرین", "نقشه", "پرینت", "پهن", "پوشه", "چسب", "چهارگانه", "کلاسور"]),
        ("تاسیسات و انشعابات برق", ["آنالوگ", "انشعاب", "برق", "راهی", "سرویس", "صنعتی", "فیوز", "قاب", "کابل"]),
        ("تاسیسات و انشعابات گاز", ["آب", "انشعابات", "حضور", "شیرینی", "علمک", "پلمپ", "گاز"]),
        ("تاسیسات و انشعابات آب", ["آب", "آژانس", "انشعاب", "تخریب", "حفاری", "سازمان", "شیرینی", "علمک", "قطع", "منتهی", "کارشناس", "کرایه", "گاز"]),
        ("پرداخت قبوض", ["آب", "آخر", "ایرانسل", "بدهی", "برق", "سیم", "قبض", "قرائت", "کارت"]),
        ("حمل و نقل", ["آژانس", "بارگیری", "تحویل", "جاده", "حمل", "خانه", "خشکبیجار", "منزل", "پدری", "پیک", "کرایه"]),
        ("هزینه های کارگاهی", ["اتصالات", "ارسال", "استفاده", "اسپری", "الوار", "انباری", "انتظار", "ایرانی", "باقی", "بشکه", "بیل", "تخریبچی", "توالت", "جلوگیری", "جهت", "جوشکار", "حفاری", "خانه", "حلب", "دار", "درب", "درها", "دستشویی", "زبانک", "زنگار", "سانتی", "سایز", "سر", "سنگ", "سیم", "غذا", "غذای", "فرقون", "قابل", "قفل", "لول", "لولا", "لوله", "لیتری", "مانده", "متری", "مته", "مشکی", "میخ", "نجاری", "نیم", "واشر", "پا", "پروفیلهای", "پولیکا", "پیچ", "چاه", "چای", "چرخ", "چوب", "کار", "کارگران"]),
        ("ابزار و تجهیزات", ["اسپری", "جارو", "رنگ", "قرمز", "میخ", "نجاری"]),
        ("دستمزد", ["اضافی", "انتظار", "بتن", "تمیز", "جلوی", "جوشکار", "جوشکاری", "حساب", "حلبهای", "درخت", "دستشویی", "دستمزد", "روز", "ریزی", "ریشه", "زبانه", "زن", "زنی", "سازی", "سیمانکاری", "طرف", "فونداسیون", "قطع", "لوله", "نجار", "نصب", "نیم", "پایه", "پروفیل", "کارگر", "کارگری", "کشی", "گذاری", "گلهای", "گِل"]),
        ("مصالح ساختمانی", ["آریا", "آلات", "آهن", "بلوک", "تحویل", "تن", "جوبن", "خزر", "سانتی", "سفارش", "سقف", "سوم", "سیمان", "شایان", "شرکت", "شن", "فوم", "فونداسیون", "میلگردها", "میلگردهای", "چهارم", "کامل", "یونولیت"]),
        ("کمیسیون", ["آلات", "آهن", "سقف", "شایان", "میلگردها", "چهارم", "کامل", "کمیسیون"]),
        ("خوراک", ["تهیه", "تیم", "حفاری", "نهار", "چاه"])
    ]
    static let basePhrases: [(String, String)] = [
        ("قبض برق", "پرداخت قبوض"), ("قبض آب", "پرداخت قبوض"), ("تغییر نام انشعاب", "تاسیسات و انشعابات برق"),
        ("کابل سرویس کنتور", "تاسیسات و انشعابات برق"), ("سه راهی صنعتی", "تاسیسات و انشعابات برق"),
        ("قطع انشعاب", "تاسیسات و انشعابات آب"), ("عکس کنتور گاز", "هزینه های تحریر و فوتوکپی"),
        ("فوتوکپی نقشه سازه", "هزینه های تحریر و فوتوکپی"), ("منگنه جیبی", "هزینه های تحریر و فوتوکپی"),
        ("پروفیل حصار کارگاهی", "هزینه های کارگاهی"), ("حلب دیوار", "هزینه های کارگاهی"),
        ("کرایه حمل", "حمل و نقل"), ("پیک تحویل", "حمل و نقل"), ("دستمزد نجار", "دستمزد")
    ]

    // MARK: text helpers (JS semantics)

    /// JS String.length
    static func len(_ s: String) -> Int { s.utf16.count }

    /// JS `str.trim().split(/\s+/)`
    static func split(_ s: String) -> [String] {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return [""] }
        return t.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }

    /// web isNumericToken
    static func isNumericToken(_ tok: String) -> Bool {
        let stripped = tok.unicodeScalars.filter { u in
            !(("۰"..."۹").contains(u) || ("0"..."9").contains(u) || "./\"'()+-٪%".unicodeScalars.contains(u))
        }
        return String(String.UnicodeScalarView(stripped)).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public static func descWords(_ desc: String) -> [String] {
        split(desc).filter { len($0) >= 2 && !stopwords.contains($0) && !isNumericToken($0) }
    }

    public static func descSignature(_ desc: String) -> String {
        let w = descWords(desc)
        return w.isEmpty ? "" : w.sorted(by: jsLess).joined(separator: " ")
    }

    /// JS default sort compares UTF-16 code units
    static func jsLess(_ a: String, _ b: String) -> Bool { Array(a.utf16).lexicographicallyPrecedes(Array(b.utf16)) }

    public static func normalizeFa(_ s: String) -> String {
        s.replacingOccurrences(of: "ي", with: "ی").replacingOccurrences(of: "ك", with: "ک")
            .replacingOccurrences(of: "\u{200C}", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func overlap(_ a: [String], _ b: [String]) -> Double {
        if a.isEmpty || b.isEmpty { return 0 }
        let setB = Set(b)
        let inter = a.filter { setB.contains($0) }.count
        let union = a.count + b.count - inter
        return union > 0 ? Double(inter) / Double(union) : 0
    }

    // MARK: learning (on save)

    /// web learnCategory
    public static func learnCategory(_ st: inout [String: JSONValue], _ ctx: LearnContext, desc: String, category: String) {
        guard !category.isEmpty else { return }
        let sig = descSignature(desc)
        guard !sig.isEmpty else { return }
        var map = st[ctx.descMap]?.objectValue ?? [:]
        map[sig] = .string(category)
        st[ctx.descMap] = .object(map)
        var kw = st[ctx.keywordMap]?.objectValue ?? [:]
        var existing = (kw[category]?.arrayValue ?? []).compactMap(\.stringValue)
        for w in descWords(desc) where !existing.contains(w) { existing.append(w) }
        kw[category] = .array(existing.map { .string($0) })
        st[ctx.keywordMap] = .object(kw)
    }

    /// web learnSubcategory / learnPersonalSubcategory / learnIncomeSubcategory
    public static func learnSubcategory(_ st: inout [String: JSONValue], _ ctx: LearnContext, category: String, desc: String, sub: String) {
        guard !category.isEmpty, !sub.isEmpty else { return }
        let sig = descSignature(desc)
        guard !sig.isEmpty else { return }
        var map = st[ctx.subDescMap]?.objectValue ?? [:]
        map[category + "|||" + sig] = .string(sub)
        st[ctx.subDescMap] = .object(map)
        var kw = st[ctx.subKeywordMap]?.objectValue ?? [:]
        var forCat = kw[category]?.objectValue ?? [:]
        var existing = (forCat[sub]?.arrayValue ?? []).compactMap(\.stringValue)
        for w in descWords(desc) where !existing.contains(w) { existing.append(w) }
        forCat[sub] = .array(existing.map { .string($0) })
        kw[category] = .object(forCat)
        st[ctx.subKeywordMap] = .object(kw)
    }

    // MARK: suggestions

    /// web suggestCategory (exact signature, then fuzzy ≥ 0.5)
    public static func exactCategory(_ st: [String: JSONValue], _ ctx: LearnContext, _ desc: String) -> String? {
        let words = descWords(desc)
        guard !words.isEmpty else { return nil }
        let map = st[ctx.descMap]?.objectValue ?? [:]
        let sig = words.sorted(by: jsLess).joined(separator: " ")
        if let v = map[sig]?.stringValue { return v }
        var best = 0.0, cat: String?
        for key in map.keys.sorted(by: jsLess) {
            let s = overlap(words, key.components(separatedBy: " "))
            if s > best { best = s; cat = map[key]?.stringValue }
        }
        return best >= 0.5 ? cat : nil
    }

    static func baseScores(_ desc: String) -> [String: Double] {
        let norm = normalizeFa(desc)
        let words = descWords(norm)
        var scores: [String: Double] = [:]
        for (phrase, cat) in basePhrases where norm.contains(normalizeFa(phrase)) { scores[cat, default: 0] += 3 }
        for (cat, kws) in baseKeywords { for kw in kws where words.contains(kw) { scores[cat, default: 0] += 1 } }
        return scores
    }

    static func learnedScores(_ st: [String: JSONValue], _ ctx: LearnContext, _ desc: String) -> [String: Double] {
        let norm = normalizeFa(desc)
        var scores: [String: Double] = [:]
        for (cat, list) in st[ctx.keywordMap]?.objectValue ?? [:] {
            for kw in (list.arrayValue ?? []).compactMap(\.stringValue) {
                let k = normalizeFa(kw)
                if !k.isEmpty && !isNumericToken(k) && norm.contains(k) { scores[cat, default: 0] += 1.2 }
            }
        }
        return scores
    }

    /// web rankScoreMap: drop zero, keep ≥ 60% of the best, at most `max`
    static func rank(_ scores: [String: Double], max: Int = 4) -> [String] {
        let arr = scores.sorted { a, b in a.value != b.value ? a.value > b.value : jsLess(a.key, b.key) }
        guard let top = arr.first?.value, top > 0 else { return [] }
        return Array(arr.filter { $0.value >= top * 0.6 }.prefix(max).map(\.key))
    }

    /// web suggestCategoryCandidates
    public static func categoryCandidates(_ st: [String: JSONValue], _ ctx: LearnContext, desc: String) -> [String] {
        guard !descWords(desc).isEmpty else { return [] }
        if let exact = exactCategory(st, ctx, desc) { return [exact] }
        var merged = ctx == .ledger ? baseScores(desc) : [:]
        for (k, v) in learnedScores(st, ctx, desc) { merged[k, default: 0] += v }
        return rank(merged)
    }

    /// web suggestSubcategory (exact / fuzzy / keyword without a tie)
    static func exactSub(_ st: [String: JSONValue], _ ctx: LearnContext, category: String, desc: String) -> String? {
        guard !category.isEmpty else { return nil }
        let words = descWords(desc)
        guard !words.isEmpty else { return nil }
        let map = st[ctx.subDescMap]?.objectValue ?? [:]
        let prefix = category + "|||"
        if let v = map[prefix + words.sorted(by: jsLess).joined(separator: " ")]?.stringValue { return v }
        var best = 0.0, sub: String?
        for key in map.keys.sorted(by: jsLess) where key.hasPrefix(prefix) {
            let s = overlap(words, String(key.dropFirst(prefix.count)).components(separatedBy: " "))
            if s > best { best = s; sub = map[key]?.stringValue }
        }
        if best >= 0.5 { return sub }
        let norm = normalizeFa(desc)
        var kwBest = 0, kwSecond = 0
        var kwSub: String?
        let learned = st[ctx.subKeywordMap]?[category]?.objectValue ?? [:]
        for s in learned.keys.sorted(by: jsLess) {
            let score = (learned[s]?.arrayValue ?? []).compactMap(\.stringValue).filter { norm.contains(normalizeFa($0)) }.count
            if score > kwBest { kwSecond = kwBest; kwBest = score; kwSub = s } else if score > kwSecond { kwSecond = score }
        }
        return kwBest > 0 && kwBest > kwSecond ? kwSub : nil
    }

    /// web suggestSubcategoryCandidates / suggestPersonal… / suggestIncome…
    public static func subcategoryCandidates(_ st: [String: JSONValue], _ ctx: LearnContext, category: String, desc: String) -> [String] {
        guard !category.isEmpty, !descWords(desc).isEmpty else { return [] }
        if let e = exactSub(st, ctx, category: category, desc: desc) { return [e] }
        let norm = normalizeFa(desc)
        var scores: [String: Double] = [:]
        for (s, list) in st[ctx.subKeywordMap]?[category]?.objectValue ?? [:] {
            for kw in (list.arrayValue ?? []).compactMap(\.stringValue) {
                let k = normalizeFa(kw)
                if ctx == .income {
                    if norm.contains(k) { scores[s, default: 0] += 1 }
                } else if !k.isEmpty && !isNumericToken(k) && norm.contains(k) {
                    scores[s, default: 0] += 1
                }
            }
        }
        return rank(scores)
    }
}
