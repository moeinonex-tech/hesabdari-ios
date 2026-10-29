import SwiftUI
import UIKit
import Charts
import UniformTypeIdentifiers
import HesabCore

// MARK: - theming wrapper (also used inside sheets)

struct Themed<Content: View>: View {
    @AppStorage("palette") private var paletteRaw = Palette.web.rawValue
    @ViewBuilder let content: Content

    var body: some View {
        ThemeHost(palette: Palette(rawValue: paletteRaw) ?? .web) { content }
            .environment(\.layoutDirection, .rightToLeft)
            .environment(\.locale, Locale(identifier: "fa_IR"))
            .environment(\.font, AppFont.body)
    }
}

enum AppTab: Hashable { case home, ledger, cards, settings }

// MARK: - root

struct RootView: View {
    @ObservedObject var model: AppModel
    @AppStorage("appearance") private var appearanceRaw = Appearance.system.rawValue
    @State private var showImporter = false
    @State private var exportFile: ExportFile?
    @State private var tab: AppTab = .home
    @State private var ledgerSheet: LedgerSheet?

    var body: some View {
        Themed {
            Group {
                if model.hasData {
                    TabView(selection: $tab) {
                        Tab("خانه", systemImage: "house.fill", value: AppTab.home) {
                            NavigationStack { HomeView(model: model, tab: $tab, ledgerSheet: $ledgerSheet, exportFile: $exportFile) }
                        }
                        Tab("دفتر حساب", systemImage: "book.pages.fill", value: AppTab.ledger) {
                            NavigationStack { LedgerHomeView(model: model, sheet: $ledgerSheet) }
                        }
                        Tab("کیف کارت", systemImage: "creditcard.fill", value: AppTab.cards) {
                            NavigationStack { CardsView(model: model) }
                        }
                        Tab("تنظیمات", systemImage: "gearshape.fill", value: AppTab.settings) {
                            NavigationStack { SettingsView(model: model, showImporter: $showImporter, exportFile: $exportFile) }
                        }
                    }
                } else {
                    WelcomeView(showImporter: $showImporter)
                }
            }
        }
        .preferredColorScheme(Appearance(rawValue: appearanceRaw)?.scheme)
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json, .plainText, .data]) { result in
            switch result {
            case .success(let url): model.openFile(url)
            case .failure(let error): model.errorMessage = error.localizedDescription
            }
        }
        .sheet(isPresented: Binding(get: { model.pending != nil }, set: { if !$0 { model.pending = nil } })) {
            if let report = model.pending {
                Themed {
                    NavigationStack {
                        ImportReportView(report: report, replacesExisting: model.hasData,
                                         onConfirm: { model.confirmImport(); Haptics.success() },
                                         onCancel: { model.pending = nil })
                    }
                }
            }
        }
        .sheet(item: $exportFile) { file in
            ActivityView(items: [file.url])
        }
        .alert("پیام", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("باشه", role: .cancel) { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}

// MARK: - welcome

struct WelcomeView: View {
    @Binding var showImporter: Bool
    @Environment(\.theme) private var t

    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 22) {
                Spacer()
                Image(systemName: "book.pages.fill")
                    .font(.system(size: 60, weight: .medium))
                    .foregroundStyle(LinearGradient(colors: [t.accent, t.accent2], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .padding(26)
                    .glassEffect(.regular, in: Circle())
                Text("دفتر حساب").font(AppFont.heavy(34)).foregroundStyle(t.ink)
                Text("برای شروع، فایل «پشتیبان کامل» اپ وب را انتخاب کنید. قبل از ورود، گزارش کامل آن را می‌بینید و تا تأیید نکنید چیزی ذخیره نمی‌شود.")
                    .font(AppFont.regular(15))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(t.soft)
                    .padding(.horizontal, 34)
                Button {
                    showImporter = true
                } label: {
                    Label("انتخاب فایل پشتیبان", systemImage: "doc.badge.plus")
                        .font(AppFont.bold(17))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.glassProminent)
                .padding(.horizontal, 34)
                Spacer()
                Spacer()
            }
        }
    }
}

