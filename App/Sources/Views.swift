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

/// Date field: the phone's own calendar (Persian, Iran time). Tapping the date opens it in a half-height sheet with
/// «امروز» at its top centre — away from the fields, so editing an old row never jumps to today by accident.
struct JalaliDateField: View {
    let title: String
    @Binding var date: JalaliDate
    @State private var open = false
    @Environment(\.theme) private var t

    private static let persian: Calendar = { var c = Calendar(identifier: .persian); c.timeZone = Fmt.tehran; return c }()

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
            Spacer(minLength: 8)
            Button {
                Haptics.tap()
                open = true
            } label: {
                Text(BackupExporter.formatJalali(date))
                    .font(AppFont.medium(15)).foregroundStyle(t.ink)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(t.ink.opacity(0.08), in: Capsule())
            }
            .buttonStyle(.plain)
            // the phone's calendar in a half-height sheet (full width, nothing cut off); «امروز» on its top bar
            .sheet(isPresented: $open) {
                NavigationStack {
                    DatePicker("", selection: Binding(get: { Fmt.date(date) }, set: { date = Fmt.jalali($0); open = false }),
                               displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .labelsHidden()
                        .environment(\.calendar, Self.persian)
                        .environment(\.timeZone, Fmt.tehran)
                        .environment(\.locale, Locale(identifier: "fa_IR"))
                        .padding(.horizontal, 16)
                        .frame(maxHeight: .infinity, alignment: .top)
                        .navigationTitle(title)
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .principal) {
                                Button {
                                    Haptics.tap()
                                    date = AppModel.today
                                    open = false
                                } label: {
                                    Label("امروز", systemImage: "smallcircle.filled.circle")
                                        .font(AppFont.bold(14)).foregroundStyle(t.accent)
                                        .padding(.horizontal, 14).padding(.vertical, 6)
                                        .background(t.accent.opacity(0.12), in: Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                            ToolbarItem(placement: .cancellationAction) {
                                Button { open = false } label: { Image(systemName: "xmark") }
                            }
                        }
                }
                .presentationDetents([.height(500)])
                .presentationDragIndicator(.visible)
            }
        }
    }
}

/// Amount entry: the digits show big and bold while typing, grouped (۱۲.۵۰۰.۰۰۰) as they are typed, cursor kept at the end.
/// UIKit text field, because SwiftUI's TextField loses the display when the text is rewritten while editing.
struct AmountField: View {
    let title: String
    @Binding var text: String
    @Environment(\.theme) private var t

    var body: some View {
        let n = Fmt.parseAmount(text)
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(AppFont.medium(12)).foregroundStyle(t.soft)
            MoneyTextField(text: $text, placeholder: "۰")
                .frame(height: 34)
            if n > 0 {
                // live helpers: the amount in rials and in words (toman)
                Text(Money.persianDigits(Money.format(n * 10)) + " ریال")
                    .font(AppFont.medium(12)).foregroundStyle(t.soft)
                Text(PersianWords.of(n) + " تومان")
                    .font(AppFont.regular(12)).foregroundStyle(t.accent.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 2)
    }
}

struct MoneyTextField: UIViewRepresentable {
    @Binding var text: String
    var placeholder = ""
    var size: CGFloat = 22

    func makeUIView(context: Context) -> UITextField {
        let f = UITextField()
        f.keyboardType = .numberPad
        f.font = UIFont(name: "Vazirmatn-Bold", size: size) ?? .systemFont(ofSize: size, weight: .bold)
        f.textAlignment = .natural
        f.semanticContentAttribute = .forceRightToLeft
        f.placeholder = placeholder
        f.accessibilityIdentifier = "amount"
        f.adjustsFontSizeToFitWidth = true
        f.minimumFontSize = 14
        f.delegate = context.coordinator
        f.text = text
        f.setContentHuggingPriority(.defaultLow, for: .horizontal)
        f.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return f
    }

