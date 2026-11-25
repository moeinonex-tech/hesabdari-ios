import SwiftUI
import HesabCore
import HesabStore

@main
struct HesabdariApp: App {
    @StateObject private var model = AppModel()

    init() {
        AppFont.configureUIKit()
        TempExports.purgeAll()      // shared files left behind by an earlier run (never backups: see TempExports)
    }

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
        }
    }
}

// MARK: - model

struct LedgerRowVM: Identifiable {
    let id: String              // list identity
    let rowId: String           // record id
    let number: Int
    let desc: String
    let dateValue: JalaliDate
    let date: String
    let toman: Int
    let kind: Kind
    let isLinked: Bool
    let category: String
    let subcategory: String
    let payMethod: String?
    let cardId: String?
    let partyId: String?
    var itemCount = 0
    enum Kind { case expense, tankhah, commission, reward }
}

struct Choice: Identifiable, Hashable {
    let id: String
    let label: String
}

struct UndoItem: Identifiable {
    let id: UUID
    let message: String
}

struct ExportFile: Identifiable {
    let id = UUID()
    let url: URL
}

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var state: [String: JSONValue] = [:] { didSet { stateVersion &+= 1 } }
    /// changes whenever `state` does (caches such as the search index are rebuilt when it moves on)
    private(set) var stateVersion = 0
    @Published private(set) var hasData = false
    @Published var pending: ImportReport?
    @Published var errorMessage: String?
    /// a confirmation the person should read (e.g. what was added to the phone's Reminders and when it will remind)
    @Published var infoMessage: String?
    @Published var lastImportText: String?

    private let store: SafeStore?
    /// set when the stored data could not be read: nothing is saved until it can (see SafeStore)
    @Published private(set) var readOnlyReason: String?
    static let readOnlyMessage = "داده‌های ذخیره‌شده خوانده نشدند. برای اینکه چیزی از دست نرود، ثبت و ویرایش قفل شد و پشتیبان‌گیری خودکار هم متوقف شد. پشتیبان‌های قبلی سالم‌اند؛ از تنظیمات › داده‌ها می‌توانید یکی را بازگردانید."

    init() {
        var opened: SafeStore?
        var openError: String?
        #if DEBUG
        // UI smoke tests (simulator, Debug builds only): start from a small synthetic state in memory
        let env = ProcessInfo.processInfo.environment
        // performance test: a synthetic 20,000-row state instead of the small one
        var clock = Date()
        var phases: [String] = []
        func phase(_ name: String) { phases.append(name + "=" + String(Int(Date().timeIntervalSince(clock) * 1000))); clock = Date() }
        let synthetic: [String: JSONValue]? = Int(env["UITEST_SYNTH"] ?? "").map { SyntheticLedger.make(rows: $0) }
        if synthetic != nil { phase("synth") }
        if let st = synthetic ?? env["UITEST_STATE"].flatMap({ $0.data(using: .utf8) })
            .flatMap({ try? JSONDecoder().decode([String: JSONValue].self, from: $0) }), let mem = try? HesabStore() {
            UserDefaults.standard.set(false, forKey: AppLock.enabledKey)      // no Face ID on the simulator
            UserDefaults.standard.set(false, forKey: "notify.enabled")
            try? mem.save(st)
            if synthetic != nil { phase("seed") }
            // a damaged database (UI test of the read-only safety)
            if ProcessInfo.processInfo.environment["UITEST_CORRUPT"] == "1" { try? mem.corruptOneRecordForTesting() }
            store = SafeStore(mem)
            reload()
            if synthetic != nil { phase("reload") }
            completePendingBackup()
            if synthetic != nil { phase("pending"); debugPerfNote = phases.joined(separator: " ") }
            if env["UITEST_MUTATE"] == "1" {      // UI test: one change, so a backup is pending
                _ = apply(state.merging(["uitestMutation": .int(Int64(Date().timeIntervalSince1970))]) { _, b in b })
                debugBackupNote += " startOfDay=\(Backups.hasStartOfDay()) pending=\(backupDebouncer.hasPending)"
            }
            return
        }
        #endif
        do {
            let url = try AppModel.databaseURL()
            opened = SafeStore(try HesabStore(path: url.path))
            try? FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: url.path)
        } catch {
            openError = "پایگاه داده باز نشد: \(error.localizedDescription)"
        }
        store = opened
        errorMessage = openError
        reload()
        completePendingBackup()
    }

    /// The app was closed while an end-of-day backup was still waiting: write it now, from the stored data.
    private func completePendingBackup() {
        let marker = UserDefaultsBackupMarker()
        guard marker.isSet else { return }
        guard hasData, readOnlyReason == nil else { return }      // never from data that could not be read
        backupToday()
        marker.isSet = false
        #if DEBUG
        debugBackupNote = "pendingCompleted"
        #endif
    }

    /// Back up the current state soon (the app became active: today's backup should exist), in the background.
    func scheduleBackup() {
        guard hasData, readOnlyReason == nil else { return }
        backupDebouncer.schedule(state)
    }

    /// The app goes to the background: write a pending backup now, with the time iOS allows for it.
    func flushPendingBackup() {
        guard backupDebouncer.hasPending else { return }
        let debouncer = backupDebouncer
        var task = UIBackgroundTaskIdentifier.invalid
        task = UIApplication.shared.beginBackgroundTask(withName: "backup") {
            UIApplication.shared.endBackgroundTask(task)
            task = .invalid
        }
        DispatchQueue.global(qos: .utility).async {
            debouncer.flush()
            DispatchQueue.main.async {
                if task != .invalid { UIApplication.shared.endBackgroundTask(task); task = .invalid }
            }
        }
    }

    static func databaseURL() throws -> URL {
        let dir = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                              appropriateFor: nil, create: true)
        return dir.appendingPathComponent("hesabdari.sqlite")
    }

    /// today's date in Iran (Asia/Tehran), whatever time zone the phone is set to
    nonisolated static var today: JalaliDate {
        let c = Fmt.gregorian.dateComponents([.year, .month, .day], from: Date())
        return Jalali.toJalali(c.year ?? 2000, c.month ?? 1, c.day ?? 1)
    }

    func reload() {
        guard let store else { return }
        undoTracker.invalidate()
        undo = nil
        if let loaded = store.load() {
            state = loaded
            readOnlyReason = nil
        } else {
            // never show "empty" and save it over the real data: read-only until the data can be read again
            state = [:]
            readOnlyReason = store.readFailure ?? "?"
            errorMessage = Self.readOnlyMessage
        }
        hasData = !store.isEmpty
        guard readOnlyReason == nil else { return }
        // commission incomes belong to «مدیریت پیمان ساختمان» (the user's rule) — one-time move of older ones
        if hasData, let migrated = LedgerOps.migrateCommissionIncomes(state) { _ = apply(migrated, undoMessage: nil) }
        if hasData { Notifier.sync(state) }
        if let last = try? store.lastImport() {
            lastImportText = last.sourceExportedAtJalali.map { "داده از پشتیبان \($0)" }
        }
    }

    // import

    func openFile(_ url: URL) {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            switch BackupParser.parse(data) {
            case .success(let parsed): pending = ImportAnalyzer.analyze(parsed)
            case .failure(let e): errorMessage = e.message
            }
        } catch {
            errorMessage = "فایل خوانده نشد: \(error.localizedDescription)"
        }
    }

    func confirmImport() {
        guard let report = pending, report.canImport, let store else { return }
        if hasData {   // safety copy of the current data before it is replaced
            do { try safetyCopy() }
            catch { errorMessage = "قبل از جایگزینی، پشتیبان از داده‌ی فعلی ساخته نشد؛ ورود انجام نشد: \(error.localizedDescription)"; return }
        }
        do {
            backupDebouncer.cancel()      // a backup of the replaced data must not land after the import
            try store.replaceAll(with: report.cleanedState, sourceExportedAtJalali: report.exportedAtJalali,
                                 reportLines: report.summaryLines + report.issues.map(\.title))
            pending = nil
            reload()
            backupToday()
        } catch {
            errorMessage = "ورود ناموفق بود و هیچ داده‌ای تغییر نکرد: \(error.localizedDescription)"
        }
    }

    /// web factoryResetAllData — a safety copy is written first; without it nothing is deleted.
    func factoryReset() -> Bool {
        guard let store else { return false }
        do { try safetyCopy() }
        catch { errorMessage = "پشتیبان ایمنی ساخته نشد؛ چیزی پاک نشد: \(error.localizedDescription)"; return false }
        do {
            backupDebouncer.cancel()
            try store.wipe()
            reload()
            lastImportText = nil
            Notifier.sync([:])
            return true
        } catch {
            errorMessage = "پاک‌سازی انجام نشد: \(error.localizedDescription)"
            return false
        }
    }

    /// The copy kept before a restore / reset replaces the data: a JSON backup, or — when the data cannot be read —
    /// the raw database file itself, so nothing is lost either way.
    private func safetyCopy() throws {
        guard let store else { throw LedgerError.notFound }
        if store.isReadOnly {
            try Backups.writeRawDatabase { try store.copyDatabase(to: $0) }
        } else {
            try Backups.write(try exportData(), reason: .beforeRestore)
        }
    }

    // export

    /// Full backup (web format v1) of what is stored right now.
    func exportData() throws -> Data {
        guard let store else { throw LedgerError.notFound }
        return try store.exportBackup(today: Self.today)
    }

    func makeExportFile() -> ExportFile? {
        guard let store else { return nil }
        do {
            let t = Self.today
            let data = try store.exportBackup(today: t)
            let name = "پشتیبان-کامل-اپ - " + Money.persianDigits("\(t.jy)-\(t.jm)-\(t.jd)") + ".json"
            return ExportFile(url: try TempExports.write(data, name: name, options: [.atomic, .completeFileProtection]))
        } catch {
            errorMessage = "خروجی ساخته نشد: \(error.localizedDescription)"
            return nil
        }
    }

    // read models

    /// Stage 3: read models are cached per state version (pure memoization — same results, rebuilt on any change).
    private var readCache = ReadCache()
    private struct ReadCache {
        var version = -1
        var accounts: [AccountImportSummary]?
        var rows: [String: [LedgerRowVM]] = [:]
    }
    private func freshCache() {
        if readCache.version != stateVersion { readCache = ReadCache(); readCache.version = stateVersion }
    }

    var accounts: [AccountImportSummary] {
        freshCache()
        if let a = readCache.accounts { return a }
        let a = computeAccounts()
        readCache.accounts = a
        return a
    }

    private func computeAccounts() -> [AccountImportSummary] {
        let expenses = state["expenses"]?.arrayValue ?? []
        return (state["accounts"]?.arrayValue ?? []).map { ImportAnalyzer.accountSummary($0, expenses: expenses) }
    }

    var personalTotal: Int { (state["personalExpenses"]?.arrayValue ?? []).reduce(0) { $0 + ImportAnalyzer.toman($1) } }
    var incomeTotal: Int { (state["incomes"]?.arrayValue ?? []).reduce(0) { $0 + ImportAnalyzer.toman($1) } }

    /// Rows of one account in the web order (date, then entry time), numbered like the web ledger.
    func rows(accountId: String) -> [LedgerRowVM] {
        freshCache()
        if let r = readCache.rows[accountId] { return r }
        let r = computeRows(accountId: accountId)
        readCache.rows[accountId] = r
        return r
    }

    private func computeRows(accountId: String) -> [LedgerRowVM] {
        let mine = (state["expenses"]?.arrayValue ?? []).filter { $0["accountId"]?.idString == accountId }
        let sorted = mine.enumerated().sorted { a, b in
            let da = ImportAnalyzer.date(a.element["date"]), db = ImportAnalyzer.date(b.element["date"])
            if da != db { return da < db }
            let ta = a.element["ts"]?.intValue ?? 0, tb = b.element["ts"]?.intValue ?? 0
            if ta != tb { return ta < tb }
            return a.offset < b.offset
        }.map(\.element)
        return sorted.enumerated().map { i, e in
            let d = ImportAnalyzer.date(e["date"])
            let kind: LedgerRowVM.Kind = e["commissionSettlementId"]?.idString != nil ? .commission
                : (e["type"]?.stringValue == "tankhah" ? .tankhah : ((e["reward"]?.isTruthy ?? false) ? .reward : .expense))
            let rid = e["id"]?.idString ?? ""
            return LedgerRowVM(id: rid + "#\(i)", rowId: rid, number: i + 1,
                               desc: e["desc"]?.stringValue ?? "", dateValue: d,
                               date: Money.persianDigits("\(d.jy)/\(d.jm)/\(d.jd)"),
                               toman: ImportAnalyzer.toman(e), kind: kind,
                               isLinked: e["linked"]?["kind"]?.stringValue != nil,
                               category: e["category"]?.stringValue ?? "",
                               subcategory: e["subcategory"]?.stringValue ?? "",
                               payMethod: e["payMethod"]?.stringValue, cardId: e["cardId"]?.idString,
                               partyId: e["partyId"]?.idString, itemCount: e["items"]?.arrayValue?.count ?? 0)
        }
    }

    // MARK: changes (each one saved in one transaction)

    /// Stage 3: the end-of-day backup is written 2 s after the last change, in the background, from a snapshot of the
    /// saved state (same bytes as an export from the database). Start-of-day and before-restore copies are not delayed.
    let backupDebouncer: BackupDebouncer = {
        var delay: TimeInterval = 2
        #if DEBUG
        if let d = Double(ProcessInfo.processInfo.environment["UITEST_BACKUP_DELAY"] ?? "") { delay = d }
        #endif
        return BackupDebouncer(delay: delay, marker: UserDefaultsBackupMarker()) { snapshot in
            Backups.writeDailySnapshot(snapshot)
        }
    }()
    #if DEBUG
    /// UI tests only: what happened to backups (read through a hidden label)
    @Published var debugBackupNote = ""
    /// UI performance test only: launch phases in ms (synthetic data)
    @Published var debugPerfNote = ""
    #endif

    /// the undo bar; the state to put back lives in `undoTracker`
    @Published var undo: UndoItem?
    private var undoTracker = UndoTracker<[String: JSONValue]>()
    private var unlockedUntil = Date.distantPast

    private func apply(_ newState: [String: JSONValue], undoMessage: String? = nil) -> Bool {
        guard let store else { return false }
        if store.isReadOnly { errorMessage = Self.readOnlyMessage; return false }
        // the day's first change: keep the data as it was before it (start-of-day copy, written once). If that copy
        // cannot be written, the change is not saved — nothing is put at risk without a clear warning.
        if hasData && !Backups.hasStartOfDay() {
            do { try Backups.write(try exportData(), reason: .startOfDay) }
            catch {
                errorMessage = "نسخه‌ی «شروع روز» پشتیبان ساخته نشد، پس این تغییر ذخیره نشد تا چیزی بدون پشتیبان از دست نرود. فضای خالی گوشی را بررسی کنید و دوباره امتحان کنید. (\(error.localizedDescription))"
                return false
            }
        }
        let previous = state
        do {
            try store.save(newState)
            state = newState
            backupDebouncer.schedule(newState)
            Notifier.sync(newState)
            // every change gets a number: an older undo can never wipe a newer change
            if let offer = undoTracker.didChange(previous: previous, message: undoMessage) {
                undo = UndoItem(id: offer.id, message: offer.message)
                DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
                    guard let self else { return }
                    undoTracker.expire(offer.id)
                    if undo?.id == offer.id { undo = nil }
                }
            } else {
                undo = nil
            }
            return true
        } catch {
            errorMessage = "ذخیره نشد و هیچ چیزی تغییر نکرد: \(error.localizedDescription)"
            return false
        }
    }

    private func run(_ op: () throws -> [String: JSONValue], undoMessage: String? = nil) -> Bool {
        do { return apply(try op(), undoMessage: undoMessage) }
        catch let e as LedgerError { errorMessage = e.message; return false }
        catch { errorMessage = error.localizedDescription; return false }
    }

    /// Runs a change and saves it (one transaction); used by the other screens.
    func change(_ op: () throws -> [String: JSONValue], undoMessage: String? = nil) -> Bool {
        run(op, undoMessage: undoMessage)
    }

    func add(_ input: ExpenseInput) -> Bool { run { try LedgerOps.addExpense(state, input).state } }
    func edit(rowId: String, _ input: ExpenseInput) -> Bool { run { try LedgerOps.editExpense(state, id: rowId, input) } }
    func delete(rowId: String) -> Bool { run({ try LedgerOps.deleteExpense(state, id: rowId) }, undoMessage: "حذف شد") }
    func settle(accountId: String, amount: Int, date: JalaliDate, upTo: String? = nil, payMethod: PayMethod, cardId: String?) -> Bool {
        run { try LedgerOps.settleCommission(state, accountId: accountId, amount: amount, date: date, upTo: upTo,
                                             payMethod: payMethod, cardId: cardId).state }
    }

    func performUndo() {
        undo = nil
        guard undoTracker.offer != nil else { return }      // its time ran out
        guard let previous = undoTracker.takeUndo() else {
            errorMessage = "بعد از آن، تغییر دیگری ثبت شده؛ برای اینکه آن تغییر از بین نرود، برگرداندن انجام نشد."
            return
        }
        _ = apply(previous)
    }

    /// What the commission balance would be after a payment (preview only, nothing is saved).
    func previewRemaining(accountId: String, amount: Int, date: JalaliDate, upTo: String? = nil) -> Int? {
        guard amount > 0, let r = try? LedgerOps.settleCommission(state, accountId: accountId, amount: amount, date: date, upTo: upTo),
              let a = r.state["accounts"]?.arrayValue?.first(where: { $0["id"]?.idString == accountId }) else { return nil }
        return ImportAnalyzer.accountSummary(a, expenses: r.state["expenses"]?.arrayValue ?? []).remaining
    }

    // edit lock (web: rows 8+ days old need the password; one unlock lasts 15 minutes)

    func isLocked(_ date: JalaliDate) -> Bool {
        LedgerOps.isEditLocked(rowDate: date, today: Self.today, password: state["editLockPassword"]?.stringValue,
                               sessionUnlocked: Date() < unlockedUntil)
    }

    func unlock(password: String) -> Bool {
        // Persian / Arabic / Latin digits are the same password (the web keyboard gave ۱۲۳۴, the iPhone keypad gives 1234)
        guard let p = state["editLockPassword"]?.stringValue, !p.isEmpty,
              SearchEngine.latinDigits(password.trimmingCharacters(in: .whitespaces)) == SearchEngine.latinDigits(p.trimmingCharacters(in: .whitespaces))
        else { return false }
        unlockedUntil = Date().addingTimeInterval(LedgerOps.unlockSeconds)
        return true
    }

    // lists for the form

    var ledgerCategories: [String] { (state["ledgerCategories"]?.arrayValue ?? []).compactMap(\.stringValue) }
    func subcategories(of category: String) -> [String] {
        (state["ledgerSubcategories"]?[category]?.arrayValue ?? []).compactMap(\.stringValue)
    }
    var activeCards: [Choice] {
        (state["cards"]?.arrayValue ?? []).compactMap { c -> Choice? in
            guard let id = c["id"]?.idString, !(c["archived"]?.isTruthy ?? false) else { return nil }
            let bank = c["bankName"]?.stringValue ?? ""
            let last4 = c["last4"]?.stringValue ?? ""
            return Choice(id: id, label: bank + " •" + Money.persianDigits(last4))
        }
    }
    /// the card this ledger uses most (smart default); then the last used one, the default card, the first card
    func defaultCard(accountId: String) -> String? {
        if let most = SmartDefaults.mostUsedCard(state, listKey: "expenses", accountId: accountId) { return most }
        if let last = state["lastCardByAccount"]?[accountId]?.idString, activeCards.contains(where: { $0.id == last }) { return last }
        let cards = state["cards"]?.arrayValue ?? []
        if let def = cards.first(where: { $0["isDefault"]?.isTruthy == true && !($0["archived"]?.isTruthy ?? false) })?["id"]?.idString { return def }
        return activeCards.first?.id
    }
    var tankhahParties: [Choice] {
        (state["tankhahParties"]?.arrayValue ?? []).compactMap { p -> Choice? in
            guard let id = p["id"]?.idString else { return nil }
            return Choice(id: id, label: p["name"]?.stringValue ?? "")
        }
    }
}

