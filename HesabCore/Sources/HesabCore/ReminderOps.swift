import Foundation

// Checks, people (debtors / creditors) with installments, appointments — ports of the web app:
// remCheckSaveBtn, remAnswerCheckCollected, commitCheckRowDelete/purgeCheckRefs, remPersonSaveBtn,
// remInstallSaveBtn, toggle-paid, remDeletePersonBtn, apptSubmitBtn, linkNasiyehExpense(Personal),
// and the heart of it: syncReminderExpense + reminderExpenseDesc + reminderExpenseStatus.

public struct CheckInput: Sendable {
    public var amount: Int
    public var party: String
    public var bankName: String
    public var checkNumber: String
    public var sayadId: String
    public var checkSeries: String
    public var desc: String
    public var category: String
    public var subcategory: String
    public var dueDate: JalaliDate
    public var accountId: String?          // nil = not linked, "personal" = personal ledger, else a ledger account
    public var status: String              // pending | cashed | bounced | cancelled (edit only)

    public init(amount: Int, party: String, bankName: String, checkNumber: String, sayadId: String, checkSeries: String,
                desc: String, category: String, subcategory: String, dueDate: JalaliDate, accountId: String?, status: String = "pending") {
        self.amount = amount; self.party = party; self.bankName = bankName; self.checkNumber = checkNumber; self.sayadId = sayadId
        self.checkSeries = checkSeries; self.desc = desc; self.category = category; self.subcategory = subcategory
        self.dueDate = dueDate; self.accountId = accountId; self.status = status
    }

    public var missingFields: [String] {
        var m: [String] = []
        if amount <= 0 { m.append("مبلغ") }
        if category.trimmingCharacters(in: .whitespaces).isEmpty { m.append("نوع هزینه") }
        if subcategory.trimmingCharacters(in: .whitespaces).isEmpty { m.append("زیردسته") }
        return m
    }
}

public struct InstallmentInput: Sendable {
    public var amount: Int
    public var desc: String
    public var category: String
    public var subcategory: String
    public var dueDate: JalaliDate
    public var accountId: String?

    public init(amount: Int, desc: String, category: String, subcategory: String, dueDate: JalaliDate, accountId: String?) {
        self.amount = amount; self.desc = desc; self.category = category; self.subcategory = subcategory
        self.dueDate = dueDate; self.accountId = accountId
    }
}

public struct AppointmentInput: Sendable {
    public var title: String
    public var date: JalaliDate
    public var time: String                // "HH:MM" or ""
    public var note: String
    public var kind: String                // work | personal
    public var apptType: String            // meeting | presence
    public var projectId: String?
    public var projectManualName: String
    public var place: String

    public init(title: String, date: JalaliDate, time: String, note: String, kind: String, apptType: String,
                projectId: String?, projectManualName: String, place: String) {
        self.title = title; self.date = date; self.time = time; self.note = note; self.kind = kind; self.apptType = apptType
        self.projectId = projectId; self.projectManualName = projectManualName; self.place = place
    }
}

public enum ReminderOps {

    public typealias Obj = [String: JSONValue]

    // MARK: texts (web reminderExpenseDesc)

    public static func expenseDesc(kind: String, ref: Obj, person: Obj?) -> String {
        if kind == "check" {
            let party = ref["party"]?.stringValue ?? ""
            let bank = ref["bankName"]?.stringValue ?? ""
            let numRaw = ref["checkNumber"]?.idString ?? ""
            let who = party.isEmpty ? "" : " به نام " + party
            let b = bank.isEmpty ? "" : " بانک " + bank
            let num = numRaw.isEmpty ? "چک" : "چک " + Money.persianDigits(numRaw)
            let base = num + b + who
            return ref["status"]?.stringValue == "cashed" ? base + " — وصول شد" : base + " — در انتظار وصول"
        }
        let name = person?["name"]?.stringValue ?? ""
        let d = ref["description"]?.stringValue ?? ""
        let due = ImportAnalyzer.isValidDate(ref["dueDate"]) || ref["dueDate"]?.objectValue != nil
            ? " — سررسید " + BackupExporter.formatJalali(ImportAnalyzer.date(ref["dueDate"])) : ""
        let base = "بدهی به " + name + (d.isEmpty ? "" : " (" + d + ")") + due
        return (ref["paid"]?.isTruthy ?? false) ? base + " — پرداخت شد" : base + " — در انتظار پرداخت"
    }

