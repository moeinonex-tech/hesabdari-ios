import SwiftUI
import HesabCore
import HesabStore

@main
struct HesabdariApp: App {
    @StateObject private var model = AppModel()

    init() {
        AppFont.configureUIKit()
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
    enum Kind { case expense, tankhah, commission }
}

struct Choice: Identifiable, Hashable {
    let id: String
    let label: String
}

struct UndoItem: Identifiable {
    let id = UUID()
    let message: String
    let previous: [String: JSONValue]
}

struct ExportFile: Identifiable {
    let id = UUID()
    let url: URL
}

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var state: [String: JSONValue] = [:]
    @Published private(set) var hasData = false
    @Published var pending: ImportReport?
    @Published var errorMessage: String?
    @Published var lastImportText: String?

    private let store: HesabStore?

    init() {
        var opened: HesabStore?
        var openError: String?
        do {
            let url = try AppModel.databaseURL()
            opened = try HesabStore(path: url.path)
            try? FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: url.path)
        } catch {
            openError = "پایگاه داده باز نشد: \(error.localizedDescription)"
        }
        store = opened
        errorMessage = openError
        reload()
    }

    static func databaseURL() throws -> URL {
        let dir = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                              appropriateFor: nil, create: true)
        return dir.appendingPathComponent("hesabdari.sqlite")
    }

    static var today: JalaliDate {
        let c = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: Date())
        return Jalali.toJalali(c.year ?? 2000, c.month ?? 1, c.day ?? 1)
    }

    func reload() {
        guard let store else { return }
        state = (try? store.loadState()) ?? [:]
        hasData = !store.isEmpty
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
            do { try Backups.write(try exportData(), reason: .beforeRestore) }
            catch { errorMessage = "قبل از جایگزینی، پشتیبان از داده‌ی فعلی ساخته نشد؛ ورود انجام نشد: \(error.localizedDescription)"; return }
        }
        do {
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
        do { try Backups.write(try exportData(), reason: .beforeRestore) }
        catch { errorMessage = "پشتیبان ایمنی ساخته نشد؛ چیزی پاک نشد: \(error.localizedDescription)"; return false }
        do {
            try store.wipe()
            undo = nil
            reload()
            lastImportText = nil
            Notifier.sync([:])
            return true
        } catch {
            errorMessage = "پاک‌سازی انجام نشد: \(error.localizedDescription)"
            return false
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
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
            try data.write(to: url, options: [.atomic, .completeFileProtection])
            return ExportFile(url: url)
        } catch {
            errorMessage = "خروجی ساخته نشد: \(error.localizedDescription)"
            return nil
        }
    }

    // read models

    var accounts: [AccountImportSummary] {
        let expenses = state["expenses"]?.arrayValue ?? []
        return (state["accounts"]?.arrayValue ?? []).map { ImportAnalyzer.accountSummary($0, expenses: expenses) }
    }

    var personalTotal: Int { (state["personalExpenses"]?.arrayValue ?? []).reduce(0) { $0 + ImportAnalyzer.toman($1) } }
    var incomeTotal: Int { (state["incomes"]?.arrayValue ?? []).reduce(0) { $0 + ImportAnalyzer.toman($1) } }

    /// Rows of one account in the web order (date, then entry time), numbered like the web ledger.
    func rows(accountId: String) -> [LedgerRowVM] {
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
                : (e["type"]?.stringValue == "tankhah" ? .tankhah : .expense)
            let rid = e["id"]?.idString ?? ""
            return LedgerRowVM(id: rid + "#\(i)", rowId: rid, number: i + 1,
                               desc: e["desc"]?.stringValue ?? "", dateValue: d,
                               date: Money.persianDigits("\(d.jy)/\(d.jm)/\(d.jd)"),
                               toman: ImportAnalyzer.toman(e), kind: kind,
                               isLinked: e["linked"]?["kind"]?.stringValue != nil,
                               category: e["category"]?.stringValue ?? "",
                               subcategory: e["subcategory"]?.stringValue ?? "",
                               payMethod: e["payMethod"]?.stringValue, cardId: e["cardId"]?.idString,
                               partyId: e["partyId"]?.idString)
        }
    }

    // MARK: changes (each one saved in one transaction)

    @Published var undo: UndoItem?
    private var unlockedUntil = Date.distantPast

    private func apply(_ newState: [String: JSONValue], undoMessage: String? = nil) -> Bool {
        guard let store else { return false }
        let previous = state
        do {
            try store.save(newState)
            state = newState
            backupToday()
            Notifier.sync(newState)
            if let m = undoMessage {
                let item = UndoItem(message: m, previous: previous)
                undo = item
                DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
                    if self?.undo?.id == item.id { self?.undo = nil }
                }
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
    func settle(accountId: String, amount: Int, date: JalaliDate) -> Bool {
        run { try LedgerOps.settleCommission(state, accountId: accountId, amount: amount, date: date).state }
    }

    func performUndo() {
        guard let u = undo else { return }
        undo = nil
        _ = apply(u.previous)
    }

    /// What the commission balance would be after a payment (preview only, nothing is saved).
    func previewRemaining(accountId: String, amount: Int, date: JalaliDate) -> Int? {
        guard amount > 0, let r = try? LedgerOps.settleCommission(state, accountId: accountId, amount: amount, date: date),
              let a = r.state["accounts"]?.arrayValue?.first(where: { $0["id"]?.idString == accountId }) else { return nil }
        return ImportAnalyzer.accountSummary(a, expenses: r.state["expenses"]?.arrayValue ?? []).remaining
    }

    // edit lock (web: rows 8+ days old need the password; one unlock lasts 15 minutes)

    func isLocked(_ date: JalaliDate) -> Bool {
        LedgerOps.isEditLocked(rowDate: date, today: Self.today, password: state["editLockPassword"]?.stringValue,
                               sessionUnlocked: Date() < unlockedUntil)
    }

    func unlock(password: String) -> Bool {
        guard let p = state["editLockPassword"]?.stringValue, !p.isEmpty, password == p else { return false }
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
    func defaultCard(accountId: String) -> String? {
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

    static let gregorian = Calendar(identifier: .gregorian)

    static func jalali(_ date: Date) -> JalaliDate {
        let c = gregorian.dateComponents([.year, .month, .day], from: date)
        return Jalali.toJalali(c.year ?? 2000, c.month ?? 1, c.day ?? 1)
    }

    static func date(_ j: JalaliDate) -> Date {
        let g = Jalali.toGregorian(j)
        return gregorian.date(from: DateComponents(year: g.gy, month: g.gm, day: g.gd, hour: 12)) ?? Date()
    }
}
