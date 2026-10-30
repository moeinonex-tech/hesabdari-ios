import SwiftUI
import UIKit
import UniformTypeIdentifiers
import HesabCore

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
    @State private var linkParty = ""      // check: payee / nasiyeh: creditor
    @State private var checkBank = ""
    @State private var checkNumber = ""
    @State private var sayadId = ""
    @State private var nasiyehDue = AppModel.today

    private var isCommission: Bool { editing?.kind == .commission }
    private var makesCheck: Bool { editing == nil && !isTankhah && payMethod == .check }
    private var makesNasiyeh: Bool { editing == nil && !isTankhah && payMethod == .nasiyeh }

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
                    NavigationLink {
                        TankhahPartyPicker(model: model, partyId: $partyId)
                    } label: {
                        LabeledContent("طرف حساب", value: model.tankhahParties.first { $0.id == partyId }?.label ?? "انتخاب کنید")
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
                JalaliDateField(title: makesCheck ? "تاریخ سررسید چک" : "تاریخ", date: $date)
            }

            if !isCommission {
                Section(isTankhah ? "روش دریافت" : "روش پرداخت") {
                    Picker("روش", selection: $payMethod) {
                        ForEach(methods, id: \.self) { m in
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
                if makesCheck {
                    Section {
                        SuggestField(title: "در وجه (طرف چک)", text: $linkParty, suggestions: model.partyNames)
                        TextField("بانک", text: $checkBank)
                        TextField("شماره چک", text: $checkNumber).keyboardType(.numberPad)
                        TextField("شناسه صیاد (اختیاری)", text: $sayadId).keyboardType(.numberPad)
                    } header: {
                        Text("اطلاعات چک")
                    } footer: {
                        Text("چک در «یادآوری‌ها» ثبت می‌شود و یک ردیف «در انتظار وصول» در همین دفتر می‌سازد. وقتی وصول شد، از یادآوری‌ها علامتش بزنید.")
                    }
                }
                if makesNasiyeh {
                    Section {
                        SuggestField(title: "طلبکار (فروشنده)", text: $linkParty, suggestions: model.creditorNames)
                        JalaliDateField(title: "سررسید پرداخت", date: $nasiyehDue)
                    } header: {
                        Text("نسیه")
                    } footer: {
                        Text("این مبلغ به‌عنوان بدهی به این شخص در «یادآوری‌ها» ثبت می‌شود و شب قبل از سررسید یادآوری می‌آید.")
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

    /// New rows: every method (check / nasiyeh create linked reminders). Edits keep the row's own method selectable.
    private var methods: [PayMethod] {
        var list = PayMethod.available(forTankhah: isTankhah)
        if editing != nil { list.removeAll { $0 == .check || $0 == .nasiyeh } }
        if let m = editing?.payMethod.flatMap(PayMethod.init(rawValue:)), !list.contains(m) { list.append(m) }
        return list
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
        let ok: Bool
        if makesCheck {
            ok = model.addCheck(CheckInput(amount: input.toman, party: linkParty, bankName: checkBank, checkNumber: checkNumber,
                                           sayadId: sayadId, checkSeries: "", desc: desc, category: category,
                                           subcategory: subcategory, dueDate: date, accountId: accountId))
        } else if makesNasiyeh {
            ok = model.addNasiyehExpense(input, party: linkParty, due: nasiyehDue)
        } else {
            ok = editing.map { model.edit(rowId: $0.rowId, input) } ?? model.add(input)
        }
        if ok { Haptics.success(); dismiss() }
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