    static func expenseStatus(kind: String, ref: Obj) -> String {
        if kind == "check" {
            switch ref["status"]?.stringValue {
            case "cashed": return "resolved"
            case "pending": return "pending"
            default: return "drop"
            }
        }
        return (ref["paid"]?.isTruthy ?? false) ? "resolved" : "pending"
    }

    // MARK: linked ledger row (web syncReminderExpense — idempotent)

    static func removeLinked(_ ref: inout Obj, _ st: inout [String: JSONValue]) {
        guard let lid = ref["linkedExpenseId"]?.idString else { return }
        for key in ["expenses", "personalExpenses"] {
            st[key] = .array(LedgerOps.array(st, key).filter { $0["id"]?.idString != lid })
        }
        ref["linkedExpenseId"] = .null
    }

    static func sync(kind: String, ref: inout Obj, person: Obj?, st: inout [String: JSONValue], now: Int, ids: IdSource, today: JalaliDate) {
        if kind == "debt" && person?["type"]?.stringValue != "creditor" { removeLinked(&ref, &st); return }
        guard let accountId = ref["accountId"]?.idString else { removeLinked(&ref, &st); return }
        let status = expenseStatus(kind: kind, ref: ref)
        if status == "drop" { removeLinked(&ref, &st); return }
        let desc = expenseDesc(kind: kind, ref: ref, person: person)
        let category = ref["category"]?.stringValue ?? ""
        let subcategory = ref["subcategory"]?.stringValue ?? ""
        let meta: JSONValue = kind == "check"
            ? .object(["kind": .string(kind), "status": .string(status), "checkId": ref["id"] ?? .null])
            : .object(["kind": .string(kind), "status": .string(status), "personId": person?["id"] ?? .null, "installId": ref["id"] ?? .null])
        let targetKey = accountId == "personal" ? "personalExpenses" : "expenses"
        let amount = ref["amount"] ?? .int(0)

        // existing linked row, in whichever list it is
        var existing: Obj?
        var existingKey: String?
        if let lid = ref["linkedExpenseId"]?.idString {
            for key in ["expenses", "personalExpenses"] {
                if let row = LedgerOps.array(st, key).first(where: { $0["id"]?.idString == lid })?.objectValue {
                    existing = row; existingKey = key; break
                }
            }
        }
        if var row = existing, existingKey == targetKey {
            row["desc"] = .string(desc); row["toman"] = amount; row["accountId"] = .string(accountId)
            row["category"] = .string(category); row["subcategory"] = .string(subcategory)
            if kind != "debt" { row["date"] = ref["dueDate"] ?? .null }
            row["linked"] = meta
            if kind == "check" { row["payMethod"] = .string("check") }
            let rid = row["id"]?.idString
            st[targetKey] = .array(LedgerOps.array(st, targetKey).map { $0["id"]?.idString == rid ? .object(row) : $0 })
            return
        }
        let carryDate: JSONValue = existing?["date"] ?? (kind == "debt" ? LedgerOps.date(today) : (ref["dueDate"] ?? .null))
        if let old = existing, let oldKey = existingKey {
            let oid = old["id"]?.idString
            st[oldKey] = .array(LedgerOps.array(st, oldKey).filter { $0["id"]?.idString != oid })
        }
        var exp: Obj = [
            "id": existing?["id"] ?? .string(ids.make("e", now)), "accountId": .string(accountId), "desc": .string(desc),
            "toman": amount, "date": carryDate, "ts": existing?["ts"] ?? .int(Int64(now)), "type": .string("expense"),
            "category": .string(category), "subcategory": .string(subcategory), "linked": meta
        ]
        if kind == "check" { exp["payMethod"] = .string("check") }
        var list = LedgerOps.array(st, targetKey)
        list.append(.object(exp))
        st[targetKey] = .array(list)
        ref["linkedExpenseId"] = exp["id"]
    }

