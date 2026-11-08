import SwiftUI
import HesabCore

/// Home search. One query, a scope bar (کلی / دفترها / شخصی / درآمد / یادآوری‌ها), and under «دفترها» a ledger picker and
/// expense/tankhah filter. Results are always grouped by where they live — every ledger is its own group, then personal,
/// income, checks, persons, appointments — so data from different places never mixes in one list.
struct SearchView: View {
    @ObservedObject var model: AppModel
    @Environment(\.theme) private var t
    @State private var query = ""
    @FocusState private var focused: Bool
    @State private var sheet: SearchSheet?
    @State private var personTarget: String?
    @AppStorage("search.scope") private var scopeRaw = Scope.all.rawValue
    @AppStorage("search.ledger") private var ledgerId = ""          // "" = every ledger
    @AppStorage("search.ledgerKind") private var kindRaw = LedgerKind.any.rawValue

    enum Scope: String, CaseIterable, Identifiable {
        case all, ledgers, personal, income, reminders
        var id: String { rawValue }
        var title: String {
            switch self {
            case .all: return "کلی"
            case .ledgers: return "دفترها"
            case .personal: return "شخصی"
            case .income: return "درآمد"
            case .reminders: return "یادآوری‌ها"
            }
        }
        var icon: String {
            switch self {
            case .all: return "square.grid.2x2"
            case .ledgers: return "book.closed"
            case .personal: return "wallet.bifold"
            case .income: return "arrow.down.circle"
            case .reminders: return "bell"
            }
        }
        var hint: String {
            switch self {
            case .all: return "در همه‌ی بخش‌ها جستجو می‌شود، ولی نتیجه‌ی هر دفتر و هر بخش جدا نشان داده می‌شود."
            case .ledgers: return "فقط در دفترهای حساب. می‌توانید یک دفتر را انتخاب کنید و فقط هزینه یا فقط تنخواه را ببینید."
            case .personal: return "فقط در هزینه‌های شخصی."
            case .income: return "فقط در درآمدها."
            case .reminders: return "در چک‌ها، بدهکاران/طلبکاران و قرارها."
            }
        }
        func contains(_ k: SearchResult.Kind) -> Bool {
            switch self {
            case .all: return true
            case .ledgers: return k == .expense
            case .personal: return k == .personal
            case .income: return k == .income
            case .reminders: return k == .check || k == .person || k == .appointment
            }
        }
    }

    enum LedgerKind: String, CaseIterable, Identifiable {
        case any, expense, tankhah
        var id: String { rawValue }
        var title: String { self == .any ? "همه" : self == .expense ? "هزینه" : "تنخواه" }
    }

    enum SearchSheet: Identifiable {
        case expense(String, LedgerRowVM), personal(SimpleRowVM), income(SimpleRowVM), check(String), appointment(String)
        var id: String {
            switch self {
            case .expense(_, let r): return "e" + r.rowId
            case .personal(let r): return "p" + r.rowId
            case .income(let r): return "i" + r.rowId
            case .check(let id): return "c" + id
            case .appointment(let id): return "a" + id
            }
        }
    }

    private var scope: Scope { Scope(rawValue: scopeRaw) ?? .all }
    private var kind: LedgerKind { LedgerKind(rawValue: kindRaw) ?? .any }
    private var trimmed: String { query.trimmingCharacters(in: .whitespaces) }

    /// every hit, all places (scope chips show their own counts from this)
    private var everything: [SearchResult] {
        trimmed.isEmpty ? [] : SearchEngine.find(model.state, query: trimmed, scope: .all, limit: 5000)
    }

    private func inLedgerFilter(_ r: SearchResult) -> Bool {
        guard r.kind == .expense else { return true }
        if scope == .ledgers {
            if !ledgerId.isEmpty, r.accountId != ledgerId { return false }
            if kind == .expense, r.isTankhah { return false }
            if kind == .tankhah, !r.isTankhah { return false }
        }
        return true
    }

