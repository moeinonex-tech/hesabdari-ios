import SwiftUI
import HesabCore

// MARK: - model: reminder changes

extension AppModel {
    var partyNames: [String] {
        var names: [String] = []
        for p in state["parties"]?.arrayValue ?? [] { if let n = p["fullName"]?.stringValue, !n.isEmpty { names.append(n) } }
        for p in state["checkParties"]?.arrayValue ?? [] { if let n = p["name"]?.stringValue, !n.isEmpty { names.append(n) } }
        for c in state["reminderChecks"]?.arrayValue ?? [] { if let n = c["party"]?.stringValue, !n.isEmpty { names.append(n) } }
        var seen = Set<String>()
        return names.filter { seen.insert($0).inserted }
    }
    var creditorNames: [String] {
        (state["reminderPersons"]?.arrayValue ?? []).filter { $0["type"]?.stringValue == "creditor" }.compactMap { $0["name"]?.stringValue }
    }
    var accountLinkChoices: [Choice] {
        [Choice(id: "", label: "بدون اتصال به دفتر"), Choice(id: "personal", label: "دفتر شخصی")]
            + accounts.map { Choice(id: $0.id, label: $0.name) }
    }

    func record(_ key: String, _ id: String) -> JSONValue? {
        state[key]?.arrayValue?.first { $0["id"]?.idString == id }
    }

    func addCheck(_ i: CheckInput) -> Bool { change { try ReminderOps.saveCheck(state, editingId: nil, i, today: Self.today).state } }
    func editCheck(_ id: String, _ i: CheckInput) -> Bool { change { try ReminderOps.saveCheck(state, editingId: id, i, today: Self.today).state } }
    func setCheckStatus(_ id: String, _ status: String) -> Bool { change { try ReminderOps.setCheckStatus(state, id: id, status: status, today: Self.today) } }
    func deleteCheck(_ id: String) -> Bool { change({ try ReminderOps.deleteCheck(state, id: id) }, undoMessage: "چک حذف شد") }

    func addNasiyehExpense(_ input: ExpenseInput, party: String, due: JalaliDate) -> Bool {
        change {
            var i = input; i.payMethod = .nasiyeh; i.cardId = nil
            let r = try LedgerOps.addExpense(state, i)
            return try ReminderOps.linkLastRowAsNasiyeh(r.state, listKey: "expenses", partyName: party, dueDate: due)
        }
    }
    func addNasiyehPersonal(_ input: PersonalInput, party: String, due: JalaliDate) -> Bool {
        change {
            var i = input; i.payMethod = "nasiyeh"; i.cardId = nil
            let r = try RecordOps.addPersonal(state, i)
            return try ReminderOps.linkLastRowAsNasiyeh(r.state, listKey: "personalExpenses", partyName: party, dueDate: due)
        }
    }

    func addPerson(name: String, creditor: Bool) -> String? {
        var newId: String?
        let ok = change {
            let r = try ReminderOps.addPerson(state, name: name, creditor: creditor, partyId: nil)
            newId = r.id
            return r.state
        }
        return ok ? newId : nil
    }
    func deletePerson(_ id: String) -> Bool { change({ try ReminderOps.deletePerson(state, id: id) }, undoMessage: "شخص حذف شد") }
    func saveInstallment(personId: String, editingId: String?, _ i: InstallmentInput) -> Bool {
        change { try ReminderOps.saveInstallment(state, personId: personId, editingId: editingId, i, today: Self.today) }
    }
    func toggleInstallment(personId: String, id: String) -> Bool {
        change { try ReminderOps.toggleInstallmentPaid(state, personId: personId, installmentId: id, today: Self.today) }
    }
    func deleteInstallment(personId: String, id: String) -> Bool {
        change({ try ReminderOps.deleteInstallment(state, personId: personId, installmentId: id) }, undoMessage: "قسط حذف شد")
    }
    func saveAppointment(editingId: String?, _ i: AppointmentInput) -> Bool {
        change { try ReminderOps.saveAppointment(state, editingId: editingId, i) }
    }
    func toggleAppointment(_ id: String) -> Bool { change { try ReminderOps.toggleAppointmentDone(state, id: id) } }
    func deleteAppointment(_ id: String) -> Bool { change({ try ReminderOps.deleteAppointment(state, id: id) }, undoMessage: "قرار حذف شد") }
}