    // MARK: checks

    public static func saveCheck(_ state: [String: JSONValue], editingId: String?, _ input: CheckInput,
                                 ids: IdSource = .system, today: JalaliDate) throws -> (state: [String: JSONValue], id: String) {
        let missing = input.missingFields
        guard missing.isEmpty else { throw LedgerError.invalid(missing) }
        var st = state
        LedgerOps.addCategoryIfNew(&st, list: "ledgerCategories", input.category)
        LedgerOps.addSubcategoryIfNew(&st, map: "ledgerSubcategories", category: input.category, input.subcategory)
        let now = ids.nowMs()
        var checks = LedgerOps.array(st, "reminderChecks")
        var c: Obj
        var index: Int?
        if let id = editingId {
            guard let i = checks.firstIndex(where: { $0["id"]?.idString == id }), let o = checks[i].objectValue else { throw LedgerError.notFound }
            c = o; index = i
            if input.status != (c["status"]?.stringValue ?? "pending") {
                c["status"] = .string(input.status); c["statusChangedTs"] = .int(Int64(now))
            }
        } else {
            c = ["id": .string(ids.make("c", now).dropLast(1).description), "status": .string("pending"), "statusChangedTs": .null,
                 "calendarAdded": .bool(false), "calendarEventId": .null, "calendarSeq": .int(0), "linkedExpenseId": .null,
                 "muted": .bool(false), "partyNationalCode": .string(""), "partyId": .null, "cardId": .null,
                 // web mcStampCheck (single check)
                 "direction": .string("pay"), "sourceKind": .string(input.accountId == "personal" ? "personal" : "expense"),
                 "createdTs": .int(Int64(now)), "groupId": .null, "groupIndex": .int(1), "groupCount": .int(1), "groupTotal": .null]
        }
        c["amount"] = .int(Int64(input.amount)); c["party"] = .string(input.party); c["bankName"] = .string(input.bankName)
        c["checkSeries"] = .string(input.checkSeries); c["checkNumber"] = .string(input.checkNumber); c["sayadId"] = .string(input.sayadId)
        c["description"] = .string(input.desc); c["category"] = .string(input.category); c["subcategory"] = .string(input.subcategory)
        c["dueDate"] = LedgerOps.date(input.dueDate)
        c["accountId"] = input.accountId.map { .string($0) } ?? .null
        sync(kind: "check", ref: &c, person: nil, st: &st, now: now, ids: ids, today: today)
        applyTankhahCashedNote(c, &st)
        checks = LedgerOps.array(st, "reminderChecks")
        if let i = index { checks[i] = .object(c) } else { checks.append(.object(c)) }
        st["reminderChecks"] = .array(checks)
        return (st, c["id"]?.idString ?? "")
    }

    /// web remAnswerCheckCollected(c, true) and the status menu
    public static func setCheckStatus(_ state: [String: JSONValue], id: String, status: String,
                                      ids: IdSource = .system, today: JalaliDate) throws -> [String: JSONValue] {
        var st = state
        var checks = LedgerOps.array(st, "reminderChecks")
        guard let i = checks.firstIndex(where: { $0["id"]?.idString == id }), var c = checks[i].objectValue else { throw LedgerError.notFound }
        let now = ids.nowMs()
        c["status"] = .string(status); c["statusChangedTs"] = .int(Int64(now))
        if status == "cashed" {
            c["collectAnswer"] = .string("yes"); c["collectAnswerTs"] = .int(Int64(now))
            let d = ImportAnalyzer.date(c["dueDate"])
            c["collectAnswerDue"] = .string("\(d.jy)-\(d.jm)-\(d.jd)")
            c["notifiedFor"] = .null
        }
        sync(kind: "check", ref: &c, person: nil, st: &st, now: now, ids: ids, today: today)
        applyTankhahCashedNote(c, &st)
        checks = LedgerOps.array(st, "reminderChecks")
        checks[i] = .object(c)
        st["reminderChecks"] = .array(checks)
        return st
    }

