import SwiftUI
import UniformTypeIdentifiers
import HesabCore

/// Settings › پشتیبان و داده‌ها › «پشتیبان و بازیابی هر بخش جداگانه» (web sectionBackup / sectionRestore + text backups)
struct SectionBackupView: View {
    @ObservedObject var model: AppModel
    @State private var share: ExportFile?
    @State private var restoring: BackupSection?
    @State private var importerOpen = false
    @State private var pendingData: [String: JSONValue]?
    @State private var message: String?
    @Environment(\.theme) private var t

    var body: some View {
        Form {
            ForEach(BackupSection.allCases) { sec in
                Section {
                    ForEach(sec.summary(model.state), id: \.self) { line in
                        Text(line).font(AppFont.caption).foregroundStyle(t.soft)
                    }
                    Button { share = json(sec) } label: { Label("خروجی JSON (برای بازیابی)", systemImage: "doc.badge.arrow.up") }
                    Button { share = text(sec) } label: { Label("خروجی متنی (برای خواندن و فرستادن)", systemImage: "text.alignright") }
                    Button {
                        restoring = sec
                        importerOpen = true
                    } label: { Label("بازیابی این بخش از فایل JSON", systemImage: "arrow.counterclockwise") }
                } header: {
                    Text(sec.title).font(AppFont.medium(13))
                }
            }
            Section {
            } footer: {
                Text("بازیابی فقط همان بخش را با فایل جایگزین می‌کند و بقیه‌ی بخش‌ها دست نمی‌خورند؛ فایل بخش دیگر یا پشتیبان کامل پذیرفته نمی‌شود. بعد از بازیابی، «برگردان» هم در دسترس است. فایل‌ها با اپ وب هم‌قالب‌اند.").font(AppFont.caption)
            }
        }
        .navigationTitle("پشتیبان بخشی")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $share) { f in ActivityView(items: [f.url]) }
        .fileImporter(isPresented: $importerOpen, allowedContentTypes: [.json, .data, .plainText]) { result in
            guard let sec = restoring, case .success(let url) = result else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard let raw = try? Data(contentsOf: url) else { message = "فایل خوانده نشد."; return }
            switch SectionBackup.parse(raw, sec) {
            case .success(let data): pendingData = data
            case .failure(let e): message = e.message
            }
        }
        .alert("بازیابی «\(restoring?.title ?? "")»", isPresented: Binding(get: { pendingData != nil }, set: { if !$0 { pendingData = nil } })) {
            Button("بله، جایگزین کن", role: .destructive) { apply() }
            Button("انصراف", role: .cancel) { pendingData = nil }
        } message: {
            Text("اطلاعات فعلی این بخش با محتوای فایل جایگزین می‌شود:\n" + (pendingData.map { restoring?.summary($0).joined(separator: "\n") ?? "" } ?? ""))
        }
        .alert("پشتیبان بخشی", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("باشه", role: .cancel) {}
        } message: { Text(message ?? "") }
    }

    private var todayText: String { BackupExporter.formatJalali(AppModel.today) }
    private func fileName(_ sec: BackupSection, _ ext: String) -> String {
        "پشتیبان-" + sec.title.replacingOccurrences(of: "/", with: "-") + " - " + AppModel.todayTag() + "." + ext
    }

    private func json(_ sec: BackupSection) -> ExportFile? {
        do { return model.exportFile(name: fileName(sec, "json"), data: try SectionBackup.build(model.state, sec, todayText: todayText)) }
        catch { message = "فایل ساخته نشد: " + error.localizedDescription; return nil }
    }

    private func text(_ sec: BackupSection) -> ExportFile? {
        model.exportFile(name: fileName(sec, "txt"), data: Data(SectionText.text(model.state, sec, todayText: todayText).utf8))
    }

    private func apply() {
        guard let sec = restoring, let data = pendingData else { return }
        pendingData = nil
        if model.change({ SectionBackup.apply(model.state, sec, data) }, undoMessage: "بخش «" + sec.title + "» بازیابی شد") {
            Haptics.success()
            message = "بخش «" + sec.title + "» بازیابی شد."
        }
    }
}
