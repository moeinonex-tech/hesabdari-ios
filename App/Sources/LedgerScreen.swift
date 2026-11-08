import SwiftUI
import UIKit
import Charts
import UniformTypeIdentifiers
import HesabCore

struct LedgerRowLine: View {
    let row: LedgerRowVM
    let color: Color?
    var subtitle: String? = nil
    /// the transactions card: category / subcategory as coloured tags, pay method with its icon
    var detailed = false
    @Environment(\.theme) private var t

    var body: some View {
        if detailed { detailedBody } else { compactBody }
    }

    private var dot: Color { row.kind == .commission ? Color.purple : (row.kind == .tankhah ? t.success : (color ?? t.accent)) }

    private var detailedBody: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle().fill(dot).frame(width: 10, height: 10).padding(.top, 5)
            VStack(alignment: .leading, spacing: 4) {
                Text(row.desc.isEmpty ? "—" : row.desc).font(AppFont.medium(14)).foregroundStyle(t.ink).lineLimit(1)
                HStack(spacing: 5) {
                    if row.kind == .tankhah {
                        CategoryTag(text: "تنخواه", color: t.success)
                    } else {
                        if !row.category.isEmpty { CategoryTag(text: row.category, color: dot) }
                        if !row.subcategory.isEmpty { CategoryTag(text: row.subcategory, color: dot, light: true) }
                    }
                    if row.itemCount > 1 { InvoiceTag(count: row.itemCount) }
                }
                .lineLimit(1)
                HStack(spacing: 6) {
                    Text(row.date)
                    PayGlyph(method: row.payMethod)
                    if row.isLinked { Image(systemName: "link").font(.system(size: 10)) }
                }
                .font(AppFont.caption).foregroundStyle(t.soft).lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(Money.persianDigits(Money.format(row.toman)))
                .font(AppFont.bold(14))
                .foregroundStyle(row.kind == .tankhah ? t.success : t.ink)
                .padding(.top, 1)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    private var compactBody: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(row.kind == .commission ? Color.purple : (row.kind == .tankhah ? t.success : (color ?? t.accent)))
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.desc.isEmpty ? "—" : row.desc).font(AppFont.medium(14)).foregroundStyle(t.ink).lineLimit(1)
                HStack(spacing: 6) {
                    if let s = subtitle, !s.isEmpty { Text(s) }
                    if row.itemCount > 1 { InvoiceTag(count: row.itemCount) }
                    if !row.category.isEmpty { Text(row.category) }
                    Text(row.date)
                    if let p = payTitle(row.payMethod) { Text("· " + p) }
                    if row.kind == .tankhah { Text("تنخواه").foregroundStyle(t.success) }
                    if row.isLinked { Image(systemName: "link") }
                }
                .font(AppFont.caption)
                .foregroundStyle(t.soft)
                .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(Money.persianDigits(Money.format(row.toman)))
                .font(AppFont.bold(14))
                .foregroundStyle(row.kind == .tankhah ? t.success : t.ink)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}

// MARK: - ledger

enum LedgerSheet: Identifiable {
    case new, edit(LedgerRowVM), settle
    var id: String {
        switch self {
        case .new: return "new"
        case .edit(let r): return "edit-" + r.rowId
        case .settle: return "settle"
        }
    }
}

struct LedgerHomeView: View {
    @ObservedObject var model: AppModel
    @Binding var sheet: LedgerSheet?
    @Environment(\.theme) private var t
    @State private var selected: String?
    @State private var pendingLocked: (() -> Void)?
    @State private var budgetAccount: String?
    @State private var showManage = false
    @State private var showPartyReport = false
    @State private var showIncome = false
    @State private var incomeSheet: PersonalSheet?
    @State private var editingCards = false
    @State private var showPassword = false
    @State private var password = ""

    private var accountId: String? { model.activeAccountId }