// MARK: - sheets

enum ReminderSheet: Identifiable {
    case newCheck, editCheck(String), newPerson, newAppointment, editAppointment(String)
    var id: String {
        switch self {
        case .newCheck: return "nc"
        case .editCheck(let i): return "ec" + i
        case .newPerson: return "np"
        case .newAppointment: return "na"
        case .editAppointment(let i): return "ea" + i
        }
    }
}

struct AccountLinkPicker: View {
    @ObservedObject var model: AppModel
    @Binding var accountId: String?

    var body: some View {
        Picker("اتصال به دفتر", selection: Binding(get: { accountId ?? "" }, set: { accountId = $0.isEmpty ? nil : $0 })) {
            ForEach(model.accountLinkChoices) { c in Text(c.label).tag(c.id) }
        }
    }
}

// MARK: - check form

struct CheckFormView: View {
    @ObservedObject var model: AppModel
    let editingId: String?
    @Environment(\.dismiss) private var dismiss
    @State private var amount = ""
    @State private var party = ""
    @State private var bank = ""
    @State private var number = ""
    @State private var sayad = ""
    @State private var series = ""
    @State private var desc = ""
    @State private var category = ""
    @State private var subcategory = ""
    @State private var due = AppModel.today
    @State private var accountId: String?
    @State private var status = "pending"
    @State private var loaded = false
    @State private var confirmDelete = false
    @State private var checkCount = 1
    @State private var slots: [CheckSlot] = []
    @State private var checkTotal = ""
    private var multiCheck: Bool { editingId == nil && checkCount > 1 }

    var body: some View {
        Form {
            if editingId == nil {
                Section { CountRow(title: "تعداد چک", count: $checkCount, max: CheckGroup.maxCount) }
            }
            if !multiCheck {
                Section {
                    AmountField(title: "مبلغ چک (تومان)", text: $amount)
                    JalaliDateField(title: "تاریخ سررسید", date: $due)
                }
            }
            Section("اطلاعات چک") {
                SuggestField(title: "در وجه", text: $party, suggestions: model.partyNames)
                BankNameField(title: "بانک", text: $bank)
                if !multiCheck { TextField("شماره چک", text: $number).keyboardType(.numberPad) }
                TextField("سری", text: $series)
                if !multiCheck { TextField("شناسه صیاد", text: $sayad).keyboardType(.numberPad) }
                TextField("توضیحات", text: $desc)
            }
            if multiCheck { MultiCheckSections(slots: $slots, total: $checkTotal) }
            Section {
                SuggestField(title: "نوع هزینه", text: $category, suggestions: model.ledgerCategories)
                LearnChips(model: model, ctx: .ledger, desc: desc, category: $category, subcategory: $subcategory, sub: false)
                SuggestField(title: "زیردسته", text: $subcategory, suggestions: model.subcategories(of: category))
                LearnChips(model: model, ctx: .ledger, desc: desc, category: $category, subcategory: $subcategory, sub: true)
                AccountLinkPicker(model: model, accountId: $accountId)
            } header: {
                Text("دسته و دفتر")
            } footer: {
                Text("اگر به یک دفتر وصل باشد، یک ردیف «در انتظار وصول» در همان دفتر ساخته می‌شود و با وصول یا برگشت چک خودکار به‌روز می‌شود.")
            }
            if editingId != nil {
                Section("وضعیت") {
                    Picker("وضعیت", selection: $status) {
                        Text("در انتظار وصول").tag("pending")
                        Text("وصول شد").tag("cashed")
                        Text("برگشتی").tag("bounced")
                        Text("باطل").tag("cancelled")
                    }
                    .pickerStyle(.segmented)
                }
                Section {
                    Button("حذف چک", role: .destructive) { confirmDelete = true }
                }
            }
        }
        .navigationTitle(editingId == nil ? "چک جدید" : "ویرایش چک")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("انصراف") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("ذخیره") { save() }.bold() }
        }
        .confirmationDialog("این چک و ردیف متصلش حذف شود؟", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("حذف", role: .destructive) {
                if let id = editingId, model.deleteCheck(id) { Haptics.warning(); dismiss() }
            }
        }
        .onAppear(perform: load)
        .onChange(of: checkCount) { old, new in
            if new > 1 {
                MultiCheckSections.resize(&slots, to: new, first: CheckSlot(amount: Fmt.parseAmount(amount), due: due, number: number, sayad: sayad))
            } else if old > 1, let first = slots.first {
                amount = first.amount > 0 ? Money.persianDigits(Money.format(first.amount)) : ""
                due = first.due; number = first.number; sayad = first.sayad
                slots = []
            }
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let id = editingId, let c = model.record("reminderChecks", id) else { return }
        amount = Money.persianDigits(Money.format(c["amount"]?.intValue ?? 0))
        party = c["party"]?.stringValue ?? ""; bank = c["bankName"]?.stringValue ?? ""
        number = c["checkNumber"]?.idString ?? ""; sayad = c["sayadId"]?.idString ?? ""; series = c["checkSeries"]?.stringValue ?? ""
        desc = c["description"]?.stringValue ?? ""; category = c["category"]?.stringValue ?? ""; subcategory = c["subcategory"]?.stringValue ?? ""
        due = ImportAnalyzer.date(c["dueDate"]); accountId = c["accountId"]?.idString; status = c["status"]?.stringValue ?? "pending"
    }

    private func save() {
        let input = CheckInput(amount: Fmt.parseAmount(amount), party: party, bankName: bank, checkNumber: number, sayadId: sayad,
                               checkSeries: series, desc: desc, category: category, subcategory: subcategory, dueDate: due,
                               accountId: accountId, status: status)
        let ok: Bool
        if multiCheck {
            ok = model.addChecks(input, slots: slots, total: Fmt.parseAmount(checkTotal))
        } else {
            ok = editingId.map { model.editCheck($0, input) } ?? model.addCheck(input)
        }
        if ok { Haptics.success(); dismiss() }
    }
}

