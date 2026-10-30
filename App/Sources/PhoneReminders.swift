import Foundation
import EventKit
import HesabCore

/// iOS version of the web «به Reminders گوشی اضافه بشه؟» flow (web builds a VTODO .ics; here EventKit adds the
/// same item straight into the Reminders app). Same titles, notes and alert times as the web:
///   check: 2 days before at 21:00, the day before at 21:00, the day itself at 00:00
///   appointment: the day before at 21:00, the day itself at 00:00
///   installment: the day before at 15:00 (web default -P0DT9H)
/// A check/appointment that was added before is updated in place (web reuses UID + SEQUENCE).
enum PhoneReminders {
    static let store = EKEventStore()

    static func access() async -> Bool {
        do { return try await store.requestFullAccessToReminders() } catch { return false }
    }

    static func midnight(_ j: JalaliDate) -> Date { Calendar.current.startOfDay(for: Fmt.date(j)) }  // Fmt.date is noon

    static func longDate(_ d: JalaliDate) -> String {
        Money.persianDigits(String(d.jd)) + " " + BackupExporter.months[d.jm - 1] + " " + Money.persianDigits(String(d.jy))
    }

    /// Adds or updates; returns the reminder identifier.
    static func save(existingId: String?, title: String, notes: String, due: JalaliDate, alarmOffsets: [TimeInterval]) throws -> String {
        let r: EKReminder
        if let id = existingId, let found = store.calendarItem(withIdentifier: id) as? EKReminder {
            r = found
        } else {
            r = EKReminder(eventStore: store)
            guard let cal = store.defaultCalendarForNewReminders() else { throw LedgerError.message("لیست پیش‌فرض Reminders پیدا نشد.") }
            r.calendar = cal
        }
        r.title = title
        r.notes = notes
        let g = Jalali.toGregorian(due)
        r.dueDateComponents = DateComponents(calendar: Calendar(identifier: .gregorian), year: g.gy, month: g.gm, day: g.gd)
        r.alarms?.forEach { r.removeAlarm($0) }
        let base = midnight(due)
        for o in alarmOffsets { r.addAlarm(EKAlarm(absoluteDate: base.addingTimeInterval(o))) }
        try store.save(r, commit: true)
        return r.calendarItemIdentifier
    }
}

extension AppModel {
    private func object(_ key: String, _ id: String) -> [String: JSONValue]? { record(key, id)?.objectValue }

    /// web promptCheckCalendarAdd
    func addCheckToPhoneReminders(_ id: String) async {
        guard let c = object("reminderChecks", id) else { return }
        guard await PhoneReminders.access() else { errorMessage = Self.remindersDenied; return }
        let number = c["checkNumber"]?.idString ?? ""
        let party = c["party"]?.stringValue ?? ""
        let title = "چک " + number + (party.isEmpty ? "" : " - " + party)
        let due = ImportAnalyzer.date(c["dueDate"])
        var lines = ["شماره چک: " + (number.isEmpty ? "-" : number),
                     "مبلغ: " + Money.format(c["amount"]?.intValue ?? 0) + " تومان",
                     "طرف حساب: " + (party.isEmpty ? "-" : party)]
        if let b = c["bankName"]?.stringValue, !b.isEmpty { lines.append("نام بانک: " + b) }
        if let d = c["description"]?.stringValue, !d.isEmpty { lines.append("توضیحات: " + d) }
        lines.append("تاریخ سررسید: " + PhoneReminders.longDate(due))
        do {
            let rid = try PhoneReminders.save(existingId: c["calendarEventId"]?.stringValue, title: title, notes: lines.joined(separator: "\n"),
                                              due: due, alarmOffsets: [-(27 * 3600), -(3 * 3600), 0])
            markCalendarAdded(listKey: "reminderChecks", id: id, eventId: rid)
            Haptics.success()
        } catch { errorMessage = "افزودن به Reminders نشد: " + error.localizedDescription }
    }