    /// web commitCheckRowDelete: the check, its linked row (either list) and references from tankhah rows.
    public static func deleteCheck(_ state: [String: JSONValue], id: String) throws -> [String: JSONValue] {
        var st = state
        let checks = LedgerOps.array(st, "reminderChecks")
        guard let c = checks.first(where: { $0["id"]?.idString == id }) else { throw LedgerError.notFound }
        if let lid = c["linkedExpenseId"]?.idString {
            for key in ["expenses", "personalExpenses"] { st[key] = .array(LedgerOps.array(st, key).filter { $0["id"]?.idString != lid }) }
        }
        st["reminderChecks"] = .array(checks.filter { $0["id"]?.idString != id })
        // purgeCheckRefs
        st["expenses"] = .array(LedgerOps.array(st, "expenses").map { e in
            guard e["type"]?.stringValue == "tankhah", var o = e.objectValue else { return e }
            if var ids = o["checkIds"]?.arrayValue {
                ids = ids.filter { $0.idString != id }
                if ids.count < 2 { o.removeValue(forKey: "checkIds") } else { o["checkIds"] = .array(ids) }
            }
            if o["checkId"]?.idString == id {
                if let first = o["checkIds"]?.arrayValue?.first { o["checkId"] = first } else { o.removeValue(forKey: "checkId") }
            }
            return .object(o)
        })
        return st
    }

    /// web remApplyTankhahCashedNote
    static func applyTankhahCashedNote(_ c: Obj, _ st: inout [String: JSONValue]) {
        guard let cid = c["id"]?.idString else { return }
        st["expenses"] = .array(LedgerOps.array(st, "expenses").map { e in
            guard e["type"]?.stringValue == "tankhah", var row = e.objectValue else { return e }
            let ids = row["checkIds"]?.arrayValue?.compactMap(\.idString) ?? []
            guard row["checkId"]?.idString == cid || ids.contains(cid) else { return e }
            let multi = ids.count > 1
            let ident = NotificationPlanner.checkIdent(.object(c))
            let groupIndex = Money.persianDigits(c["groupIndex"]?.intValue ?? 1)
            let noteText = multi ? "چک " + (ident.isEmpty ? groupIndex : ident) + " وصول شد" : "وصول شد"
            let note = " — " + noteText
            let desc = row["desc"]?.stringValue ?? ""
            let has = desc.hasSuffix(note) || desc == noteText
            if c["status"]?.stringValue == "cashed" && !has {
                row["desc"] = .string(desc.isEmpty ? noteText : desc + note)
            } else if c["status"]?.stringValue != "cashed" && has {
                row["desc"] = .string(desc == noteText ? "" : String(desc.dropLast(note.count)))
            }
            return .object(row)
        })
    }

    // MARK: people and installments