    var body: some View {
        let all = everything
        let shown = all.filter { scope.contains($0.kind) && inLedgerFilter($0) }
        let groups = Dictionary(grouping: shown, by: \.groupOrder).sorted { $0.key < $1.key }.map(\.value)
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10, pinnedViews: []) {
                field
                scopeBar(all)
                if scope == .ledgers { ledgerFilters(all) }

                if trimmed.isEmpty {
                    Label(scope.hint, systemImage: "info.circle")
                        .font(AppFont.regular(13)).foregroundStyle(t.soft).padding(.horizontal, 4).padding(.top, 4)
                    Text("چند کلمه را با فاصله بنویسید تا ردیف‌هایی بیایند که همه‌شان را دارند (مثلاً «سیمان مصالح»). مبلغ و شماره‌ی چک هم جستجو می‌شود؛ رقم فارسی یا انگلیسی فرقی ندارد.")
                        .font(AppFont.caption).foregroundStyle(t.soft).padding(.horizontal, 4)
                } else if shown.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "magnifyingglass").font(.system(size: 28)).foregroundStyle(t.soft)
                        Text(all.isEmpty ? "چیزی پیدا نشد" : "در «\(scopeTitle)» چیزی نیست")
                            .font(AppFont.medium(15)).foregroundStyle(t.ink)
                        if !all.isEmpty {
                            Button("نمایش در همه‌ی بخش‌ها (\(Fmt.count(all.count)))") { withAnimation { scopeRaw = Scope.all.rawValue } }
                                .font(AppFont.medium(14)).foregroundStyle(t.accent)
                        }
                    }
                    .frame(maxWidth: .infinity).padding(30)
                } else {
                    Text(Fmt.count(shown.count) + " نتیجه در " + Fmt.count(groups.count) + " بخش")
                        .font(AppFont.caption).foregroundStyle(t.soft).padding(.horizontal, 4)
                    ForEach(groups, id: \.first!.groupOrder) { g in group(g) }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(AppBackground())
        .navigationTitle("جستجو")
        .onAppear {
            // a ledger that no longer exists → back to every ledger
            if !ledgerId.isEmpty, !model.accounts.contains(where: { $0.id == ledgerId }) { ledgerId = "" }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { focused = true }
        }
        .navigationDestination(isPresented: Binding(get: { personTarget != nil }, set: { if !$0 { personTarget = nil } })) {
            if let id = personTarget { PersonDetailView(model: model, personId: id) }
        }
        .sheet(item: $sheet) { s in
            Themed {
                NavigationStack {
                    switch s {
                    case .expense(let acc, let row): ExpenseFormView(model: model, accountId: acc, editing: row)
                    case .personal(let row): PersonalFormView(model: model, editing: row)
                    case .income(let row): IncomeFormView(model: model, editing: row)
                    case .check(let id): CheckFormView(model: model, editingId: id)
                    case .appointment(let id): AppointmentFormView(model: model, editingId: id)
                    }
                }
            }
        }
    }

    private var scopeTitle: String {
        if scope == .ledgers, let a = model.accounts.first(where: { $0.id == ledgerId }) { return a.name }
        return scope.title
    }

    // MARK: pieces

    private var field: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(t.soft)
            TextField("جستجو در «\(scopeTitle)»…", text: $query)
                .font(AppFont.regular(16))
                .focused($focused)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .accessibilityIdentifier("search.field")
            if !query.isEmpty {
                Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(t.soft) }
                    .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .glassEffect(.regular.interactive(), in: Capsule())
    }

    private func scopeBar(_ all: [SearchResult]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Scope.allCases) { s in
                    chip(s.title, icon: s.icon, count: trimmed.isEmpty ? nil : all.filter { s.contains($0.kind) }.count,
                         on: scope == s, id: "search.scope.\(s.rawValue)") {
                        withAnimation(.snappy) { scopeRaw = s.rawValue }
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func ledgerFilters(_ all: [SearchResult]) -> some View {
        let ledgerHits = all.filter { $0.kind == .expense }
        return VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    chip("همه‌ی دفترها", icon: nil, count: trimmed.isEmpty ? nil : ledgerHits.count, on: ledgerId.isEmpty,
                         id: "search.ledger.all") { withAnimation(.snappy) { ledgerId = "" } }
                    ForEach(model.accounts) { a in
                        chip(a.name, icon: nil, count: trimmed.isEmpty ? nil : ledgerHits.filter { $0.accountId == a.id }.count,
                             on: ledgerId == a.id, id: "search.ledger.\(a.id)") { withAnimation(.snappy) { ledgerId = a.id } }
                    }
                }
                .padding(.vertical, 2)
            }
            Picker("نوع ردیف", selection: $kindRaw) {
                ForEach(LedgerKind.allCases) { k in Text(k.title).tag(k.rawValue) }
            }
            .pickerStyle(.segmented)
        }
        .padding(12)
        .background(t.accent.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private func chip(_ title: String, icon: String?, count: Int?, on: Bool, id: String, action: @escaping () -> Void) -> some View {
        Button(action: { Haptics.tap(); action() }) {
            HStack(spacing: 5) {
                if let icon { Image(systemName: icon).font(.system(size: 12, weight: .semibold)) }
                Text(title).font(AppFont.medium(13)).lineLimit(1)
                if let count {
                    Text(Fmt.count(count))
                        .font(AppFont.bold(11))
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background((on ? Color.white : t.accent).opacity(on ? 0.25 : 0.12), in: Capsule())
                        .opacity(count == 0 ? 0.5 : 1)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .foregroundStyle(on ? Color.white : t.ink)
            .background(on ? AnyShapeStyle(t.accent) : AnyShapeStyle(t.accent.opacity(0.08)), in: Capsule())
            .overlay(Capsule().strokeBorder(t.accent.opacity(on ? 0 : 0.18), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func groupIcon(_ r: SearchResult) -> String {
        switch r.kind {
        case .expense: return "book.closed.fill"
        case .personal: return "wallet.bifold.fill"
        case .income: return "arrow.down.circle.fill"
        case .check: return "doc.text.fill"
        case .person: return "person.2.fill"
        case .appointment: return "calendar"
        }
    }

    @ViewBuilder private func group(_ rows: [SearchResult]) -> some View {
        let head = rows[0]
        let total = rows.reduce(0) { $0 + $1.amount }
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: groupIcon(head)).font(.system(size: 13, weight: .semibold)).foregroundStyle(t.accent)
                Text(head.group).font(AppFont.bold(15)).foregroundStyle(t.ink).lineLimit(1)
                Text(Fmt.count(rows.count)).font(AppFont.bold(11)).foregroundStyle(t.accent)
                    .padding(.horizontal, 7).padding(.vertical, 2).background(t.accent.opacity(0.12), in: Capsule())
                Spacer(minLength: 6)
                if head.kind != .appointment {
                    Text(Fmt.toman(total)).font(AppFont.medium(12)).foregroundStyle(t.soft).lineLimit(1)
                }
            }
            .padding(.horizontal, 4).padding(.top, 8)
            ForEach(rows) { r in row(r) }
        }
    }

    private func row(_ r: SearchResult) -> some View {
        Button { open(r) } label: {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(r.tag)
                        .font(AppFont.bold(11)).padding(.horizontal, 8).padding(.vertical, 3)
                        .foregroundStyle(r.isTankhah ? t.ink : t.accent)
                        .background((r.isTankhah ? t.soft : t.accent).opacity(0.13), in: Capsule())
                    Text(r.title).font(AppFont.medium(15)).foregroundStyle(t.ink).lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if !r.sub.isEmpty {
                        Text(r.sub).font(AppFont.caption).foregroundStyle(t.soft).lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                if r.kind != .appointment {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(Money.persianDigits(Money.format(r.amount))).font(AppFont.heavy(15)).foregroundStyle(t.ink)
                        Text("تومان").font(AppFont.caption).foregroundStyle(t.soft)
                    }
                }
            }
            .glassCard(padding: 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func open(_ r: SearchResult) {
        Haptics.tap()
        switch r.kind {
        case .expense:
            guard let acc = r.accountId, let row = model.rows(accountId: acc).first(where: { $0.rowId == r.recordId }) else { return }
            if row.isLinked { model.errorMessage = LedgerError.linkedRow("چک یا بدهی").message; return }
            if model.isLocked(row.dateValue) { model.errorMessage = "این ردیف قدیمی است؛ از صفحه‌ی دفتر حساب با رمز بازش کنید."; return }
            sheet = .expense(acc, row)
        case .personal:
            guard let row = model.personalRows.first(where: { $0.rowId == r.recordId }) else { return }
            if row.isLinked { model.errorMessage = LedgerError.linkedRow("چک یا بدهی").message; return }
            sheet = .personal(row)
        case .income:
            guard let row = model.incomeRows.first(where: { $0.rowId == r.recordId }) else { return }
            if row.isCommission { model.errorMessage = LedgerError.commissionIncome.message; return }
            sheet = .income(row)
        case .check:
            sheet = .check(r.recordId)
        case .person:
            personTarget = r.recordId
        case .appointment:
            sheet = .appointment(r.recordId)
        }
    }
}
