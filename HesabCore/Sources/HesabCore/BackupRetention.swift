import Foundation

// Backup retention (owner-approved policy, 2026-11-25).
//
//   end of day      «پشتیبان-کامل-اپ - ۱۴۰۵-۹-۴.json»          last 14 days (iCloud: 60) + one per week for 8 weeks
//                                                                + one per month for 12 months
//   start of day    «شروع-روز - ۱۴۰۵-۹-۴.json»                 last 14 days
//   before restore  «قبل-از-بازگردانی - ۱۴۰۵-۹-۴ - ۱۴۳۰۰۵.json»   newest 10, a pool of its own
//   raw database    «قبل-از-بازگردانی - … .sqlite»              never removed automatically
//   anything else   (a file the person put there, a sidecar, …) never touched
//
// Safety rules, all enforced here (pure function, no file access):
//   • only names that match the patterns exactly, with a valid Jalali date, can ever be removed
//   • dates come from the name, never from file timestamps
//   • nothing is removed unless the newest end-of-day backup is healthy (SHA-256 sidecar matches)
//   • a file that is not healthy (no sidecar, mismatch, older format) is never removed: suspicious stays
//   • a week / month keeps its newest *healthy* backup; with none healthy it keeps all of them
//   • today and yesterday are never removed
//   • a file dated after "today" means the device clock is wrong: nothing is removed
//   • at most `maxRemovalsPerRun` files per run, oldest first (removal is a move to the trash folder anyway)

public enum BackupKind: String, Equatable, Sendable {
    case endOfDay, startOfDay, beforeRestore, rawDatabase
}

public struct BackupName: Equatable, Sendable {
    public var kind: BackupKind
    public var date: JalaliDate
    public var time: Int             // hhmmss for before-restore files, 0 otherwise
    public var fileName: String
}

public enum BackupNames {
    public static let endOfDayPrefix = "پشتیبان-کامل-اپ - "
    public static let startOfDayPrefix = "شروع-روز - "
    public static let beforeRestorePrefix = "قبل-از-بازگردانی - "
    public static let sidecarExtension = "sha256"

    static func day(_ d: JalaliDate) -> String { Money.persianDigits("\(d.jy)-\(d.jm)-\(d.jd)") }

    public static func endOfDay(_ d: JalaliDate) -> String { endOfDayPrefix + day(d) + ".json" }
    public static func startOfDay(_ d: JalaliDate) -> String { startOfDayPrefix + day(d) + ".json" }
    public static func beforeRestore(_ d: JalaliDate, hhmmss: Int, ext: String = "json") -> String {
        beforeRestorePrefix + day(d) + " - " + Money.persianDigits(String(format: "%06d", hhmmss)) + "." + ext
    }

    public static func isValid(_ d: JalaliDate) -> Bool {
        d.jy >= 1300 && d.jy <= 1600 && (1...12).contains(d.jm) && d.jd >= 1 && d.jd <= Jalali.monthLength(d.jy, d.jm)
    }

    private static let datePart = "([0-9]{3,4})-([0-9]{1,2})-([0-9]{1,2})"
    private static let patterns: [(BackupKind?, NSRegularExpression)] = [
        (.endOfDay, try! NSRegularExpression(pattern: "^" + NSRegularExpression.escapedPattern(for: endOfDayPrefix) + datePart + "\\.json$")),
        (.startOfDay, try! NSRegularExpression(pattern: "^" + NSRegularExpression.escapedPattern(for: startOfDayPrefix) + datePart + "\\.json$")),
        (nil, try! NSRegularExpression(pattern: "^" + NSRegularExpression.escapedPattern(for: beforeRestorePrefix) + datePart
                                       + " - ([0-9]{6})\\.(json|sqlite)$")),
    ]

    /// The backup a file name stands for, or nil for any other file (those are never touched).
    public static func parse(_ fileName: String) -> BackupName? {
        let latin = SearchEngine.latinDigits(fileName)
        let ns = latin as NSString
        for (kind, re) in patterns {
            guard let m = re.firstMatch(in: latin, range: NSRange(location: 0, length: ns.length)) else { continue }
            func n(_ i: Int) -> Int { Int(ns.substring(with: m.range(at: i))) ?? 0 }
            let d = JalaliDate(jy: n(1), jm: n(2), jd: n(3))
            guard isValid(d) else { return nil }
            if let kind { return BackupName(kind: kind, date: d, time: 0, fileName: fileName) }
            let ext = ns.substring(with: m.range(at: 5))
            return BackupName(kind: ext == "sqlite" ? .rawDatabase : .beforeRestore, date: d, time: n(4), fileName: fileName)
        }
        return nil
    }
}

public struct BackupRetentionPolicy: Equatable, Sendable {
    public var endOfDayDays: Int
    public var weeks: Int
    public var months: Int
    public var startOfDayDays: Int
    public var beforeRestoreKeep: Int
    public var maxRemovalsPerRun: Int