    public static func addPerson(_ state: [String: JSONValue], name: String, creditor: Bool, partyId: String?,
                                 ids: IdSource = .system) throws -> (state: [String: JSONValue], id: String) {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { throw LedgerError.invalid(["نام"]) }
        var st = state
        let now = ids.nowMs()
        var pid = partyId
        if pid == nil {   // keep the central party registry in step (web registers people there)
            var parties = LedgerOps.array(st, "parties")
            if let found = parties.first(where: { ($0["fullName"]?.stringValue ?? "").trimmingCharacters(in: .whitespaces) == n }) {
                pid = found["id"]?.idString
            } else {
                let id = ids.make("party", now).dropLast(1).description
                parties.append(.object(["id": .string(id), "fullName": .string(n), "nationalCode": .string(""), "mobile": .string(""),
                                        "cardNumber": .string(""), "accountNumber": .string(""), "iban": .string(""),
                                        "bankName": .string(""), "createdAt": .int(Int64(now))]))
                st["parties"] = .array(parties)
                pid = id
            }
        }
        let id = ids.make("p", now).dropLast(1).description
        var persons = LedgerOps.array(st, "reminderPersons")
        persons.append(.object(["id": .string(id), "name": .string(n), "partyId": pid.map { .string($0) } ?? .null,
                                "type": .string(creditor ? "creditor" : "debtor"), "installments": .array([])]))
        st["reminderPersons"] = .array(persons)
        return (st, id)
    }

    /// web remDeletePersonBtn: linked rows of its installments go too.
    public static func deletePerson(_ state: [String: JSONValue], id: String) throws -> [String: JSONValue] {
        var st = state
        let persons = LedgerOps.array(st, "reminderPersons")
        guard let p = persons.first(where: { $0["id"]?.idString == id }) else { throw LedgerError.notFound }
        for i in p["installments"]?.arrayValue ?? [] {
            if var o = i.objectValue { removeLinked(&o, &st) }
        }
        st["reminderPersons"] = .array(persons.filter { $0["id"]?.idString != id })
        return st
    }

    public static func saveInstallment(_ state: [String: JSONValue], personId: String, editingId: String?, _ input: InstallmentInput,
                                       ids: IdSource = .system, today: JalaliDate) throws -> [String: JSONValue] {
        guard input.amount > 0 else { throw LedgerError.invalid(["مبلغ"]) }
        var st = state
        var persons = LedgerOps.array(st, "reminderPersons")
        guard let pi = persons.firstIndex(where: { $0["id"]?.idString == personId }), var person = persons[pi].objectValue else { throw LedgerError.notFound }
        if person["type"]?.stringValue == "creditor" {
            var m: [String] = []
            if input.category.trimmingCharacters(in: .whitespaces).isEmpty { m.append("نوع هزینه") }
            if input.subcategory.trimmingCharacters(in: .whitespaces).isEmpty { m.append("زیردسته") }
            guard m.isEmpty else { throw LedgerError.invalid(m) }
        }
        LedgerOps.addCategoryIfNew(&st, list: "ledgerCategories", input.category)
        LedgerOps.addSubcategoryIfNew(&st, map: "ledgerSubcategories", category: input.category, input.subcategory)
        let now = ids.nowMs()
        var list = person["installments"]?.arrayValue ?? []
        var inst: Obj
        var index: Int?
        if let eid = editingId {
            guard let k = list.firstIndex(where: { $0["id"]?.idString == eid }), let o = list[k].objectValue else { throw LedgerError.notFound }
            inst = o; index = k
        } else {
            inst = ["id": .string(ids.make("i", now).dropLast(1).description), "paid": .bool(false), "paidDate": .null,
                    "linkedExpenseId": .null, "muted": .bool(false)]
        }
        inst["amount"] = .int(Int64(input.amount)); inst["description"] = .string(input.desc)
        inst["category"] = .string(input.category); inst["subcategory"] = .string(input.subcategory)
        inst["dueDate"] = LedgerOps.date(input.dueDate)
        inst["accountId"] = input.accountId.map { .string($0) } ?? .null
        sync(kind: "debt", ref: &inst, person: person, st: &st, now: now, ids: ids, today: today)
        if let k = index { list[k] = .object(inst) } else { list.append(.object(inst)) }
        person["installments"] = .array(list)
        persons = LedgerOps.array(st, "reminderPersons")
        persons[pi] = .object(person)
        st["reminderPersons"] = .array(persons)
        return st
    }

