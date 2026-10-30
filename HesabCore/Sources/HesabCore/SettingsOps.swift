import Foundation

// Wallet cards, budgets, motivational quotes, home widget layout — web: cwSaveCard (no CVV, D17), CW_BANKS,
// budget fields, customQuotes, homeQuoteOfNow, homeWidgets / homeWidgetOrder.

public struct Bank: Sendable {
    public let key: String
    public let name: String
    public let color: UInt32
    public let prefixes: [String]
}

public struct CardInput: Sendable {
    public var bankName: String
    public var bankKey: String?
    public var cardNumber: String
    public var accountNumber: String
    public var iban: String
    public var accountType: String
    public var expiryYear: Int?
    public var expiryMonth: Int?
    public var holderName: String
    public var bgColor: String?
    public var bgImage: String?        // data URL
    public var archived: Bool

    public init(bankName: String, bankKey: String?, cardNumber: String, accountNumber: String, iban: String, accountType: String,
                expiryYear: Int?, expiryMonth: Int?, holderName: String, bgColor: String?, bgImage: String?, archived: Bool) {
        self.bankName = bankName; self.bankKey = bankKey; self.cardNumber = cardNumber; self.accountNumber = accountNumber
        self.iban = iban; self.accountType = accountType; self.expiryYear = expiryYear; self.expiryMonth = expiryMonth
        self.holderName = holderName; self.bgColor = bgColor; self.bgImage = bgImage; self.archived = archived
    }
}

public struct Quote: Equatable, Sendable {
    public let id: String
    public let text: String
    public let author: String
    public init(id: String, text: String, author: String) { self.id = id; self.text = text; self.author = author }
}

public enum SettingsOps {

    // web CW_BANKS (logos left out)
    public static let banks: [Bank] = [
        Bank(key: "melli", name: "بانک ملی ایران", color: 0x0F6B3A, prefixes: ["603799"]),
        Bank(key: "sepah", name: "بانک سپه", color: 0x1B4D8C, prefixes: ["589210"]),
        Bank(key: "tosesaderat", name: "بانک توسعه صادرات", color: 0x0A4F6E, prefixes: ["207177", "627648"]),
        Bank(key: "sanatmadan", name: "بانک صنعت و معدن", color: 0x5B3A8C, prefixes: ["627961"]),
        Bank(key: "keshavarzi", name: "بانک کشاورزی", color: 0x1E7A34, prefixes: ["603770", "639217"]),
        Bank(key: "maskan", name: "بانک مسکن", color: 0x8C5A1B, prefixes: ["628023"]),
        Bank(key: "post", name: "پست بانک ایران", color: 0x0B7A6E, prefixes: ["627760"]),
        Bank(key: "tosetaavon", name: "بانک توسعه تعاون", color: 0x2E6B8C, prefixes: ["502908"]),
        Bank(key: "tejarat", name: "بانک تجارت", color: 0x2B6CB0, prefixes: ["585983", "627353"]),
        Bank(key: "saderat", name: "بانک صادرات ایران", color: 0xB0722B, prefixes: ["603769"]),
        Bank(key: "refah", name: "بانک رفاه کارگران", color: 0x0E7C61, prefixes: ["589463"]),
        Bank(key: "mellat", name: "بانک ملت", color: 0xC4142F, prefixes: ["610433"]),
        Bank(key: "saman", name: "بانک سامان", color: 0x7C1FA0, prefixes: ["621986"]),
        Bank(key: "parsian", name: "بانک پارسیان", color: 0x7C1F3C, prefixes: ["622106", "639194"]),
        Bank(key: "eghtesad", name: "بانک اقتصاد نوین", color: 0x0B8C7A, prefixes: ["627412"]),
        Bank(key: "pasargad", name: "بانک پاسارگاد", color: 0x1B6B4D, prefixes: ["502229", "639347"]),
        Bank(key: "shahr", name: "بانک شهر", color: 0xB0862B, prefixes: ["502806", "504706"]),
        Bank(key: "iranzamin", name: "بانک ایران زمین", color: 0x2B6B6B, prefixes: ["505785"]),
        Bank(key: "sarmayeh", name: "بانک سرمایه", color: 0x5B5B8C, prefixes: ["639607"]),
        Bank(key: "sina", name: "بانک سینا", color: 0x0E5B8C, prefixes: ["639346"]),
        Bank(key: "dey", name: "بانک دی", color: 0x8C2B4A, prefixes: ["502938"]),
        Bank(key: "mellal", name: "موسسه اعتباری ملل", color: 0x6B3A1B, prefixes: ["606373"]),
        Bank(key: "ansar", name: "بانک انصار", color: 0x1B7A4D, prefixes: ["627381"]),
        Bank(key: "gardeshgari", name: "بانک گردشگری", color: 0x8C6B1B, prefixes: ["505416", "505426"]),
        Bank(key: "hekmat", name: "بانک حکمت ایرانیان", color: 0x4A2B8C, prefixes: ["636795"]),
        Bank(key: "khavarmianeh", name: "بانک خاورمیانه", color: 0x1B4A6B, prefixes: ["585949"]),
        Bank(key: "karafarin", name: "بانک کارآفرین", color: 0x0B6B8C, prefixes: ["627488", "502910"]),
        Bank(key: "kosar", name: "موسسه اعتباری کوثر", color: 0x6B8C1B, prefixes: ["505801"]),
        Bank(key: "mehreghtesad", name: "بانک مهر اقتصاد", color: 0x8C4A1B, prefixes: ["639370"]),
    ]

