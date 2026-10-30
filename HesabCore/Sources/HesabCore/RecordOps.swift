import Foundation

// Personal expenses and incomes — same record shapes as the web app (personal form submit, income form submit).

public struct PersonalInput: Sendable {
    public var desc: String
    public var category: String
    public var subcategory: String
    public var toman: Int
    public var date: JalaliDate
    public var payMethod: String          // web personal methods: card (پوز), hamrahbank, cash, …
    public var cardId: String?

    public init(desc: String, category: String, subcategory: String, toman: Int, date: JalaliDate, payMethod: String, cardId: String?) {
        self.desc = desc; self.category = category; self.subcategory = subcategory; self.toman = toman
        self.date = date; self.payMethod = payMethod; self.cardId = cardId
    }

    public var missingFields: [String] {
        var m: [String] = []
        if desc.trimmingCharacters(in: .whitespaces).isEmpty { m.append("شرح") }
        if category.trimmingCharacters(in: .whitespaces).isEmpty { m.append("نوع هزینه") }
        if subcategory.trimmingCharacters(in: .whitespaces).isEmpty { m.append("زیردسته") }
        if toman <= 0 { m.append("مبلغ") }
        return m
    }

    /// web: personal methods offered in this version (check / nasiyeh / branch come with the reminders step)
    public static let methods: [(id: String, title: String)] = [("card", "پوز"), ("hamrahbank", "همراه‌بانک"), ("check", "چک"), ("cash", "نقدی"), ("nasiyeh", "نسیه")]
    public static func usesCard(_ m: String) -> Bool { m == "card" || m == "hamrahbank" }
}

public struct IncomeInput: Sendable {
    public var desc: String
    public var category: String
    public var subcategory: String
    public var toman: Int
    public var date: JalaliDate
    public var accountLink: String        // "personal" or a ledger account id

    public init(desc: String, category: String, subcategory: String, toman: Int, date: JalaliDate, accountLink: String) {
        self.desc = desc; self.category = category; self.subcategory = subcategory; self.toman = toman
        self.date = date; self.accountLink = accountLink
    }

    public var missingFields: [String] {
        var m: [String] = []
        if desc.trimmingCharacters(in: .whitespaces).isEmpty { m.append("شرح") }
        if category.trimmingCharacters(in: .whitespaces).isEmpty { m.append("نوع درآمد") }
        if toman <= 0 { m.append("مبلغ") }
        return m
    }
}

public enum RecordOps {

    // MARK: personal

    public static func addPersonal(_ state: [String: JSONValue], _ input: PersonalInput, ids: IdSource = .system)
        throws -> (state: [String: JSONValue], id: String) {
        let missing = input.missingFields
        guard missing.isEmpty else { throw LedgerError.invalid(missing) }
        var st = state
        learnPersonal(&st, input)
        let now = ids.nowMs()
        let id = ids.make("p", now)
        var row: [String: JSONValue] = ["id": .string(id), "desc": .string(input.desc), "toman": .int(Int64(input.toman)),
                                        "date": LedgerOps.date(input.date), "ts": .int(Int64(now))]
        fill(&row, input)
        var list = LedgerOps.array(st, "personalExpenses")
        list.append(.object(row))
        st["personalExpenses"] = .array(list)
        return (st, id)
    }

    public static func editPersonal(_ state: [String: JSONValue], id: String, _ input: PersonalInput) throws -> [String: JSONValue] {
        let missing = input.missingFields
        guard missing.isEmpty else { throw LedgerError.invalid(missing) }
        var st = state
        var list = LedgerOps.array(st, "personalExpenses")
        guard let i = list.firstIndex(where: { $0["id"]?.idString == id }), var row = list[i].objectValue else { throw LedgerError.notFound }
        if let k = LedgerOps.linkedKind(list[i]) { throw LedgerError.linkedRow(k) }
        learnPersonal(&st, input)
        row["desc"] = .string(input.desc); row["toman"] = .int(Int64(input.toman)); row["date"] = LedgerOps.date(input.date)
        row.removeValue(forKey: "items")
        fill(&row, input)
        list[i] = .object(row)
        st["personalExpenses"] = .array(list)
        return st
    }

    public static func deletePersonal(_ state: [String: JSONValue], id: String) throws -> [String: JSONValue] {
        var st = state
        let list = LedgerOps.array(st, "personalExpenses")
        guard let row = list.first(where: { $0["id"]?.idString == id }) else { throw LedgerError.notFound }
        if let k = LedgerOps.linkedKind(row) { throw LedgerError.linkedRow(k) }
        st["personalExpenses"] = .array(list.filter { $0["id"]?.idString != id })
        return st
    }

    static func fill(_ row: inout [String: JSONValue], _ input: PersonalInput) {
        let c = input.category.trimmingCharacters(in: .whitespaces), s = input.subcategory.trimmingCharacters(in: .whitespaces)
        if c.isEmpty { row.removeValue(forKey: "category") } else { row["category"] = .string(input.category) }
        if s.isEmpty { row.removeValue(forKey: "subcategory") } else { row["subcategory"] = .string(input.subcategory) }
        row["payMethod"] = .string(input.payMethod)                 // web applyPayMethodToPersonal
        for k in ["cardId", "bankName", "branchName"] { row.removeValue(forKey: k) }
        if PersonalInput.usesCard(input.payMethod), let card = input.cardId, !card.isEmpty { row["cardId"] = .string(card) }
    }

