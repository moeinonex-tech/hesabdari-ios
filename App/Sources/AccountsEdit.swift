import SwiftUI
import HesabCore

// MARK: - model: accounts, parties, ledger income

struct TankhahPartyChoice: Identifiable, Hashable {
    let id: String          // tankhah party id, or "cp:<registry id>"
    let name: String
    let company: Bool
    let fromRegistry: Bool
}

struct PartyVM: Identifiable, Hashable {
    let id: String
    let fullName: String
    let summary: String
    let nationalCode, mobile, cardNumber, accountNumber, iban, bankName: String
}

extension AppModel {
    @discardableResult
    func addAccount(_ name: String) -> String? {
        var newId: String?
        let ok = change {
            let r = try AccountOps.addAccount(state, name: name)
            newId = r.id
            return r.state
        }
        return ok ? newId : nil
    }
    func renameAccount(_ id: String, _ name: String) -> Bool { change { try AccountOps.renameAccount(state, id: id, name: name) } }
    func deleteAccount(_ id: String) -> Bool { change({ try AccountOps.deleteAccount(state, id: id) }, undoMessage: "دفتر حذف شد") }
    func setCommissionEnabled(_ id: String, _ on: Bool) -> Bool { change { try AccountOps.setCommissionEnabled(state, id: id, on) } }
    func setCommissionPercent(_ id: String, _ p: Int) -> Bool { change { try AccountOps.setCommissionPercent(state, id: id, p) } }
    func selectAccount(_ id: String) {
        guard state["activeAccountId"]?.idString != id else { return }
        _ = change { AccountOps.setActiveAccount(state, id: id) }
    }
    func accountRecord(_ id: String) -> JSONValue? { state["accounts"]?.arrayValue?.first { $0["id"]?.idString == id } }
    func commissionPercent(_ id: String) -> Int { accountRecord(id)?["commissionPercent"]?.intValue ?? 0 }
    func commissionEnabled(_ id: String) -> Bool { accountRecord(id)?["commissionEnabled"]?.isTruthy ?? false }

    /// web tankhahPartyResultsHtml: own tankhah parties + registry people without a same-name tankhah party.
    var tankhahPartyChoices: [TankhahPartyChoice] {
        let own = (state["tankhahParties"]?.arrayValue ?? []).compactMap { p -> TankhahPartyChoice? in
            guard let id = p["id"]?.idString else { return nil }
            return TankhahPartyChoice(id: id, name: p["name"]?.stringValue ?? "", company: p["type"]?.stringValue == "company", fromRegistry: false)
        }
        let names = Set(own.map { AccountOps.normalizeName($0.name) })
        let extra = (state["parties"]?.arrayValue ?? []).compactMap { p -> TankhahPartyChoice? in
            guard let id = p["id"]?.idString, let n = p["fullName"]?.stringValue, !names.contains(AccountOps.normalizeName(n)) else { return nil }
            return TankhahPartyChoice(id: "cp:" + id, name: n, company: false, fromRegistry: true)
        }
        return (own + extra).sorted { $0.name.compare($1.name, locale: Locale(identifier: "fa")) == .orderedAscending }
    }
    /// Returns the tankhah party id to put on the row.
    func resolveTankhahChoice(_ c: TankhahPartyChoice) -> String? {
        guard c.fromRegistry else { return c.id }
        var newId: String?
        let ok = change {
            let r = try AccountOps.tankhahPartyFromRegistry(state, partyId: String(c.id.dropFirst(3)))
            newId = r.id
            return r.state
        }
        return ok ? newId : nil
    }
    func addTankhahParty(_ name: String, company: Bool) -> String? {
        var newId: String?
        var existed = false
        let ok = change {
            let r = try AccountOps.addTankhahParty(state, name: name, company: company)
            newId = r.id; existed = r.result == .existing
            return r.state
        }
        if ok && existed { errorMessage = "این نام قبلاً ثبت شده بود — همون انتخاب شد" }
        return ok ? newId : nil
    }

    var parties: [PartyVM] {
        (state["parties"]?.arrayValue ?? []).compactMap { p -> PartyVM? in
            guard let id = p["id"]?.idString else { return nil }
            let s = { (k: String) in p[k]?.idString ?? p[k]?.stringValue ?? "" }
            var bits: [String] = []
            if !s("mobile").isEmpty { bits.append(Money.persianDigits(s("mobile"))) }
            if !s("bankName").isEmpty { bits.append(s("bankName")) }
            if bits.isEmpty && !s("nationalCode").isEmpty { bits.append("کد ملی " + Money.persianDigits(s("nationalCode"))) }
            return PartyVM(id: id, fullName: s("fullName"), summary: bits.joined(separator: " · "), nationalCode: s("nationalCode"),
                           mobile: s("mobile"), cardNumber: s("cardNumber"), accountNumber: s("accountNumber"), iban: s("iban"), bankName: s("bankName"))
        }
        .sorted { $0.fullName.compare($1.fullName, locale: Locale(identifier: "fa")) == .orderedAscending }
    }
    func saveParty(_ id: String?, _ input: PartyInput) -> Bool { change { try AccountOps.saveParty(state, editingId: id, input).state } }
    func deleteParty(_ id: String) -> Bool { change({ AccountOps.deleteParty(state, id: id) }, undoMessage: "طرف حساب حذف شد") }

