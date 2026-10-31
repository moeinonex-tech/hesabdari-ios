import SwiftUI
import LocalAuthentication
import HesabCore

// MARK: - automatic backups (decision D18: daily JSON backup to iCloud Drive, no live sync)
//
// Every saved change rewrites TODAY's backup file, so each day keeps its latest state.
// Files use the web full-backup format (version 1), so the web app can restore them too.
//   iCloud Drive › دفتر حساب › پشتیبان‌ها   (last 60 files)
//   Files › On My iPhone › دفتر حساب › پشتیبان‌ها   (last 14 files, works without iCloud too)
// Before an import replaces the data, a separate "before restore" copy is written.

enum BackupReason { case daily, beforeRestore }

enum Backups {
    static let folderName = "پشتیبان‌ها"
    static let iCloudContainer = "iCloud.uk.moein.hesabdari"

    // UserDefaults keys (read by the settings screen through @AppStorage)
    static let lastAtKey = "backup.lastAt"
    static let lastICloudKey = "backup.lastICloud"       // 1 = in iCloud, 0 = iCloud unavailable, -1 = failed

    static var localFolder: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent(folderName, isDirectory: true)
    }

    static func fileName(_ reason: BackupReason, now: Date = Date()) -> String {
        let t = Fmt.jalali(now)
        let day = Money.persianDigits("\(t.jy)-\(t.jm)-\(t.jd)")
        switch reason {
        case .daily:
            return "پشتیبان-کامل-اپ - " + day + ".json"
        case .beforeRestore:
            let c = Calendar(identifier: .gregorian).dateComponents([.hour, .minute, .second], from: now)
            let time = Money.persianDigits(String(format: "%02d%02d%02d", c.hour ?? 0, c.minute ?? 0, c.second ?? 0))
            return "قبل-از-بازگردانی - " + day + " - " + time + ".json"
        }
    }

    /// Writes the local copy synchronously (throws if that fails) and the iCloud copy in the background.
    @discardableResult
    static func write(_ data: Data, reason: BackupReason) throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: localFolder, withIntermediateDirectories: true)
        let name = fileName(reason)
        let url = localFolder.appendingPathComponent(name)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        prune(localFolder, keep: 14)
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastAtKey)
        copyToICloud(data, name: name)
        return url
    }

    /// does the signed app carry the iCloud container entitlement? (looks inside its own code signature)
    static let hasICloudEntitlement: Bool = {
        guard let exe = Bundle.main.executableURL, let data = try? Data(contentsOf: exe, options: .alwaysMapped) else { return false }
        return data.range(of: Data("com.apple.developer.ubiquity-container-identifiers".utf8)) != nil
            || data.range(of: Data("com.apple.developer.icloud-container-identifiers".utf8)) != nil
    }()

    static func copyToICloud(_ data: Data, name: String) {
        DispatchQueue.global(qos: .utility).async {
            let fm = FileManager.default
            guard let base = fm.url(forUbiquityContainerIdentifier: iCloudContainer) else {
                // why: not signed in to iCloud Drive (no identity token) / this build lacks the iCloud permission / other
                let code = fm.ubiquityIdentityToken == nil ? 0 : (hasICloudEntitlement ? -3 : -2)
                DispatchQueue.main.async { UserDefaults.standard.set(code, forKey: lastICloudKey) }
                return
            }
            let dir = base.appendingPathComponent("Documents", isDirectory: true)
                .appendingPathComponent(folderName, isDirectory: true)
            var ok = false
            do {
                try fm.createDirectory(at: dir, withIntermediateDirectories: true)
                let dest = dir.appendingPathComponent(name)
                var coordError: NSError?
                var writeError: Error?
                NSFileCoordinator().coordinate(writingItemAt: dest, options: .forReplacing, error: &coordError) { u in
                    do { try data.write(to: u, options: .atomic) } catch { writeError = error }
                }
                ok = coordError == nil && writeError == nil
                if ok { prune(dir, keep: 60) }
            } catch {
                ok = false
            }
            let result = ok ? 1 : -1
            DispatchQueue.main.async { UserDefaults.standard.set(result, forKey: lastICloudKey) }
        }
    }

    /// Keeps the newest `keep` JSON files (by modification date).
    static func prune(_ dir: URL, keep: Int) {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        let jsons = items.filter { $0.pathExtension.lowercased() == "json" }
        guard jsons.count > keep else { return }
        let dated = jsons.map { u -> (URL, Date) in
            ((u), (try? u.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast)
        }.sorted { $0.1 > $1.1 }
        for (u, _) in dated.dropFirst(keep) { try? fm.removeItem(at: u) }
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
        guard hasData else { return }
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
