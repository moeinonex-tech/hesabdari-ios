import SwiftUI
import UserNotifications
import HesabCore

// MARK: - read models

struct SimpleRowVM: Identifiable {
    let id: String
    let rowId: String
    let desc: String
    let dateValue: JalaliDate
    let date: String
    let toman: Int
    let category: String
    let subcategory: String
    let payMethod: String?
    let cardId: String?
    let accountLink: String
    let accountName: String
    let isLinked: Bool
    let isCommission: Bool
    var itemCount = 0
}

struct CheckVM: Identifiable {
    let id: String
    let party: String
    let amount: Int
    let due: JalaliDate
    let daysLeft: Int
    let status: String
    let pay: Bool               // true = paid by me (pay), false = received
    let ident: String
    let bank: String
}

struct PersonVM: Identifiable {
    let id: String
    let name: String
    let creditor: Bool          // I owe them
    let installments: [InstallmentVM]
    var unpaid: Int { installments.filter { !$0.paid }.reduce(0) { $0 + $1.amount } }
    var total: Int { installments.reduce(0) { $0 + $1.amount } }
}

struct InstallmentVM: Identifiable {
    let id: String
    let amount: Int
    let due: JalaliDate
    let daysLeft: Int
    let paid: Bool
    let desc: String
}

struct AppointmentVM: Identifiable {
    let id: String
    let title: String
    let date: JalaliDate
    let daysLeft: Int
    let time: String
    let place: String
    let done: Bool
}

extension AppModel {

    private func simpleRows(_ key: String) -> [SimpleRowVM] {
        let list = state[key]?.arrayValue ?? []
        let sorted = list.enumerated().sorted { a, b in
            let da = ImportAnalyzer.date(a.element["date"]), db = ImportAnalyzer.date(b.element["date"])
            if da != db { return da > db }
            let ta = a.element["ts"]?.intValue ?? 0, tb = b.element["ts"]?.intValue ?? 0
            if ta != tb { return ta > tb }
            return a.offset > b.offset
        }.map(\.element)
        return sorted.enumerated().map { i, e in
            let d = ImportAnalyzer.date(e["date"])
            let rid = e["id"]?.idString ?? ""
            return SimpleRowVM(id: rid + "#\(i)", rowId: rid, desc: e["desc"]?.stringValue ?? "", dateValue: d,
                               date: Money.persianDigits("\(d.jy)/\(d.jm)/\(d.jd)"), toman: ImportAnalyzer.toman(e),
                               category: e["category"]?.stringValue ?? "", subcategory: e["subcategory"]?.stringValue ?? "",
                               payMethod: e["payMethod"]?.stringValue, cardId: e["cardId"]?.idString,
                               accountLink: e["accountId"]?.idString ?? "personal", accountName: e["accountName"]?.stringValue ?? "",
                               isLinked: e["linked"]?["kind"]?.stringValue != nil,
                               isCommission: e["commissionSettlementId"]?.idString != nil,
                               itemCount: e["items"]?.arrayValue?.count ?? 0)
        }
    }

    var personalRows: [SimpleRowVM] { simpleRows("personalExpenses") }
    var incomeRows: [SimpleRowVM] { simpleRows("incomes") }
    var personalBudget: Int { state["personalBudget"]?.intValue ?? 0 }
    var personalCategories: [String] { (state["personalCategories"]?.arrayValue ?? []).compactMap(\.stringValue) }
    func personalSubcategories(of c: String) -> [String] { (state["personalSubcategories"]?[c]?.arrayValue ?? []).compactMap(\.stringValue) }
    var incomeCategories: [String] { (state["incomeCategories"]?.arrayValue ?? []).compactMap(\.stringValue) }
    func incomeSubcategories(of c: String) -> [String] { (state["incomeSubcategories"]?[c]?.arrayValue ?? []).compactMap(\.stringValue) }
    var incomeLinks: [Choice] { [Choice(id: "personal", label: "شخصی")] + accounts.map { Choice(id: $0.id, label: $0.name) } }

    func slices(_ rows: [SimpleRowVM]) -> [CategorySlice] {
        var sums: [String: Int] = [:]
        for r in rows { sums[r.category.isEmpty ? "بدون دسته" : r.category, default: 0] += r.toman }
        let palette: [Color] = [.blue, .teal, .orange, .pink, .purple, .green, .indigo, .mint, .red, .yellow]
        let incomeColors = state["categoryColorsIncome"]
        return sums.sorted { $0.value > $1.value }.enumerated().map { i, kv in
            CategorySlice(name: kv.key, total: kv.value,
                          color: categoryColor(kv.key) ?? Color.web(incomeColors?[kv.key]?.stringValue) ?? palette[i % palette.count])
        }
    }