    func updateUIView(_ f: UITextField, context: Context) {
        if f.text != text { f.text = text }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: MoneyTextField
        init(_ p: MoneyTextField) { parent = p }

        func textField(_ f: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
            let old = f.text ?? ""
            guard let r = Range(range, in: old) else { return false }
            var next = old.replacingCharacters(in: r, with: string)
            // deleting a separator deletes the digit before it
            if string.isEmpty, range.length == 1, old[r] == "." || old[r] == "٬" || old[r] == "," {
                let digitsBefore = SearchEngine.latinDigits(String(old[..<r.lowerBound])).filter(\.isNumber)
                let digitsAfter = SearchEngine.latinDigits(String(old[r.upperBound...])).filter(\.isNumber)
                next = String(digitsBefore.dropLast()) + digitsAfter
            }
            let digits = String(SearchEngine.latinDigits(next).filter(\.isNumber).prefix(15))
            let n = Int(digits) ?? 0
            let formatted = n > 0 ? Money.persianDigits(Money.format(n)) : ""
            f.text = formatted
            parent.text = formatted
            let end = f.endOfDocument
            f.selectedTextRange = f.textRange(from: end, to: end)
            return false
        }
    }
}

struct SuggestField: View {
    let title: String
    @Binding var text: String
    let suggestions: [String]
    /// category / subcategory fields: a typed value that is almost an existing one asks «منظورتان X است؟» (web
    /// confirmFuzzyDuplicate). The owner decides: pick the existing one, or keep the new name exactly as typed.
    var dedupe = false
    @FocusState private var focused: Bool
    @State private var similar: [String] = []
    @State private var checked = ""

    var body: some View {
        HStack {
            TextField(title, text: $text)
                .focused($focused)
                .onSubmit { checkSimilar() }
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
        .onChange(of: focused) { _, f in if !f { checkSimilar() } }
        .confirmationDialog("عبارت مشابه پیدا شد", isPresented: Binding(get: { !similar.isEmpty }, set: { if !$0 { similar = [] } }),
                            titleVisibility: .visible) {
            ForEach(similar, id: \.self) { s in
                Button(similar.count == 1 ? "بله، «\(s)»" : s) { text = s; checked = s }
            }
            Button("خیر، مورد جدید است", role: .cancel) {}
        } message: {
            Text(similar.count == 1 ? "منظورتان «\(similar.first ?? "")» است؟" : "کدام‌یک منظور شماست؟")
        }
    }

    private func checkSimilar() {
        guard dedupe else { return }
        let v = text.trimmingCharacters(in: .whitespaces)
        guard !v.isEmpty, v != checked else { return }
        checked = v
        similar = Fuzzy.matches(suggestions, v)
    }
}

struct ExpenseFormView: View {
    @ObservedObject var model: AppModel
    let accountId: String
    let editing: LedgerRowVM?
    @Environment(\.dismiss) private var dismiss

    @State private var isTankhah = false
    @State private var isReward = false
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
    @State private var itemCount = 1
    @State private var items: [ExpenseItem] = []
    @State private var checkCount = 1
    @State private var slots: [CheckSlot] = []
    @State private var checkTotal = ""
    @State private var loadedPay: PayMethod?
    // تنخواه received by check
    @State private var tkCheckId: String?        // nil = record a new check
    @State private var tkAmount = ""
    @State private var tkBank = ""
    @State private var tkNumber = ""
    @State private var tkDesc = ""
    @State private var tkDue = AppModel.today

    private var isCommission: Bool { editing?.kind == .commission }
    private var isMulti: Bool { itemCount > 1 && !isTankhah && !isReward && !isCommission && !makesCheck }
    private var multiCheck: Bool { makesCheck && checkCount > 1 }
    private var makesCheck: Bool { editing == nil && !isTankhah && !isReward && payMethod == .check }
    private var makesNasiyeh: Bool { editing == nil && !isTankhah && !isReward && payMethod == .nasiyeh }
    /// 0 هزینه · 1 تنخواه · 2 پاداش
    private var kindBinding: Binding<Int> {
        Binding(get: { isTankhah ? 1 : (isReward ? 2 : 0) }, set: { k in
            let wasTankhah = isTankhah
            isTankhah = k == 1
            isReward = k == 2
            if wasTankhah != isTankhah { payMethod = PayMethod.defaultFor(tankhah: isTankhah) }
            if isReward, payMethod == .check || payMethod == .nasiyeh { payMethod = PayMethod.defaultFor(tankhah: false) }
        })
    }
    private var tankhahByCheck: Bool { editing == nil && isTankhah && payMethod == .check }