    /// web toggle-paid
    public static func toggleInstallmentPaid(_ state: [String: JSONValue], personId: String, installmentId: String,
                                             ids: IdSource = .system, today: JalaliDate) throws -> [String: JSONValue] {
        try updateInstallment(state, personId: personId, installmentId: installmentId, ids: ids, today: today) { inst in
            let paid = !(inst["paid"]?.isTruthy ?? false)
            inst["paid"] = .bool(paid)
            inst["paidDate"] = paid ? LedgerOps.date(today) : .null
        }
    }

    public static func deleteInstallment(_ state: [String: JSONValue], personId: String, installmentId: String) throws -> [String: JSONValue] {
        var st = state
        var persons = LedgerOps.array(st, "reminderPersons")
        guard let pi = persons.firstIndex(where: { $0["id"]?.idString == personId }), var person = persons[pi].objectValue else { throw LedgerError.notFound }
        var list = person["installments"]?.arrayValue ?? []
        guard let k = list.firstIndex(where: { $0["id"]?.idString == installmentId }), var inst = list[k].objectValue else { throw LedgerError.notFound }
        removeLinked(&inst, &st)
        list.remove(at: k)
        person["installments"] = .array(list)
        persons = LedgerOps.array(st, "reminderPersons")
        persons[pi] = .object(person)
        st["reminderPersons"] = .array(persons)
        return st
    }

    static func updateInstallment(_ state: [String: JSONValue], personId: String, installmentId: String, ids: IdSource,
                                  today: JalaliDate, _ change: (inout Obj) -> Void) throws -> [String: JSONValue] {
        var st = state
        var persons = LedgerOps.array(st, "reminderPersons")
        guard let pi = persons.firstIndex(where: { $0["id"]?.idString == personId }), var person = persons[pi].objectValue else { throw LedgerError.notFound }
        var list = person["installments"]?.arrayValue ?? []
        guard let k = list.firstIndex(where: { $0["id"]?.idString == installmentId }), var inst = list[k].objectValue else { throw LedgerError.notFound }
        change(&inst)
        sync(kind: "debt", ref: &inst, person: person, st: &st, now: ids.nowMs(), ids: ids, today: today)
        list[k] = .object(inst)
        person["installments"] = .array(list)
        persons = LedgerOps.array(st, "reminderPersons")
        persons[pi] = .object(person)
        st["reminderPersons"] = .array(persons)
        return st
    }

    // MARK: nasiyeh (web linkNasiyehExpense / linkNasiyehExpensePersonal)

    /// Adds a ledger (or personal) row paid "on credit": the creditor person is found by name or created,
    /// an installment is added, and the row becomes a linked debt row.
    public static func addNasiyehRow(_ state: [String: JSONValue], listKey: String, row: Obj, partyName: String,
                                     dueDate: JalaliDate?, ids: IdSource = .system) throws -> [String: JSONValue] {
        let name = partyName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { throw LedgerError.invalid(["طرف نسیه"]) }
        var st = state
        var exp = row
        let now = ids.nowMs()
        var persons = LedgerOps.array(st, "reminderPersons")
        var pi = persons.firstIndex { $0["type"]?.stringValue == "creditor" && $0["name"]?.stringValue == name }
        if pi == nil {
            persons.append(.object(["id": .string(ids.make("p", now).dropLast(1).description), "name": .string(name),
                                    "type": .string("creditor"), "installments": .array([])]))
            pi = persons.count - 1
        }
        guard let index = pi, var person = persons[index].objectValue else { throw LedgerError.notFound }
        let personal = listKey == "personalExpenses"
        let inst: Obj = [
            "id": .string(ids.make("i", now).dropLast(1).description), "amount": exp["toman"] ?? .int(0),
            "description": exp["desc"] ?? .string(""), "category": .string(exp["category"]?.stringValue ?? ""),
            "subcategory": .string(personal ? "" : (exp["subcategory"]?.stringValue ?? "")),
            "dueDate": dueDate.map { LedgerOps.date($0) } ?? (exp["date"] ?? .null), "paid": .bool(false), "paidDate": .null,
            "accountId": personal ? .string("personal") : (exp["accountId"] ?? .null), "linkedExpenseId": exp["id"] ?? .null,
            "muted": .bool(false)
        ]
        var list = person["installments"]?.arrayValue ?? []
        list.append(.object(inst))
        person["installments"] = .array(list)
        persons[index] = .object(person)
        st["reminderPersons"] = .array(persons)
        exp["linked"] = .object(["kind": .string("debt"), "status": .string("pending"), "personId": person["id"] ?? .null, "installId": inst["id"] ?? .null])
        exp["desc"] = .string(expenseDesc(kind: "debt", ref: inst, person: person))
        var rows = LedgerOps.array(st, listKey)
        rows.append(.object(exp))
        st[listKey] = .array(rows)
        return st
    }