    // changes
    func addPersonal(_ i: PersonalInput) -> Bool { change { try RecordOps.addPersonal(state, i).state } }
    func editPersonal(_ id: String, _ i: PersonalInput) -> Bool { change { try RecordOps.editPersonal(state, id: id, i) } }
    func deletePersonal(_ id: String) -> Bool { change({ try RecordOps.deletePersonal(state, id: id) }, undoMessage: "حذف شد") }
    func addIncome(_ i: IncomeInput) -> Bool { change { try RecordOps.addIncome(state, i).state } }
    func editIncome(_ id: String, _ i: IncomeInput) -> Bool { change { try RecordOps.editIncome(state, id: id, i) } }
    func deleteIncome(_ id: String) -> Bool { change({ try RecordOps.deleteIncome(state, id: id) }, undoMessage: "حذف شد") }

    // reminders
    private func daysFromToday(_ d: JalaliDate) -> Int {
        let t = Self.today
        return Jalali.j2d(d.jy, d.jm, d.jd) - Jalali.j2d(t.jy, t.jm, t.jd)
    }

    var checks: [CheckVM] {
        (state["reminderChecks"]?.arrayValue ?? []).map { c in
            let due = ImportAnalyzer.date(c["dueDate"])
            return CheckVM(id: c["id"]?.idString ?? UUID().uuidString, party: c["party"]?.stringValue ?? "",
                           amount: c["amount"]?.intValue ?? 0, due: due, daysLeft: daysFromToday(due),
                           status: c["status"]?.stringValue ?? "pending",
                           pay: (c["direction"]?.stringValue ?? "pay") != "receive",
                           ident: NotificationPlanner.checkIdent(c), bank: c["bankName"]?.stringValue ?? "")
        }.sorted { $0.daysLeft < $1.daysLeft }
    }

    var persons: [PersonVM] {
        (state["reminderPersons"]?.arrayValue ?? []).map { p in
            let ins = (p["installments"]?.arrayValue ?? []).map { i -> InstallmentVM in
                let due = ImportAnalyzer.date(i["dueDate"])
                return InstallmentVM(id: i["id"]?.idString ?? UUID().uuidString, amount: i["amount"]?.intValue ?? 0, due: due,
                                     daysLeft: daysFromToday(due), paid: i["paid"]?.isTruthy ?? false,
                                     desc: i["description"]?.stringValue ?? "")
            }.sorted { $0.daysLeft < $1.daysLeft }
            return PersonVM(id: p["id"]?.idString ?? UUID().uuidString, name: p["name"]?.stringValue ?? "",
                            creditor: p["type"]?.stringValue == "creditor", installments: ins)
        }
    }

    var appointments: [AppointmentVM] {
        (state["appointments"]?.arrayValue ?? []).map { a in
            let d = ImportAnalyzer.date(a["date"])
            return AppointmentVM(id: a["id"]?.idString ?? UUID().uuidString, title: a["title"]?.stringValue ?? "قرار", date: d,
                                 daysLeft: daysFromToday(d), time: a["time"]?.stringValue ?? "",
                                 place: a["location"]?["label"]?.stringValue ?? "", done: a["done"]?.isTruthy ?? false)
        }.sorted { $0.daysLeft < $1.daysLeft }
    }

    /// web reminders header: what others owe me / what I owe
    var owedToMe: Int {
        persons.filter { !$0.creditor }.reduce(0) { $0 + $1.unpaid }
            + checks.filter { !$0.pay && $0.status == "pending" }.reduce(0) { $0 + $1.amount }
    }
    var iOwe: Int {
        persons.filter { $0.creditor }.reduce(0) { $0 + $1.unpaid }
            + checks.filter { $0.pay && $0.status == "pending" }.reduce(0) { $0 + $1.amount }
    }
}

// MARK: - notifications

enum Notifier {
    static let enabledKey = "notify.enabled"
    static let deliveredKey = "notify.delivered"      // catch-up items already shown (id|endAt)

    static var enabled: Bool { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }

    /// Re-plans everything: removes our pending requests, adds the 60 nearest, delivers catch-ups once.
    static func sync(_ state: [String: JSONValue]) {
        let center = UNUserNotificationCenter.current()
        guard enabled else {
            center.removeAllPendingNotificationRequests()
            return
        }
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            guard granted else { return }
            let plan = NotificationPlanner.plan(state, now: Date())
            center.removeAllPendingNotificationRequests()
            let cal = Calendar.current
            for n in plan.scheduled {
                guard let fire = n.fireAt else { continue }
                let content = UNMutableNotificationContent()
                content.title = n.title
                content.body = n.body
                content.sound = .default
                let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
                let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
                center.add(UNNotificationRequest(identifier: n.id, content: content, trigger: trigger))
            }
            var delivered = Set(UserDefaults.standard.stringArray(forKey: deliveredKey) ?? [])
            for n in plan.immediate {
                let key = n.id + "|" + String(Int(n.endAt.timeIntervalSince1970))
                guard !delivered.contains(key) else { continue }
                delivered.insert(key)
                let content = UNMutableNotificationContent()
                content.title = n.title
                content.body = n.body
                content.sound = .default
                center.add(UNNotificationRequest(identifier: n.id + "-now", content: content, trigger: nil))
            }
            UserDefaults.standard.set(Array(delivered.suffix(500)), forKey: deliveredKey)
        }
    }
}

// MARK: - personal tab (personal expenses + income)

enum PersonalSheet: Identifiable {
    case newExpense, editExpense(SimpleRowVM), newIncome, editIncome(SimpleRowVM)
    var id: String {
        switch self {
        case .newExpense: return "ne"
        case .editExpense(let r): return "ee-" + r.rowId
        case .newIncome: return "ni"
        case .editIncome(let r): return "ei-" + r.rowId
        }
    }
}

struct PersonalView: View {
    @ObservedObject var model: AppModel
    @Environment(\.theme) private var t
    @State private var showIncome = false
    @State private var sheet: PersonalSheet?
    @State private var showBudget = false

    var body: some View {
        let rows = showIncome ? model.incomeRows : model.personalRows
        let total = rows.reduce(0) { $0 + $1.toman }
        PageScrollView(tab: .personal) {
            LazyVStack(alignment: .leading, spacing: 16) {
                ScreenHeader(title: showIncome ? "درآمد" : "دفتر شخصی", subtitle: showIncome ? "همه‌ی درآمدها" : "هزینه‌های شخصی")
                Segmented(selection: $showIncome.animation(.snappy), [(false, "هزینه‌های شخصی"), (true, "درآمد")])

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(showIncome ? "جمع درآمدها" : "جمع هزینه‌ها").font(AppFont.regular(13)).foregroundStyle(t.soft)
                        Spacer()
                        if !showIncome {
                            Button { showBudget = true } label: {
                                Label(model.personalBudget > 0 ? "بودجه" : "تنظیم بودجه", systemImage: "target").font(AppFont.caption)
                            }
                            .buttonStyle(.glass)
                        }
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(Money.persianDigits(Money.format(total))).font(AppFont.heavy(30))
                            .foregroundStyle(showIncome ? t.success : t.accent).contentTransition(.numericText())
                        Text("تومان").font(AppFont.regular(13)).foregroundStyle(t.soft)
                    }
                    if !showIncome && model.personalBudget > 0 {
                        let pct = min(1, Double(total) / Double(model.personalBudget))
                        GradientBar(value: pct, from: t.accent, to: pct >= 0.8 ? t.warning : t.accent2)
                        Text("\(Money.persianDigits(Money.jsRound(pct * 100)))٪ از بودجه‌ی " + Fmt.toman(model.personalBudget))
                            .font(AppFont.caption).foregroundStyle(t.soft)
                    }
                    Button {
                        sheet = showIncome ? .newIncome : .newExpense
                    } label: {
                        Label(showIncome ? "ثبت درآمد" : "ثبت هزینه", systemImage: "plus")
                            .font(AppFont.bold(15)).frame(maxWidth: .infinity).padding(.vertical, 4)
                    }
                    .buttonStyle(.glassProminent)
                }
                .glassCard()

                let st = model.statItems(showIncome ? "incomes" : "personalExpenses")
                let s = model.breakdown(st, kind: showIncome ? .income : .expense)
                let sub = model.breakdown(st, kind: showIncome ? .income : .expense, sub: true)
                let colors = model.colorMap(s)
                let scope = showIncome ? "درآمد" : "دفتر شخصی"
                if !s.isEmpty { CategoryChartCard(slices: s, subs: sub, model: model, scope: scope) }
                if !sub.isEmpty { SubcategoryChartCard(slices: sub, model: model, scope: scope) }

                if rows.isEmpty {
                    Text("هنوز ردیفی نیست").font(AppFont.regular(14)).foregroundStyle(t.soft).frame(maxWidth: .infinity).padding(30)
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(rows) { r in
                            SimpleRowLine(row: r, income: showIncome, color: colors[r.category.isEmpty ? "بدون دسته" : r.category])
                                .onTapGesture { open(r) }
                                .contextMenu {
                                    Button { open(r) } label: { Label("ویرایش", systemImage: "pencil") }
                                    Button(role: .destructive) { remove(r) } label: { Label("حذف", systemImage: "trash") }
                                }
                            if r.id != rows.last?.id { Divider().opacity(0.5) }
                        }
                    }
                    .glassCard()
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .background(AppBackground())
        .scrollsToTopOnDockTap(.personal)
        .pageSwipe(.personal, $showIncome, [false, true])
        .toolbar(.hidden, for: .navigationBar)
        .overlay(alignment: .bottom) { UndoBanner(model: model).padding(.bottom, AppShell.dockClearance) }
        .sheet(isPresented: $showBudget) {
            NavigationStack {
                BudgetEditor(title: "بودجه‌ی شخصی", current: model.personalBudget) { _ = model.setPersonalBudget($0) }
            }
            .presentationDetents([.medium])
        }
        .sheet(item: $sheet) { s in
            Themed {
                NavigationStack {
                    switch s {
                    case .newExpense: PersonalFormView(model: model, editing: nil)
                    case .editExpense(let r): PersonalFormView(model: model, editing: r)
                    case .newIncome: IncomeFormView(model: model, editing: nil)
                    case .editIncome(let r): IncomeFormView(model: model, editing: r)
                    }
                }
            }
        }
    }