    var body: some View {
        Form {
            if editing == nil && !isTankhah && !isReward {
                NotesImportLink(model: model, ledgerAccountId: accountId) { dismiss() }
            }
            if editing == nil {
                Segmented(selection: kindBinding, [(0, "هزینه"), (1, "تنخواه"), (2, "پاداش")])
                    .accessibilityIdentifier("ledger.kind")
            }

            if isCommission {
                // a commission payment: every field is editable
                Section {
                    TextField("شرح", text: $desc, axis: .vertical).lineLimit(1...4)
                    SuggestField(title: "نوع هزینه", text: $category, suggestions: model.ledgerCategories, dedupe: true)
                    SuggestField(title: "زیردسته", text: $subcategory, suggestions: model.subcategories(of: category), dedupe: true)
                } footer: {
                    Text("این ردیف پرداخت کمیسیون است. با تغییر مبلغ، مانده‌ی این پرداخت و پرداخت‌های بعدی دوباره حساب می‌شود و متن مانده‌ها به‌روز می‌شود.")
                }
            } else if isReward {
                Section {
                    TextField("شرح (اختیاری)", text: $desc)
                    if editing != nil {
                        Toggle("پاداش (بدون کمیسیون)", isOn: $isReward)
                    }
                } header: {
                    Label("پاداش کارفرما", systemImage: "gift.fill")
                } footer: {
                    Text("پاداشی که کارفرما جدا از کمیسیون درصدی به شما می‌دهد. در دفتر مثل یک هزینه ثبت می‌شود، با کادر سبز روشن، ولی هیچ‌وقت کمیسیون از آن حساب نمی‌شود.")
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
                    if editing != nil && !isMulti {
                        Toggle("پاداش (بدون کمیسیون)", isOn: $isReward)
                    }
                    if !makesCheck { CountRow(title: "تعداد اقلام", count: itemCountBinding, max: MultiItem.maxCount) }
                    if !isMulti {
                        SuggestField(title: "نوع هزینه", text: $category, suggestions: model.ledgerCategories, dedupe: true)
                        LearnChips(model: model, ctx: .ledger, desc: desc, category: $category, subcategory: $subcategory, sub: false)
                        SuggestField(title: "زیردسته", text: $subcategory, suggestions: model.subcategories(of: category), dedupe: true)
                        LearnChips(model: model, ctx: .ledger, desc: desc, category: $category, subcategory: $subcategory, sub: true)
                    }
                }
                if isMulti {
                    MultiItemSections(model: model, ctx: .ledger, mainDesc: desc, items: $items,
                                      categories: model.ledgerCategories, subcategories: { model.subcategories(of: $0) })
                }
            }

            if !multiCheck {
                Section {
                    if !isMulti { AmountField(title: "مبلغ (تومان)", text: $amount) }
                    JalaliDateField(title: makesCheck ? "تاریخ سررسید چک" : "تاریخ", date: $date)
                }
            }

            Group {
                Section {
                    Picker("روش", selection: $payMethod) {
                        ForEach(methods, id: \.self) { m in
                            Text(m.title).tag(m)
                        }
                    }
                    if payMethod.usesCard && !model.activeCards.isEmpty {
                        CardPicker(model: model, cardId: $cardId)
                    }
                } header: {
                    Text(isTankhah ? "روش دریافت" : "روش پرداخت")
                } footer: {
                    if editing != nil && (editing?.payMethod ?? "").isEmpty {
                        Text("این ردیف روش پرداخت نداشت؛ با ذخیره، روشی که این‌جا انتخاب شده ثبت می‌شود.").foregroundStyle(.orange)
                    }
                }
                if makesCheck {
                    Section {
                        CountRow(title: "تعداد چک", count: checkCountBinding, max: CheckGroup.maxCount)
                        SuggestField(title: "در وجه (طرف چک)", text: $linkParty, suggestions: model.partyNames)
                        BankNameField(title: "بانک", text: $checkBank)
                        if !multiCheck {
                            TextField("شماره چک", text: $checkNumber).keyboardType(.numberPad)
                            TextField("شناسه صیاد (اختیاری)", text: $sayadId).keyboardType(.numberPad)
                        }
                    } header: {
                        Text("اطلاعات چک")
                    } footer: {
                        Text("چک در «یادآوری‌ها» ثبت می‌شود و یک ردیف «در انتظار وصول» در همین دفتر می‌سازد. وقتی وصول شد، از یادآوری‌ها علامتش بزنید.")
                    }
                    if multiCheck { MultiCheckSections(slots: $slots, total: $checkTotal) }
                }
                if tankhahByCheck {
                    let open = model.openTankhahChecks
                    Section {
                        if !open.isEmpty {
                            Picker("چک", selection: $tkCheckId) {
                                Text("ثبت چک جدید").tag(String?.none)
                                ForEach(open, id: \.id) { c in Text(c.label).tag(String?.some(c.id)) }
                            }
                        }
                        if tkCheckId == nil {
                            TextField("شماره چک", text: $tkNumber).keyboardType(.numberPad)
                            AmountField(title: "مبلغ چک (تومان) — خالی = همان مبلغ تنخواه", text: $tkAmount)
                            BankNameField(title: "نام بانک", text: $tkBank)
                            JalaliDateField(title: "تاریخ سررسید چک", date: $tkDue)
                            TextField("توضیحات چک (اختیاری)", text: $tkDesc)
                        }
                    } header: {
                        Text("چک تنخواه (دریافتی)")
                    } footer: {
                        Text("چک فقط به‌عنوان رکورد این پروژه در «یادآوری‌ها» ثبت می‌شود؛ ردیف هزینه نمی‌سازد و روی جمع‌ها اثر ندارد. وقتی وصول شد، کنار همین تنخواه «وصول شد» نوشته می‌شود.")
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
        .onChange(of: makesCheck) { _, check in if check && itemCount > 1 { itemCountBinding.wrappedValue = 1 } }
    }

    /// New rows: every method (check / nasiyeh create linked reminders). Edits keep the row's own method selectable.
    private var methods: [PayMethod] {
        var list = PayMethod.available(forTankhah: isTankhah)
        if editing != nil || isReward { list.removeAll { $0 == .check || $0 == .nasiyeh } }
        if let m = editing?.payMethod.flatMap(PayMethod.init(rawValue:)), !list.contains(m) { list.append(m) }
        return list
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let r = editing {
            isTankhah = r.kind == .tankhah
            isReward = r.kind == .reward
            desc = r.desc; category = r.category; subcategory = r.subcategory
            amount = Money.persianDigits(Money.format(r.toman))
            date = r.dateValue
            payMethod = r.payMethod.flatMap(PayMethod.init(rawValue:)) ?? PayMethod.defaultFor(tankhah: isTankhah)
            cardId = r.cardId; partyId = r.partyId
            loadedPay = payMethod
            let its = model.items(ofRow: "expenses", r.rowId)
            if its.count > 1 && r.kind != .tankhah { items = its; itemCount = its.count }
        } else {
            payMethod = .hamrahbank
            cardId = model.defaultCard(accountId: accountId)
        }
    }

    /// the count and its rows change in one step (never a frame where they disagree)
    private var itemCountBinding: Binding<Int> {
        Binding(get: { itemCount }, set: { new in
            let old = itemCount
            guard new != old else { return }
        if new > 1 {
            if items.count != new {
                MultiItemState.resize(&items, to: new, from: old, single: (category, subcategory, Fmt.parseAmount(amount)))
            }
        } else if old > 1, let first = items.first {
            category = first.category; subcategory = first.subcategory
            amount = first.toman > 0 ? Money.persianDigits(Money.format(first.toman)) : ""
            items = []
        }
            itemCount = new
        })
    }
    /// the count and its rows change in one step (never a frame where they disagree)
    private var checkCountBinding: Binding<Int> {
        Binding(get: { checkCount }, set: { new in
            let old = checkCount
            guard new != old else { return }
        if new > 1 {
            MultiCheckSections.resize(&slots, to: new, first: CheckSlot(amount: Fmt.parseAmount(amount), due: date, number: checkNumber, sayad: sayadId))
        } else if old > 1, let first = slots.first {
            amount = first.amount > 0 ? Money.persianDigits(Money.format(first.amount)) : ""
            date = first.due; checkNumber = first.number; sayadId = first.sayad
            slots = []
        }
            checkCount = new
        })
    }

    private func save() {
        var input = ExpenseInput(accountId: accountId, isTankhah: isTankhah, desc: desc, category: category,
                                 subcategory: subcategory, toman: Fmt.parseAmount(amount), date: date,
                                 payMethod: payMethod, cardId: payMethod.usesCard ? cardId : nil,
                                 partyId: isTankhah ? partyId : nil)
        input.isReward = isReward && !isTankhah && !isCommission
        if isMulti { input.items = items; input.toman = items.reduce(0) { $0 + $1.toman } }
        let ok: Bool
        if multiCheck {
            ok = model.addChecks(CheckInput(amount: 0, party: linkParty, bankName: checkBank, checkNumber: "", sayadId: "", checkSeries: "",
                                            desc: desc, category: category, subcategory: subcategory, dueDate: date, accountId: accountId),
                                 slots: slots, total: Fmt.parseAmount(checkTotal))
        } else if makesCheck {
            ok = model.addCheck(CheckInput(amount: input.toman, party: linkParty, bankName: checkBank, checkNumber: checkNumber,
                                           sayadId: sayadId, checkSeries: "", desc: desc, category: category,
                                           subcategory: subcategory, dueDate: date, accountId: accountId))
        } else if makesNasiyeh {
            ok = model.addNasiyehExpense(input, party: linkParty, due: nasiyehDue)
        } else if tankhahByCheck {
            let checkAmount = Fmt.parseAmount(tkAmount) > 0 ? Fmt.parseAmount(tkAmount) : input.toman
            let party = model.tankhahParties.first { $0.id == partyId }?.label ?? ""
            ok = model.addTankhahWithCheck(input, existingCheckId: tkCheckId, amount: checkAmount, party: party, bank: tkBank,
                                           number: tkNumber, desc: tkDesc, due: tkDue)
        } else {
            ok = editing.map { model.edit(rowId: $0.rowId, input) } ?? model.add(input)
        }
        if ok { Haptics.success(); dismiss() }
    }
}

/// Commission payment. The open rows (only the ones after the last payment) are listed with what the commission
/// would be up to each of them; a gauge (or a tap on a row) picks the last row this payment covers. The rows after it
/// stay open, and the live commission shown in the app always counts every open row.
struct SettleView: View {
    @ObservedObject var model: AppModel
    let accountId: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var t
    @State private var amount = ""
    @State private var autoAmount = ""
    @State private var date = AppModel.today
    @State private var loaded = false
    @State private var cut = 0
    @State private var open: [OpenRow] = []
    @State private var payMethod: PayMethod?
    @State private var cardId: String?

    private var balance: Int { model.accounts.first { $0.id == accountId }?.balance ?? 0 }
    private var chosen: OpenRow? { open.indices.contains(cut) ? open[cut] : nil }
    private var due: Int { (chosen?.cumulativeCommission ?? 0) + balance }
    private var isAll: Bool { cut >= open.count - 1 }
    private var upTo: String? { isAll ? nil : chosen?.key }

    var body: some View {
        let account = model.accounts.first { $0.id == accountId }
        let n = Fmt.parseAmount(amount)
        Form {
            if let a = account {
                Section {
                    LabeledContent("کمیسیون همه‌ی ردیف‌های باز", value: Fmt.toman(a.accrued))
                    if a.balance != 0 {
                        LabeledContent(a.balance > 0 ? "بدهی قبلی" : "بستانکاری قبلی", value: Fmt.toman(abs(a.balance)))
                    }
                    LabeledContent("کل قابل پرداخت", value: Fmt.balance(a.remaining)).bold()
                } footer: {
                    if let f = open.first, let l = open.last {
                        Text(openFooter(f.num, l.num))
                    }
                }
            }

            if !open.isEmpty { gauge }

            Section {
                AmountField(title: "مبلغ پرداخت (تومان)", text: $amount)
                JalaliDateField(title: "تاریخ", date: $date)
            }
            Section {
                Picker("روش", selection: $payMethod) {
                    Text("انتخاب کنید").tag(PayMethod?.none)
                    ForEach(Self.methods, id: \.self) { m in Text(m.title).tag(PayMethod?.some(m)) }
                }
                .accessibilityIdentifier("settle.method")
                if let m = payMethod, m.usesCard, !model.activeCards.isEmpty {
                    CardPicker(model: model, cardId: $cardId)
                }
            } header: {
                Text("روش پرداخت")
            } footer: {
                if payMethod == nil { Text("برای ثبت، روش پرداخت را انتخاب کنید.").foregroundStyle(.orange) }
            }
            if let after = model.previewRemaining(accountId: accountId, amount: n, date: date, upTo: upTo) {
                Section {
                    if !isAll, let c = chosen {
                        Label("ردیف‌های بعد از " + Money.persianDigits(c.num) + " باز می‌مانند و کمیسیونشان بعداً حساب می‌شود",
                              systemImage: "arrow.down.to.line").foregroundStyle(t.soft)
                    }
                    // this payment against what is due up to the chosen row (the debt / credit carries to the next payment)
                    if n == due {
                        Label("این مرحله تسویه کامل می‌شود", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
                    } else if n < due {
                        Label(Fmt.toman(due - n) + " از این مرحله بدهی می‌ماند و به کمیسیون بعدی اضافه می‌شود",
                              systemImage: "exclamationmark.circle").foregroundStyle(.orange)
                    } else {
                        Label(Fmt.toman(n - due) + " اضافه پرداخت می‌شود و از کمیسیون بعدی کم می‌شود",
                              systemImage: "arrow.uturn.down.circle").foregroundStyle(.blue)
                    }
                    LabeledContent(after < 0 ? "بستانکاری بعد از پرداخت" : "مانده‌ی کمیسیون بعد از پرداخت", value: Fmt.toman(abs(after)))
                        .font(AppFont.medium(14))
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
                    guard let m = payMethod else { return }
                    if model.settle(accountId: accountId, amount: n, date: date, upTo: upTo, payMethod: m,
                                    cardId: m.usesCard ? cardId : nil) { Haptics.success(); dismiss() }
                }
                .bold()
                .disabled(n <= 0 || payMethod == nil)
                .accessibilityIdentifier("settle.save")
            }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            open = LedgerOps.openCommissionRows(model.state, accountId: accountId)
            cut = max(0, open.count - 1)
            cardId = model.defaultCard(accountId: accountId)
            setAuto()
        }
    }

    private func rowsText(_ a: Int, _ b: Int) -> String {
        let from: String = "ردیف " + Money.persianDigits(a)
        if a == b { return from }
        let to: String = Money.persianDigits(b)
        return from + " تا " + to
    }

    private func openFooter(_ a: Int, _ b: Int) -> String {
        let count: String = Money.persianDigits(open.count)
        return "ردیف‌های باز: " + rowsText(a, b) + " (" + count + " ردیف). پاداش‌ها و تنخواه‌ها کمیسیون ندارند."
    }

    private func chosenText(_ a: Int, _ b: Int) -> String {
        let count: String = Money.persianDigits(cut + 1)
        return rowsText(a, b) + " · " + count + " ردیف"
    }

    static let methods: [PayMethod] = [.hamrahbank, .pos, .cash, .transfer]

    /// the amount follows the chosen row until it is typed by hand
    private func setAuto() {
        let v = due > 0 ? Money.persianDigits(Money.format(due)) : ""
        if amount.isEmpty || amount == autoAmount { amount = v }
        autoAmount = v
    }

    private var gauge: some View {
        Section {
            if let c = chosen, let first = open.first {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(isAll ? "همه‌ی ردیف‌های باز" : "تا ردیف " + Money.persianDigits(c.num))
                            .font(AppFont.bold(16)).foregroundStyle(t.ink)
                        Spacer()
                        Text(chosenText(first.num, c.num))
                            .font(AppFont.caption).foregroundStyle(t.soft)
                    }
                    HStack(spacing: 10) {
                        figure("جمع هزینه‌ها", c.cumulativeBase, t.ink)
                        figure("کمیسیون", c.cumulativeCommission, t.accent)
                        figure("قابل پرداخت", max(0, due), t.accent2)
                    }
                    if open.count > 1 {
                        Slider(value: Binding(get: { Double(cut) }, set: { v in
                            let k = Int(v.rounded())
                            if k != cut { cut = k; Haptics.tap(); setAuto() }
                        }), in: 0...Double(open.count - 1), step: 1)
                        .tint(t.accent)
                        .accessibilityIdentifier("settle.gauge")
                        HStack {
                            Text("ردیف " + Money.persianDigits(first.num))
                            Spacer()
                            Text("ردیف " + Money.persianDigits(open.last?.num ?? 0))
                        }
                        .font(AppFont.caption).foregroundStyle(t.soft)
                    }
                    if balance != 0 {
                        Text((balance > 0 ? "قابل پرداخت شامل بدهی قبلی " : "قابل پرداخت با کسر بستانکاری قبلی ") + Fmt.toman(abs(balance)) + " است.")
                            .font(AppFont.caption).foregroundStyle(t.soft)
                    }
                }
                .padding(.vertical, 4)
            }
            ForEach(Array(open.enumerated()), id: \.element.key) { i, r in
                Button {
                    Haptics.tap()
                    withAnimation(.snappy) { cut = i; setAuto() }
                } label: {
                    HStack(spacing: 10) {
                        Text(Money.persianDigits(r.num))
                            .font(AppFont.bold(12)).foregroundStyle(i <= cut ? t.onAccent : t.soft)
                            .frame(minWidth: 30, minHeight: 24)
                            .background(i <= cut ? AnyShapeStyle(t.accent) : AnyShapeStyle(t.soft.opacity(0.15)),
                                        in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r.desc.isEmpty ? "—" : r.desc).font(AppFont.medium(14)).foregroundStyle(t.ink).lineLimit(1)
                            Text(Money.persianDigits("\(r.date.jy)/\(r.date.jm)/\(r.date.jd)") + " · " + Money.persianDigits(Money.format(r.toman)))
                                .font(AppFont.caption).foregroundStyle(t.soft).lineLimit(1)
                        }
                        Spacer(minLength: 6)
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(Money.persianDigits(Money.format(r.cumulativeCommission + balance)))
                                .font(AppFont.bold(13)).foregroundStyle(i == cut ? t.accent : t.ink)
                            Text("تا اینجا").font(AppFont.caption).foregroundStyle(t.soft)
                        }
                        Image(systemName: i == cut ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(i == cut ? t.accent : t.soft.opacity(0.5))
                    }
                    .opacity(i <= cut ? 1 : 0.5)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("settle.row." + String(r.num))
            }
        } header: {
            Text("تا کدام ردیف تسویه می‌کنید؟")
        } footer: {
            Text("گیج را بکشید یا روی یک ردیف بزنید. عدد سمت چپ هر ردیف، مبلغ قابل پرداخت اگر تا همان ردیف تسویه کنید. کمیسیون زنده‌ی دفتر همیشه همه‌ی ردیف‌های باز را حساب می‌کند.")
        }
    }

    private func figure(_ title: String, _ v: Int, _ c: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(AppFont.caption).foregroundStyle(t.soft)
            Text(Money.persianDigits(Money.format(abs(v)))).font(AppFont.bold(15)).foregroundStyle(c)
                .lineLimit(1).minimumScaleFactor(0.6).contentTransition(.numericText(value: Double(v)))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

/// Smart suggestions (web «suggest chips»): the category chips appear while the category is empty, the subcategory
/// chips once a category is chosen and the subcategory is still empty. Tapping one fills the field.
struct LearnChips: View {
    @ObservedObject var model: AppModel
    let ctx: LearnContext
    let desc: String
    @Binding var category: String
    @Binding var subcategory: String
    let sub: Bool
    @Environment(\.theme) private var t

    var body: some View {
        let cat = category.trimmingCharacters(in: .whitespaces)
        let items: [String] = {
            guard !desc.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
            if sub {
                guard !cat.isEmpty, subcategory.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
                return Learning.subcategoryCandidates(model.state, ctx, category: cat, desc: desc)
            }
            guard cat.isEmpty else { return [] }
            return Learning.categoryCandidates(model.state, ctx, desc: desc)
        }()
        if !items.isEmpty {
            HScroll {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles").font(.system(size: 13, weight: .semibold)).foregroundStyle(t.accent)
                    ForEach(items, id: \.self) { s in
                        Button {
                            Haptics.tap()
                            withAnimation(.spring(duration: 0.3)) {
                                if sub { subcategory = s } else { category = s }
                            }
                        } label: {
                            Text(s).font(AppFont.medium(13)).foregroundStyle(t.accent)
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .glassEffect(.regular.tint(t.accent.opacity(0.10)).interactive(), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }
}