    func ledgerIncomeRows(_ accountId: String) -> [SimpleRowVM] { incomeRows.filter { $0.accountLink == accountId } }
    func hasTankhah(_ accountId: String) -> Bool {
        (state["expenses"]?.arrayValue ?? []).contains { $0["accountId"]?.idString == accountId && $0["type"]?.stringValue == "tankhah" }
    }
}

// MARK: - account management

struct AccountManageView: View {
    @ObservedObject var model: AppModel
    let accountId: String?
    var onCreated: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var newName = ""
    @State private var name = ""
    @State private var percent = ""
    @State private var commission = false
    @State private var confirmDelete = false

    var body: some View {
        Form {
            if let id = accountId, let a = model.accounts.first(where: { $0.id == id }) {
                Section("این دفتر") {
                    HStack {
                        TextField("نام دفتر", text: $name)
                        Button("ثبت نام") { _ = model.renameAccount(id, name); Haptics.success() }
                            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || name == a.name)
                    }
                }
                Section {
                    Toggle("کمیسیون این دفتر", isOn: $commission)
                        .onChange(of: commission) { _, on in _ = model.setCommissionEnabled(id, on) }
                    if commission {
                        HStack {
                            Text("درصد کمیسیون")
                            Spacer()
                            TextField("۰", text: $percent)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 80)
                                .onChange(of: percent) { _, v in
                                    let digits = SearchEngine.latinDigits(v).filter(\.isNumber)
                                    _ = model.setCommissionPercent(id, Int(digits) ?? 0)
                                }
                            Text("٪")
                        }
                    }
                } header: {
                    Text("کمیسیون")
                } footer: {
                    Text("خاموش کردن کمیسیون فقط کارت کمیسیون را پنهان می‌کند؛ پرداخت‌های قبلی و درآمدهایشان دست نمی‌خورند.")
                }
                Section {
                    Button("حذف این دفتر", role: .destructive) { confirmDelete = true }
                        .disabled(model.accounts.count <= 1)
                } footer: {
                    Text(model.accounts.count <= 1
                         ? "حداقل یک حساب باید باقی بماند."
                         : "هزینه‌ها، تنخواه‌ها و درآمدهای این دفتر حذف می‌شوند. چک‌ها و قسط‌ها در یادآوری‌ها می‌مانند و فقط از این دفتر جدا می‌شوند.")
                }
            }
            Section("دفتر جدید") {
                HStack {
                    TextField("نام دفتر جدید", text: $newName)
                    Button("افزودن") {
                        if let id = model.addAccount(newName) {
                            Haptics.success()
                            onCreated(id)
                            dismiss()
                        }
                    }
                    .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .navigationTitle("مدیریت دفترها")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("بستن") { dismiss() } } }
        .confirmationDialog("این دفتر و همه‌ی ردیف‌هایش حذف شود؟", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("حذف دفتر", role: .destructive) {
                if let id = accountId, model.deleteAccount(id) { Haptics.warning(); dismiss() }
            }
        } message: {
            Text("تا چند ثانیه می‌توانید با «بازگرداندن» برش گردانید.")
        }
        .onAppear {
            if let id = accountId, let a = model.accounts.first(where: { $0.id == id }) {
                name = a.name
                commission = model.commissionEnabled(id)
                let p = model.commissionPercent(id)
                percent = p > 0 ? Money.persianDigits(String(p)) : ""
            }
        }
    }
}

// MARK: - tankhah party picker (web tankhahPartyPickModalHtml)

struct TankhahPartyPicker: View {
    @ObservedObject var model: AppModel
    @Binding var partyId: String?
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var filter = 0          // 0 all, 1 person, 2 company
    @State private var newName = ""
    @State private var newCompany = false