    private func open(_ r: SimpleRowVM) {
        if showIncome {
            if r.isCommission { model.errorMessage = LedgerError.commissionIncome.message; return }
            sheet = .editIncome(r)
        } else {
            if r.isLinked { model.errorMessage = LedgerError.linkedRow("چک یا بدهی").message; return }
            sheet = .editExpense(r)
        }
    }

    private func remove(_ r: SimpleRowVM) {
        let ok = showIncome ? model.deleteIncome(r.rowId) : model.deletePersonal(r.rowId)
        if ok { Haptics.warning() }
    }
}

struct SimpleRowLine: View {
    let row: SimpleRowVM
    let income: Bool
    let color: Color?
    @Environment(\.theme) private var t

    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(color ?? (income ? t.success : t.accent)).frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.desc.isEmpty ? "—" : row.desc).font(AppFont.medium(14)).foregroundStyle(t.ink).lineLimit(2)
                HStack(spacing: 6) {
                    if row.itemCount > 1 { InvoiceTag(count: row.itemCount) }
                    if !row.category.isEmpty { Text(row.category) }
                    Text(row.date)
                    if income && row.accountLink != "personal" && !row.accountName.isEmpty { Text("· " + row.accountName) }
                    if row.isCommission || row.isLinked { Image(systemName: "link") }
                }
                .font(AppFont.caption).foregroundStyle(t.soft).lineLimit(1)
            }
            Spacer(minLength: 8)
            Text((income ? "+" : "") + Money.persianDigits(Money.format(row.toman)))
                .font(AppFont.bold(14)).foregroundStyle(income ? t.success : t.ink)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}

struct PersonalFormView: View {
    @ObservedObject var model: AppModel
    let editing: SimpleRowVM?
    @Environment(\.dismiss) private var dismiss
    @State private var desc = ""
    @State private var category = ""
    @State private var subcategory = ""
    @State private var amount = ""
    @State private var date = AppModel.today
    @State private var method = "hamrahbank"
    @State private var cardId: String?
    @State private var loaded = false
    @State private var linkParty = ""
    @State private var checkBank = ""
    @State private var checkNumber = ""
    @State private var nasiyehDue = AppModel.today
    @State private var itemCount = 1
    @State private var items: [ExpenseItem] = []
    @State private var checkCount = 1
    @State private var slots: [CheckSlot] = []
    @State private var checkTotal = ""

    private var makesCheck: Bool { editing == nil && method == "check" }
    private var makesNasiyeh: Bool { editing == nil && method == "nasiyeh" }
    private var isMulti: Bool { itemCount > 1 && !makesCheck }
    private var multiCheck: Bool { makesCheck && checkCount > 1 }

