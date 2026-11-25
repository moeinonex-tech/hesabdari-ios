import SwiftUI
import LocalAuthentication
import HesabCore

// MARK: - automatic backups (decision D18: daily JSON backup to iCloud Drive, no live sync)
//
// Files use the web full-backup format (version 1), so the web app can restore them too; each has a «.sha256»
// sidecar written after it. Retention (BackupRetention, owner-approved 2026-11-25):
//   end of day     rewritten with every change — 14 days (iCloud 60) + one per week × 8 + one per month × 12
//   start of day   the data as it was before the day's first change, written once — 14 days
//   before restore written before an import / reset replaces the data — newest 10, own pool
//   raw database   (.sqlite, when the data could not be read) — never removed automatically
// Removal is a move into «_حذف‌شده»; deleted for good 30 days later. Retention runs once a day per folder.
//   iCloud Drive › دفتر حساب › پشتیبان‌ها
//   Files › On My iPhone › دفتر حساب › پشتیبان‌ها   (works without iCloud too)

enum BackupReason { case daily, startOfDay, beforeRestore }

enum Backups {
    static let folderName = "پشتیبان‌ها"
    static let iCloudContainer = "iCloud.uk.moein.hesabdari"

    // UserDefaults keys (read by the settings screen through @AppStorage)
    static let lastAtKey = "backup.lastAt"
    static let lastICloudKey = "backup.lastICloud"       // 1 = in iCloud, 0 = iCloud unavailable, -1 = failed
    static let retentionDayKey = "backup.retentionDay."  // + "local" / "icloud": the day retention last ran

    static var localFolder: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent(folderName, isDirectory: true)
    }
    static var local: BackupFolder { BackupFolder(url: localFolder) }
    static let localOptions: Data.WritingOptions = [.atomic, .completeFileProtectionUntilFirstUserAuthentication]

    static func fileName(_ reason: BackupReason, now: Date = Date()) -> String {
        let t = Fmt.jalali(now)
        switch reason {
        case .daily: return BackupNames.endOfDay(t)
        case .startOfDay: return BackupNames.startOfDay(t)
        case .beforeRestore:
            let c = Calendar(identifier: .gregorian).dateComponents([.hour, .minute, .second], from: now)
            return BackupNames.beforeRestore(t, hhmmss: (c.hour ?? 0) * 10000 + (c.minute ?? 0) * 100 + (c.second ?? 0))
        }
    }

    /// whether today's start-of-day copy is already there (it is written once, before the day's first change)
    static func hasStartOfDay(now: Date = Date()) -> Bool { local.exists(fileName(.startOfDay, now: now)) }

    /// Before a restore replaces data that cannot be read: the raw database file, kept next to the JSON backups
    /// (with its sidecar). Never removed automatically.
    @discardableResult
    static func writeRawDatabase(_ copy: (URL) throws -> Void) throws -> URL {
        try FileManager.default.createDirectory(at: localFolder, withIntermediateDirectories: true)
        let name = fileName(.beforeRestore).replacingOccurrences(of: ".json", with: ".sqlite")
        let url = localFolder.appendingPathComponent(name)
        try copy(url)
        try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                                               ofItemAtPath: url.path)
        try local.writeSidecar(for: name, options: localOptions)
        return url
    }

    /// iCloud copies are written one after another, newest last (an older copy never lands over a newer one)
    static let iCloudQueue = LatestWinsQueue(label: "backup.icloud")

    /// Writes the local copy (and its sidecar) synchronously — throws if that fails — and the iCloud copy in the
    /// background. A start-of-day copy is never overwritten.
    @discardableResult
    static func write(_ data: Data, reason: BackupReason) throws -> URL {
        let name = fileName(reason)
        if reason == .startOfDay, local.exists(name) { return localFolder.appendingPathComponent(name) }
        let url = try local.write(data, name: name, options: localOptions)
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastAtKey)
        runRetentionOncePerDay(local, policy: .local, key: "local")
        copyToICloud(data, name: name)
        return url
    }

    /// Retention at most once a day per folder (it reads and hashes files, so not on every change).
    static func runRetentionOncePerDay(_ folder: BackupFolder, policy: BackupRetentionPolicy, key: String) {
        let today = Fmt.jalali(Date())
        let tag = BackupNames.endOfDay(today)
        let defaults = UserDefaults.standard
        guard defaults.string(forKey: retentionDayKey + key) != tag else { return }
        folder.applyRetention(today: today, policy: policy)
        defaults.set(tag, forKey: retentionDayKey + key)
    }

    /// does the signed app carry the iCloud container entitlement? (looks inside its own code signature)
    static let hasICloudEntitlement: Bool = {
        guard let exe = Bundle.main.executableURL, let data = try? Data(contentsOf: exe, options: .alwaysMapped) else { return false }
        return data.range(of: Data("com.apple.developer.ubiquity-container-identifiers".utf8)) != nil
            || data.range(of: Data("com.apple.developer.icloud-container-identifiers".utf8)) != nil
    }()

    static var iCloudFolderURL: URL? {
        FileManager.default.url(forUbiquityContainerIdentifier: iCloudContainer)?
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent(folderName, isDirectory: true)
    }

    static func copyToICloud(_ data: Data, name: String) {
        iCloudQueue.submit(key: name) {
            let fm = FileManager.default
            guard let dir = iCloudFolderURL else {
                // why: not signed in to iCloud Drive (no identity token) / this build lacks the iCloud permission / other
                let code = fm.ubiquityIdentityToken == nil ? 0 : (hasICloudEntitlement ? -3 : -2)
                DispatchQueue.main.async { UserDefaults.standard.set(code, forKey: lastICloudKey) }
                return
            }
            // conservative in iCloud: files from another device that are not downloaded are invisible or unreadable,
            // so they are never healthy and never removed (see BackupRetention)
            let folder = BackupFolder(url: dir, coordinated: true)
            let ok = (try? folder.write(data, name: name)) != nil
            if ok { runRetentionOncePerDay(folder, policy: .iCloud, key: "icloud") }
            let result = ok ? 1 : -1
            DispatchQueue.main.async { UserDefaults.standard.set(result, forKey: lastICloudKey) }
        }
    }

    static func describeLast() -> String {
        let ts = UserDefaults.standard.double(forKey: lastAtKey)
        guard ts > 0 else { return "هنوز پشتیبانی گرفته نشده" }
        let d = Date(timeIntervalSince1970: ts)
        let j = Fmt.jalali(d)
        let c = Calendar(identifier: .gregorian).dateComponents([.hour, .minute], from: d)
        let time = Money.persianDigits(String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0))
        return BackupExporter.formatJalali(j) + "، ساعت " + time
    }
}

