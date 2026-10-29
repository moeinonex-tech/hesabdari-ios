import SwiftUI
import HesabCore
import HesabStore

@main
struct HesabdariApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
                .environment(\.layoutDirection, .rightToLeft)
                .environment(\.locale, Locale(identifier: "fa_IR"))
        }
    }
}

// MARK: - model

struct LedgerRowVM: Identifiable {
    let id: String
    let number: Int
    let desc: String
    let date: String
    let toman: Int
    let kind: Kind
    enum Kind { case expense, tankhah, commission }
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
        do {
            try store.replaceAll(with: report.cleanedState, sourceExportedAtJalali: report.exportedAtJalali,
                                 reportLines: report.summaryLines + report.issues.map(\.title))
            pending = nil
            reload()
        } catch {
            errorMessage = "ورود ناموفق بود و هیچ داده‌ای تغییر نکرد: \(error.localizedDescription)"
        }
    }

    // export

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
            return LedgerRowVM(id: (e["id"]?.idString ?? "") + "#\(i)", number: i + 1,
                               desc: e["desc"]?.stringValue ?? "",
                               date: Money.persianDigits("\(d.jy)/\(d.jm)/\(d.jd)"),
                               toman: ImportAnalyzer.toman(e), kind: kind)
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
}