    var body: some View {
        Form {
            if editing == nil {
                NotesImportLink(model: model, ledgerAccountId: nil) { dismiss() }
            }
            Section {
                TextField("شرح", text: $desc)
                if !makesCheck { CountRow(title: "تعداد اقلام", count: itemCountBinding, max: MultiItem.maxCount) }
                if !isMulti {
                    SuggestField(title: "نوع هزینه", text: $category, suggestions: model.personalCategories)
                    LearnChips(model: model, ctx: .personal, desc: desc, category: $category, subcategory: $subcategory, sub: false)
                    SuggestField(title: "زیردسته", text: $subcategory, suggestions: model.personalSubcategories(of: category))
                    LearnChips(model: model, ctx: .personal, desc: desc, category: $category, subcategory: $subcategory, sub: true)
                }
            }
            if isMulti {
                MultiItemSections(model: model, ctx: .personal, mainDesc: desc, items: $items,
                                  categories: model.personalCategories, subcategories: { model.personalSubcategories(of: $0) })
            }
            if !multiCheck {
                Section {
                    if !isMulti { AmountField(title: "مبلغ (تومان)", text: $amount) }
                    JalaliDateField(title: makesCheck ? "تاریخ سررسید چک" : "تاریخ", date: $date)
                }
            }
            Section("روش پرداخت") {
                Picker("روش", selection: $method) {
                    ForEach(methodChoices) { m in Text(m.label).tag(m.id) }
                }
                if PersonalInput.usesCard(method) && !model.activeCards.isEmpty {
                    CardPicker(model: model, cardId: $cardId)
                }
            }
            if makesCheck {
                Section("اطلاعات چک") {
                    CountRow(title: "تعداد چک", count: checkCountBinding, max: CheckGroup.maxCount)
                    SuggestField(title: "در وجه", text: $linkParty, suggestions: model.partyNames)
                    BankNameField(title: "بانک", text: $checkBank)
                    if !multiCheck { TextField("شماره چک", text: $checkNumber).keyboardType(.numberPad) }
                }
                if multiCheck { MultiCheckSections(slots: $slots, total: $checkTotal, showSayad: false) }
            }
            if makesNasiyeh {
                Section("نسیه") {
                    SuggestField(title: "طلبکار", text: $linkParty, suggestions: model.creditorNames)
                    JalaliDateField(title: "سررسید پرداخت", date: $nasiyehDue)
                }
            }
        }
        .navigationTitle(editing == nil ? "هزینه‌ی شخصی" : "ویرایش")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("انصراف") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("ذخیره") { save() }.bold() }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            if let r = editing {
                desc = r.desc; category = r.category; subcategory = r.subcategory
                amount = Money.persianDigits(Money.format(r.toman)); date = r.dateValue
                method = r.payMethod ?? "hamrahbank"; cardId = r.cardId
                let its = model.items(ofRow: "personalExpenses", r.rowId)
                if its.count > 1 { items = its; itemCount = its.count }
            } else {
                cardId = model.activeCards.first?.id
            }
        }
        .onChange(of: makesCheck) { _, check in if check && itemCount > 1 { itemCountBinding.wrappedValue = 1 } }
    }

    private var methodChoices: [Choice] {
        var list = PersonalInput.methods.map { Choice(id: $0.id, label: $0.title) }
        if editing != nil { list.removeAll { $0.id == "check" || $0.id == "nasiyeh" } }
        if let m = editing?.payMethod, !list.contains(where: { $0.id == m }) {
            list.append(Choice(id: m, label: PayMethod(rawValue: m)?.title ?? m))
        }
        return list
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
            MultiCheckSections.resize(&slots, to: new, first: CheckSlot(amount: Fmt.parseAmount(amount), due: date, number: checkNumber, sayad: ""))
        } else if old > 1, let first = slots.first {
            amount = first.amount > 0 ? Money.persianDigits(Money.format(first.amount)) : ""
            date = first.due; checkNumber = first.number
            slots = []
        }
            checkCount = new
        })
    }

    private func save() {
        var input = PersonalInput(desc: desc, category: category, subcategory: subcategory, toman: Fmt.parseAmount(amount),
                                  date: date, payMethod: method, cardId: PersonalInput.usesCard(method) ? cardId : nil)
        if isMulti { input.items = items; input.toman = items.reduce(0) { $0 + $1.toman } }
        let ok: Bool
        if multiCheck {
            ok = model.addChecks(CheckInput(amount: 0, party: linkParty, bankName: checkBank, checkNumber: "", sayadId: "", checkSeries: "",
                                            desc: desc, category: category, subcategory: subcategory, dueDate: date, accountId: "personal"),
                                 slots: slots, total: Fmt.parseAmount(checkTotal))
        } else if makesCheck {
            ok = model.addCheck(CheckInput(amount: input.toman, party: linkParty, bankName: checkBank, checkNumber: checkNumber,
                                           sayadId: "", checkSeries: "", desc: desc, category: category, subcategory: subcategory,
                                           dueDate: date, accountId: "personal"))
        } else if makesNasiyeh {
            ok = model.addNasiyehPersonal(input, party: linkParty, due: nasiyehDue)
        } else {
            ok = editing.map { model.editPersonal($0.rowId, input) } ?? model.addPersonal(input)
        }
        if ok { Haptics.success(); dismiss() }
    }
}

