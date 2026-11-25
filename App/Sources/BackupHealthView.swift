import SwiftUI
import HesabCore
import HesabStore

/// Settings › داده‌ها › «بررسی سلامت بکاپ‌ها»: every backup on the phone, with its SHA-256, structure and a real
/// restore test into a throw-away database. Nothing here writes to the real data or to any backup.
struct BackupHealthView: View {
    @Environment(\.theme) private var t
    @State private var files: [BackupName] = []
    @State private var reports: [String: BackupCheckReport] = [:]
    @State private var running = false
    @State private var trashCount = 0

    private var folder: BackupFolder { Backups.local }

    var body: some View {
        Form {
            Section {
                Button {
                    run()
                } label: {
                    HStack {
                        Label("بررسی همه‌ی بکاپ‌ها", systemImage: "checkmark.shield")
                        if running { Spacer(); ProgressView() }
                    }
                }
                .disabled(running || files.isEmpty)
                .accessibilityIdentifier("backup.health.run")
                if !reports.isEmpty {
                    let ok = reports.values.filter(\.usable).count
                    LabeledContent("قابل بازگردانی", value: Money.persianDigits(ok) + " از " + Money.persianDigits(reports.count))
                        .accessibilityIdentifier("backup.health.summary")
                }
            } footer: {
                Text("هر بکاپ با کد SHA-256، ساختار فایل و یک بازگردانی آزمایشی در یک پایگاه داده‌ی موقت بررسی می‌شود. داده‌ی اصلی و خود بکاپ‌ها دست نمی‌خورند.")
            }

            if files.isEmpty {
                Section { Text("هنوز بکاپی روی این گوشی ساخته نشده").foregroundStyle(t.soft) }
            }
            ForEach(groups, id: \.0) { title, items in
                Section(title) {
                    ForEach(items, id: \.fileName) { b in row(b) }
                }
            }
            if trashCount > 0 {
                Section {
                    Text(Money.persianDigits(trashCount) + " فایل در پوشه‌ی «_حذف‌شده» است؛ ۳۰ روز پس از انتقال برای همیشه پاک می‌شوند و تا آن موقع از Files قابل برگرداندن‌اند.")
                        .font(AppFont.caption).foregroundStyle(t.soft)
                }
            }
        }
        .navigationTitle("سلامت بکاپ‌ها")
        .task {
            load()
            try? await Task.sleep(for: .seconds(1))      // a backup written while the screen opened
            load()
        }
    }

    private var groups: [(String, [BackupName])] {
        let order: [(BackupKind, String)] = [(.endOfDay, "پایان روز"), (.startOfDay, "شروع روز"),
                                             (.beforeRestore, "قبل از بازگردانی"), (.rawDatabase, "کپی خام پایگاه داده")]
        return order.compactMap { kind, title in
            let items = files.filter { $0.kind == kind }.sorted { ($0.date, $0.time) > ($1.date, $1.time) }
            return items.isEmpty ? nil : (title, items)
        }
    }

    private func row(_ b: BackupName) -> some View {
        let r = reports[b.fileName]
        return HStack(spacing: 10) {
            Image(systemName: r == nil ? "circle.dotted" : (r!.usable ? "checkmark.circle.fill" : "xmark.octagon.fill"))
                .foregroundStyle(r == nil ? t.soft : (r!.usable ? Color.green : Color.red))
            VStack(alignment: .leading, spacing: 2) {
                Text(BackupExporter.formatJalali(b.date)).font(AppFont.medium(14))
                if let r {
                    Text(detail(r)).font(AppFont.caption).foregroundStyle(r.usable ? t.soft : Color.red)
                }
            }
        }
        .accessibilityIdentifier("backup.row")
    }

    private func detail(_ r: BackupCheckReport) -> String {
        let sha: String
        switch r.health {
        case .healthy: sha = "کد سلامت درست"
        case .noSidecar: sha = "بدون کد سلامت (بکاپ قدیمی)"
        case .mismatch: sha = "کد سلامت نمی‌خواند"
        case .unreadable: sha = "خوانده نشد"
        }
        var parts = [sha]
        if r.restoreOK { parts.append("بازگردانی آزمایشی موفق · " + Money.persianDigits(r.records) + " ردیف") }
        if let p = r.problem { parts.append(p) }
        return parts.joined(separator: " · ")
    }

    private func load() {
        files = folder.names().compactMap(BackupNames.parse)
        trashCount = ((try? FileManager.default.contentsOfDirectory(atPath: folder.trashURL.path)) ?? [])
            .filter { $0.hasPrefix(BackupFolder.trashPrefix) && !$0.hasSuffix("." + BackupNames.sidecarExtension) }.count
    }

    private func run() {
        running = true
        let f = folder
        let names = files.map(\.fileName)
        Task.detached(priority: .userInitiated) {
            var out: [String: BackupCheckReport] = [:]
            for n in names { out[n] = BackupCheck.run(f, n) }
            let result = out
            await MainActor.run {
                reports = result
                running = false
            }
        }
    }
}