    var body: some View {
        let q = AccountOps.normalizeName(SearchEngine.latinDigits(query))
        let list = model.tankhahPartyChoices.filter { c in
            if filter == 1 && c.company { return false }
            if filter == 2 && (!c.company || c.fromRegistry) { return false }
            return q.isEmpty || AccountOps.normalizeName(SearchEngine.latinDigits(c.name)).contains(q)
        }
        List {
            Section {
                Picker("", selection: $filter) {
                    Text("همه").tag(0)
                    Text("شخص").tag(1)
                    Text("شرکت").tag(2)
                }
                .pickerStyle(.segmented)
            }
            Section {
                if list.isEmpty { Text("موردی یافت نشد.").foregroundStyle(.secondary) }
                ForEach(list) { c in
                    Button {
                        if let id = model.resolveTankhahChoice(c) { partyId = id; Haptics.tap(); dismiss() }
                    } label: {
                        HStack {
                            Image(systemName: c.company ? "building.2" : "person")
                            VStack(alignment: .leading) {
                                Text(c.name).font(AppFont.bold(15))
                                Text(c.fromRegistry ? "از طرف‌های حساب" : (c.company ? "شرکت" : "شخص"))
                                    .font(AppFont.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if c.id == partyId { Image(systemName: "checkmark") }
                        }
                    }
                    .foregroundStyle(.primary)
                }
            }
            Section("افزودن طرف حساب جدید") {
                TextField("مثلاً حامد یا شرکت آریا", text: $newName)
                Picker("نوع", selection: $newCompany) {
                    Text("شخص").tag(false)
                    Text("شرکت").tag(true)
                }
                .pickerStyle(.segmented)
                Button("افزودن") {
                    if let id = model.addTankhahParty(newName, company: newCompany) { partyId = id; Haptics.success(); dismiss() }
                }
                .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .searchable(text: $query, prompt: "جستجوی نام...")
        .navigationTitle("انتخاب طرف حساب")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - central party registry (web «طرف‌های حساب»)

struct PartiesView: View {
    @ObservedObject var model: AppModel
    @State private var editing: IdBox?
    @Environment(\.theme) private var t

    var body: some View {
        List {
            if model.parties.isEmpty {
                Text("هنوز طرف حسابی ثبت نشده").foregroundStyle(.secondary)
            }
            ForEach(model.parties) { p in
                Button { editing = IdBox(id: p.id) } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(p.fullName).font(AppFont.bold(15)).foregroundStyle(t.ink)
                        if !p.summary.isEmpty { Text(p.summary).font(AppFont.caption).foregroundStyle(t.soft) }
                    }
                }
                .swipeActions { Button("حذف", role: .destructive) { _ = model.deleteParty(p.id) } }
            }
        }
        .navigationTitle("طرف‌های حساب")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { editing = IdBox(id: "") } label: { Image(systemName: "plus") }
            }
        }
        .sheet(item: $editing) { e in
            NavigationStack { PartyFormView(model: model, party: model.parties.first { $0.id == e.id }) }
        }
    }
}

struct PartyFormView: View {
    @ObservedObject var model: AppModel
    let party: PartyVM?
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var code = ""
    @State private var mobile = ""
    @State private var card = ""
    @State private var account = ""
    @State private var iban = ""
    @State private var bank = ""

    var body: some View {
        Form {
            Section {
                TextField("نام و نام خانوادگی", text: $name)
                TextField("کد ملی (اختیاری)", text: $code).keyboardType(.numberPad)
            }
            Section("موارد زیر اختیاری‌اند") {
                TextField("شماره موبایل", text: $mobile).keyboardType(.phonePad)
                TextField("شماره کارت", text: $card).keyboardType(.numberPad)
                TextField("شماره حساب", text: $account)
                TextField("شماره شبا (IR…)", text: $iban).textInputAutocapitalization(.characters)
                BankNameField(title: "نام بانک", text: $bank)
            }
        }
        .navigationTitle(party == nil ? "افزودن طرف حساب" : "ویرایش طرف حساب")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("انصراف") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button(party == nil ? "ثبت" : "به‌روزرسانی") {
                    let input = PartyInput(fullName: name, nationalCode: code, mobile: mobile, cardNumber: card,
                                           accountNumber: account, iban: iban, bankName: bank)
                    if model.saveParty(party?.id, input) { Haptics.success(); dismiss() }
                }
                .bold()
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .onAppear {
            guard let p = party else { return }
            name = p.fullName; code = p.nationalCode; mobile = p.mobile; card = p.cardNumber
            account = p.accountNumber; iban = p.iban; bank = p.bankName
        }
    }
}

// MARK: - tankhah by party report (web tankhahPartyReportModalHtml)

struct TankhahPartyReportView: View {
    @ObservedObject var model: AppModel
    let accountId: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var t

    var body: some View {
        let rep = AccountOps.tankhahPartyReport(model.state, accountId: accountId)
        let name = model.accounts.first { $0.id == accountId }?.name ?? "حساب"
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("جمع کل تنخواه دریافتی").font(AppFont.regular(13)).foregroundStyle(t.soft)
                    Text(Fmt.toman(rep.total)).font(AppFont.heavy(26)).foregroundStyle(t.accent)
                }
                .glassCard()
                if rep.groups.isEmpty {
                    Text("هنوز تنخواهی برای این پروژه ثبت نشده.").foregroundStyle(t.soft).padding()
                }
                ForEach(rep.groups, id: \.name) { g in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: g.type == "company" ? "building.2.fill" : (g.type == nil ? "questionmark.circle" : "person.fill"))
                                .foregroundStyle(t.accent)
                            Text(g.name).font(AppFont.bold(16)).foregroundStyle(t.ink)
                            Spacer()
                            Text(Fmt.toman(g.total)).font(AppFont.bold(14)).foregroundStyle(t.ink)
                        }
                        GradientBar(value: rep.total > 0 ? Double(g.total) / Double(rep.total) : 0, from: t.accent, to: t.accent2)
                        ForEach(Array(g.rows.enumerated()), id: \.offset) { _, r in
                            let d = ImportAnalyzer.date(r["date"])
                            HStack {
                                Text(Money.persianDigits("\(d.jy)/\(d.jm)/\(d.jd)")).font(AppFont.caption).foregroundStyle(t.soft)
                                Text(r["desc"]?.stringValue ?? "").font(AppFont.regular(13)).foregroundStyle(t.ink).lineLimit(1)
                                Spacer()
                                Text(Money.persianDigits(Money.format(ImportAnalyzer.toman(.object(r))))).font(AppFont.medium(13)).foregroundStyle(t.ink)
                            }
                        }
                        Text(Money.persianDigits(String(g.rows.count)) + " مورد").font(AppFont.caption).foregroundStyle(t.soft)
                    }
                    .glassCard()
                }
            }
            .padding(16)
        }
        .background(AppBackground())
        .navigationTitle("تنخواه به تفکیک طرف حساب")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("بستن") { dismiss() } }
            ToolbarItem(placement: .primaryAction) {
                ShareLink(item: Self.text(rep, accountName: name, state: model.state)) { Image(systemName: "square.and.arrow.up") }
            }
        }
    }

    /// web tankhahPartyReportText (+ tankhahEntryDetailText)
    static func text(_ rep: (groups: [TankhahPartyGroup], total: Int), accountName: String, state st: [String: JSONValue]) -> String {
        let t = AppModel.today
        func longDate(_ d: JalaliDate) -> String { Money.persianDigits(String(d.jd)) + " " + BackupExporter.months[d.jm - 1] + " " + Money.persianDigits(String(d.jy)) }
        func fmt(_ n: Int) -> String { Money.format(n) }
        func detail(_ e: [String: JSONValue]) -> String {
            switch e["payMethod"]?.stringValue {
            case "transfer":
                let card = (st["cards"]?.arrayValue ?? []).first { $0["id"]?.idString == e["cardId"]?.idString && e["cardId"]?.idString != nil }
                return "روش دریافت: حواله به حساب" + (card.map { " (" + ($0["bankName"]?.stringValue ?? "") + " • ****" + ($0["last4"]?.idString ?? "") + ")" } ?? "")
            case "check":
                guard let chk = (st["reminderChecks"]?.arrayValue ?? []).first(where: { $0["id"]?.idString == e["checkId"]?.idString && e["checkId"]?.idString != nil })
                else { return "روش دریافت: چک" }
                var bits = ["روش دریافت: چک"]
                if let b = chk["bankName"]?.stringValue, !b.isEmpty { bits.append("بانک " + b) }
                if let n = chk["checkNumber"]?.idString, !n.isEmpty { bits.append("شماره " + Money.persianDigits(n)) }
                if chk["dueDate"]?.objectValue != nil { bits.append("سررسید " + longDate(ImportAnalyzer.date(chk["dueDate"]))) }
                if let s = chk["status"]?.stringValue, !s.isEmpty { bits.append("وضعیت " + (s == "pending" ? "در انتظار" : s == "cashed" ? "وصول‌شده" : s)) }
                return bits.joined(separator: " — ")
            default:
                return "روش دریافت: نقدی"
            }
        }
        var lines = ["گزارش تنخواه به تفکیک طرف حساب — «" + accountName + "»", "تاریخ گزارش: " + longDate(t), ""]
        if rep.groups.isEmpty { lines.append("هنوز تنخواهی برای این پروژه ثبت نشده.") }
        for g in rep.groups {
            lines.append("— \(g.name) — جمع: \(fmt(g.total)) تومان (\(g.rows.count) مورد)")
            for r in g.rows {
                let d = ImportAnalyzer.date(r["date"])
                let desc = r["desc"]?.stringValue ?? ""
                lines.append("  \(d.jy)/\(d.jm)/\(d.jd) | \(fmt(ImportAnalyzer.toman(.object(r)))) تومان" + (desc.isEmpty ? "" : " | " + desc) + " | " + detail(r))
            }
            lines.append("")
        }
        lines.append("جمع کل تنخواه دریافتی این پروژه: \(fmt(rep.total)) تومان")
        return lines.joined(separator: "\n")
    }
}
