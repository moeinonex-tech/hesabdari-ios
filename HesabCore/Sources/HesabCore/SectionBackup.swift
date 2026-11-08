import Foundation

/// web SECTION_BACKUP_DEFS / buildSectionBackupObject / validateSectionBackupJson / applySectionRestore:
/// a JSON file with only one part of the app, and restoring only that part (the other parts are not touched).
/// Same envelope as the web app, so files move both ways.
public enum BackupSection: String, CaseIterable, Sendable, Identifiable {
    case ledger, cards, personal, income, reminders
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .ledger: return "دفتر حساب (همه‌ی حساب‌ها)"
        case .cards: return "کیف کارت"
        case .personal: return "هزینه‌های شخصی"
        case .income: return "درآمد"
        case .reminders: return "یادآوری‌ها (چک/بدهکار/طلبکار)"
        }
    }

    public var fields: [String] {
        switch self {
        case .ledger: return ["accounts", "expenses", "ledgerCategories", "categoryColors", "ledgerDescMap", "ledgerKeywordMap",
                              "ledgerSubcategories", "ledgerSubDescMap", "ledgerSubKeywordMap", "tankhahParties", "starredAccountId"]
        case .cards: return ["cards", "lastCardByAccount", "cwAccountTypes"]
        case .personal: return ["personalExpenses", "personalCommission", "personalBudget", "personalCategories", "personalDescMap",
                                "personalKeywordMap", "personalSubcategories", "personalSubDescMap", "personalSubKeywordMap"]
        case .income: return ["incomes", "incomeCategories", "categoryColorsIncome", "incomeDescMap", "incomeSubcategories",
                              "incomeSubDescMap", "incomeSubKeywordMap", "incomeKeywordMap"]
        case .reminders: return ["reminderChecks", "reminderPersons", "checkParties", "parties", "appointments"]
        }
    }

    public func summary(_ st: [String: JSONValue]) -> [String] {
        func n(_ k: String) -> String { Money.persianDigits(st[k]?.arrayValue?.count ?? 0) }
        switch self {
        case .ledger: return ["حساب‌های دفتر: " + n("accounts"), "ردیف‌های دفتر حساب: " + n("expenses")]
        case .cards: return ["کارت‌ها: " + n("cards")]
        case .personal: return ["هزینه‌های شخصی: " + n("personalExpenses")]
        case .income: return ["درآمدها: " + n("incomes")]
        case .reminders:
            let persons = st["reminderPersons"]?.arrayValue ?? []
            let inst = persons.reduce(0) { $0 + ($1["installments"]?.arrayValue?.count ?? 0) }
            return ["چک‌ها: " + n("reminderChecks"),
                    "بدهکار/طلبکار: " + Money.persianDigits(persons.count) + " نفر (" + Money.persianDigits(inst) + " قسط)",
                    "قرارها: " + n("appointments")]
        }
    }
}

public enum SectionBackup {
    public static func build(_ st: [String: JSONValue], _ section: BackupSection, todayText: String, now: Date = Date()) throws -> Data {
        var data: [String: JSONValue] = [:]
        for f in section.fields { if let v = st[f] { data[f] = v } }
        let iso = ISO8601DateFormatter().string(from: now)
        let obj: JSONValue = .object(["__appBackup": .string("hesabdari-section"), "section": .string(section.rawValue),
                                      "version": .int(1), "exportedAtIso": .string(iso), "exportedAtJalali": .string(todayText),
                                      "data": .object(data)])
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted]
        return try enc.encode(obj)
    }

    /// the file must be a section backup of exactly this section (another section or a full backup is refused, clearly)
    public static func parse(_ raw: Data, _ section: BackupSection) -> Result<[String: JSONValue], LedgerError> {
        guard let v = try? JSONDecoder().decode(JSONValue.self, from: raw) else {
            return .failure(.message("فایل انتخاب‌شده یک JSON معتبر نیست."))
        }
        guard v["__appBackup"]?.stringValue == "hesabdari-section", v["section"]?.stringValue == section.rawValue,
              let data = v["data"]?.objectValue else {
            return .failure(.message("این فایل، پشتیبانِ JSON بخشِ «" + section.title + "» نیست."))
        }
        return .success(data)
    }

    /// only this section's fields are replaced (a field missing from the file stays as it is)
    public static func apply(_ state: [String: JSONValue], _ section: BackupSection, _ data: [String: JSONValue]) -> [String: JSONValue] {
        var st = state
        for f in section.fields { if let v = data[f] { st[f] = v } }
        return st
    }
}

/// web build*BackupText: a readable text copy of one section (for reading / sending; the JSON file is for restoring)
public enum SectionText {
    static func d(_ v: JSONValue?) -> String {
        let x = ImportAnalyzer.date(v)
        return Money.persianDigits("\(x.jy)/\(x.jm)/\(x.jd)")
    }
    static func m(_ n: Int) -> String { Money.persianDigits(Money.format(n)) }
    static func s(_ v: JSONValue?) -> String { (v?.stringValue ?? v?.idString ?? "").trimmingCharacters(in: .whitespaces) }