struct IncomeFormView: View {
    @ObservedObject var model: AppModel
    let editing: SimpleRowVM?
    var presetLink: String? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var desc = ""
    @State private var category = ""
    @State private var subcategory = ""
    @State private var amount = ""
    @State private var date = AppModel.today
    @State private var link = "personal"
    @State private var loaded = false

    var body: some View {
        Form {
            Section {
                TextField("شرح", text: $desc)
                SuggestField(title: "نوع درآمد", text: $category, suggestions: model.incomeCategories)
                LearnChips(model: model, ctx: .income, desc: desc, category: $category, subcategory: $subcategory, sub: false)
                SuggestField(title: "زیردسته (اختیاری)", text: $subcategory, suggestions: model.incomeSubcategories(of: category))
                LearnChips(model: model, ctx: .income, desc: desc, category: $category, subcategory: $subcategory, sub: true)
            }
            Section {
                AmountField(title: "مبلغ (تومان)", text: $amount)
                JalaliDateField(title: "تاریخ", date: $date)
            }
            Section("مربوط به") {
                Picker("حساب", selection: $link) {
                    ForEach(model.incomeLinks) { c in Text(c.label).tag(c.id) }
                }
            }
        }
        .navigationTitle(editing == nil ? "درآمد" : "ویرایش درآمد")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("انصراف") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("ذخیره") { save() }.bold() }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            if let r = editing {
                desc = r.desc; category = r.category; subcategory = r.subcategory
                amount = Money.persianDigits(Money.format(r.toman)); date = r.dateValue; link = r.accountLink
            } else if let p = presetLink {
                link = p
            }
        }
    }

    private func save() {
        let input = IncomeInput(desc: desc, category: category, subcategory: subcategory, toman: Fmt.parseAmount(amount),
                                date: date, accountLink: link)
        let ok = editing.map { model.editIncome($0.rowId, input) } ?? model.addIncome(input)
        if ok { Haptics.success(); dismiss() }
    }
}

// MARK: - reminders tab (view)

struct RemindersView: View {
    @ObservedObject var model: AppModel
    @Environment(\.theme) private var t
    @State private var filter = 0
    @State private var sheet: ReminderSheet?