    /// web promptAppointmentCalendarAdd
    func addAppointmentToPhoneReminders(_ id: String) async {
        guard let a = object("appointments", id) else { return }
        guard await PhoneReminders.access() else { errorMessage = Self.remindersDenied; return }
        let type = a["apptType"]?.stringValue == "presence" ? "قرار حضور" : "قرار ملاقات"
        let time = a["time"]?.stringValue ?? ""
        let t = a["title"]?.stringValue ?? ""
        let title = type + ": " + (t.isEmpty ? "بدون عنوان" : t) + (time.isEmpty ? "" : " — ساعت " + time)
        var lines: [String] = []
        if !time.isEmpty { lines.append("ساعت: " + time) }
        if a["kind"]?.stringValue == "work" {
            let pid = a["projectId"]?.idString
            let pn = accounts.first { $0.id == pid && pid != nil }?.name ?? (a["projectManualName"]?.stringValue ?? "")
            if !pn.isEmpty { lines.append("پروژه: " + pn) }
        }
        if let loc = a["location"]?.objectValue, (!(loc["label"]?.stringValue ?? "").isEmpty || loc["lat"]?.doubleValue != nil) {
            let label = loc["label"]?.stringValue ?? ""
            lines.append("لوکیشن: " + (label.isEmpty ? "\(loc["lat"]?.doubleValue ?? 0), \(loc["lng"]?.doubleValue ?? 0)" : label))
        }
        if let n = a["note"]?.stringValue, !n.isEmpty { lines.append("توضیحات: " + n) }
        let due = ImportAnalyzer.date(a["date"])
        lines.append("تاریخ: " + PhoneReminders.longDate(due))
        do {
            let rid = try PhoneReminders.save(existingId: a["calendarEventId"]?.stringValue, title: title, notes: lines.joined(separator: "\n"),
                                              due: due, alarmOffsets: [-(27 * 3600), 0])
            markCalendarAdded(listKey: "appointments", id: id, eventId: rid)
            Haptics.success()
        } catch { errorMessage = "افزودن به Reminders نشد: " + error.localizedDescription }
    }

    /// web: installment save → promptAddToCalendar (no update tracking on the web either)
    func addInstallmentToPhoneReminders(personId: String, id: String) async {
        guard let p = object("reminderPersons", personId),
              let i = p["installments"]?.arrayValue?.first(where: { $0["id"]?.idString == id }) else { return }
        guard await PhoneReminders.access() else { errorMessage = Self.remindersDenied; return }
        let name = p["name"]?.stringValue ?? ""
        let desc = i["description"]?.stringValue ?? ""
        let title = "قسط " + name + (desc.isEmpty ? "" : " — " + desc)
        do {
            _ = try PhoneReminders.save(existingId: nil, title: title, notes: "مبلغ: " + Money.format(i["amount"]?.intValue ?? 0) + " تومان",
                                        due: ImportAnalyzer.date(i["dueDate"]), alarmOffsets: [-(9 * 3600)])
            Haptics.success()
        } catch { errorMessage = "افزودن به Reminders نشد: " + error.localizedDescription }
    }

    static let remindersDenied = "اجازه‌ی دسترسی به Reminders داده نشده. از Settings › دفتر حساب › Reminders روشنش کنید."

    private func markCalendarAdded(listKey: String, id: String, eventId: String) {
        _ = change {
            var st = state
            var list = st[listKey]?.arrayValue ?? []
            guard let i = list.firstIndex(where: { $0["id"]?.idString == id }), var o = list[i].objectValue else { throw LedgerError.notFound }
            let was = o["calendarAdded"]?.isTruthy ?? false
            o["calendarAdded"] = .bool(true)
            o["calendarEventId"] = .string(eventId)
            o["calendarSeq"] = .int(Int64(was ? (o["calendarSeq"]?.intValue ?? 0) + 1 : 0))
            list[i] = .object(o)
            st[listKey] = .array(list)
            return st
        }
    }
}