    public static let defaultAccountTypes = ["جاری", "جاری با دسته‌چک", "قرض‌الحسنه", "کوتاه‌مدت", "بلندمدت", "مشترک", "ارزی"]

    /// web: bank from the first 6 digits
    public static func bank(forCardNumber n: String) -> Bank? {
        let digits = SearchEngine.latinDigits(n).filter(\.isNumber)
        guard digits.count >= 6 else { return nil }
        let p6 = String(digits.prefix(6))
        return banks.first { $0.prefixes.contains(p6) }
    }

    // MARK: cards

    public static func saveCard(_ state: [String: JSONValue], editingId: String?, _ input: CardInput,
                                ids: IdSource = .system) throws -> [String: JSONValue] {
        let number = SearchEngine.latinDigits(input.cardNumber).filter(\.isNumber)
        guard !input.bankName.trimmingCharacters(in: .whitespaces).isEmpty || !number.isEmpty else { throw LedgerError.invalid(["بانک یا شماره کارت"]) }
        if let m = input.expiryMonth, !(1...12).contains(m) { throw LedgerError.invalid(["ماه انقضا (۱ تا ۱۲)"]) }
        var st = state
        if !input.accountType.isEmpty {
            if st["cwAccountTypes"] == nil { st["cwAccountTypes"] = .array(defaultAccountTypes.map { .string($0) }) }
            LedgerOps.addCategoryIfNew(&st, list: "cwAccountTypes", input.accountType)
        }
        var cards = LedgerOps.array(st, "cards")
        var c: [String: JSONValue]
        var index: Int?
        if let id = editingId {
            guard let i = cards.firstIndex(where: { $0["id"]?.idString == id }), let o = cards[i].objectValue else { throw LedgerError.notFound }
            c = o; index = i
        } else {
            c = ["id": .string(ids.make("crd", ids.nowMs()).dropLast(1).description), "isDefault": .bool(cards.isEmpty)]
        }
        func set(_ k: String, _ v: String?) { if let v, !v.isEmpty { c[k] = .string(v) } else { c.removeValue(forKey: k) } }
        let oldBank = c["bankName"]?.stringValue ?? ""
        c["bankName"] = .string(input.bankName.isEmpty ? oldBank : input.bankName)
        set("bankKey", input.bankKey)
        set("cardNumber", number)
        if !number.isEmpty { c["last4"] = .string(String(number.suffix(4))) }
        set("accountNumber", SearchEngine.latinDigits(input.accountNumber))
        set("iban", SearchEngine.latinDigits(input.iban).uppercased())
        set("accountType", input.accountType)
        c.removeValue(forKey: "cvv")                         // D17
        if let y = input.expiryYear, let m = input.expiryMonth {
            c["expiry"] = .object(["ey": .int(Int64(y)), "em": .int(Int64(m))])
        } else {
            c["expiry"] = .null
        }
        set("holderName", input.holderName)
        set("bgImage", input.bgImage)
        set("bgColor", input.bgColor)
        c["archived"] = .bool(input.archived)
        if let i = index { cards[i] = .object(c) } else { cards.append(.object(c)) }
        st["cards"] = .array(cards)
        return st
    }