// MARK: - formatting

enum Fmt {
    static func toman(_ n: Int) -> String {
        Money.persianDigits(Money.format(abs(n))) + " تومان"
    }
    static func balance(_ n: Int) -> String {
        if n < 0 { return toman(n) + " بستانکار" }
        return toman(n)
    }
    static func percent(_ p: Double) -> String { Money.persianDigits(Money.jsNumberString(p)) + "٪" }
    static func count(_ n: Int) -> String { Money.persianDigits(n) }

    /// Accepts Persian, Arabic and Latin digits; ignores separators (web stripDigits).
    static func parseAmount(_ text: String) -> Int {
        var digits = ""
        for ch in text.unicodeScalars {
            switch ch.value {
            case 0x30...0x39: digits.unicodeScalars.append(ch)
            case 0x6F0...0x6F9: digits.unicodeScalars.append(Unicode.Scalar(ch.value - 0x6F0 + 0x30)!)
            case 0x660...0x669: digits.unicodeScalars.append(Unicode.Scalar(ch.value - 0x660 + 0x30)!)
            default: break
            }
        }
        return Int(digits.prefix(15)) ?? 0
    }

    /// Gregorian calendar on Tehran time: every Jalali date / «today» in the app is the Iranian one
    static let tehran = TimeZone(identifier: "Asia/Tehran") ?? .current
    static let gregorian: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = tehran; return c }()

    static func jalali(_ date: Date) -> JalaliDate {
        let c = gregorian.dateComponents([.year, .month, .day], from: date)
        return Jalali.toJalali(c.year ?? 2000, c.month ?? 1, c.day ?? 1)
    }

    static func date(_ j: JalaliDate) -> Date {
        let g = Jalali.toGregorian(j)
        return gregorian.date(from: DateComponents(year: g.gy, month: g.gm, day: g.gd, hour: 12)) ?? Date()
    }
}
