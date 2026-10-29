import Foundation

// Import of the web app's full backup (پشتیبان کامل).
//
// Validation is a port of the web `validateFullAppBackupJson` (same order, same messages), plus
// decision D4: an envelope must be `__appBackup: "hesabdari-full"`, `version: 1`; a raw state is accepted.
// The analysis implements the approved import decisions:
//   D1  rows without id get a deterministic id (same file → same id), listed in the report
//   D9  invalid Jalali dates are kept as stored and flagged
//   D14 legacy commission settlements are kept as stored (balance = web balance)
//   D17 CVV is removed and never stored or exported
// Open decisions block the import instead of guessing:
//   D2  duplicate ids,  D3  rows without entry time (ts)

public enum BackupFormatError: Error, Equatable, Sendable {
    case notJSON
    case unrecognized
    case notFullBackup
    case badStructure
    case unsupportedFormat(tag: String, version: String)

    /// Same texts as the web app; the D4 text is new.
    public var message: String {
        switch self {
        case .notJSON: return "فایل انتخاب‌شده یک JSON معتبر نیست."
        case .unrecognized: return "محتوای فایل قابل شناسایی نیست."
        case .notFullBackup: return "این فایل، خروجیِ «پشتیبان‌گیری کامل» همین اپ نیست."
        case .badStructure: return "ساختار فایل با پشتیبان کامل این اپ مطابقت نداره."
        case .unsupportedFormat(let tag, let version):
            return "این پشتیبان قالب دیگری دارد (برچسب «\(tag)»، نسخه‌ی \(Money.persianDigits(version))). این نسخه‌ی آیفون فقط پشتیبان کامل نسخه‌ی ۱ را می‌شناسد و برای اینکه عددی اشتباه خوانده نشود، آن را وارد نمی‌کند."
        }
    }
}

public struct ParsedBackup: Sendable {
    public var state: [String: JSONValue]
    public var isEnvelope: Bool
    public var exportedAtJalali: String?
    public var exportedAtIso: String?
}

public enum BackupParser {
    public static func parse(_ data: Data) -> Result<ParsedBackup, BackupFormatError> {
        let parsed: JSONValue
        do { parsed = try JSONCoding.decode(data) } catch { return .failure(.notJSON) }

        var root: [String: JSONValue] = [:]
        switch parsed {
        case .object(let o): root = o
        case .array: root = [:]                       // JS: an array is an object without .state/.accounts
        default: return .failure(.unrecognized)
        }

        var st: [String: JSONValue]?
        var stateWasArray = false
        var isEnvelope = false
        switch root["state"] {
        case .object(let o)?: st = o; isEnvelope = true
        case .array?: stateWasArray = true; isEnvelope = true
        default: break
        }
        if st == nil && !stateWasArray, case .array? = root["accounts"] { st = root }
        if stateWasArray { return .failure(.badStructure) }
        guard let state = st else { return .failure(.notFullBackup) }

        for key in ["accounts", "expenses", "personalExpenses"] {
            guard case .array? = state[key] else { return .failure(.badStructure) }
        }

        if isEnvelope {   // D4
            let tag = root["__appBackup"]?.stringValue ?? "—"
            let version = root["version"]?.intValue
            if tag != "hesabdari-full" || version != 1 {
                let v = root["version"].flatMap { $0.idString } ?? "—"
                return .failure(.unsupportedFormat(tag: tag, version: v))
            }
        }
        return .success(ParsedBackup(state: state, isEnvelope: isEnvelope,
                                     exportedAtJalali: root["exportedAtJalali"]?.stringValue,
                                     exportedAtIso: root["exportedAtIso"]?.stringValue))
    }
}

// MARK: - report

public struct ImportIssue: Identifiable, Equatable, Sendable {
    public enum Level: Int, Sendable { case blocking = 0, warning = 1, info = 2 }
    public var id: String
    public var level: Level
    public var title: String
    public var details: [String]
}