    static func learnPersonal(_ st: inout [String: JSONValue], _ input: PersonalInput) {
        LedgerOps.addCategoryIfNew(&st, list: "personalCategories", input.category)
        Learning.learnCategory(&st, .personal, desc: input.desc, category: input.category)
        if !input.category.isEmpty && !input.subcategory.isEmpty {
            LedgerOps.addSubcategoryIfNew(&st, map: "personalSubcategories", category: input.category, input.subcategory)
            Learning.learnSubcategory(&st, .personal, category: input.category, desc: input.desc, sub: input.subcategory)
        }
    }

    // MARK: income

    /// web incAccountLinkLabel
    public static func accountLabel(_ st: [String: JSONValue], _ link: String) -> String {
        if link == "personal" || link.isEmpty { return "شخصی" }
        return LedgerOps.array(st, "accounts").first { $0["id"]?.idString == link }?["name"]?.stringValue ?? "حساب حذف‌شده"
    }

    public static func addIncome(_ state: [String: JSONValue], _ input: IncomeInput, ids: IdSource = .system)
        throws -> (state: [String: JSONValue], id: String) {
        let missing = input.missingFields
        guard missing.isEmpty else { throw LedgerError.invalid(missing) }
        var st = state
        learnIncome(&st, input)
        let now = ids.nowMs()
        let id = ids.make("i", now)
        var row: [String: JSONValue] = [
            "id": .string(id), "desc": .string(input.desc), "toman": .int(Int64(input.toman)), "date": LedgerOps.date(input.date),
            "ts": .int(Int64(now)), "subcategory": .string(input.subcategory),
            "accountId": .string(input.accountLink), "accountName": .string(accountLabel(st, input.accountLink)),
            "source": .string("manual"), "commissionSettlementId": .null
        ]
        if !input.category.trimmingCharacters(in: .whitespaces).isEmpty { row["category"] = .string(input.category) }
        var list = LedgerOps.array(st, "incomes")
        list.append(.object(row))
        st["incomes"] = .array(list)
        return (st, id)
    }

    public static func editIncome(_ state: [String: JSONValue], id: String, _ input: IncomeInput) throws -> [String: JSONValue] {
        let missing = input.missingFields
        guard missing.isEmpty else { throw LedgerError.invalid(missing) }
        var st = state
        var list = LedgerOps.array(st, "incomes")
        guard let i = list.firstIndex(where: { $0["id"]?.idString == id }), var row = list[i].objectValue else { throw LedgerError.notFound }
        if row["commissionSettlementId"]?.idString != nil { throw LedgerError.commissionIncome }
        learnIncome(&st, input)
        row["desc"] = .string(input.desc); row["toman"] = .int(Int64(input.toman)); row["date"] = LedgerOps.date(input.date)
        if input.category.trimmingCharacters(in: .whitespaces).isEmpty { row.removeValue(forKey: "category") } else { row["category"] = .string(input.category) }
        row["subcategory"] = .string(input.subcategory)
        row["accountId"] = .string(input.accountLink)
        row["accountName"] = .string(accountLabel(st, input.accountLink))
        list[i] = .object(row)
        st["incomes"] = .array(list)
        return st
    }

    public static func deleteIncome(_ state: [String: JSONValue], id: String) throws -> [String: JSONValue] {
        var st = state
        let list = LedgerOps.array(st, "incomes")
        guard let row = list.first(where: { $0["id"]?.idString == id }) else { throw LedgerError.notFound }
        if row["commissionSettlementId"]?.idString != nil { throw LedgerError.commissionIncome }
        st["incomes"] = .array(list.filter { $0["id"]?.idString != id })
        return st
    }

    static func learnIncome(_ st: inout [String: JSONValue], _ input: IncomeInput) {
        LedgerOps.addCategoryIfNew(&st, list: "incomeCategories", input.category)
        Learning.learnCategory(&st, .income, desc: input.desc, category: input.category)
        if !input.subcategory.isEmpty {
            LedgerOps.addSubcategoryIfNew(&st, map: "incomeSubcategories", category: input.category, input.subcategory)
            Learning.learnSubcategory(&st, .income, category: input.category, desc: input.desc, sub: input.subcategory)
        }
    }
}

// MARK: - notifications (approved iOS rule, phase1 model/notify_ios_model.js)
//   checks: pending, not muted → 20:00 local on the day before the due date (same text as the web app)
//   installments: not paid, not muted → 20:00 the day before;  appointments: not done → 3 h before, or 09:00 if no time
//   catch-up: fire time passed but not over yet → deliver now;  cap: the 60 nearest