// MARK: - people

struct PersonAddView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var creditor = true

    var body: some View {
        Form {
            Section {
                SuggestField(title: "نام", text: $name, suggestions: model.partyNames)
                Picker("نوع", selection: $creditor) {
                    Text("طلبکار (من به او بدهکارم)").tag(true)
                    Text("بدهکار (او به من بدهکار است)").tag(false)
                }
                .pickerStyle(.inline)
            }
        }
        .navigationTitle("شخص جدید")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("انصراف") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("ثبت") {
                    if model.addPerson(name: name, creditor: creditor) != nil { Haptics.success(); dismiss() }
                }
                .bold()
            }
        }
    }
}

struct PersonDetailView: View {
    @ObservedObject var model: AppModel
    let personId: String
    @Environment(\.theme) private var t
    @Environment(\.dismiss) private var dismiss
    @State private var editing: InstallmentSheet?
    @State private var confirmDelete = false

    struct InstallmentSheet: Identifiable {
        let id: String
        let installmentId: String?
    }

    var body: some View {
        let person = model.persons.first { $0.id == personId }
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let p = person {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(p.creditor ? "به این شخص بدهکارید" : "این شخص به شما بدهکار است")
                            .font(AppFont.regular(13)).foregroundStyle(t.soft)
                        Text(Fmt.toman(p.unpaid)).font(AppFont.heavy(28)).foregroundStyle(p.creditor ? t.danger : t.success)
                        if p.total > 0 {
                            GradientBar(value: Double(p.total - p.unpaid) / Double(p.total), from: t.accent2, to: t.success)
                            Text("پرداخت‌شده " + Fmt.toman(p.total - p.unpaid) + " از " + Fmt.toman(p.total))
                                .font(AppFont.caption).foregroundStyle(t.soft)
                        }
                        Button {
                            editing = InstallmentSheet(id: "new", installmentId: nil)
                        } label: {
                            Label("افزودن قسط", systemImage: "plus").font(AppFont.bold(15)).frame(maxWidth: .infinity).padding(.vertical, 4)
                        }
                        .buttonStyle(.glassProminent)
                    }
                    .glassCard()

                    VStack(alignment: .leading, spacing: 4) {
                        if p.installments.isEmpty { EmptyNote(text: "هنوز قسطی ثبت نشده") }
                        ForEach(p.installments) { i in
                            HStack(spacing: 10) {
                                Button {
                                    if model.toggleInstallment(personId: personId, id: i.id) { Haptics.success() }
                                } label: {
                                    Image(systemName: i.paid ? "checkmark.circle.fill" : "circle")
                                        .font(.title3).foregroundStyle(i.paid ? t.success : t.soft)
                                }
                                .buttonStyle(.plain)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(Fmt.toman(i.amount)).font(AppFont.bold(15)).foregroundStyle(t.ink)
                                    Text((i.desc.isEmpty ? "" : i.desc + " · ") + BackupExporter.formatJalali(i.due))
                                        .font(AppFont.caption).foregroundStyle(t.soft)
                                }
                                Spacer()
                                DueBadge(days: i.daysLeft, resolved: i.paid)
                            }
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                            .onTapGesture { editing = InstallmentSheet(id: i.id, installmentId: i.id) }
                            .contextMenu {
                                Button { _ = model.toggleInstallment(personId: personId, id: i.id) } label: {
                                    Label(i.paid ? "پرداخت‌نشده" : "پرداخت شد", systemImage: "checkmark.circle")
                                }
                                Button { Task { await model.addInstallmentToPhoneReminders(personId: personId, id: i.id) } } label: {
                                    Label("افزودن به Reminders گوشی", systemImage: "checklist")
                                }
                                Button(role: .destructive) { _ = model.deleteInstallment(personId: personId, id: i.id) } label: {
                                    Label("حذف", systemImage: "trash")
                                }
                            }
                            if i.id != p.installments.last?.id { Divider().opacity(0.5) }
                        }
                    }
                    .glassCard()