public struct AccountImportSummary: Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var rows: Int
    public var expenseTotal: Int      // every non-tankhah row, as the web ledger total
    public var tankhahTotal: Int
    public var percent: Double
    public var commissionEnabled: Bool
    public var openBase: Int
    public var accrued: Int
    public var balance: Int           // debt > 0, credit < 0
    public var remaining: Int         // accrued + balance
    public var settled: Int
}

public struct ImportReport: Sendable {
    public var summaryLines: [String]
    public var accounts: [AccountImportSummary]
    public var personalTotal: Int
    public var incomeTotal: Int
    public var issues: [ImportIssue]
    public var cvvRemoved: Int
    public var generatedIds: [String]          // "collection#index → id"
    public var exportedAtJalali: String?
    /// The state that will be stored: CVV removed, generated ids filled in, nothing else changed.
    public var cleanedState: [String: JSONValue]

    public var canImport: Bool { !issues.contains { $0.level == .blocking } }
}

public enum ImportAnalyzer {

    static let idCollections = ["accounts", "expenses", "personalExpenses", "incomes", "reminderChecks", "cards",
                                "reminderPersons", "appointments", "parties", "checkParties", "tankhahParties", "customQuotes"]
    static let tsCollections = ["expenses", "personalExpenses", "incomes"]

    static let collectionNames: [String: String] = [
        "accounts": "حساب‌های دفتر", "expenses": "ردیف‌های دفتر حساب", "personalExpenses": "هزینه‌های شخصی",
        "incomes": "درآمدها", "reminderChecks": "چک‌ها", "cards": "کارت‌ها", "reminderPersons": "بدهکار/طلبکار",
        "appointments": "قرارها", "parties": "طرف حساب‌ها", "checkParties": "طرف حساب‌های چک",
        "tankhahParties": "طرف حساب‌های تنخواه", "customQuotes": "جمله‌ها", "installments": "اقساط",
        "commissionSettlements": "تسویه‌های کمیسیون"
    ]