    public static func deleteCard(_ state: [String: JSONValue], id: String) throws -> [String: JSONValue] {
        var st = state
        let cards = LedgerOps.array(st, "cards")
        guard cards.contains(where: { $0["id"]?.idString == id }) else { throw LedgerError.notFound }
        st["cards"] = .array(cards.filter { $0["id"]?.idString != id })
        return st
    }

    /// Display like the web cwExpiryDisplay: "1409/10"; old string values are shown as they are.
    public static func expiryText(_ v: JSONValue?) -> String {
        if let s = v?.stringValue { return Money.persianDigits(s) }
        guard let y = v?["ey"]?.intValue, let m = v?["em"]?.intValue, y > 0, m > 0 else { return "" }
        return Money.persianDigits("\(y)/" + String(format: "%02d", m))
    }

    // MARK: card copy / share text (web cwComposeCopyText / cwCopyAllFields)

    public static func cardCopyText(_ card: JSONValue) -> String? {
        func raw(_ f: String) -> String {
            switch f {
            case "cardNumber":
                if let n = card["cardNumber"]?.idString, !n.isEmpty { return n }
                if let l = card["last4"]?.idString, !l.isEmpty { return "****" + l }
                return ""
            default: return card[f]?.idString ?? card[f]?.stringValue ?? ""
            }
        }
        let fields = ["cardNumber", "accountNumber", "iban"].filter { !raw($0).isEmpty }
        guard !fields.isEmpty else { return nil }
        let bank = card["bankName"]?.stringValue ?? ""
        var short = bank
        if let r = short.range(of: "^بانک\\s+", options: .regularExpression) { short.removeSubrange(r) }
        var lines: [String] = []
        if !bank.isEmpty { lines.append(bank); lines.append("") }
        let word = ["cardNumber": "کارت", "accountNumber": "حساب", "iban": "شبا"]
        for f in fields {
            lines.append("شماره " + word[f]! + " " + short + " :")
            lines.append(raw(f))
        }
        if let h = card["holderName"]?.stringValue, !h.isEmpty { lines.append("به نام " + h) }
        return lines.joined(separator: "\n")
    }

    // MARK: budgets

    public static func setAccountBudget(_ state: [String: JSONValue], accountId: String, budget: Int) throws -> [String: JSONValue] {
        var st = state
        var accounts = LedgerOps.array(st, "accounts")
        guard let i = accounts.firstIndex(where: { $0["id"]?.idString == accountId }), var a = accounts[i].objectValue else { throw LedgerError.notFound }
        a["budget"] = .int(Int64(max(0, budget)))
        accounts[i] = .object(a)
        st["accounts"] = .array(accounts)
        return st
    }

    public static func setPersonalBudget(_ state: [String: JSONValue], budget: Int) -> [String: JSONValue] {
        var st = state
        st["personalBudget"] = .int(Int64(max(0, budget)))
        return st
    }

    // MARK: quotes (web homeQuotePool / homeQuoteOfNow)

    public static func quotes(_ st: [String: JSONValue]) -> [Quote] {
        (st["customQuotes"]?.arrayValue ?? []).compactMap { q in
            guard let t = q["text"]?.stringValue, !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return Quote(id: "custom-" + (q["id"]?.idString ?? ""), text: t, author: q["author"]?.stringValue ?? "")
        }
    }

    /// web quoteHash32 (32-bit, JS semantics)
    public static func quoteHash32(_ s: String) -> UInt32 {
        var h: UInt32 = 2166136261
        for u in s.utf16 {
            h ^= UInt32(u)
            h = h &+ (h << 1) &+ (h << 4) &+ (h << 7) &+ (h << 8) &+ (h << 24)
        }
        return h
    }