    /// The row just added by addExpense / addPersonal becomes a nasiyeh row (web: the form pushes, then links).
    public static func linkLastRowAsNasiyeh(_ state: [String: JSONValue], listKey: String, partyName: String,
                                            dueDate: JalaliDate?, ids: IdSource = .system) throws -> [String: JSONValue] {
        var st = state
        var rows = LedgerOps.array(st, listKey)
        guard let last = rows.popLast()?.objectValue else { throw LedgerError.notFound }
        st[listKey] = .array(rows)
        return try addNasiyehRow(st, listKey: listKey, row: last, partyName: partyName, dueDate: dueDate, ids: ids)
    }

    // MARK: appointments (web apptSubmitBtn)

    public static func saveAppointment(_ state: [String: JSONValue], editingId: String?, _ input: AppointmentInput,
                                       ids: IdSource = .system) throws -> [String: JSONValue] {
        let title = input.title.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { throw LedgerError.invalid(["عنوان"]) }
        var st = state
        var list = LedgerOps.array(st, "appointments")
        var a: Obj
        var index: Int?
        if let id = editingId {
            guard let i = list.firstIndex(where: { $0["id"]?.idString == id }), let o = list[i].objectValue else { throw LedgerError.notFound }
            a = o; index = i
        } else {
            a = ["id": .string(ids.make("apt", ids.nowMs()).dropLast(1).description), "done": .bool(false), "calendarAdded": .bool(false),
                 "calendarEventId": .null, "calendarSeq": .int(0)]
        }
        let work = input.kind == "work"
        a["title"] = .string(title); a["date"] = LedgerOps.date(input.date); a["time"] = .string(input.time); a["note"] = .string(input.note)
        a["kind"] = .string(input.kind); a["apptType"] = .string(input.apptType)
        a["projectId"] = work ? (input.projectId.map { .string($0) } ?? .null) : .null
        a["projectManualName"] = .string(work && input.projectId == nil ? input.projectManualName : "")
        a["location"] = .object(["label": .string(input.place), "lat": .null, "lng": .null])
        if let i = index { list[i] = .object(a) } else { list.append(.object(a)) }
        st["appointments"] = .array(list)
        return st
    }

    public static func toggleAppointmentDone(_ state: [String: JSONValue], id: String) throws -> [String: JSONValue] {
        var st = state
        var list = LedgerOps.array(st, "appointments")
        guard let i = list.firstIndex(where: { $0["id"]?.idString == id }), var a = list[i].objectValue else { throw LedgerError.notFound }
        a["done"] = .bool(!(a["done"]?.isTruthy ?? false))
        list[i] = .object(a)
        st["appointments"] = .array(list)
        return st
    }

    public static func deleteAppointment(_ state: [String: JSONValue], id: String) throws -> [String: JSONValue] {
        var st = state
        let list = LedgerOps.array(st, "appointments")
        guard list.contains(where: { $0["id"]?.idString == id }) else { throw LedgerError.notFound }
        st["appointments"] = .array(list.filter { $0["id"]?.idString != id })
        return st
    }
}