    public static func analyze(_ backup: ParsedBackup) -> ImportReport {
        var st = backup.state
        var issues: [ImportIssue] = []

        // D17 — CVV
        var cvvRemoved = 0
        if case .array(let cards)? = st["cards"] {
            var out: [JSONValue] = []
            for card in cards {
                if case .object(var o) = card, let v = o["cvv"] {
                    if v.isTruthy { cvvRemoved += 1 }
                    o.removeValue(forKey: "cvv")
                    out.append(.object(o))
                } else { out.append(card) }
            }
            st["cards"] = .array(out)
        }
        if cvvRemoved > 0 {
            issues.append(ImportIssue(id: "cvv", level: .info,
                title: "کد CVV \(Money.persianDigits(cvvRemoved)) کارت حذف شد",
                details: ["طبق تصمیم شما، CVV در آیفون ذخیره نمی‌شود و در پشتیبان‌های بعدی هم نوشته نمی‌شود."]))
        }

        // D1 — missing ids (deterministic)
        var generated: [String] = []
        for col in idCollections {
            guard case .array(var arr)? = st[col] else { continue }
            var changed = false
            for (i, item) in arr.enumerated() {
                guard case .object(var o) = item else { continue }
                if o["id"]?.idString == nil {
                    let newId = deterministicId(collection: col, index: i, record: item)
                    o["id"] = .string(newId)
                    arr[i] = .object(o)
                    generated.append("\(col)#\(i) → \(newId)")
                    changed = true
                }
            }
            if changed { st[col] = .array(arr) }
        }
        if !generated.isEmpty {
            issues.append(ImportIssue(id: "d1", level: .warning,
                title: "\(Money.persianDigits(generated.count)) ردیف قدیمی شناسه نداشت و شناسه‌ی تازه گرفت",
                details: ["مبلغ و تاریخ این ردیف‌ها تغییر نکرده است. ورود دوباره‌ی همین فایل همین شناسه‌ها را می‌دهد."] + generated))
        }

        // D2 — duplicate ids (open decision → block)
        var dupDetails: [String] = []
        for col in idCollections {
            guard let arr = st[col]?.arrayValue else { continue }
            var count: [String: Int] = [:]
            for item in arr { if let id = item["id"]?.idString { count[id, default: 0] += 1 } }
            let dups = count.filter { $0.value > 1 }.keys.sorted()
            if !dups.isEmpty {
                dupDetails.append("\(collectionNames[col] ?? col): \(Money.persianDigits(dups.count)) شناسه‌ی تکراری")
            }
        }
        if !dupDetails.isEmpty {
            issues.append(ImportIssue(id: "d2", level: .blocking,
                title: "چند ردیف شناسه‌ی تکراری دارند",
                details: ["در اپ وب حذف یکی از این ردیف‌ها هر دو را پاک می‌کند. تا وقتی درباره‌ی آن تصمیم نگرفته‌اید (D2)، این فایل وارد نمی‌شود."] + dupDetails))
        }

        // D3 — rows without entry time (open decision → block)
        var noTs: [String] = []
        for col in tsCollections {
            guard let arr = st[col]?.arrayValue else { continue }
            let n = arr.filter { ($0["ts"]?.isNumber ?? false) == false }.count
            if n > 0 { noTs.append("\(collectionNames[col] ?? col): \(Money.persianDigits(n)) ردیف") }
        }
        if !noTs.isEmpty {
            issues.append(ImportIssue(id: "d3", level: .blocking,
                title: "چند ردیف زمان ثبت ندارند",
                details: ["قاعده‌ی کمیسیون به ترتیب ثبت تکیه دارد. تا وقتی درباره‌ی آن تصمیم نگرفته‌اید (D3)، این فایل وارد نمی‌شود."] + noTs))
        }

        // D9 — invalid dates (kept, flagged)
        var badDates: [String] = []
        func checkDates(_ col: String, _ field: String) {
            guard let arr = st[col]?.arrayValue else { return }
            let n = arr.filter { !isValidDate($0[field]) }.count
            if n > 0 { badDates.append("\(collectionNames[col] ?? col): \(Money.persianDigits(n))") }
        }
        checkDates("expenses", "date"); checkDates("personalExpenses", "date"); checkDates("incomes", "date")
        checkDates("reminderChecks", "dueDate"); checkDates("appointments", "date")
        var nestedBad = 0
        for p in st["reminderPersons"]?.arrayValue ?? [] {
            for ins in p["installments"]?.arrayValue ?? [] where !isValidDate(ins["dueDate"]) { nestedBad += 1 }
        }
        if nestedBad > 0 { badDates.append("اقساط: \(Money.persianDigits(nestedBad))") }
        for a in st["accounts"]?.arrayValue ?? [] {
            let n = (a["commissionSettlements"]?.arrayValue ?? []).filter { !isValidDate($0["date"]) }.count
            if n > 0 { badDates.append("تسویه‌های کمیسیون «\(a["name"]?.stringValue ?? "")»: \(Money.persianDigits(n))") }
        }
        if !badDates.isEmpty {
            issues.append(ImportIssue(id: "d9", level: .warning, title: "تاریخ نامعتبر",
                details: ["تاریخ ذخیره‌شده عوض نمی‌شود و محاسبه مثل اپ وب انجام می‌شود."] + badDates))
        }

        // references (informational)
        issues.append(contentsOf: referenceIssues(st))

        // accounts and totals
        let accounts = (st["accounts"]?.arrayValue ?? []).map { accountSummary($0, expenses: st["expenses"]?.arrayValue ?? []) }
        let personalTotal = (st["personalExpenses"]?.arrayValue ?? []).reduce(0) { $0 + toman($1) }
        let incomeTotal = (st["incomes"]?.arrayValue ?? []).reduce(0) { $0 + toman($1) }

        issues.sort { $0.level.rawValue < $1.level.rawValue }
        return ImportReport(summaryLines: summaryLines(st), accounts: accounts, personalTotal: personalTotal,
                            incomeTotal: incomeTotal, issues: issues, cvvRemoved: cvvRemoved, generatedIds: generated,
                            exportedAtJalali: backup.exportedAtJalali, cleanedState: st)
    }

