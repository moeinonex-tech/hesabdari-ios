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
                        LedgerView(model: model, accountId: a.id)
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
                    Text("برای ثبت، ویرایش، حذف و پرداخت کمیسیون، وارد هر دفتر شوید.")
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
    let accountId: String

    enum Sheet: Identifiable {
        case new, edit(LedgerRowVM), settle
        var id: String {
            switch self {
            case .new: return "new"
            case .edit(let r): return "edit-" + r.rowId
            case .settle: return "settle"
            }
        }
    }

    @State private var sheet: Sheet?
    @State private var pendingLocked: (() -> Void)?
    @State private var showPassword = false
    @State private var password = ""

    private var account: AccountImportSummary? { model.accounts.first { $0.id == accountId } }

    var body: some View {
        let rows = model.rows(accountId: accountId)
        List {
            if let a = account {
                Section {
                    AccountNumbers(account: a)
                    if a.commissionEnabled || a.percent != 0 {
                        Button {
                            sheet = .settle
                        } label: {
                            Label("پرداخت کمیسیون", systemImage: "banknote")
                        }
                    }
                }
            }
            Section {
                ForEach(rows.reversed()) { r in
                    RowView(row: r)
                        .contentShape(Rectangle())
                        .onTapGesture { guarded(r) { sheet = .edit(r) } }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                guarded(r) { _ = model.delete(rowId: r.rowId) }
                            } label: {
                                Label("حذف", systemImage: "trash")
                            }
                            Button {
                                guarded(r) { sheet = .edit(r) }
                            } label: {
                                Label("ویرایش", systemImage: "pencil")
                            }
                            .tint(.blue)
                        }
                }
            } header: {
                Text("ردیف‌ها (\(Fmt.count(rows.count))) — جدیدترین بالا")
            }
        }
        .navigationTitle(account?.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    sheet = .new
                } label: {
                    Image(systemName: "plus.circle.fill")
                }
            }
        }
        .sheet(item: $sheet) { s in
            NavigationStack {
                switch s {
                case .new:
                    ExpenseFormView(model: model, accountId: accountId, editing: nil)
                case .edit(let r):
                    ExpenseFormView(model: model, accountId: accountId, editing: r)
                case .settle:
                    SettleView(model: model, accountId: accountId)
                }
            }
            .environment(\.layoutDirection, .rightToLeft)
        }
        .alert("این رکورد قدیمیه", isPresented: $showPassword) {
            SecureField("رمز", text: $password)
            Button("تأیید") {
                if model.unlock(password: password) {
                    let action = pendingLocked
                    pendingLocked = nil
                    action?()
                } else {
                    model.errorMessage = "رمز اشتباهه"
                }
                password = ""
            }
            Button("انصراف", role: .cancel) { pendingLocked = nil; password = "" }
        } message: {
            Text("این رکورد مربوط به بیش از ۸ روز پیشه. برای ویرایش یا حذفش، رمز رو وارد کن.")
        }
        .overlay(alignment: .bottom) { UndoBanner(model: model) }
    }

    /// Linked rows are managed elsewhere; old rows need the password first (web withEditUnlock).
    private func guarded(_ r: LedgerRowVM, _ action: @escaping () -> Void) {
        if r.isLinked {
            model.errorMessage = LedgerError.linkedRow("چک یا بدهی").message
            return
        }
        if model.isLocked(r.dateValue) {
            pendingLocked = action
            showPassword = true
        } else {
            action()
        }
    }
}

struct RowView: View {
    let row: LedgerRowVM

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(Fmt.count(row.number))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 24, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                Text(row.desc.isEmpty ? "—" : row.desc).font(.subheadline)
                HStack(spacing: 6) {
                    Text(row.date)
                    if row.kind == .commission { Text("کمیسیون").foregroundStyle(.purple) }
                    if row.kind == .tankhah { Text("تنخواه").foregroundStyle(.teal) }
                    if row.isLinked { Image(systemName: "link") }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text(Fmt.toman(row.toman))
                .font(.subheadline.monospacedDigit())
        }
    }
}