    /// Same quote as the web app for the same half day: every quote once per lap, deterministic shuffle per lap.
    public static func quoteOfNow(_ st: [String: JSONValue], now: Date = Date(), calendar: Calendar = .current) -> Quote? {
        let pool = quotes(st)
        guard !pool.isEmpty else { return nil }
        let start = calendar.startOfDay(for: now)
        let days = Int((start.timeIntervalSince1970 / 86400).rounded(.down))
        let half = calendar.component(.hour, from: now) < 12 ? 0 : 1
        let slot = days * 2 + half
        let lap = slot / pool.count
        let pos = slot % pool.count
        let ordered = pool.map { ($0, quoteHash32($0.id + "|" + String(lap))) }
            .sorted { a, b in a.1 != b.1 ? a.1 < b.1 : a.0.id < b.0.id }
            .map(\.0)
        return ordered[pos]
    }

    public static func addQuote(_ state: [String: JSONValue], text: String, author: String, ids: IdSource = .system) throws -> [String: JSONValue] {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { throw LedgerError.invalid(["متن جمله"]) }
        var st = state
        var list = LedgerOps.array(st, "customQuotes")
        let id = String(ids.nowMs()) + "-" + String(Int.random(in: 0..<1_000_000))
        list.append(.object(["id": .string(id), "text": .string(t), "author": .string(author.trimmingCharacters(in: .whitespaces))]))
        st["customQuotes"] = .array(list)
        return st
    }

    public static func editQuote(_ state: [String: JSONValue], id: String, text: String, author: String) throws -> [String: JSONValue] {
        var st = state
        var list = LedgerOps.array(st, "customQuotes")
        guard let i = list.firstIndex(where: { $0["id"]?.idString == id }), var q = list[i].objectValue else { throw LedgerError.notFound }
        q["text"] = .string(text.trimmingCharacters(in: .whitespacesAndNewlines)); q["author"] = .string(author.trimmingCharacters(in: .whitespaces))
        list[i] = .object(q)
        st["customQuotes"] = .array(list)
        return st
    }

    public static func deleteQuote(_ state: [String: JSONValue], id: String) -> [String: JSONValue] {
        var st = state
        st["customQuotes"] = .array(LedgerOps.array(st, "customQuotes").filter { $0["id"]?.idString != id })
        return st
    }

    // MARK: home widgets

    public static let widgetKeys = ["date", "attention", "financial", "shortcuts", "activity"]

    public static func widgetOrder(_ st: [String: JSONValue]) -> [String] {
        var order = (st["homeWidgetOrder"]?.arrayValue ?? []).compactMap(\.stringValue).filter { widgetKeys.contains($0) }
        for k in widgetKeys where !order.contains(k) { order.append(k) }
        return order
    }

    public static func widgetVisible(_ st: [String: JSONValue], _ key: String) -> Bool {
        st["homeWidgets"]?[key]?.boolValue ?? true
    }

    public static func setWidgets(_ state: [String: JSONValue], order: [String], visible: [String: Bool]) -> [String: JSONValue] {
        var st = state
        // keep the web-only keys (e.g. weather) the way they were
        var existing = (st["homeWidgetOrder"]?.arrayValue ?? []).compactMap(\.stringValue).filter { !widgetKeys.contains($0) }
        existing = order + existing
        st["homeWidgetOrder"] = .array(existing.map { .string($0) })
        var w = st["homeWidgets"]?.objectValue ?? [:]
        for (k, v) in visible { w[k] = .bool(v) }
        st["homeWidgets"] = .object(w)
        return st
    }

    // MARK: home shortcuts (web HOME_SHORTCUT_TARGETS / state.homeShortcuts) and typewriter speed

    public static let shortcutKeys = ["ledger", "personal", "income", "cards", "reminders", "reports", "appointments"]

    public static func homeShortcuts(_ st: [String: JSONValue]) -> [String] {
        (st["homeShortcuts"]?.arrayValue ?? []).compactMap(\.stringValue).filter { shortcutKeys.contains($0) }
    }

    public static func setHomeShortcuts(_ state: [String: JSONValue], _ keys: [String]) -> [String: JSONValue] {
        var st = state
        var seen = Set<String>()
        st["homeShortcuts"] = .array(keys.filter { shortcutKeys.contains($0) && seen.insert($0).inserted }.map { .string($0) })
        return st
    }

    /// web quoteTypewriterMsPerChar
    public static func typewriterMs(_ st: [String: JSONValue]) -> Int {
        switch st["quoteTypewriterSpeed"]?.stringValue {
        case "slow": return 55
        case "fast": return 16
        default: return 32
        }
    }
}