    /// Port of the web `fullAppBackupSummaryLinesFor`.
    public static func summaryLines(_ st: [String: JSONValue]) -> [String] {
        func n(_ k: String) -> Int { st[k]?.arrayValue?.count ?? 0 }
        let persons = st["reminderPersons"]?.arrayValue ?? []
        let installments = persons.reduce(0) { $0 + ($1["installments"]?.arrayValue?.count ?? 0) }
        let p = { (x: Int) in Money.persianDigits(x) }
        return [
            "حساب‌های دفتر: " + p(n("accounts")),
            "ردیف‌های دفتر حساب: " + p(n("expenses")),
            "هزینه‌های شخصی: " + p(n("personalExpenses")),
            "درآمدها: " + p(n("incomes")),
            "چک‌ها: " + p(n("reminderChecks")),
            "بدهکار/طلبکار: " + p(persons.count) + " نفر (" + p(installments) + " قسط)",
            "قرارها: " + p(n("appointments")),
            "کارت‌ها: " + p(n("cards"))
        ]
    }

    public static func toman(_ v: JSONValue) -> Int {
        if let i = v["toman"]?.intValue { return i }
        if let d = v["toman"]?.doubleValue { return Money.jsRound(d) }
        return 0
    }

    public static func date(_ v: JSONValue?) -> JalaliDate {
        JalaliDate(jy: v?["jy"]?.intValue ?? 0, jm: v?["jm"]?.intValue ?? 0, jd: v?["jd"]?.intValue ?? 0)
    }

    public static func isValidDate(_ v: JSONValue?) -> Bool {
        guard let y = v?["jy"]?.intValue, let m = v?["jm"]?.intValue, let d = v?["jd"]?.intValue else { return false }
        guard (1...12).contains(m), d >= 1 else { return false }
        return d <= Jalali.monthLength(y, m)
    }

    /// Commission state of one account with the approved rules (legacy settlements kept as stored, D14).
    public static func ledger(account: JSONValue, expenses: [JSONValue]) -> CommissionLedger {
        let accId = account["id"]?.idString ?? ""
        let rows: [LedgerRow] = expenses.filter { $0["accountId"]?.idString == accId }.map { e in
            LedgerRow(key: e["id"]?.idString ?? "", type: e["type"]?.stringValue ?? "expense",
                      desc: e["desc"]?.stringValue ?? "", toman: toman(e), date: date(e["date"]),
                      ts: e["ts"]?.intValue ?? 0, subcategory: e["subcategory"]?.stringValue,
                      commission: e["commissionSettlementId"]?.idString,
                      linked: e["linked"].map { _ in "linked" })
        }
        let settlements: [Settlement] = (account["commissionSettlements"]?.arrayValue ?? []).map { s in
            Settlement(key: s["id"]?.idString ?? "", toman: toman(s), date: date(s["date"]), ts: s["ts"]?.intValue ?? 0,
                       calculatedAmount: s["calculatedAmount"]?.intValue ?? 0,
                       remainingForStage: s["remainingForStage"]?.intValue ?? 0,
                       isFull: s["isFull"]?.isTruthy ?? false, balanceAfter: s["balanceAfter"]?.intValue)
        }
        return CommissionLedger(accountId: accId, accountName: account["name"]?.stringValue ?? "",
                                percent: account["commissionPercent"]?.doubleValue ?? 0, rows: rows, settlements: settlements)
    }