    var body: some View {
        let checks = model.checks
        let pending = checks.filter { $0.status == "pending" }
        let done = checks.filter { $0.status != "pending" }
        PageScrollView(tab: .reminders) {
            LazyVStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    ScreenHeader(title: "یادآوری‌ها", subtitle: "چک‌ها، بدهکاران و طلبکاران، قرارها")
                    Menu {
                        Button { sheet = .newCheck } label: { Label("چک جدید", systemImage: "doc.text") }
                        Button { sheet = .newPerson } label: { Label("شخص جدید (بدهکار/طلبکار)", systemImage: "person.badge.plus") }
                        Button { sheet = .newAppointment } label: { Label("قرار جدید", systemImage: "calendar.badge.plus") }
                    } label: {
                        Image(systemName: "plus").font(.title3.bold()).padding(10)
                    }
                    .buttonStyle(.glassProminent)
                    .padding(.top, 8)
                }

                HStack(spacing: 12) {
                    SummaryTile(title: "طلب من", value: model.owedToMe, color: t.success)
                    SummaryTile(title: "بدهی من", value: model.iOwe, color: t.danger)
                }

                Segmented(selection: $filter, [(0, "چک‌ها"), (1, "اشخاص"), (2, "قرارها")])

                switch filter {
                case 0:
                    if pending.isEmpty && done.isEmpty { EmptyNote(text: "چکی ثبت نشده") }
                    ForEach(pending) { c in checkRow(c) }
                    if !done.isEmpty {
                        SectionTitle(text: "وصول‌شده یا بسته‌شده")
                        ForEach(done) { c in checkRow(c).opacity(0.6) }
                    }
                case 1:
                    let persons = model.persons
                    if persons.isEmpty { EmptyNote(text: "کسی ثبت نشده") }
                    ForEach(persons) { p in
                        NavigationLink {
                            PersonDetailView(model: model, personId: p.id)
                        } label: {
                            PersonCard(person: p)
                        }
                        .buttonStyle(.plain)
                    }
                default:
                    let apts = model.appointments
                    if apts.isEmpty { EmptyNote(text: "قراری ثبت نشده") }
                    ForEach(apts) { a in
                        AppointmentCard(apt: a)
                            .onTapGesture { sheet = .editAppointment(a.id) }
                            .contextMenu {
                                Button { _ = model.toggleAppointment(a.id) } label: {
                                    Label(a.done ? "انجام‌نشده" : "انجام شد", systemImage: "checkmark.circle")
                                }
                                Button { Task { await model.addAppointmentToPhoneReminders(a.id) } } label: {
                                    Label("افزودن به Reminders گوشی", systemImage: "checklist")
                                }
                                Button(role: .destructive) { _ = model.deleteAppointment(a.id) } label: { Label("حذف", systemImage: "trash") }
                            }
                    }
                }

                Text("برای ویرایش روی هر مورد بزنید؛ برای کارهای سریع (وصول، برگشت، حذف) انگشت را روی آن نگه دارید.")
                    .font(AppFont.caption).foregroundStyle(t.soft)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .background(AppBackground())
        .scrollsToTopOnDockTap(.reminders)
        .pageSwipe(.reminders, $filter, [0, 1, 2])
        .toolbar(.hidden, for: .navigationBar)
        .overlay(alignment: .bottom) { UndoBanner(model: model).padding(.bottom, AppShell.dockClearance) }
        .sheet(item: $sheet) { s in
            Themed {
                NavigationStack {
                    switch s {
                    case .newCheck: CheckFormView(model: model, editingId: nil)
                    case .editCheck(let id): CheckFormView(model: model, editingId: id)
                    case .newPerson: PersonAddView(model: model)
                    case .newAppointment: AppointmentFormView(model: model, editingId: nil)
                    case .editAppointment(let id): AppointmentFormView(model: model, editingId: id)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func checkRow(_ c: CheckVM) -> some View {
        CheckCard(check: c)
            .onTapGesture { sheet = .editCheck(c.id) }
            .contextMenu {
                if c.status != "cashed" {
                    Button { if model.setCheckStatus(c.id, "cashed") { Haptics.success() } } label: { Label("وصول شد", systemImage: "checkmark.seal") }
                }
                if c.status != "pending" {
                    Button { _ = model.setCheckStatus(c.id, "pending") } label: { Label("برگرداندن به «در انتظار»", systemImage: "arrow.uturn.backward") }
                }
                if c.status != "bounced" {
                    Button { _ = model.setCheckStatus(c.id, "bounced") } label: { Label("برگشت خورد", systemImage: "xmark.octagon") }
                }
                Button { Task { await model.addCheckToPhoneReminders(c.id) } } label: {
                    Label("افزودن به Reminders گوشی", systemImage: "checklist")
                }
                Button(role: .destructive) { _ = model.deleteCheck(c.id) } label: { Label("حذف", systemImage: "trash") }
            }
    }
}

struct EmptyNote: View {
    let text: String
    @Environment(\.theme) private var t
    var body: some View {
        Text(text).font(AppFont.regular(14)).foregroundStyle(t.soft).frame(maxWidth: .infinity).padding(30)
    }
}

struct SummaryTile: View {
    let title: String
    let value: Int
    let color: Color
    @Environment(\.theme) private var t
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(AppFont.regular(12)).foregroundStyle(t.soft)
            Text(Money.persianDigits(Money.format(value))).font(AppFont.heavy(19)).foregroundStyle(color)
                .minimumScaleFactor(0.6).lineLimit(1)
            Text("تومان").font(AppFont.caption).foregroundStyle(t.soft)
        }
        .glassCard(padding: 14)
    }
}

struct DueBadge: View {
    let days: Int
    let resolved: Bool
    @Environment(\.theme) private var t

    private var info: (text: String, color: Color) {
        if resolved { return ("انجام‌شده", t.soft) }
        if days < 0 { return (Money.persianDigits(-days) + " روز گذشته", t.danger) }
        if days == 0 { return ("امروز", t.danger) }
        if days <= 3 { return (Money.persianDigits(days) + " روز دیگر", t.warning) }
        return (Money.persianDigits(days) + " روز دیگر", t.accent)
    }

    var body: some View {
        Text(info.text)
            .font(AppFont.bold(11))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .foregroundStyle(info.color)
            .background(info.color.opacity(0.13), in: Capsule())
    }
}

struct CheckCard: View {
    let check: CheckVM
    @Environment(\.theme) private var t

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: check.pay ? "arrow.up.right.circle.fill" : "arrow.down.left.circle.fill")
                    .foregroundStyle(check.pay ? t.danger : t.success)
                Text(check.party.isEmpty ? "بدون نام" : check.party).font(AppFont.bold(15)).foregroundStyle(t.ink)
                Spacer()
                DueBadge(days: check.daysLeft, resolved: check.status != "pending")
            }
            Text(Fmt.toman(check.amount)).font(AppFont.heavy(20)).foregroundStyle(t.ink)
            HStack(spacing: 8) {
                Text(BackupExporter.formatJalali(check.due))
                if !check.ident.isEmpty { Text("· چک " + check.ident) }
                if !check.bank.isEmpty {
                    HStack(spacing: 4) {
                        Text("·")
                        if let bk = SettingsOps.bank(named: check.bank) { BankLogo(bank: bk, size: 16) }
                        Text(check.bank)
                    }
                }
                Spacer()
                Text(statusText).foregroundStyle(statusColor)
            }
            .font(AppFont.caption).foregroundStyle(t.soft)
        }
        .glassCard()
    }

    private var statusText: String {
        switch check.status {
        case "cashed": return "وصول شد"
        case "bounced": return "برگشتی"
        case "cancelled": return "باطل"
        default: return check.pay ? "پرداختی" : "دریافتی"
        }
    }
    private var statusColor: Color {
        switch check.status {
        case "cashed": return t.success
        case "bounced", "cancelled": return t.danger
        default: return t.soft
        }
    }
}