// MARK: - home

struct HomeView: View {
    @ObservedObject var model: AppModel
    @Binding var tab: AppTab
    @Binding var ledgerSheet: LedgerSheet?
    @Binding var exportFile: ExportFile?
    @Environment(\.theme) private var t
    @State private var appeared = false

    var body: some View {
        let greet = AppModel.greeting(hour: Calendar.current.component(.hour, from: Date()))
        let today = model.todayTitle
        let attention = model.attentionItems
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ScreenHeader(title: "خانه", subtitle: "نمای کلی و امروز")

                HStack(spacing: 8) {
                    Image(systemName: greet.icon).foregroundStyle(t.accent).symbolEffect(.pulse, options: .repeating)
                    Text(greet.text + "، " + AppModel.ownerName).font(AppFont.bold(19)).foregroundStyle(t.ink)
                }

                // date
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(today.weekday).font(AppFont.heavy(22)).foregroundStyle(t.ink)
                        Text(today.date).font(AppFont.regular(14)).foregroundStyle(t.soft)
                    }
                    Spacer()
                    Image(systemName: "calendar")
                        .font(.title2)
                        .foregroundStyle(t.accent)
                        .frame(width: 52, height: 52)
                        .background(t.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .glassCard()

                if !attention.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionTitle(text: "نیازمند توجه")
                        ForEach(attention) { item in
                            AttentionRow(item: item)
                        }
                    }
                    .glassCard()
                }

                // ledgers summary
                VStack(alignment: .leading, spacing: 12) {
                    SectionTitle(text: "دفترها")
                    ForEach(model.accounts) { a in
                        Button {
                            Haptics.tap()
                            tab = .ledger
                        } label: {
                            AccountMiniCard(account: a, budget: model.budget(accountId: a.id))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .glassCard()

                // shortcuts
                VStack(alignment: .leading, spacing: 12) {
                    SectionTitle(text: "میانبرها")
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                        ShortcutTile(title: "ثبت هزینه", icon: "plus.circle.fill") { tab = .ledger; ledgerSheet = .new }
                        ShortcutTile(title: "پرداخت کمیسیون", icon: "banknote.fill") { tab = .ledger; ledgerSheet = .settle }
                        ShortcutTile(title: "کیف کارت", icon: "creditcard.fill") { tab = .cards }
                        ShortcutTile(title: "خروجی پشتیبان", icon: "square.and.arrow.up.fill") { exportFile = model.makeExportFile() }
                        ShortcutTile(title: "تنظیمات", icon: "paintpalette.fill") { tab = .settings }
                    }
                }
                .glassCard()

                // recent activity
                let recent = model.recentRows
                if !recent.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionTitle(text: "فعالیت اخیر")
                        ForEach(recent) { item in
                            LedgerRowLine(row: item.row, color: model.categoryColor(item.row.category), subtitle: item.account)
                        }
                    }
                    .glassCard()
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 14)
        }
        .background(AppBackground())
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { withAnimation(.spring(duration: 0.55)) { appeared = true } }
    }
}

struct AttentionRow: View {
    let item: AttentionItem
    @Environment(\.theme) private var t

    var body: some View {
        let color: Color = item.level == .danger ? t.danger : (item.level == .warning ? t.warning : t.accent)
        HStack(spacing: 10) {
            Image(systemName: item.icon).foregroundStyle(color)
            Text(item.text).font(AppFont.medium(14)).foregroundStyle(t.ink)
            Spacer()
        }
        .padding(12)
        .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 3).padding(.vertical, 8)
        }
    }
}