                    Button("حذف این شخص", role: .destructive) { confirmDelete = true }
                        .font(AppFont.medium(14))
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .background(AppBackground())
        .navigationTitle(person?.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .overlay(alignment: .bottom) { UndoBanner(model: model).padding(.bottom, AppShell.dockClearance) }
        .sheet(item: $editing) { e in
            Themed {
                NavigationStack {
                    InstallmentFormView(model: model, personId: personId, editingId: e.installmentId,
                                        creditor: person?.creditor ?? true)
                }
            }
        }
        .confirmationDialog("این شخص و همه‌ی اقساطش حذف شود؟", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("حذف", role: .destructive) {
                if model.deletePerson(personId) { Haptics.warning(); dismiss() }
            }
        }
    }
}

struct InstallmentFormView: View {
    @ObservedObject var model: AppModel
    let personId: String
    let editingId: String?
    let creditor: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var amount = ""
    @State private var desc = ""
    @State private var category = ""
    @State private var subcategory = ""
    @State private var due = AppModel.today
    @State private var accountId: String?
    @State private var loaded = false

    var body: some View {
        Form {
            Section {
                AmountField(title: "مبلغ قسط (تومان)", text: $amount)
                JalaliDateField(title: "سررسید", date: $due)
                TextField("توضیحات", text: $desc)
            }
            if creditor {
                Section {
                    SuggestField(title: "نوع هزینه", text: $category, suggestions: model.ledgerCategories)
                    LearnChips(model: model, ctx: .ledger, desc: desc, category: $category, subcategory: $subcategory, sub: false)
                    SuggestField(title: "زیردسته", text: $subcategory, suggestions: model.subcategories(of: category))
                    LearnChips(model: model, ctx: .ledger, desc: desc, category: $category, subcategory: $subcategory, sub: true)
                    AccountLinkPicker(model: model, accountId: $accountId)
                } header: {
                    Text("دسته و دفتر")
                } footer: {
                    Text("اگر به یک دفتر وصل باشد، یک ردیف «بدهی … در انتظار پرداخت» در آن دفتر ساخته می‌شود و با پرداخت قسط به‌روز می‌شود.")
                }
            }
        }
        .navigationTitle(editingId == nil ? "قسط جدید" : "ویرایش قسط")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("انصراف") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("ذخیره") {
                    let input = InstallmentInput(amount: Fmt.parseAmount(amount), desc: desc, category: category,
                                                 subcategory: subcategory, dueDate: due, accountId: creditor ? accountId : nil)
                    if model.saveInstallment(personId: personId, editingId: editingId, input) { Haptics.success(); dismiss() }
                }
                .bold()
            }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            guard let eid = editingId,
                  let p = model.record("reminderPersons", personId),
                  let i = p["installments"]?.arrayValue?.first(where: { $0["id"]?.idString == eid }) else { return }
            amount = Money.persianDigits(Money.format(i["amount"]?.intValue ?? 0))
            desc = i["description"]?.stringValue ?? ""; category = i["category"]?.stringValue ?? ""
            subcategory = i["subcategory"]?.stringValue ?? ""; due = ImportAnalyzer.date(i["dueDate"]); accountId = i["accountId"]?.idString
        }
    }
}