struct PersonCard: View {
    let person: PersonVM
    @Environment(\.theme) private var t

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: person.creditor ? "person.fill.badge.minus" : "person.fill.badge.plus")
                    .foregroundStyle(person.creditor ? t.danger : t.success)
                Text(person.name).font(AppFont.bold(15)).foregroundStyle(t.ink)
                Spacer()
                Text(person.creditor ? "طلبکار" : "بدهکار").font(AppFont.caption).foregroundStyle(t.soft)
            }
            if person.total > 0 {
                let paidPct = Double(person.total - person.unpaid) / Double(person.total)
                GradientBar(value: paidPct, from: t.accent2, to: t.success)
                Text("مانده: " + Fmt.toman(person.unpaid) + " از " + Fmt.toman(person.total))
                    .font(AppFont.caption).foregroundStyle(t.soft)
            }
            ForEach(person.installments) { i in
                HStack {
                    Image(systemName: i.paid ? "checkmark.circle.fill" : "circle").foregroundStyle(i.paid ? t.success : t.soft)
                    Text(Fmt.toman(i.amount)).font(AppFont.medium(13)).foregroundStyle(t.ink)
                    Text(BackupExporter.formatJalali(i.due)).font(AppFont.caption).foregroundStyle(t.soft)
                    Spacer()
                    DueBadge(days: i.daysLeft, resolved: i.paid)
                }
            }
        }
        .glassCard()
    }
}

struct AppointmentCard: View {
    let apt: AppointmentVM
    @Environment(\.theme) private var t

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 2) {
                Text(Money.persianDigits(apt.date.jd)).font(AppFont.heavy(22)).foregroundStyle(t.accent)
                Text(BackupExporter.months.indices.contains(apt.date.jm - 1) ? BackupExporter.months[apt.date.jm - 1] : "")
                    .font(AppFont.caption).foregroundStyle(t.soft)
            }
            .frame(width: 58)
            VStack(alignment: .leading, spacing: 4) {
                Text(apt.title).font(AppFont.bold(15)).foregroundStyle(t.ink)
                HStack(spacing: 6) {
                    if !apt.time.isEmpty { Label(Money.persianDigits(apt.time), systemImage: "clock") }
                    if !apt.place.isEmpty { Label(apt.place, systemImage: "mappin") }
                }
                .font(AppFont.caption).foregroundStyle(t.soft)
            }
            Spacer()
            DueBadge(days: apt.daysLeft, resolved: apt.done)
        }
        .glassCard()
    }
}
