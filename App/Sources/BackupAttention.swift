import SwiftUI
import HesabCore

/// Backup warnings for «نیازمند توجه» on the home screen. Read-only: it looks at what the backup code already
/// records (time of the last backup, the newest end-of-day file and its SHA-256 sidecar, the last iCloud result)
/// and never writes, schedules or changes a backup.
extension AppModel {
    func refreshBackupAttention() async {
        guard hasData, readOnlyReason == nil else {
            if !backupAttention.isEmpty { backupAttention = [] }
            return
        }
        var alerts = await Self.currentBackupAlerts(hasData: true)
        if !alerts.isEmpty {
            // a backup is written seconds after the app opens or the data changes: look again before warning
            try? await Task.sleep(for: .seconds(4))
            if Task.isCancelled { return }
            alerts = await Self.currentBackupAlerts(hasData: hasData)
        }
        let items = alerts.map { a in
            AttentionItem(id: "backup-" + a.id,
                          icon: a.id.hasPrefix("icloud") ? "icloud.slash.fill" : "externaldrive.fill.badge.exclamationmark",
                          level: a.level == .danger ? .danger : .warning,
                          text: a.text)
        }
        if items.map(\.id) != backupAttention.map(\.id) || items.map(\.text) != backupAttention.map(\.text) {
            backupAttention = items
        }
    }

    /// the facts, read off the main thread (the newest backup is hashed to check its sidecar)
    nonisolated static func currentBackupAlerts(hasData: Bool) async -> [BackupStatusAlerts.Alert] {
        await Task.detached(priority: .utility) {
            let defaults = UserDefaults.standard
            let ts = defaults.double(forKey: Backups.lastAtKey)
            let folder = Backups.local
            let health = BackupStatusAlerts.newestEndOfDay(folder.names()).map { folder.health($0) }
            let iCloud: BackupStatusAlerts.ICloud
            if Backups.hasICloudEntitlement, defaults.object(forKey: Backups.lastICloudKey) != nil {
                switch defaults.integer(forKey: Backups.lastICloudKey) {
                case 1: iCloud = .ok
                case 0: iCloud = .notSignedIn
                case -1: iCloud = .failed
                case -3: iCloud = .notReady
                default: iCloud = .unknown
                }
            } else {
                iCloud = .unknown          // a build without the iCloud permission: nothing the person can fix
            }
            return BackupStatusAlerts.evaluate(hasData: hasData, lastBackupAt: ts > 0 ? Date(timeIntervalSince1970: ts) : nil,
                                               now: Date(), latestHealth: health, iCloud: iCloud)
        }.value
    }
}