    static func rows(_ list: [JSONValue]) -> [String] {
        let sorted = list.enumerated().sorted { a, b in
            let da = ImportAnalyzer.date(a.element["date"]), db = ImportAnalyzer.date(b.element["date"])
            return da != db ? da < db : a.offset < b.offset
        }.map(\.element)
        return sorted.map { e in
            var bits = [d(e["date"]), m(ImportAnalyzer.toman(e)) + " تومان"]
            if !s(e["desc"]).isEmpty { bits.append(s(e["desc"])) }
            let cat = [s(e["category"]), s(e["subcategory"])].filter { !$0.isEmpty }.joined(separator: " / ")
            if !cat.isEmpty { bits.append("دسته: " + cat) }
            return bits.joined(separator: " | ")
        }
    }

    public static func text(_ st: [String: JSONValue], _ section: BackupSection, todayText: String) -> String {
        var out = ["پشتیبان متنی — " + section.title, "تاریخ: " + todayText, ""]
        switch section {
        case .ledger:
            let rowsAll = st["expenses"]?.arrayValue ?? []
            for a in st["accounts"]?.arrayValue ?? [] {
                let id = a["id"]?.idString
                let list = rowsAll.filter { $0["accountId"]?.idString == id }
                out.append("— " + s(a["name"]) + " —")
                let exp = list.filter { $0["type"]?.stringValue != "tankhah" }, tk = list.filter { $0["type"]?.stringValue == "tankhah" }
                out += rows(exp)
                out.append("جمع هزینه‌ها: " + m(exp.reduce(0) { $0 + ImportAnalyzer.toman($1) }) + " تومان")
                if !tk.isEmpty {
                    out.append("تنخواه:")
                    out += rows(tk)
                    out.append("جمع تنخواه: " + m(tk.reduce(0) { $0 + ImportAnalyzer.toman($1) }) + " تومان")
                }
                out.append("")
            }
        case .personal, .income:
            let list = st[section == .income ? "incomes" : "personalExpenses"]?.arrayValue ?? []
            out += rows(list)
            out.append("جمع: " + m(list.reduce(0) { $0 + ImportAnalyzer.toman($1) }) + " تومان")
        case .cards:
            for c in st["cards"]?.arrayValue ?? [] where !(c["archived"]?.isTruthy ?? false) {
                out.append(s(c["bankName"]) + " — " + s(c["holderName"]))
                if !s(c["cardNumber"]).isEmpty { out.append("شماره کارت: " + s(c["cardNumber"])) }
                if !s(c["iban"]).isEmpty { out.append("شبا: " + s(c["iban"])) }
                if !s(c["accountNumber"]).isEmpty { out.append("شماره حساب: " + s(c["accountNumber"])) }
                out.append("")
            }
        case .reminders:
            let status = ["pending": "در انتظار وصول", "cashed": "وصول شد", "bounced": "برگشت خورد", "cancelled": "باطل شد"]
            out.append("### چک‌ها")
            for c in st["reminderChecks"]?.arrayValue ?? [] {
                let num = s(c["checkNumber"])
                out.append(["سررسید " + d(c["dueDate"]), m(c["amount"]?.intValue ?? 0) + " تومان",
                            s(c["party"]).isEmpty ? "" : "طرف: " + s(c["party"]), s(c["bankName"]),
                            num.isEmpty ? "" : "شماره " + num, status[s(c["status"])] ?? s(c["status"])]
                    .filter { !$0.isEmpty }.joined(separator: " | "))
            }
            out += ["", "### اشخاص"]
            for p in st["reminderPersons"]?.arrayValue ?? [] {
                out.append(s(p["name"]) + " — " + (p["type"]?.stringValue == "creditor" ? "طلبکار" : "بدهکار"))
                for i in p["installments"]?.arrayValue ?? [] {
                    out.append("  قسط " + d(i["dueDate"]) + " | " + m(i["amount"]?.intValue ?? 0) + " تومان"
                               + ((i["paid"]?.isTruthy ?? false) ? " | پرداخت‌شده" : "") + (s(i["description"]).isEmpty ? "" : " | " + s(i["description"])))
                }
            }
            out += ["", "### قرارها"]
            for a in st["appointments"]?.arrayValue ?? [] {
                out.append(d(a["date"]) + (s(a["time"]).isEmpty ? "" : " ساعت " + s(a["time"])) + " | " + s(a["title"])
                           + ((a["done"]?.isTruthy ?? false) ? " | انجام شد" : ""))
            }
        }
        return out.joined(separator: "\n")
    }
}
