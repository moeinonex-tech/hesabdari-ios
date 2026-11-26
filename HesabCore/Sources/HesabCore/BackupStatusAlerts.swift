import Foundation

/// «نیازمند توجه» on the home screen: what to say about the backups, from facts the app already records
/// (time of the last backup written, health of the newest end-of-day file, the last iCloud result).
/// Read-only: it never writes, schedules or changes a backup.
public enum BackupStatusAlerts {
    /// the last iCloud copy, as the app records it (only when the build carries the iCloud permission)
    public enum ICloud: Equatable, Sendable {
        case ok
        case notSignedIn      // the phone is not connected to iCloud Drive
        case failed           // writing the copy failed
        case notReady         // the app's iCloud folder is not available
        case unknown          // never tried yet, or this build has no iCloud
    }

    public struct Alert: Equatable, Sendable {
        public enum Level: Equatable, Sendable { case danger, warning }
        public var id: String
        public var level: Level
        public var text: String
    }

    /// a backup older than this many days is reported (a backup is written within seconds of opening the app)
    public static let staleDays = 2
    public static let veryStaleDays = 7

    /// - Parameters:
    ///   - hasData: false → nothing to back up, nothing to say
    ///   - lastBackupAt: when the last backup file was written (nil: never)
    ///   - latestHealth: health of the newest end-of-day backup on the phone (nil: no such file)
    public static func evaluate(hasData: Bool, lastBackupAt: Date?, now: Date,
                                latestHealth: BackupFolder.Health?, iCloud: ICloud) -> [Alert] {
        guard hasData else { return [] }
        var out: [Alert] = []
        if let last = lastBackupAt {
            let days = Int(now.timeIntervalSince(last) / 86_400)
            if days >= staleDays {
                out.append(Alert(id: "stale", level: days >= veryStaleDays ? .danger : .warning,
                                 text: Money.persianDigits(days) + " روز است پشتیبان تازه‌ای گرفته نشده"))
            }
            switch latestHealth {
            case .healthy?: break
            case nil:
                out.append(Alert(id: "missing", level: .warning, text: "فایل آخرین پشتیبان روی گوشی پیدا نشد"))
            case .noSidecar?, .mismatch?, .unreadable?:
                out.append(Alert(id: "unhealthy", level: .danger, text: "آخرین پشتیبان سالم نیست؛ بررسی کنید"))
            }
        } else {
            out.append(Alert(id: "never", level: .danger, text: "هنوز هیچ پشتیبانی گرفته نشده"))
        }
        switch iCloud {
        case .ok, .unknown: break
        case .notSignedIn:
            out.append(Alert(id: "icloud-off", level: .warning, text: "گوشی به iCloud Drive وصل نیست؛ پشتیبان فقط روی همین گوشی است"))
        case .notReady:
            out.append(Alert(id: "icloud-not-ready", level: .warning, text: "پوشه‌ی iCloud اپ آماده نیست؛ پشتیبان فقط روی همین گوشی است"))
        case .failed:
            out.append(Alert(id: "icloud-failed", level: .danger, text: "پشتیبان در iCloud ذخیره نشد"))
        }
        return out
    }

    /// the newest end-of-day backup among file names (nil: none)
    public static func newestEndOfDay(_ names: [String]) -> String? {
        names.compactMap(BackupNames.parse).filter { $0.kind == .endOfDay }.max { $0.date < $1.date }?.fileName
    }
}
