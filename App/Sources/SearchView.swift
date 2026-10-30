import SwiftUI
import HesabCore

struct SearchView: View {
    @ObservedObject var model: AppModel
    @Environment(\.theme) private var t
    @State private var query = ""
    @FocusState private var focused: Bool
    @State private var sheet: SearchSheet?

    enum SearchSheet: Identifiable {
        case expense(String, LedgerRowVM), personal(SimpleRowVM), income(SimpleRowVM), check(String)
        var id: String {
            switch self {
            case .expense(_, let r): return "e" + r.rowId
            case .personal(let r): return "p" + r.rowId
            case .income(let r): return "i" + r.rowId
            case .check(let id): return "c" + id
            }
        }
    }

    var body: some View {
        let results = query.trimmingCharacters(in: .whitespaces).isEmpty ? [] : SearchEngine.search(model.state, query: query)
        List {
            // search field at the top of the page (the system search bar sits at the bottom on iOS 26,
            // under our dock, so it is drawn here instead)
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(t.soft)
                TextField("جستجو در همه‌ی بخش‌ها…", text: $query)
                    .font(AppFont.regular(16))
                    .focused($focused)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(t.soft) }
                        .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 11)
            .glassEffect(.regular.interactive(), in: Capsule())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            if query.trimmingCharacters(in: .whitespaces).isEmpty {
                Text("در دفترها، هزینه‌های شخصی، درآمدها، چک‌ها و اشخاص جستجو کنید. عدد را با رقم فارسی یا انگلیسی بنویسید.")
                    .font(AppFont.regular(14)).foregroundStyle(t.soft)
                    .listRowBackground(Color.clear)
            } else if results.isEmpty {
                Text("چیزی پیدا نشد").font(AppFont.regular(14)).foregroundStyle(t.soft).listRowBackground(Color.clear)
            }
            ForEach(results) { r in
                Button { open(r) } label: {
                    HStack(spacing: 10) {
                        Text(r.tag)
                            .font(AppFont.bold(11)).padding(.horizontal, 8).padding(.vertical, 3)
                            .foregroundStyle(t.accent).background(t.accent.opacity(0.13), in: Capsule())
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r.title).font(AppFont.medium(14)).foregroundStyle(t.ink).lineLimit(2)
                            Text(r.sub).font(AppFont.caption).foregroundStyle(t.soft)
                        }
                        Spacer()
                        Text(Money.persianDigits(Money.format(r.amount)) + " ت").font(AppFont.bold(13)).foregroundStyle(t.ink)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppBackground())
        .navigationTitle("جستجو")
        .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { focused = true } }
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
                    }
                }
            }
        }
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
        }
    }

    @State private var personTarget: String?
}