extension AppModel {
    /// Rewrites today's backup with the current data. Silent on success; a failure is shown once.
    func backupToday(showErrors: Bool = false) {
        guard hasData, readOnlyReason == nil else { return }    // never back up a state that could not be read
        do {
            try Backups.write(try exportData(), reason: .daily)
        } catch {
            if showErrors { errorMessage = "پشتیبان ساخته نشد: \(error.localizedDescription)" }
        }
    }
}

// MARK: - Face ID lock

@MainActor
final class AppLock: ObservableObject {
    @Published var locked: Bool
    @Published var authenticating = false
    private var backgroundAt: Date?
    static let enabledKey = "lock.enabled"
    static let graceSeconds: TimeInterval = 60

    init() {
        let enabled = UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true
        locked = enabled
    }

    var enabled: Bool { UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true }

    func didEnterBackground() { backgroundAt = Date() }

    func didBecomeActive() {
        guard enabled else { locked = false; return }
        if let b = backgroundAt, Date().timeIntervalSince(b) > Self.graceSeconds { locked = true }
        backgroundAt = nil
    }

    func unlock() {
        guard enabled else { locked = false; return }
        guard !authenticating else { return }
        let ctx = LAContext()
        ctx.localizedCancelTitle = "انصراف"
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else {
            locked = false      // no Face ID and no passcode on this phone: nothing to check against
            return
        }
        authenticating = true
        ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "باز کردن دفتر حساب") { ok, _ in
            DispatchQueue.main.async {
                self.authenticating = false
                if ok { withAnimation(.smooth) { self.locked = false } }
            }
        }
    }
}

struct LockScreen: View {
    @ObservedObject var lock: AppLock
    @Environment(\.theme) private var t

    var body: some View {
        ZStack {
            AppBackground()
            Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
            VStack(spacing: 20) {
                Image(systemName: "faceid")
                    .font(.system(size: 54, weight: .light))
                    .foregroundStyle(t.accent)
                    .padding(24)
                    .glassEffect(.regular, in: Circle())
                Text("دفتر حساب قفل است").font(AppFont.heavy(22)).foregroundStyle(t.ink)
                Button {
                    lock.unlock()
                } label: {
                    Label("باز کردن", systemImage: "lock.open.fill")
                        .font(AppFont.bold(16))
                        .padding(.horizontal, 20).padding(.vertical, 4)
                }
                .buttonStyle(.glassProminent)
            }
        }
        .onAppear { lock.unlock() }
    }
}

/// Hides the content in the app switcher.
struct PrivacyCover: View {
    var body: some View {
        ZStack {
            AppBackground()
            Rectangle().fill(.ultraThickMaterial).ignoresSafeArea()
            Image(systemName: "book.pages.fill").font(.system(size: 48)).foregroundStyle(.secondary)
        }
    }
}