struct UndoBanner: View {
    @ObservedObject var model: AppModel

    var body: some View {
        if let u = model.undo {
            HStack {
                Text(u.message)
                Spacer()
                Button("برگرداندن") { model.performUndo() }
                    .bold()
            }
            .padding()
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .padding()
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

// MARK: - forms

struct JalaliDateField: View {
    let title: String
    @Binding var date: JalaliDate

    var body: some View {
        DatePicker(title, selection: Binding(get: { Fmt.date(date) }, set: { date = Fmt.jalali($0) }),
                   displayedComponents: .date)
            .environment(\.calendar, Calendar(identifier: .persian))
            .environment(\.locale, Locale(identifier: "fa_IR"))
    }
}

struct AmountField: View {
    let title: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField(title, text: $text)
                .keyboardType(.numberPad)
                .font(.title3.monospacedDigit())
                .onChange(of: text) { _, new in
                    let n = Fmt.parseAmount(new)
                    let formatted = n > 0 ? Money.persianDigits(Money.format(n)) : ""
                    if formatted != new { text = formatted }
                }
            if Fmt.parseAmount(text) > 0 {
                Text(Fmt.toman(Fmt.parseAmount(text)) + " · " + Money.persianDigits(Money.format(Fmt.parseAmount(text) * 10)) + " ریال")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct SuggestField: View {
    let title: String
    @Binding var text: String
    let suggestions: [String]

    var body: some View {
        HStack {
            TextField(title, text: $text)
            if !suggestions.isEmpty {
                Menu {
                    ForEach(suggestions, id: \.self) { s in
                        Button(s) { text = s }
                    }
                } label: {
                    Image(systemName: "chevron.down.circle")
                }
            }
        }
    }
}

struct ExpenseFormView: View {
    @ObservedObject var model: AppModel
    let accountId: String
    let editing: LedgerRowVM?
    @Environment(\.dismiss) private var dismiss

    @State private var isTankhah = false
    @State private var desc = ""
    @State private var category = ""
    @State private var subcategory = ""
    @State private var amount = ""
    @State private var date = AppModel.today
    @State private var payMethod = PayMethod.hamrahbank
    @State private var cardId: String?
    @State private var partyId: String?
    @State private var loaded = false

    private var isCommission: Bool { editing?.kind == .commission }

    var body: some View {
        Form {
            if editing == nil {
                Picker("نوع", selection: $isTankhah) {
                    Text("هزینه").tag(false)
                    Text("تنخواه").tag(true)
                }
                .pickerStyle(.segmented)
                .onChange(of: isTankhah) { _, t in
                    payMethod = PayMethod.defaultFor(tankhah: t)
                }
            }

            if isCommission {
                Section {
                    Text(desc).font(.footnote).foregroundStyle(.secondary)
                } footer: {
                    Text("این ردیف پرداخت کمیسیون است. با تغییر مبلغ، مانده‌ی این پرداخت و پرداخت‌های بعدی دوباره حساب می‌شود.")
                }
            } else if isTankhah {
                Section("طرف حساب") {
                    Picker("طرف حساب", selection: $partyId) {
                        Text("انتخاب کنید").tag(String?.none)
                        ForEach(model.tankhahParties) { p in
                            Text(p.label).tag(Optional(p.id))
                        }
                    }
                    TextField("شرح (اختیاری)", text: $desc)
                }
            } else {
                Section {
                    TextField("شرح", text: $desc)
                    SuggestField(title: "نوع هزینه", text: $category, suggestions: model.ledgerCategories)
                    SuggestField(title: "زیردسته", text: $subcategory, suggestions: model.subcategories(of: category))
                }
            }

            Section {
                AmountField(title: "مبلغ (تومان)", text: $amount)
                JalaliDateField(title: "تاریخ", date: $date)
            }

            if !isCommission {
                Section(isTankhah ? "روش دریافت" : "روش پرداخت") {
                    Picker("روش", selection: $payMethod) {
                        ForEach(PayMethod.available(forTankhah: isTankhah) + extraMethod, id: \.self) { m in
                            Text(m.title).tag(m)
                        }
                    }
                    if payMethod.usesCard && !model.activeCards.isEmpty {
                        Picker("کارت", selection: $cardId) {
                            Text("بدون کارت").tag(String?.none)
                            ForEach(model.activeCards) { c in
                                Text(c.label).tag(Optional(c.id))
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(editing == nil ? "ثبت جدید" : "ویرایش")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("انصراف") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("ذخیره") { save() }.bold() }
        }
        .onAppear(perform: load)
    }

    /// An existing row may use a method this version cannot create yet; keep it selectable so it is not changed.
    private var extraMethod: [PayMethod] {
        guard let m = editing?.payMethod.flatMap(PayMethod.init(rawValue:)),
              !PayMethod.available(forTankhah: isTankhah).contains(m) else { return [] }
        return [m]
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let r = editing {
            isTankhah = r.kind == .tankhah
            desc = r.desc; category = r.category; subcategory = r.subcategory
            amount = Money.persianDigits(Money.format(r.toman))
            date = r.dateValue
            payMethod = r.payMethod.flatMap(PayMethod.init(rawValue:)) ?? PayMethod.defaultFor(tankhah: isTankhah)
            cardId = r.cardId; partyId = r.partyId
        } else {
            payMethod = .hamrahbank
            cardId = model.defaultCard(accountId: accountId)
        }
    }

    private func save() {
        let input = ExpenseInput(accountId: accountId, isTankhah: isTankhah, desc: desc, category: category,
                                 subcategory: subcategory, toman: Fmt.parseAmount(amount), date: date,
                                 payMethod: payMethod, cardId: payMethod.usesCard ? cardId : nil,
                                 partyId: isTankhah ? partyId : nil)
        let ok = editing.map { model.edit(rowId: $0.rowId, input) } ?? model.add(input)
        if ok { dismiss() }
    }
}

struct SettleView: View {
    @ObservedObject var model: AppModel
    let accountId: String
    @Environment(\.dismiss) private var dismiss
    @State private var amount = ""
    @State private var date = AppModel.today
    @State private var loaded = false

    var body: some View {
        let account = model.accounts.first { $0.id == accountId }
        let n = Fmt.parseAmount(amount)
        Form {
            if let a = account {
                Section {
                    LabeledContent("کمیسیون تا امروز", value: Fmt.toman(a.accrued))
                    if a.balance != 0 {
                        LabeledContent(a.balance > 0 ? "بدهی قبلی" : "بستانکاری قبلی", value: Fmt.toman(a.balance))
                    }
                    LabeledContent("قابل پرداخت", value: Fmt.balance(a.remaining)).bold()
                }
            }
            Section {
                AmountField(title: "مبلغ پرداخت (تومان)", text: $amount)
                JalaliDateField(title: "تاریخ", date: $date)
            }
            if let after = model.previewRemaining(accountId: accountId, amount: n, date: date) {
                Section {
                    if after == 0 {
                        Label("تسویه کامل", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
                    } else if after > 0 {
                        Label("بعد از این پرداخت " + Fmt.toman(after) + " بدهی می‌ماند و به کمیسیون بعدی اضافه می‌شود",
                              systemImage: "exclamationmark.circle").foregroundStyle(.orange)
                    } else {
                        Label(Fmt.toman(after) + " اضافه پرداخت می‌شود و از کمیسیون بعدی کم می‌شود",
                              systemImage: "arrow.uturn.down.circle").foregroundStyle(.blue)
                    }
                } footer: {
                    Text("یک ردیف «پرداخت کمیسیون» در دفتر و یک ردیف «دریافت کمیسیون» در درآمدها ثبت می‌شود.")
                }
            }
        }
        .navigationTitle("پرداخت کمیسیون")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("انصراف") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("ثبت پرداخت") {
                    if model.settle(accountId: accountId, amount: n, date: date) { dismiss() }
                }
                .bold()
                .disabled(n <= 0)
            }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            if let a = account, a.remaining > 0 { amount = Money.persianDigits(Money.format(a.remaining)) }
        }
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
