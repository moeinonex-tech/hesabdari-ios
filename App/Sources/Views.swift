import SwiftUI
import UIKit
import UniformTypeIdentifiers
import HesabCore

struct RootView: View {
    @ObservedObject var model: AppModel
    @State private var showImporter = false
    @State private var exportFile: ExportFile?

    var body: some View {
        NavigationStack {
            Group {
                if model.hasData {
                    AccountsView(model: model, showImporter: $showImporter, exportFile: $exportFile)
                } else {
                    WelcomeView(showImporter: $showImporter)
                }
            }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json, .plainText, .data]) { result in
            switch result {
            case .success(let url): model.openFile(url)
            case .failure(let error): model.errorMessage = error.localizedDescription
            }
        }
        .sheet(isPresented: Binding(get: { model.pending != nil }, set: { if !$0 { model.pending = nil } })) {
            if let report = model.pending {
                NavigationStack {
                    ImportReportView(report: report, replacesExisting: model.hasData,
                                     onConfirm: { model.confirmImport() },
                                     onCancel: { model.pending = nil })
                }
                .environment(\.layoutDirection, .rightToLeft)
            }
        }
        .sheet(item: $exportFile) { file in
            ActivityView(items: [file.url])
        }
        .alert("خطا", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("باشه", role: .cancel) { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}

// MARK: - welcome

struct WelcomeView: View {
    @Binding var showImporter: Bool

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "tray.and.arrow.down")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.tint)
            Text("دفتر حساب")
                .font(.largeTitle.bold())
            Text("برای شروع، فایل «پشتیبان کامل» اپ وب را انتخاب کنید. قبل از ورود، گزارش کامل آن را می‌بینید و تا تأیید نکنید چیزی ذخیره نمی‌شود.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)
            Button {
                showImporter = true
            } label: {
                Label("انتخاب فایل پشتیبان", systemImage: "doc.badge.plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 32)
            Spacer()
            Spacer()
        }
        .navigationTitle("")
    }
}

// MARK: - import report

struct ImportReportView: View {
    let report: ImportReport
    let replacesExisting: Bool
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        List {
            Section {
                if let d = report.exportedAtJalali {
                    LabeledContent("تاریخ پشتیبان", value: d)
                }
                ForEach(report.summaryLines, id: \.self) { line in
                    let parts = line.components(separatedBy: ": ")
                    LabeledContent(parts.first ?? line, value: parts.count > 1 ? parts[1] : "")
                }
            } header: {
                Text("محتوای فایل")
            }

            Section {
                ForEach(report.accounts) { a in
                    AccountNumbers(account: a)
                }
                LabeledContent("هزینه‌های شخصی", value: Fmt.toman(report.personalTotal))
                LabeledContent("درآمدها", value: Fmt.toman(report.incomeTotal))
            } header: {
                Text("عددها")
            } footer: {
                Text("این عددها را با اپ وب مقایسه کنید. باید دقیقاً یکی باشند.")
            }

            Section {
                if report.issues.isEmpty {
                    Label("هیچ مشکلی پیدا نشد", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                }
                ForEach(report.issues) { issue in
                    IssueRow(issue: issue)
                }
            } header: {
                Text("بررسی‌ها")
            }

            if replacesExisting {
                Section {
                    Text("با ورود این فایل، داده‌های فعلی آیفون کامل جایگزین می‌شوند.")
                        .foregroundStyle(.orange)
                }
            }
        }
        .navigationTitle("گزارش ورود")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("انصراف", action: onCancel)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("ورود به اپ", action: onConfirm)
                    .bold()
                    .disabled(!report.canImport)
            }
        }
    }
}

struct AccountNumbers: View {
    let account: AccountImportSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(account.name).font(.headline)
            LabeledContent("ردیف‌ها", value: Fmt.count(account.rows))
            LabeledContent("جمع دفتر (بدون تنخواه)", value: Fmt.toman(account.expenseTotal))
            if account.tankhahTotal != 0 {
                LabeledContent("جمع تنخواه", value: Fmt.toman(account.tankhahTotal))
            }
            if account.commissionEnabled || account.percent != 0 {
                LabeledContent("کمیسیون", value: Fmt.percent(account.percent))
                LabeledContent("پرداخت‌شده", value: Fmt.toman(account.settled))
                LabeledContent("مانده‌ی کمیسیون", value: Fmt.balance(account.remaining))
                    .bold()
            }
        }
        .font(.subheadline)
        .padding(.vertical, 4)
    }
}

struct IssueRow: View {
    let issue: ImportIssue

    var body: some View {
        DisclosureGroup {
            ForEach(Array(issue.details.enumerated()), id: \.offset) { _, line in
                Text(line).font(.footnote).foregroundStyle(.secondary)
            }
        } label: {
            Label(issue.title, systemImage: icon)
                .foregroundStyle(color)
        }
    }

    private var icon: String {
        switch issue.level {
        case .blocking: return "xmark.octagon.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .info: return "info.circle.fill"
        }
    }

    private var color: Color {
        switch issue.level {
        case .blocking: return .red
        case .warning: return .orange
        case .info: return .blue
        }
    }
}

// MARK: - accounts

struct AccountsView: View {
    @ObservedObject var model: AppModel
    @Binding var showImporter: Bool
    @Binding var exportFile: ExportFile?

    var body: some View {
        List {
            Section {
                ForEach(model.accounts) { a in
                    NavigationLink {
                        LedgerView(model: model, account: a)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(a.name).font(.headline)
                            Text(Fmt.toman(a.expenseTotal)).font(.subheadline).foregroundStyle(.secondary)
                            if a.commissionEnabled || a.percent != 0 {
                                Text("مانده‌ی کمیسیون: " + Fmt.balance(a.remaining))
                                    .font(.subheadline)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            } header: {
                Text("دفترها")
            }

            Section {
                LabeledContent("هزینه‌های شخصی", value: Fmt.toman(model.personalTotal))
                LabeledContent("درآمدها", value: Fmt.toman(model.incomeTotal))
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    if let t = model.lastImportText { Text(t) }
                    Text("نسخه‌ی آزمایشی: فعلاً فقط نمایش است. ثبت و ویرایش در مرحله‌ی بعد اضافه می‌شود.")
                }
            }
        }
        .navigationTitle("دفتر حساب")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        exportFile = model.makeExportFile()
                    } label: {
                        Label("خروجی پشتیبان کامل", systemImage: "square.and.arrow.up")
                    }
                    Button {
                        showImporter = true
                    } label: {
                        Label("ورود دوباره‌ی پشتیبان", systemImage: "square.and.arrow.down")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
    }
}

struct LedgerView: View {
    @ObservedObject var model: AppModel
    let account: AccountImportSummary

    var body: some View {
        let rows = model.rows(accountId: account.id)
        List {
            Section {
                AccountNumbers(account: account)
            }
            Section {
                ForEach(rows) { r in
                    HStack(alignment: .top, spacing: 10) {
                        Text(Fmt.count(r.number))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 24, alignment: .leading)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(r.desc).font(.subheadline)
                            HStack(spacing: 6) {
                                Text(r.date)
                                if r.kind == .commission { Text("کمیسیون").foregroundStyle(.purple) }
                                if r.kind == .tankhah { Text("تنخواه").foregroundStyle(.teal) }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        Text(Fmt.toman(r.toman))
                            .font(.subheadline.monospacedDigit())
                    }
                }
            } header: {
                Text("ردیف‌ها (\(Fmt.count(rows.count)))")
            }
        }
        .navigationTitle(account.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - share sheet

struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