    public static func accountSummary(_ a: JSONValue, expenses: [JSONValue]) -> AccountImportSummary {
        let accId = a["id"]?.idString ?? ""
        let mine = expenses.filter { $0["accountId"]?.idString == accId }
        let L = ledger(account: a, expenses: expenses)
        let s = L.summary()
        return AccountImportSummary(
            id: accId, name: a["name"]?.stringValue ?? "", rows: mine.count,
            expenseTotal: mine.filter { $0["type"]?.stringValue != "tankhah" }.reduce(0) { $0 + toman($1) },
            tankhahTotal: mine.filter { $0["type"]?.stringValue == "tankhah" }.reduce(0) { $0 + toman($1) },
            percent: s.percent, commissionEnabled: a["commissionEnabled"]?.isTruthy ?? false,
            openBase: s.openBase, accrued: s.accrued, balance: s.pastShortfall, remaining: s.remaining, settled: s.settled)
    }

    static func referenceIssues(_ st: [String: JSONValue]) -> [ImportIssue] {
        func ids(_ k: String) -> Set<String> { Set((st[k]?.arrayValue ?? []).compactMap { $0["id"]?.idString }) }
        let accounts = ids("accounts"), expenses = ids("expenses"), cards = ids("cards")
        let parties = ids("parties").union(ids("tankhahParties")).union(ids("checkParties"))
        var settlements = Set<String>()
        for a in st["accounts"]?.arrayValue ?? [] {
            for s in a["commissionSettlements"]?.arrayValue ?? [] { if let id = s["id"]?.idString { settlements.insert(id) } }
        }
        let rows = st["expenses"]?.arrayValue ?? []
        var details: [String] = []
        func add(_ n: Int, _ text: String) { if n > 0 { details.append("\(text): \(Money.persianDigits(n))") } }
        func dangling(_ v: JSONValue?, _ known: Set<String>) -> Bool {
            guard let id = v?.idString else { return false }
            return !known.contains(id)
        }
        add(rows.filter { $0["accountId"]?.idString == nil || dangling($0["accountId"], accounts) }.count, "ردیف دفتر بدون حساب معتبر")
        add(rows.filter { dangling($0["cardId"], cards) }.count, "ردیف با کارت ناموجود")
        add(rows.filter { dangling($0["partyId"], parties) }.count, "ردیف با طرف حساب ناموجود")
        add(rows.filter { dangling($0["commissionSettlementId"], settlements) }.count, "ردیف کمیسیون بدون تسویه")
        add((st["reminderChecks"]?.arrayValue ?? []).filter { dangling($0["linkedExpenseId"], expenses) }.count, "چک وصل به ردیف ناموجود")
        if details.isEmpty { return [] }
        return [ImportIssue(id: "refs", level: .warning, title: "ارجاع‌های ناقص",
                            details: ["این‌ها همان‌طور که هست وارد می‌شوند و چیزی حذف نمی‌شود."] + details)]
    }

    /// Stable id for a legacy row: same file → same id.
    static func deterministicId(collection: String, index: Int, record: JSONValue) -> String {
        let canonical = (try? JSONCoding.string(record)) ?? ""
        var h: UInt64 = 0xcbf29ce484222325
        for b in Array("\(collection)|\(index)|\(canonical)".utf8) { h = (h ^ UInt64(b)) &* 0x100000001b3 }
        return "imp" + String(h, radix: 36)
    }
}

// MARK: - export

public enum BackupExporter {
    static let months = ["فروردین", "اردیبهشت", "خرداد", "تیر", "مرداد", "شهریور", "مهر", "آبان", "آذر", "دی", "بهمن", "اسفند"]

    /// Web `formatJalaliDate`: «۸ آبان ۱۴۰۵».
    public static func formatJalali(_ d: JalaliDate) -> String {
        let m = (1...12).contains(d.jm) ? months[d.jm - 1] : "?"
        return Money.persianDigits(d.jd) + " " + m + " " + Money.persianDigits(d.jy)
    }

    /// Same envelope as the web full backup (version 1), so the web app can restore it.
    public static func envelope(state: [String: JSONValue], now: Date, today: JalaliDate) -> JSONValue {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return .object([
            "__appBackup": .string("hesabdari-full"),
            "version": .int(1),
            "exportedAtIso": .string(iso.string(from: now)),
            "exportedAtJalali": .string(formatJalali(today)),
            "state": .object(state)
        ])
    }
}