// MARK: - appointments

struct AppointmentFormView: View {
    @ObservedObject var model: AppModel
    let editingId: String?
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var date = AppModel.today
    @State private var hasTime = false
    @State private var time = Calendar.current.date(bySettingHour: 10, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var note = ""
    @State private var work = true
    @State private var presence = false
    @State private var projectId: String?
    @State private var projectName = ""
    @State private var place = ""
    @State private var done = false
    @State private var loaded = false
    @State private var confirmDelete = false

    var body: some View {
        Form {
            Section {
                TextField("عنوان", text: $title)
                Picker("نوع", selection: $work) {
                    Text("کاری").tag(true)
                    Text("شخصی").tag(false)
                }
                .pickerStyle(.segmented)
                Picker("قرار", selection: $presence) {
                    Text("جلسه").tag(false)
                    Text("حضور").tag(true)
                }
                .pickerStyle(.segmented)
            }
            Section {
                JalaliDateField(title: "تاریخ", date: $date)
                Toggle("ساعت مشخص", isOn: $hasTime)
                if hasTime {
                    DatePicker("ساعت", selection: $time, displayedComponents: .hourAndMinute)
                        .environment(\.locale, Locale(identifier: "fa_IR"))
                }
            }
            if work {
                Section("پروژه") {
                    Picker("پروژه", selection: $projectId) {
                        Text("نام دستی").tag(String?.none)
                        ForEach(model.accounts) { a in Text(a.name).tag(Optional(a.id)) }
                    }
                    if projectId == nil { TextField("نام پروژه", text: $projectName) }
                }
            }
            Section {
                TextField("مکان", text: $place)
                TextField("یادداشت", text: $note, axis: .vertical)
            }
            if editingId != nil {
                Section {
                    Toggle("انجام شد", isOn: $done)
                    Button("حذف قرار", role: .destructive) { confirmDelete = true }
                }
            }
        }
        .navigationTitle(editingId == nil ? "قرار جدید" : "ویرایش قرار")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("انصراف") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("ذخیره") { save() }.bold() }
        }
        .confirmationDialog("این قرار حذف شود؟", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("حذف", role: .destructive) {
                if let id = editingId, model.deleteAppointment(id) { dismiss() }
            }
        }
        .onAppear(perform: load)
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let id = editingId, let a = model.record("appointments", id) else { return }
        title = a["title"]?.stringValue ?? ""; date = ImportAnalyzer.date(a["date"]); note = a["note"]?.stringValue ?? ""
        work = a["kind"]?.stringValue != "personal"; presence = a["apptType"]?.stringValue == "presence"
        projectId = a["projectId"]?.idString; projectName = a["projectManualName"]?.stringValue ?? ""
        place = a["location"]?["label"]?.stringValue ?? ""; done = a["done"]?.isTruthy ?? false
        let parts = (a["time"]?.stringValue ?? "").split(separator: ":").compactMap { Int($0) }
        if parts.count == 2, let d = Calendar.current.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: Date()) {
            hasTime = true; time = d
        }
    }

    private func save() {
        var hhmm = ""
        if hasTime {
            let c = Calendar.current.dateComponents([.hour, .minute], from: time)
            hhmm = String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
        }
        let input = AppointmentInput(title: title, date: date, time: hhmm, note: note, kind: work ? "work" : "personal",
                                     apptType: presence ? "presence" : "meeting", projectId: work ? projectId : nil,
                                     projectManualName: projectName, place: place)
        guard model.saveAppointment(editingId: editingId, input) else { return }
        if let id = editingId, let a = model.record("appointments", id), (a["done"]?.isTruthy ?? false) != done {
            _ = model.toggleAppointment(id)
        }
        Haptics.success()
        dismiss()
    }
}