struct AccountMiniCard: View {
    let account: AccountImportSummary
    let budget: Int
    @Environment(\.theme) private var t

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(account.name).font(AppFont.bold(16)).foregroundStyle(t.ink)
                Spacer()
                Image(systemName: "chevron.left").font(.caption).foregroundStyle(t.soft)
            }
            Text(Fmt.toman(account.expenseTotal)).font(AppFont.heavy(20)).foregroundStyle(t.accent)
            if budget > 0 {
                let pct = min(1, Double(account.expenseTotal) / Double(budget))
                ProgressView(value: pct)
                    .tint(pct >= 0.8 ? t.warning : t.accent2)
                Text("\(Money.persianDigits(Money.jsRound(pct * 100)))٪ از بودجه‌ی " + Fmt.toman(budget))
                    .font(AppFont.caption).foregroundStyle(t.soft)
            }
            if account.commissionEnabled || account.percent != 0 {
                Text("مانده‌ی کمیسیون: " + Fmt.balance(account.remaining))
                    .font(AppFont.medium(13)).foregroundStyle(t.ink)
            }
        }
        .padding(12)
        .background(t.accent.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct ShortcutTile: View {
    let title: String
    let icon: String
    let action: () -> Void
    @Environment(\.theme) private var t

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            VStack(spacing: 8) {
                Image(systemName: icon).font(.title2).foregroundStyle(t.accent)
                Text(title).font(AppFont.medium(12)).foregroundStyle(t.ink).lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 78)
            .background(t.card.opacity(0.7), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct LedgerRowLine: View {
    let row: LedgerRowVM
    let color: Color?
    var subtitle: String? = nil
    @Environment(\.theme) private var t

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(row.kind == .commission ? Color.purple : (row.kind == .tankhah ? t.success : (color ?? t.accent)))
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.desc.isEmpty ? "—" : row.desc).font(AppFont.medium(14)).foregroundStyle(t.ink).lineLimit(2)
                HStack(spacing: 6) {
                    if let s = subtitle, !s.isEmpty { Text(s) }
                    if !row.category.isEmpty { Text(row.category) }
                    Text(row.date)
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
    @State private var showPassword = false
    @State private var password = ""

    private var accountId: String? { selected ?? model.activeAccountId }

    var body: some View {
        let account = model.accounts.first { $0.id == accountId }
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16, pinnedViews: []) {
                ScreenHeader(title: "دفتر حساب", subtitle: account?.name ?? "")

                if model.accounts.count > 1 {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(model.accounts) { a in
                                let on = a.id == accountId
                                Button {
                                    Haptics.tap()
                                    withAnimation(.snappy) { selected = a.id }
                                } label: {
                                    Text(a.name)
                                        .font(AppFont.bold(14))
                                        .padding(.horizontal, 14).padding(.vertical, 8)
                                        .foregroundStyle(on ? t.onAccent : t.ink)
                                        .background(on ? t.accent : t.card.opacity(0.7), in: Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                if let a = account {
                    LedgerHero(account: a, budget: model.budget(accountId: a.id)) { sheet = .new }
                    if a.commissionEnabled || a.percent != 0 {
                        CommissionCard(account: a) { sheet = .settle }
                    }
                    let slices = model.categoryBreakdown(accountId: a.id)
                    if !slices.isEmpty { CategoryChartCard(slices: slices) }

                    ForEach(model.monthGroups(accountId: a.id)) { g in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(g.title).font(AppFont.bold(15)).foregroundStyle(t.ink)
                                Spacer()
                                Text(Fmt.toman(g.total)).font(AppFont.medium(13)).foregroundStyle(t.soft)
                            }
                            .padding(.bottom, 4)
                            ForEach(g.rows) { r in
                                LedgerRowLine(row: r, color: model.categoryColor(r.category))
                                    .onTapGesture { guarded(r) { sheet = .edit(r) } }
                                    .contextMenu {
                                        Button { guarded(r) { sheet = .edit(r) } } label: { Label("ویرایش", systemImage: "pencil") }
                                        Button(role: .destructive) {
                                            guarded(r) { if model.delete(rowId: r.rowId) { Haptics.warning() } }
                                        } label: { Label("حذف", systemImage: "trash") }
                                    }
                                if r.id != g.rows.last?.id { Divider().opacity(0.5) }
                            }
                        }
                        .glassCard()
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 90)
        }
        .background(AppBackground())
        .toolbar(.hidden, for: .navigationBar)
        .overlay(alignment: .bottom) { UndoBanner(model: model).padding(.bottom, 8) }
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
    let onAdd: () -> Void
    @Environment(\.theme) private var t

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("جمع هزینه‌ها").font(AppFont.regular(13)).foregroundStyle(t.soft)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(Money.persianDigits(Money.format(account.expenseTotal)))
                    .font(AppFont.heavy(30))
                    .foregroundStyle(t.accent)
                    .contentTransition(.numericText())
                Text("تومان").font(AppFont.regular(13)).foregroundStyle(t.soft)
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
    let onSettle: () -> Void
    @Environment(\.theme) private var t

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("کمیسیون " + Fmt.percent(account.percent)).font(AppFont.bold(15)).foregroundStyle(t.ink)
                Spacer()
                Text("پرداخت‌شده " + Fmt.toman(account.settled)).font(AppFont.caption).foregroundStyle(t.soft)
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

struct CategoryChartCard: View {
    let slices: [CategorySlice]
    @Environment(\.theme) private var t

    var body: some View {
        let total = slices.reduce(0) { $0 + $1.total }
        let top = Array(slices.prefix(6))
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(text: "تفکیک دسته‌ها")
            HStack(spacing: 16) {
                Chart(slices) { s in
                    SectorMark(angle: .value("مبلغ", s.total), innerRadius: .ratio(0.62), angularInset: 1.5)
                        .cornerRadius(3)
                        .foregroundStyle(s.color)
                }
                .frame(width: 130, height: 130)
                .overlay {
                    VStack(spacing: 0) {
                        Text(Fmt.count(slices.count)).font(AppFont.heavy(20)).foregroundStyle(t.ink)
                        Text("دسته").font(AppFont.caption).foregroundStyle(t.soft)
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(top) { s in
                        HStack(spacing: 6) {
                            Circle().fill(s.color).frame(width: 8, height: 8)
                            Text(s.name).font(AppFont.regular(12)).foregroundStyle(t.ink).lineLimit(1)
                            Spacer(minLength: 4)
                            Text(Money.persianDigits(total > 0 ? Money.jsRound(Double(s.total) / Double(total) * 100) : 0) + "٪")
                                .font(AppFont.bold(12)).foregroundStyle(t.soft)
                        }
                    }
                }
            }
        }
        .glassCard()
    }
}

// MARK: - cards

struct CardsView: View {
    @ObservedObject var model: AppModel
    @State private var showArchived = false
    @Environment(\.theme) private var t

    var body: some View {
        let cards = model.walletCards.filter { $0.archived == showArchived }
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ScreenHeader(title: "کیف کارت", subtitle: "برای کپی شماره، روی آن بزنید")
                Picker("", selection: $showArchived) {
                    Text("کارت‌های فعال").tag(false)
                    Text("بایگانی‌شده").tag(true)
                }
                .pickerStyle(.segmented)
                if cards.isEmpty {
                    Text("کارتی نیست").font(AppFont.regular(14)).foregroundStyle(t.soft).frame(maxWidth: .infinity).padding(40)
                }
                ForEach(cards) { c in
                    BankCardView(card: c)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(AppBackground())
        .toolbar(.hidden, for: .navigationBar)
    }
}

struct BankCardView: View {
    let card: WalletCard
    @State private var copied: String?

    var body: some View {
        ZStack(alignment: .topLeading) {
            background
            LinearGradient(colors: [.black.opacity(0.05), .black.opacity(0.45)], startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(card.bankName).font(AppFont.heavy(18))
                    Spacer()
                    if !card.accountType.isEmpty { Text(card.accountType).font(AppFont.medium(12)).opacity(0.85) }
                }
                Spacer()
                Button {
                    copy(card.number, label: "شماره کارت")
                } label: {
                    Text(Money.persianDigits(grouped(card.number)))
                        .font(AppFont.bold(22))
                        .environment(\.layoutDirection, .leftToRight)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .buttonStyle(.plain)
                if !card.iban.isEmpty {
                    Button { copy(card.iban, label: "شبا") } label: {
                        Text(Money.persianDigits(card.iban)).font(AppFont.regular(12)).opacity(0.9)
                            .environment(\.layoutDirection, .leftToRight)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .buttonStyle(.plain)
                }
                HStack {
                    Text(card.holder).font(AppFont.medium(13))
                    Spacer()
                    if !card.expiry.isEmpty { Text(Money.persianDigits(card.expiry)).font(AppFont.medium(13)) }
                }
            }
            .foregroundStyle(.white)
            .padding(18)
            if let c = copied {
                Text(c + " کپی شد")
                    .font(AppFont.bold(13))
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .glassEffect(.regular, in: Capsule())
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .aspectRatio(1.586, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(0.25), radius: 14, y: 8)
    }

    @ViewBuilder private var background: some View {
        if let img = card.image {
            Image(uiImage: img).resizable().scaledToFill()
        } else {
            LinearGradient(colors: [card.color ?? Color.hex(0x1F3A5F), (card.color ?? Color.hex(0x1F3A5F)).opacity(0.6)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    private func grouped(_ s: String) -> String {
        let digits = s.filter(\.isNumber)
        guard digits.count == 16 else { return s }
        var out = ""
        for (i, ch) in digits.enumerated() {
            if i > 0 && i % 4 == 0 { out.append(" ") }
            out.append(ch)
        }
        return out
    }

    private func copy(_ text: String, label: String) {
        UIPasteboard.general.string = text.filter { !$0.isWhitespace }
        Haptics.success()
        withAnimation(.spring) { copied = label }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { withAnimation { copied = nil } }
    }
}

// MARK: - settings

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @Binding var showImporter: Bool
    @Binding var exportFile: ExportFile?
    @AppStorage("palette") private var paletteRaw = Palette.web.rawValue
    @AppStorage("appearance") private var appearanceRaw = Appearance.system.rawValue
    @Environment(\.colorScheme) private var scheme
    @Environment(\.theme) private var t

    var body: some View {
        Form {
            Section {
                ForEach(Palette.allCases) { p in
                    let c = p.colors(scheme)
                    Button {
                        Haptics.tap()
                        withAnimation(.smooth) { paletteRaw = p.rawValue }
                    } label: {
                        HStack(spacing: 12) {
                            HStack(spacing: -6) {
                                Circle().fill(c.accent).frame(width: 26, height: 26)
                                Circle().fill(c.accent2).frame(width: 26, height: 26)
                                    .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 2))
                            }
                            Text(p.title).font(AppFont.medium(15)).foregroundStyle(t.ink)
                            Spacer()
                            if paletteRaw == p.rawValue {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(c.accent)
                            }
                        }
                    }
                }
            } header: {
                Text("رنگ اصلی").font(AppFont.medium(13))
            }

            Section {
                Picker("حالت نمایش", selection: $appearanceRaw) {
                    ForEach(Appearance.allCases) { a in Text(a.title).tag(a.rawValue) }
                }
            } header: {
                Text("روشن و تیره").font(AppFont.medium(13))
            }

            Section {
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
            } header: {
                Text("داده‌ها").font(AppFont.medium(13))
            } footer: {
                Text(model.lastImportText ?? "").font(AppFont.caption)
            }

            Section {
                LabeledContent("نسخه", value: Money.persianDigits(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""))
                LabeledContent("شماره‌ی ساخت", value: Money.persianDigits(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""))
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppBackground())
        .navigationTitle("تنظیمات")
    }
}