    var body: some View {
        let account = model.accounts.first { $0.id == accountId }
        PageScrollView(tab: .ledger) {
            VStack(alignment: .leading, spacing: 16) {   // not Lazy: a lazy stack kept the old height after a page switch
                HStack(alignment: .top) {
                    ScreenHeader(title: "دفتر حساب", subtitle: account?.name ?? "")
                    // ledger management opens from the «+» next to the ledger names (one button per job)
                    if account != nil && !showIncome { DeckEditButton(editing: $editingCards).padding(.top, 8) }
                }

                HScroll {
                    HStack(spacing: 8) {
                        ForEach(model.accounts) { a in
                            let on = a.id == accountId
                            Button {
                                Haptics.tap()
                                model.selectAccount(a.id)
                            } label: {
                                Text(a.name)
                                    .font(AppFont.bold(14))
                                    .padding(.horizontal, 14).padding(.vertical, 8)
                                    .foregroundStyle(on ? t.onAccent : t.ink)
                                    .background(on ? t.accent : t.card.opacity(0.7), in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                        Button {
                            Haptics.tap()
                            showManage = true
                        } label: {
                            Image(systemName: "plus")
                                .font(AppFont.bold(14))
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .foregroundStyle(t.accent)
                                .background(t.card.opacity(0.7), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }

                if account != nil {
                    Segmented(selection: $showIncome.animation(.snappy), [(false, "هزینه و تنخواه"), (true, "درآمد این دفتر")])
                }

                if let a = account, showIncome {
                    ledgerIncome(a)
                }

                if let a = account, !showIncome {
                    CardDeck(page: "ledger", editing: $editingCards, cards: ledgerCards(a))
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .background(AppBackground())
        .scrollsToTopOnDockTap(.ledger)
        .pageSwipe(.ledger, $showIncome, [false, true], enabled: account != nil)
        .toolbar(.hidden, for: .navigationBar)
        .overlay(alignment: .bottom) { UndoBanner(model: model).padding(.bottom, AppShell.dockClearance) }
        .sheet(item: Binding(get: { budgetAccount.map { IdBox(id: $0) } }, set: { budgetAccount = $0?.id })) { b in
            NavigationStack {
                BudgetEditor(title: "بودجه‌ی دفتر", current: model.budget(accountId: b.id)) { _ = model.setAccountBudget(b.id, $0) }
            }
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $showManage) {
            Themed {
                NavigationStack {
                    AccountManageView(model: model, accountId: accountId) { id in model.selectAccount(id) }
                }
            }
        }
        .sheet(isPresented: $showPartyReport) {
            Themed { NavigationStack { if let id = accountId { TankhahPartyReportView(model: model, accountId: id) } } }
        }
        .sheet(item: $incomeSheet) { s in
            Themed {
                NavigationStack {
                    switch s {
                    case .editIncome(let r): IncomeFormView(model: model, editing: r)
                    default: IncomeFormView(model: model, editing: nil, presetLink: accountId)
                    }
                }
            }
        }
        .onChange(of: model.accounts.map(\.id)) { _, ids in
            _ = ids
        }
        .sheet(item: $sheet) { s in
            Themed {
                NavigationStack {
                    if let id = accountId {
                        switch s {
                        case .new: ExpenseFormView(model: model, accountId: id, editing: nil)
                        case .edit(let r): ExpenseFormView(model: model, accountId: id, editing: r)
                        case .settle: SettleView(model: model, accountId: id)
                        }
                    }
                }
            }
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
    }

    @ViewBuilder
    private func ledgerIncome(_ a: AccountImportSummary) -> some View {
        let rows = model.ledgerIncomeRows(a.id)
        let total = rows.reduce(0) { $0 + $1.toman }
        VStack(alignment: .leading, spacing: 10) {
            Text("جمع درآمدهای این دفتر").font(AppFont.regular(13)).foregroundStyle(t.soft)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                FxNumber(total) { Money.persianDigits(Money.format($0)) }.font(AppFont.heavy(30))
                    .foregroundStyle(t.success).contentTransition(.numericText())
                Text("تومان").font(AppFont.regular(13)).foregroundStyle(t.soft)
            }
            Button {
                incomeSheet = .newIncome
            } label: {
                Label("ثبت درآمد برای این دفتر", systemImage: "plus")
                    .font(AppFont.bold(15)).frame(maxWidth: .infinity).padding(.vertical, 4)
            }
            .buttonStyle(.glassProminent)
        }
        .glassCard()
        if rows.isEmpty {
            VStack(spacing: 4) {
                Text("هنوز درآمدی برای این حساب ثبت نشده").font(AppFont.regular(14))
                Text("اولین درآمدِ این حساب رو با دکمه‌ی بالا ثبت کن").font(AppFont.caption)
            }
            .foregroundStyle(t.soft).frame(maxWidth: .infinity).padding(30)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(rows) { r in
                    SimpleRowLine(row: r, income: true, color: model.categoryColor(r.category))
                        .contentShape(Rectangle())
                        .onTapGesture { openIncome(r) }
                        .contextMenu {
                            Button { openIncome(r) } label: { Label("ویرایش", systemImage: "pencil") }
                            Button(role: .destructive) {
                                if r.isCommission { model.errorMessage = LedgerError.commissionIncome.message }
                                else if model.deleteIncome(r.rowId) { Haptics.warning() }
                            } label: { Label("حذف", systemImage: "trash") }
                        }
                    if r.id != rows.last?.id { Divider().opacity(0.5) }
                }
            }
            .glassCard()
        }
    }

    private func openIncome(_ r: SimpleRowVM) {
        if r.isCommission { model.errorMessage = LedgerError.commissionIncome.message; return }
        incomeSheet = .editIncome(r)
    }

    /// the expense side of a ledger as movable / removable cards
    private func ledgerCards(_ a: AccountImportSummary) -> [DeckCard] {
        var cards: [DeckCard] = []
        cards.append(DeckCard("hero", "جمع هزینه‌ها و ثبت", "sum") {
            // commission rows of this ledger (the automatic payments, and any row filed under «کمیسیون»)
            let commission = model.rows(accountId: a.id)
                .filter { $0.kind == .commission || ($0.kind == .expense && $0.category.trimmingCharacters(in: .whitespaces) == "کمیسیون") }
                .reduce(0) { $0 + $1.toman }
            LedgerHero(account: a, budget: model.budget(accountId: a.id), commission: commission, onBudget: { budgetAccount = a.id }) { sheet = .new }
        })
        if a.commissionEnabled || a.percent != 0 {
            cards.append(DeckCard("commission", "کمیسیون", "percent") {
                CommissionCard(account: a, pdf: { await model.commissionPDF(accountId: a.id) }) { sheet = .settle }
            })
        }
        if model.hasTankhah(a.id) {
            cards.append(DeckCard("tankhah", "تنخواه به تفکیک طرف حساب", "person.2") {
                HStack(spacing: 8) {
                    Button {
                        Haptics.tap()
                        showPartyReport = true
                    } label: {
                        Label("تنخواه به تفکیک طرف حساب", systemImage: "person.2.fill")
                            .font(AppFont.bold(14)).frame(maxWidth: .infinity).padding(.vertical, 4)
                    }
                    .buttonStyle(.glass)
                    CardPDFButton { await model.tankhahPartyPDF(accountId: a.id) }
                }
            })
        }
        let items = model.statItems("expenses", accountId: a.id)
        let slices = model.breakdown(items, kind: .expense)
        let subs = model.breakdown(items, kind: .expense, sub: true)
        let colors = model.colorMap(slices)
        if !slices.isEmpty {
            cards.append(DeckCard("categories", "تفکیک دسته‌ها", "chart.pie") { CategoryChartCard(slices: slices, subs: subs, model: model, scope: a.name, items: items) })
        }
        if !subs.isEmpty {
            cards.append(DeckCard("subcategories", "تفکیک زیردسته‌ها", "chart.bar") { SubcategoryChartCard(slices: subs, model: model, scope: a.name, items: items) })
        }
        // every row, newest first; 5 visible, the rest scroll inside the card or unfold
        let all = Array(model.rows(accountId: a.id).reversed())
        cards.append(DeckCard("transactions", "تراکنش‌ها", "list.bullet.rectangle") {
            RowsCard(title: "تراکنش‌ها", total: Fmt.count(all.count) + " ردیف", rows: all, date: \.dateValue,
                     amount: { $0.kind == .tankhah ? 0 : $0.toman }, empty: "هنوز تراکنشی ثبت نشده",
                     export: { await model.ledgerPDF(accountId: a.id, range: nil, withBudget: false) }) { r in
                ledgerRow(r, colors)
            }
        })
        return cards
    }

    private func ledgerRow(_ r: LedgerRowVM, _ colors: [String: Color]) -> some View {
        LedgerRowLine(row: r, color: colors[r.category] ?? model.categoryColor(r.category), detailed: true)
            .onTapGesture { guarded(r) { sheet = .edit(r) } }
            .contextMenu {
                Button { guarded(r) { sheet = .edit(r) } } label: { Label("ویرایش", systemImage: "pencil") }
                Button(role: .destructive) {
                    guarded(r) { if model.delete(rowId: r.rowId) { Haptics.warning() } }
                } label: { Label("حذف", systemImage: "trash") }
            }
    }

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

struct LedgerHero: View {
    let account: AccountImportSummary
    let budget: Int
    /// commission paid out of this ledger (its commission rows); > 0 shows the net total next to the gross one
    var commission: Int = 0
    var onBudget: (() -> Void)? = nil
    let onAdd: () -> Void
    @Environment(\.theme) private var t

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("جمع هزینه‌ها").font(AppFont.regular(13)).foregroundStyle(t.soft)
                Spacer()
                if let onBudget {
                    Button(action: onBudget) {
                        Label(budget > 0 ? "بودجه" : "تنظیم بودجه", systemImage: "target").font(AppFont.caption)
                    }
                    .buttonStyle(.glass)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                FxNumber(account.expenseTotal) { Money.persianDigits(Money.format($0)) }
                    .font(AppFont.heavy(30))
                    .foregroundStyle(t.accent)
                    .contentTransition(.numericText())
                Text("تومان").font(AppFont.regular(13)).foregroundStyle(t.soft)
            }
            // secondary figures under the headline total: net of commission, and the commission itself
            if commission > 0 {
                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("خالص هزینه‌ها (بدون کمیسیون)").font(AppFont.caption).foregroundStyle(t.soft)
                        FxNumber(account.expenseTotal - commission, Fmt.toman).font(AppFont.bold(16)).foregroundStyle(t.ink)
                            .contentTransition(.numericText())
                    }
                    Spacer(minLength: 12)
                    Rectangle().fill(t.ink.opacity(0.12)).frame(width: 1, height: 30)
                    Spacer(minLength: 12)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("کمیسیون پرداخت‌شده").font(AppFont.caption).foregroundStyle(t.soft)
                        Text(Fmt.toman(commission)).font(AppFont.medium(14)).foregroundStyle(t.soft)
                    }
                }
                .lineLimit(1).minimumScaleFactor(0.8)
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(t.ink.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            if budget > 0 {
                let pct = min(1, Double(account.expenseTotal) / Double(budget))
                GradientBar(value: pct, from: t.accent, to: pct >= 0.8 ? t.warning : t.accent2)
                Text("\(Money.persianDigits(Money.jsRound(pct * 100)))٪ از بودجه · مانده " + Fmt.toman(max(0, budget - account.expenseTotal)))
                    .font(AppFont.caption).foregroundStyle(t.soft)
            }
            HStack(spacing: 14) {
                Label(Fmt.count(account.rows) + " ردیف", systemImage: "list.bullet").font(AppFont.caption)
                if account.tankhahTotal != 0 {
                    Label("تنخواه " + Fmt.toman(account.tankhahTotal), systemImage: "arrow.down.circle").font(AppFont.caption)
                }
            }
            .foregroundStyle(t.soft)
            Button(action: onAdd) {
                Label("ثبت هزینه یا تنخواه", systemImage: "plus")
                    .font(AppFont.bold(15))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.glassProminent)
        }
        .glassCard()
    }
}

struct CommissionCard: View {
    let account: AccountImportSummary
    var pdf: (() async -> ExportFile?)? = nil
    let onSettle: () -> Void
    @Environment(\.theme) private var t

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("کمیسیون " + Fmt.percent(account.percent)).font(AppFont.bold(15)).foregroundStyle(t.ink)
                Spacer()
                Text("پرداخت‌شده " + Fmt.toman(account.settled)).font(AppFont.caption).foregroundStyle(t.soft)
                if let pdf { CardPDFButton(make: pdf) }
            }
            Text(account.remaining < 0 ? "بستانکاری" : "مانده‌ی کمیسیون").font(AppFont.regular(13)).foregroundStyle(t.soft)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(Money.persianDigits(Money.format(abs(account.remaining))))
                    .font(AppFont.heavy(28))
                    .foregroundStyle(account.remaining < 0 ? t.success : t.accent2)
                    .contentTransition(.numericText())
                Text("تومان").font(AppFont.regular(13)).foregroundStyle(t.soft)
            }
            if account.balance != 0 {
                Text((account.balance > 0 ? "شامل بدهی قبلی " : "با کسر بستانکاری قبلی ") + Fmt.toman(account.balance))
                    .font(AppFont.caption).foregroundStyle(t.soft)
            }
            Button(action: onSettle) {
                Label("پرداخت کمیسیون", systemImage: "banknote")
                    .font(AppFont.bold(15))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.glass)
        }
        .glassCard()
    }
}

struct GradientBar: View {
    let value: Double
    let from: Color
    let to: Color
    @Environment(\.theme) private var t

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(t.soft.opacity(0.18))
                Capsule()
                    .fill(LinearGradient(colors: [from, to], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(6, g.size.width * value))
            }
        }
        .frame(height: 7)
    }
}