    public init(endOfDayDays: Int, weeks: Int, months: Int, startOfDayDays: Int, beforeRestoreKeep: Int, maxRemovalsPerRun: Int) {
        self.endOfDayDays = endOfDayDays; self.weeks = weeks; self.months = months
        self.startOfDayDays = startOfDayDays; self.beforeRestoreKeep = beforeRestoreKeep; self.maxRemovalsPerRun = maxRemovalsPerRun
    }

    public static let local = BackupRetentionPolicy(endOfDayDays: 14, weeks: 8, months: 12, startOfDayDays: 14,
                                                    beforeRestoreKeep: 10, maxRemovalsPerRun: 5)
    /// iCloud keeps 60 days of end-of-day files (as before) on top of the weekly / monthly ones
    public static let iCloud = BackupRetentionPolicy(endOfDayDays: 60, weeks: 8, months: 12, startOfDayDays: 14,
                                                     beforeRestoreKeep: 10, maxRemovalsPerRun: 5)
}

public struct RetentionPlan: Equatable, Sendable {
    public var remove: [String]
    /// why nothing was removed, when a safety rule stopped the run
    public var skipped: String?
}

public enum BackupRetention {
    static func dayNumber(_ d: JalaliDate) -> Int { Jalali.j2d(d.jy, d.jm, d.jd) }

    /// first day (day number) of the Saturday–Friday week holding `d`
    static func weekStart(_ d: JalaliDate) -> Int {
        let g = Jalali.toGregorian(d)
        return dayNumber(d) - Jalali.weekdaySat0(g.gy, g.gm, g.gd)
    }

    public static func plan(names: [String], today: JalaliDate, policy: BackupRetentionPolicy,
                            isHealthy: (String) -> Bool) -> RetentionPlan {
        guard BackupNames.isValid(today) else { return RetentionPlan(remove: [], skipped: "invalid date") }
        let parsed = names.compactMap(BackupNames.parse)
        let todayN = dayNumber(today)
        if parsed.contains(where: { dayNumber($0.date) > todayN }) {
            return RetentionPlan(remove: [], skipped: "clock: a backup is dated after today")
        }
        var healthCache: [String: Bool] = [:]
        func healthy(_ n: String) -> Bool {
            if let h = healthCache[n] { return h }
            let h = isHealthy(n); healthCache[n] = h; return h
        }

        let ends = parsed.filter { $0.kind == .endOfDay }.sorted { $0.date > $1.date }
        guard let newest = ends.first else { return RetentionPlan(remove: [], skipped: "no end-of-day backup") }
        guard healthy(newest.fileName) else { return RetentionPlan(remove: [], skipped: "newest backup is not healthy") }

        var keep = Set<String>()
        func age(_ b: BackupName) -> Int { todayN - dayNumber(b.date) }

        // end of day: the recent days
        for b in ends where age(b) < policy.endOfDayDays || age(b) <= 1 { keep.insert(b.fileName) }
        // one per week (newest healthy), for the last `weeks` weeks
        let thisWeek = weekStart(today)
        for k in 0..<max(0, policy.weeks) {
            let ws = thisWeek - 7 * k
            let inWeek = ends.filter { weekStart($0.date) == ws }
            if let rep = inWeek.first(where: { healthy($0.fileName) }) { keep.insert(rep.fileName) }
            else { inWeek.forEach { keep.insert($0.fileName) } }
        }
        // one per month (newest healthy), for the last `months` months
        var (y, m) = (today.jy, today.jm)
        for _ in 0..<max(0, policy.months) {
            let inMonth = ends.filter { $0.date.jy == y && $0.date.jm == m }
            if let rep = inMonth.first(where: { healthy($0.fileName) }) { keep.insert(rep.fileName) }
            else { inMonth.forEach { keep.insert($0.fileName) } }
            m -= 1
            if m == 0 { m = 12; y -= 1 }
        }
        // start of day: the recent days
        for b in parsed where b.kind == .startOfDay && (age(b) < policy.startOfDayDays || age(b) <= 1) { keep.insert(b.fileName) }
        // before restore: the newest N (a pool of its own)
        let restores = parsed.filter { $0.kind == .beforeRestore }
            .sorted { ($0.date, $0.time) > ($1.date, $1.time) }
        restores.prefix(max(0, policy.beforeRestoreKeep)).forEach { keep.insert($0.fileName) }

        let candidates = parsed
            .filter { $0.kind != .rawDatabase && age($0) > 1 && !keep.contains($0.fileName) }
            .sorted { ($0.date, $0.time) < ($1.date, $1.time) }
            .filter { healthy($0.fileName) }                 // never remove a file that cannot be verified
        return RetentionPlan(remove: candidates.prefix(max(0, policy.maxRemovalsPerRun)).map(\.fileName), skipped: nil)
    }
}
