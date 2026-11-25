import Foundation
import GRDB
import HesabCore

/// «بررسی سلامت بکاپ»: checks one backup file without touching the real data.
///
/// 1. SHA-256 against its sidecar (older backups have none: reported, not failed).
/// 2. Structure: the same parser and analysis the app uses to import a backup.
/// 3. Real restore test: the file is restored into a throw-away in-memory database, read back and compared with
///    what was restored. A raw database copy is checked by opening a temporary copy of it read back the same way.
public struct BackupCheckReport: Equatable, Sendable {
    public var name: String
    public var health: BackupFolder.Health
    public var structureOK: Bool
    public var restoreOK: Bool
    public var records: Int
    public var problem: String?

    /// usable for a restore: structure and restore test passed, and the checksum is right or (older file) absent
    public var usable: Bool { structureOK && restoreOK && (health == .healthy || health == .noSidecar) }
}

public enum BackupCheck {
    public static func run(_ folder: BackupFolder, _ name: String) -> BackupCheckReport {
        var r = BackupCheckReport(name: name, health: folder.health(name), structureOK: false, restoreOK: false, records: 0, problem: nil)
        let fileURL = folder.url.appendingPathComponent(name)
        guard let data = try? Data(contentsOf: fileURL) else { r.problem = "فایل خوانده نشد"; return r }

        if name.lowercased().hasSuffix(".sqlite") {
            // never open the backup itself: a temporary copy only
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("check-\(UUID().uuidString).sqlite")
            defer { try? FileManager.default.removeItem(at: tmp) }
            do {
                try data.write(to: tmp)
                let st = try HesabStore(path: tmp.path).loadState()
                r.structureOK = true
                r.restoreOK = true
                r.records = count(st)
            } catch { r.problem = "پایگاه داده‌ی کپی‌شده خوانده نشد" }
            return r
        }

        switch BackupParser.parse(data) {
        case .failure(let e):
            r.problem = e.message
            return r
        case .success(let parsed):
            let report = ImportAnalyzer.analyze(parsed)
            guard report.canImport else { r.problem = report.issues.first { $0.level == .blocking }?.title ?? "قابل ورود نیست"; return r }
            r.structureOK = true
            r.records = count(report.cleanedState)
            do {
                let mem = try HesabStore()
                try mem.replaceAll(with: report.cleanedState, sourceExportedAtJalali: report.exportedAtJalali, reportLines: [])
                let back = try mem.loadState()
                r.restoreOK = back == report.cleanedState
                if !r.restoreOK { r.problem = "داده‌ی بازگردانده‌شده با فایل یکی نیست" }
            } catch {
                r.problem = "بازگردانی آزمایشی ناموفق بود"
            }
        }
        if r.problem == nil, r.health == .mismatch { r.problem = "کد سلامت با فایل نمی‌خواند (فایل ناقص یا تغییر کرده)" }
        return r
    }

    static func count(_ st: [String: JSONValue]) -> Int {
        st.values.reduce(0) { $0 + ($1.arrayValue?.count ?? 0) }
    }
}