public struct PlannedNotification: Equatable, Sendable {
    public var id: String
    public var kind: String
    public var title: String
    public var body: String
    public var fireAt: Date?            // nil = deliver now (catch-up)
    public var endAt: Date
}

public enum NotificationPlanner {

    /// web remCheckIdent: check number, else Sayad id, in Persian digits
    public static func checkIdent(_ c: JSONValue) -> String {
        let n = c["checkNumber"]?.idString ?? ""
        if !n.isEmpty { return Money.persianDigits(n) }
        return Money.persianDigits(c["sayadId"]?.idString ?? "")
    }

    public static func plan(_ st: [String: JSONValue], now: Date, timeZone: TimeZone = .current, cap: Int = 60)
        -> (immediate: [PlannedNotification], scheduled: [PlannedNotification]) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        func at(_ j: JalaliDate, dayOffset: Int, hour: Int, minute: Int = 0) -> Date {
            let g = Jalali.toGregorian(j)
            let base = cal.date(from: DateComponents(year: g.gy, month: g.gm, day: g.gd, hour: hour, minute: minute)) ?? now
            return cal.date(byAdding: .day, value: dayOffset, to: base) ?? base
        }
        var all: [PlannedNotification] = []
        for c in st["reminderChecks"]?.arrayValue ?? [] {
            guard c["status"]?.stringValue == "pending", !(c["muted"]?.isTruthy ?? false), ImportAnalyzer.isValidDate(c["dueDate"]) else { continue }
            let d = ImportAnalyzer.date(c["dueDate"])
            let ident = checkIdent(c)
            let party = c["party"]?.stringValue ?? ""
            let amount = Money.persianDigits(Money.format(c["amount"]?.intValue ?? 0))
            let body = "فردا سررسیدِ چک " + (ident.isEmpty ? "" : ident + " ") + "به مبلغ " + amount + " تومان"
                + (party.isEmpty ? "" : " در وجه " + party) + " است."
            all.append(PlannedNotification(id: "chk-" + (c["id"]?.idString ?? ""), kind: "check", title: "یادآوریِ سررسیدِ چک",
                                           body: body, fireAt: at(d, dayOffset: -1, hour: 20), endAt: at(d, dayOffset: 1, hour: 0)))
        }
        for p in st["reminderPersons"]?.arrayValue ?? [] {
            let creditor = p["type"]?.stringValue == "creditor"
            let name = p["name"]?.stringValue ?? ""
            for i in p["installments"]?.arrayValue ?? [] {
                guard !(i["paid"]?.isTruthy ?? false), !(i["muted"]?.isTruthy ?? false), ImportAnalyzer.isValidDate(i["dueDate"]) else { continue }
                let d = ImportAnalyzer.date(i["dueDate"])
                let amount = Money.persianDigits(Money.format(i["amount"]?.intValue ?? 0))
                all.append(PlannedNotification(
                    id: "ins-" + (i["id"]?.idString ?? ""), kind: "installment",
                    title: creditor ? "یادآوریِ قسطِ پرداختی" : "یادآوریِ قسطِ دریافتی",
                    body: "فردا سررسیدِ قسطِ " + amount + " تومان " + (creditor ? "به " : "از ") + name + " است.",
                    fireAt: at(d, dayOffset: -1, hour: 20), endAt: at(d, dayOffset: 1, hour: 0)))
            }
        }
        for a in st["appointments"]?.arrayValue ?? [] {
            guard !(a["done"]?.isTruthy ?? false), ImportAnalyzer.isValidDate(a["date"]) else { continue }
            let d = ImportAnalyzer.date(a["date"])
            let time = a["time"]?.stringValue ?? ""
            let parts = time.split(separator: ":").compactMap { Int($0) }
            let timed = parts.count == 2 && time.range(of: #"^\d{1,2}:\d{2}$"#, options: .regularExpression) != nil
            let title = a["title"]?.stringValue ?? ""
            let loc = a["location"]?["label"]?.stringValue ?? ""
            let body = (timed ? "۳ ساعت دیگر: " : "امروز: ") + (title.isEmpty ? "قرار" : title) + (loc.isEmpty ? "" : " — " + loc)
            let instant = timed ? at(d, dayOffset: 0, hour: parts[0], minute: parts[1]) : nil
            all.append(PlannedNotification(
                id: "apt-" + (a["id"]?.idString ?? ""), kind: "appointment", title: "یادآوریِ قرار", body: body,
                fireAt: instant.map { $0.addingTimeInterval(-3 * 3600) } ?? at(d, dayOffset: 0, hour: 9),
                endAt: instant ?? at(d, dayOffset: 1, hour: 0)))
        }
        let immediate = all.filter { ($0.fireAt ?? now) <= now && $0.endAt > now }.map { n -> PlannedNotification in
            var x = n; x.fireAt = nil; return x
        }
        let future = all.enumerated().filter { ($0.element.fireAt ?? now) > now }
            .sorted { a, b in a.element.fireAt! != b.element.fireAt! ? a.element.fireAt! < b.element.fireAt! : a.offset < b.offset }
            .map(\.element)
        return (immediate, Array(future.prefix(cap)))
    }
}
