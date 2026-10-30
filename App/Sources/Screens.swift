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

enum AppTab: Hashable { case home, ledger, personal, reminders, cards, search }

// MARK: - root

struct RootView: View {
    @ObservedObject var model: AppModel
    @AppStorage("appearance") private var appearanceRaw = Appearance.system.rawValue
    @State private var showImporter = false
    @State private var exportFile: ExportFile?
    @State private var tab: AppTab = .home
    @State private var ledgerSheet: LedgerSheet?
    @StateObject private var lock = AppLock()
    @Environment(\.scenePhase) private var phase

    var body: some View {
        Themed {
            Group {
                if model.hasData {
                    TabView(selection: $tab) {
                        Tab("خانه", systemImage: "house.fill", value: AppTab.home) {
                            NavigationStack {
                                HomeView(model: model, tab: $tab, ledgerSheet: $ledgerSheet, exportFile: $exportFile, showImporter: $showImporter)
                            }
                            .pageEnter(tab == .home)
                        }
                        Tab("دفتر حساب", systemImage: "book.pages.fill", value: AppTab.ledger) {
                            NavigationStack { LedgerHomeView(model: model, sheet: $ledgerSheet) }.pageEnter(tab == .ledger)
                        }
                        Tab("شخصی", systemImage: "person.crop.circle.fill", value: AppTab.personal) {
                            NavigationStack { PersonalView(model: model) }.pageEnter(tab == .personal)
                        }
                        Tab("یادآوری‌ها", systemImage: "bell.fill", value: AppTab.reminders) {
                            NavigationStack { RemindersView(model: model) }.pageEnter(tab == .reminders)
                        }
                        Tab("کیف کارت", systemImage: "creditcard.fill", value: AppTab.cards) {
                            NavigationStack { CardsView(model: model) }.pageEnter(tab == .cards)
                        }
                        Tab("جستجو", systemImage: "magnifyingglass", value: AppTab.search, role: .search) {
                            NavigationStack { SearchView(model: model) }.pageEnter(tab == .search)
                        }
                    }
                } else {
                    WelcomeView(showImporter: $showImporter)
                }
            }
            .overlay {
                if model.hasData && lock.locked {
                    LockScreen(lock: lock).transition(.opacity)
                } else if phase != .active {
                    PrivacyCover()
                }
            }
        }
        .onChange(of: phase) { _, p in
            if p == .background { lock.didEnterBackground() }
            if p == .active { lock.didBecomeActive(); model.backupToday(); if model.hasData { Notifier.sync(model.state) } }
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
    @Binding var showImporter: Bool
    @Environment(\.theme) private var t
    @State private var appeared = false
    @State private var showSettings = false
    @State private var showReports = false
    @State private var showShortcutEditor = false
    @State private var showAppointment = false
    @State private var editingWidgets = false
    @State private var draggingWidget = false

    private func widgetVisibility() -> [String: Bool] {
        Dictionary(uniqueKeysWithValues: SettingsOps.widgetKeys.map { ($0, SettingsOps.widgetVisible(model.state, $0)) })
    }

    private func go(_ k: String) {
        Haptics.tap()
        switch k {
        case "ledger": tab = .ledger
        case "personal", "income": tab = .personal
        case "cards": tab = .cards
        case "reminders": tab = .reminders
        case "reports": showReports = true
        case "appointments": showAppointment = true
        default: break
        }
    }

    var body: some View {
        let greet = AppModel.greeting(hour: Calendar.current.component(.hour, from: Date()))
        let order = SettingsOps.widgetOrder(model.state).filter { SettingsOps.widgetVisible(model.state, $0) }
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    ScreenHeader(title: "خانه", subtitle: "نمای کلی و امروز")
                    HStack(spacing: 8) {
                        Button {
                            Haptics.tap()
                            showReports = true
                        } label: {
                            Image(systemName: "chart.bar.xaxis").font(.title3).padding(10)
                        }
                        .buttonStyle(.glass)
                        Button {
                            Haptics.tap()
                            showSettings = true
                        } label: {
                            Image(systemName: "gearshape.fill").font(.title3).padding(10)
                        }
                        .buttonStyle(.glass)
                    }
                    .padding(.top, 8)
                }

                HStack(spacing: 8) {
                    Image(systemName: greet.icon).foregroundStyle(t.accent).symbolEffect(.pulse, options: .repeating)
                    Text(greet.text + "، " + AppModel.ownerName).font(AppFont.bold(19)).foregroundStyle(t.ink)
                }

                if let q = SettingsOps.quoteOfNow(model.state) {
                    QuoteCard(quote: q, typewriter: model.state["quoteTypewriterEnabled"]?.boolValue ?? true, msPerChar: SettingsOps.typewriterMs(model.state))
                }

                WidgetGrid(keys: order, editing: $editingWidgets,
                           onTap: { key, point, size in tapWidget(key, point, size) },
                           onReorder: { newOrder in
                               let all = SettingsOps.widgetOrder(model.state)
                               model.setWidgets(order: newOrder + all.filter { !newOrder.contains($0) }, visible: widgetVisibility())
                           },
                           onRemove: { key in
                               var v = widgetVisibility(); v[key] = false
                               withAnimation(.spring) { model.setWidgets(order: SettingsOps.widgetOrder(model.state), visible: v) }
                           },
                           onConfigure: { key in if key == "shortcuts" { showShortcutEditor = true } },
                           onDragging: { draggingWidget = $0 }) { key, size, frame in
                    WidgetCard(size: frame) { widget(key, size, inner(frame)) }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 14)
            .padding(.top, editingWidgets ? 8 : 0)
            .background {
                if editingWidgets {
                    Color.clear.contentShape(Rectangle())
                        .onTapGesture { withAnimation(.spring) { editingWidgets = false } }
                }
            }
        }
        .scrollDisabled(draggingWidget)
        .background(AppBackground())
        .safeAreaInset(edge: .top, spacing: 0) {
            if editingWidgets {
                WidgetEditBar(hidden: SettingsOps.widgetKeys.filter { !SettingsOps.widgetVisible(model.state, $0) },
                              onAdd: { key in
                                  var v = widgetVisibility(); v[key] = true
                                  withAnimation(.spring) { model.setWidgets(order: SettingsOps.widgetOrder(model.state), visible: v) }
                              },
                              onDone: {
                                  Haptics.tap()
                                  withAnimation(.spring) { editingWidgets = false }
                              })
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .onDisappear { editingWidgets = false }
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(isPresented: $showSettings) {
            SettingsView(model: model, showImporter: $showImporter, exportFile: $exportFile)
        }
        .navigationDestination(isPresented: $showReports) {
            ReportsView(model: model)
        }
        .onAppear { withAnimation(.spring(duration: 0.55)) { appeared = true } }
        .sheet(isPresented: $showShortcutEditor) { NavigationStack { ShortcutsEditorView(model: model) } }
        .sheet(isPresented: $showAppointment) { Themed { NavigationStack { AppointmentFormView(model: model, editingId: nil) } } }
    }

    // MARK: widgets — each size has a fixed design; row counts come from fixed row heights, so nothing overflows

    private func inner(_ frame: CGSize) -> CGSize {
        CGSize(width: max(0, frame.width - WidgetCard<EmptyView>.padding * 2), height: max(0, frame.height - WidgetCard<EmptyView>.padding * 2))
    }
    private static let titleH: CGFloat = 26
    /// how many rows of height `rowH` (with `spacing`) fit under the title
    private func fit(_ inner: CGSize, rowH: CGFloat, spacing: CGFloat = 6) -> Int {
        max(1, Int((inner.height - Self.titleH - 6 + spacing) / (rowH + spacing)))
    }
    private func shortcutTiles(_ s: WidgetSize, _ inner: CGSize, count: Int) -> (WidgetLayout.Tiles, top: CGFloat) {
        let top: CGFloat = s == .small ? 0 : Self.titleH + 6
        return (WidgetLayout.tiles(count: count, width: Double(inner.width), height: Double(inner.height - top)), top)
    }

    private func tapWidget(_ key: String, _ point: CGPoint, _ frame: CGSize) {
        switch key {
        case "attention": tab = model.attentionItems.first?.id.hasPrefix("budget") == true ? .ledger : .reminders
        case "financial", "activity": tab = .ledger
        case "shortcuts":
            let keys = SettingsOps.homeShortcuts(model.state)
            guard !keys.isEmpty else { showShortcutEditor = true; return }
            let size = HomeWidgetPrefs.decode(UserDefaults.standard.string(forKey: HomeWidgetPrefs.key) ?? "{}")["shortcuts"]
                ?? HomeWidgetPrefs.defaults["shortcuts"]!
            let inn = inner(frame)
            let (t, top) = shortcutTiles(size, inn, count: keys.count)
            let p = WidgetCard<EmptyView>.padding
            if let i = WidgetLayout.tileIndex(at: Double(point.x - p), Double(point.y - p - top), count: keys.count, t,
                                               areaWidth: Double(inn.width), rtl: true) {
                go(keys[i])
            }
        default: break
        }
    }

    private func widgetTitle(_ text: String, _ s: WidgetSize) -> some View {
        Text(text).font(AppFont.bold(s == .small ? 13 : 15)).foregroundStyle(t.ink).lineLimit(1)
            .frame(height: Self.titleH, alignment: .center)
    }

    @ViewBuilder
    private func widget(_ key: String, _ s: WidgetSize, _ inn: CGSize) -> some View {
        switch key {
        case "date": dateWidget(s, inn)
        case "attention": attentionWidget(s, inn)
        case "financial": financialWidget(s, inn)
        case "shortcuts": shortcutsWidget(s, inn)
        case "activity": activityWidget(s, inn)
        default: EmptyView()
        }
    }

    // MARK: date widget — a calendar, not an empty box

    private static let weekLetters = ["ش", "ی", "د", "س", "چ", "پ", "ج"]

    /// Saturday-first weekday (0…6) of a Jalali date
    private func weekday(_ j: JalaliDate) -> Int {
        let g = Jalali.toGregorian(j)
        return Jalali.weekdaySat0(g.gy, g.gm, g.gd)
    }

    /// the big day-number tile used by every size
    private func dayTile(_ today: JalaliDate, side: CGFloat) -> some View {
        VStack(spacing: 0) {
            Text(BackupExporter.months[today.jm - 1])
                .font(AppFont.bold(max(10, side * 0.13)))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: side * 0.26)
                .background(LinearGradient(colors: [t.accent, t.accent2], startPoint: .leading, endPoint: .trailing))
            Text(Money.persianDigits(String(today.jd)))
                .font(AppFont.heavy(side * 0.46))
                .foregroundStyle(t.ink)
                .lineLimit(1).minimumScaleFactor(0.5)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: side, height: side)
        .background(t.card.opacity(0.85))
        .clipShape(RoundedRectangle(cornerRadius: side * 0.22, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
    }

    /// current week, Saturday → Friday, today highlighted
    private func weekStrip(_ today: JalaliDate, width: CGFloat) -> some View {
        let wd = weekday(today)
        let todayN = Jalali.j2d(today.jy, today.jm, today.jd)
        let cellW = width / 7
        return HStack(spacing: 0) {
            ForEach(0..<7, id: \.self) { i in
                let d = Jalali.d2j(todayN - wd + i)
                let isToday = i == wd
                VStack(spacing: 3) {
                    Text(Self.weekLetters[i]).font(AppFont.medium(11)).foregroundStyle(isToday ? .white.opacity(0.9) : t.soft)
                    Text(Money.persianDigits(String(d.jd))).font(AppFont.bold(15)).foregroundStyle(isToday ? .white : t.ink)
                }
                .frame(width: cellW - 4, height: 46)
                .background {
                    if isToday {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(LinearGradient(colors: [t.accent, t.accent2], startPoint: .top, endPoint: .bottom))
                    }
                }
                .frame(width: cellW)
            }
        }
    }

    /// whole current month, Saturday-first, today highlighted
    private func monthGrid(_ today: JalaliDate, width: CGFloat, height: CGFloat) -> some View {
        let first = JalaliDate(jy: today.jy, jm: today.jm, jd: 1)
        let lead = weekday(first)
        let len = Jalali.monthLength(today.jy, today.jm)
        let rows = Int(((Double(lead + len)) / 7).rounded(.up))
        let cellW = width / 7
        let cellH = min(cellW, (height - 22) / CGFloat(rows))
        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(0..<7, id: \.self) { i in
                    Text(Self.weekLetters[i]).font(AppFont.medium(11)).foregroundStyle(i == 6 ? t.danger : t.soft).frame(width: cellW, height: 22)
                }
            }
            ForEach(0..<rows, id: \.self) { r in
                HStack(spacing: 0) {
                    ForEach(0..<7, id: \.self) { c in
                        let day = r * 7 + c - lead + 1
                        ZStack {
                            if day == today.jd {
                                Circle().fill(LinearGradient(colors: [t.accent, t.accent2], startPoint: .top, endPoint: .bottom))
                                    .frame(width: min(cellW, cellH) * 0.86, height: min(cellW, cellH) * 0.86)
                            }
                            if day >= 1 && day <= len {
                                Text(Money.persianDigits(String(day)))
                                    .font(AppFont.medium(min(15, cellH * 0.42)))
                                    .foregroundStyle(day == today.jd ? .white : (c == 6 ? t.danger : t.ink))
                            }
                        }
                        .frame(width: cellW, height: cellH)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func dateWidget(_ s: WidgetSize, _ inn: CGSize) -> some View {
        let title = model.todayTitle
        let today = AppModel.today
        switch s {
        case .small:
            // day tile on top, weekday + full date below — fills the square
            let side = max(40, min(inn.width, inn.height - 50))
            VStack(spacing: 4) {
                dayTile(today, side: side)
                Text(title.weekday).font(AppFont.heavy(17)).foregroundStyle(t.ink).lineLimit(1).minimumScaleFactor(0.7)
                Text(Money.persianDigits(String(today.jy))).font(AppFont.regular(11)).foregroundStyle(t.soft)
            }
            .frame(width: inn.width, height: inn.height)
        case .medium:
            // day tile + weekday/date on top line, the current week below
            let tile = min(inn.height - 58, 86)
            VStack(spacing: 8) {
                HStack(spacing: 12) {
                    dayTile(today, side: tile)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title.weekday).font(AppFont.heavy(24)).foregroundStyle(t.ink).lineLimit(1).minimumScaleFactor(0.7)
                        Text(title.date).font(AppFont.regular(13)).foregroundStyle(t.soft).lineLimit(1).minimumScaleFactor(0.7)
                    }
                    Spacer(minLength: 0)
                }
                weekStrip(today, width: inn.width)
            }
            .frame(width: inn.width, height: inn.height, alignment: .top)
        case .large:
            // header + the whole month
            VStack(spacing: 10) {
                HStack(spacing: 12) {
                    dayTile(today, side: 64)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title.weekday).font(AppFont.heavy(24)).foregroundStyle(t.ink).lineLimit(1)
                        Text(title.date).font(AppFont.regular(13)).foregroundStyle(t.soft).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                monthGrid(today, width: inn.width, height: inn.height - 74)
            }
            .frame(width: inn.width, height: inn.height, alignment: .top)
        }
    }

    @ViewBuilder
    private func attentionWidget(_ s: WidgetSize, _ inn: CGSize) -> some View {
        let items = model.attentionItems
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                widgetTitle("نیازمند توجه", s)
                Spacer(minLength: 0)
                if !items.isEmpty {
                    Text(Money.persianDigits(String(items.count))).font(AppFont.bold(13)).foregroundStyle(.white)
                        .frame(minWidth: 22, minHeight: 22).background(t.warning, in: Capsule())
                }
            }
            if items.isEmpty {
                Label("فعلاً موردی نیست", systemImage: "checkmark.circle").font(AppFont.regular(13)).foregroundStyle(t.soft)
            } else if s == .small {
                let it = items[0]
                attentionRow(it, lines: 4, font: 12).frame(height: inn.height - Self.titleH - 6)
            } else {
                let rowH: CGFloat = 46
                ForEach(items.prefix(fit(inn, rowH: rowH))) { it in
                    attentionRow(it, lines: 2, font: 13).frame(height: rowH)
                }
            }
        }
    }

    private func attentionRow(_ item: AttentionItem, lines: Int, font: CGFloat) -> some View {
        let color: Color = item.level == .danger ? t.danger : (item.level == .warning ? t.warning : t.accent)
        return HStack(alignment: .top, spacing: 8) {
            Image(systemName: item.icon).font(.system(size: 13)).foregroundStyle(color).padding(.top, 2)
            Text(item.text).font(AppFont.medium(font)).foregroundStyle(t.ink).lineLimit(lines).minimumScaleFactor(0.85)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private func financialWidget(_ s: WidgetSize, _ inn: CGSize) -> some View {
        let accounts = model.accounts
        let active = accounts.first { $0.id == model.activeAccountId } ?? accounts.first
        VStack(alignment: .leading, spacing: 6) {
            widgetTitle("دفترها", s)
            if accounts.isEmpty {
                Text("دفتری نیست").font(AppFont.regular(13)).foregroundStyle(t.soft)
            } else if s == .small, let a = active {
                accountTile(a, compact: true).frame(height: inn.height - Self.titleH - 6)
            } else {
                let cols = 2
                let rows = s == .medium ? 1 : 2
                let tileH = (inn.height - Self.titleH - 6 - CGFloat(rows - 1) * 8) / CGFloat(rows)
                let list = Array(([active].compactMap { $0 } + accounts.filter { $0.id != active?.id }).prefix(cols * rows))
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: cols), spacing: 8) {
                    ForEach(list) { a in accountTile(a, compact: false).frame(height: tileH) }
                }
            }
        }
    }

    private func accountTile(_ a: AccountImportSummary, compact: Bool) -> some View {
        let budget = model.budget(accountId: a.id)
        return VStack(alignment: .leading, spacing: 5) {
            Text(a.name).font(AppFont.bold(compact ? 12 : 13)).foregroundStyle(t.ink).lineLimit(1)
            Text(Money.persianDigits(Money.format(a.expenseTotal))).font(AppFont.heavy(compact ? 17 : 18)).foregroundStyle(t.accent)
                .lineLimit(1).minimumScaleFactor(0.55)
            Text("تومان").font(AppFont.caption).foregroundStyle(t.soft)
            Spacer(minLength: 0)
            if budget > 0 {
                let pct = min(1, Double(a.expenseTotal) / Double(budget))
                ProgressView(value: pct).tint(pct >= 0.8 ? t.warning : t.accent2)
                Text("\(Money.persianDigits(Money.jsRound(pct * 100)))٪ بودجه").font(AppFont.caption).foregroundStyle(t.soft).lineLimit(1)
            } else if a.commissionEnabled || a.percent != 0 {
                Text("کمیسیون: " + Money.persianDigits(Money.format(abs(a.remaining)))).font(AppFont.caption).foregroundStyle(t.soft).lineLimit(1)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(t.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private func shortcutsWidget(_ s: WidgetSize, _ inn: CGSize) -> some View {
        let keys = SettingsOps.homeShortcuts(model.state)
        let (tiles, top) = shortcutTiles(s, inn, count: keys.count)
        VStack(alignment: .leading, spacing: 6) {
            if s != .small { widgetTitle("میانبرها", s) }
            if keys.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "plus.circle").font(.system(size: 24)).foregroundStyle(t.accent)
                    Text("افزودن میان‌بر").font(AppFont.medium(12)).foregroundStyle(t.soft)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ZStack(alignment: .topLeading) {
                    ForEach(Array(keys.prefix(tiles.capacity).enumerated()), id: \.offset) { i, k in
                        let r = WidgetLayout.tileRect(i, tiles, areaWidth: Double(inn.width), rtl: true)
                        let d = HomeShortcut.info(k)
                        VStack(spacing: r.w * 0.07) {
                            Image(systemName: d.icon).font(.system(size: r.w * 0.3)).foregroundStyle(t.accent)
                            if r.w >= 64 {
                                Text(d.title).font(AppFont.medium(max(10, min(13, r.w * 0.15)))).foregroundStyle(t.ink)
                                    .lineLimit(1).minimumScaleFactor(0.7)
                            }
                        }
                        .frame(width: r.w, height: r.h)
                        // same Liquid Glass as the settings / reports buttons: raised, glossy, with depth
                        .glassEffect(.regular.tint(t.accent.opacity(0.06)), in: RoundedRectangle(cornerRadius: r.w * 0.28, style: .continuous))
                        .shadow(color: .black.opacity(0.10), radius: 6, y: 4)
                        .position(x: r.x + r.w / 2, y: r.y + r.h / 2)
                    }
                }
                .frame(width: inn.width, height: inn.height - top, alignment: .topLeading)
                .environment(\.layoutDirection, .leftToRight)
            }
        }
    }

    @ViewBuilder
    private func activityWidget(_ s: WidgetSize, _ inn: CGSize) -> some View {
        let recent = model.recentRows
        let compact = s == .small
        let rowH: CGFloat = compact ? 44 : 46
        VStack(alignment: .leading, spacing: 6) {
            widgetTitle("فعالیت اخیر", s)
            if recent.isEmpty {
                Text("هنوز ردیفی ثبت نشده").font(AppFont.regular(13)).foregroundStyle(t.soft)
            }
            ForEach(recent.prefix(fit(inn, rowH: rowH))) { item in
                activityRow(item, compact: compact).frame(height: rowH)
            }
        }
    }

    private func activityRow(_ item: RecentItem, compact: Bool) -> some View {
        let r = item.row
        let dot: Color = r.kind == .commission ? .purple : (r.kind == .tankhah ? t.success : (model.categoryColor(r.category) ?? t.accent))
        let amount = Text(Money.persianDigits(Money.format(r.toman))).font(AppFont.bold(compact ? 12 : 14))
            .foregroundStyle(r.kind == .tankhah ? t.success : t.ink).lineLimit(1).minimumScaleFactor(0.7)
        return HStack(spacing: 8) {
            Circle().fill(dot).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(r.desc.isEmpty ? "—" : r.desc).font(AppFont.medium(compact ? 12 : 14)).foregroundStyle(t.ink).lineLimit(1)
                if compact {
                    amount
                } else {
                    HStack(spacing: 6) {
                        if !item.account.isEmpty { Text(item.account) }
                        Text(r.date)
                        if r.kind == .tankhah { Text("تنخواه").foregroundStyle(t.success) }
                    }
                    .font(AppFont.caption).foregroundStyle(t.soft).lineLimit(1)
                }
            }
            Spacer(minLength: 6)
            if !compact { amount }
        }
    }
}

struct QuoteCard: View {
    let quote: Quote
    let typewriter: Bool
    var msPerChar = 32
    @Environment(\.theme) private var t
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = 0
    nonisolated(unsafe) static var typedOnce = false

    var body: some View {
        let chars = Array(quote.text)
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: "quote.opening").foregroundStyle(t.accent2)
            Text(String(chars.prefix(shown)))
                .font(AppFont.medium(16)).foregroundStyle(t.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
            if !quote.author.isEmpty {
                Text("— " + quote.author).font(AppFont.caption).foregroundStyle(t.soft)
            }
        }
        .glassCard()
        .task(id: quote.id) {
            // web: the typewriter plays once per app session
            guard typewriter, !reduceMotion, !QuoteCard.typedOnce else { shown = chars.count; return }
            QuoteCard.typedOnce = true
            shown = 0
            for i in 1...max(1, chars.count) {
                try? await Task.sleep(nanoseconds: UInt64(msPerChar) * 1_000_000)
                shown = i
            }
        }
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
    @State private var budgetAccount: String?
    @State private var showManage = false
    @State private var showPartyReport = false
    @State private var showIncome = false
    @State private var incomeSheet: PersonalSheet?
    @State private var showPassword = false
    @State private var password = ""

    private var accountId: String? { selected ?? model.activeAccountId }

    var body: some View {
        let account = model.accounts.first { $0.id == accountId }
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16, pinnedViews: []) {
                HStack(alignment: .top) {
                    ScreenHeader(title: "دفتر حساب", subtitle: account?.name ?? "")
                    Button {
                        Haptics.tap()
                        showManage = true
                    } label: {
                        Image(systemName: "slider.horizontal.3").font(.title3).padding(10)
                    }
                    .buttonStyle(.glass)
                    .padding(.top, 8)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(model.accounts) { a in
                            let on = a.id == accountId
                            Button {
                                Haptics.tap()
                                withAnimation(.snappy) { selected = a.id }
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
                    Picker("", selection: $showIncome.animation(.snappy)) {
                        Text("هزینه و تنخواه").tag(false)
                        Text("درآمد این دفتر").tag(true)
                    }
                    .pickerStyle(.segmented)
                }

                if let a = account, showIncome {
                    ledgerIncome(a)
                }

                if let a = account, !showIncome {
                    LedgerHero(account: a, budget: model.budget(accountId: a.id), onBudget: { budgetAccount = a.id }) { sheet = .new }
                    if a.commissionEnabled || a.percent != 0 {
                        CommissionCard(account: a) { sheet = .settle }
                    }
                    if model.hasTankhah(a.id) {
                        Button {
                            Haptics.tap()
                            showPartyReport = true
                        } label: {
                            Label("تنخواه به تفکیک طرف حساب", systemImage: "person.2.fill")
                                .font(AppFont.bold(14)).frame(maxWidth: .infinity).padding(.vertical, 4)
                        }
                        .buttonStyle(.glass)
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
        .sheet(item: Binding(get: { budgetAccount.map { IdBox(id: $0) } }, set: { budgetAccount = $0?.id })) { b in
            NavigationStack {
                BudgetEditor(title: "بودجه‌ی دفتر", current: model.budget(accountId: b.id)) { _ = model.setAccountBudget(b.id, $0) }
            }
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $showManage) {
            Themed {
                NavigationStack {
                    AccountManageView(model: model, accountId: accountId) { id in selected = id }
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
            if let s = selected, !ids.contains(s) { selected = nil }
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
                Text(Money.persianDigits(Money.format(total))).font(AppFont.heavy(30))
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
    @State private var editing: IdBox?
    @State private var confirmDelete: String?
    @State private var shareFile: ExportFile?
    @Environment(\.theme) private var t

    /// web cwShareAsPng: a clean picture of the card
    @MainActor private func shareImage(_ c: WalletCard) {
        let r = ImageRenderer(content: BankCardView(card: c).frame(width: 640).padding(24).environment(\.layoutDirection, .rightToLeft))
        r.scale = 3
        guard let img = r.uiImage, let data = img.pngData() else { return }
        let name = (c.bankName.isEmpty ? "کارت" : c.bankName) + ".png"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do { try data.write(to: url); shareFile = ExportFile(url: url) } catch { model.errorMessage = error.localizedDescription }
    }

    var body: some View {
        let cards = model.walletCards.filter { $0.archived == showArchived }
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    ScreenHeader(title: "کیف کارت", subtitle: "برای کپی شماره، روی آن بزنید؛ برای ویرایش، نگه دارید")
                    Button {
                        Haptics.tap()
                        editing = IdBox(id: "")
                    } label: {
                        Image(systemName: "plus").font(.title3).padding(10)
                    }
                    .buttonStyle(.glass)
                    .padding(.top, 8)
                }
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
                        .contextMenu {
                            Button { editing = IdBox(id: c.id) } label: { Label("ویرایش", systemImage: "pencil") }
                            if let text = model.record("cards", c.id).flatMap(SettingsOps.cardCopyText) {
                                Button {
                                    UIPasteboard.general.string = text
                                    Haptics.success()
                                } label: { Label("کپی همه‌ی اطلاعات", systemImage: "doc.on.doc") }
                                ShareLink(item: text) { Label("اشتراک به صورت متن", systemImage: "text.bubble") }
                            }
                            Button { shareImage(c) } label: { Label("اشتراک به صورت عکس", systemImage: "photo") }
                            Button {
                                _ = model.setCardArchived(c.id, !c.archived)
                            } label: {
                                Label(c.archived ? "خروج از بایگانی" : "بایگانی", systemImage: c.archived ? "tray.and.arrow.up" : "archivebox")
                            }
                            Button(role: .destructive) { confirmDelete = c.id } label: { Label("حذف", systemImage: "trash") }
                        }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(AppBackground())
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $editing) { e in
            NavigationStack { CardFormView(model: model, editingId: e.id.isEmpty ? nil : e.id) }
        }
        .sheet(item: $shareFile) { f in ActivityView(items: [f.url]) }
        .confirmationDialog("این کارت حذف شود؟", isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } }),
                            titleVisibility: .visible) {
            Button("حذف", role: .destructive) {
                if let id = confirmDelete { _ = model.deleteCard(id) }
                confirmDelete = nil
            }
        }
    }
}

struct IdBox: Identifiable, Hashable { let id: String }

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
    @AppStorage(AppLock.enabledKey) private var lockEnabled = true
    @AppStorage(Notifier.enabledKey) private var notifyEnabled = true
    @AppStorage(Backups.lastAtKey) private var lastBackupAt: Double = 0
    @AppStorage(Backups.lastICloudKey) private var lastICloud: Int = -2
    @Environment(\.colorScheme) private var scheme
    @Environment(\.theme) private var t

    var body: some View {
        Form {
            Section {
                NavigationLink {
                    WidgetsSettingsView(model: model)
                } label: {
                    Label("ویجت‌های خانه", systemImage: "square.grid.2x2")
                }
                NavigationLink {
                    QuotesSettingsView(model: model)
                } label: {
                    Label("جمله‌های انگیزشی", systemImage: "quote.bubble")
                }
                NavigationLink {
                    PartiesView(model: model)
                } label: {
                    Label("طرف‌های حساب", systemImage: "person.2")
                }
            } header: {
                Text("خانه و فهرست‌ها").font(AppFont.medium(13))
            }

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

            AppearanceSection()

            Section {
                Toggle(isOn: $lockEnabled) {
                    Label("قفل با Face ID", systemImage: "faceid")
                }
                NavigationLink {
                    EditPasswordView(model: model)
                } label: {
                    Label("رمز ویرایش ردیف‌های قدیمی", systemImage: "lock.rectangle")
                }
                Toggle(isOn: $notifyEnabled) {
                    Label("اعلان سررسید چک، قسط و قرار", systemImage: "bell.badge")
                }
                .onChange(of: notifyEnabled) { _, _ in Notifier.sync(model.state) }
            } header: {
                Text("امنیت").font(AppFont.medium(13))
            } footer: {
                Text("قفل: وقتی بیش از یک دقیقه از اپ بیرون باشید، Face ID (یا رمز گوشی) خواسته می‌شود. اعلان‌ها: شب قبل از سررسید چک و قسط ساعت ۲۰، و قرارها ۳ ساعت قبل (قرار بدون ساعت: ۹ صبح همان روز).").font(AppFont.caption)
            }

            Section {
                LabeledContent("آخرین پشتیبان", value: lastBackupAt > 0 ? Backups.describeLast() : "هنوز گرفته نشده")
                LabeledContent("iCloud Drive", value: iCloudText)
                Button {
                    model.backupToday(showErrors: true)
                    Haptics.success()
                } label: {
                    Label("پشتیبان‌گیری همین الان", systemImage: "icloud.and.arrow.up")
                }
            } header: {
                Text("پشتیبان خودکار").font(AppFont.medium(13))
            } footer: {
                Text("بعد از هر تغییر، پشتیبان امروز به‌روز می‌شود. فایل‌ها در iCloud Drive › دفتر حساب › پشتیبان‌ها، و یک نسخه هم در Files › On My iPhone › دفتر حساب ذخیره می‌شود. قالب فایل همان پشتیبان کامل اپ وب است.").font(AppFont.caption)
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
                NavigationLink {
                    DangerZoneView(model: model)
                } label: {
                    Label("پاک‌سازی (هیستوری یادگیری / همه‌ی اطلاعات)", systemImage: "trash")
                        .foregroundStyle(t.danger)
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

    private var iCloudText: String {
        switch lastICloud {
        case 1: return "ذخیره شد ✓"
        case 0: return "در دسترس نیست (iCloud Drive خاموش است؟)"
        case -1: return "ذخیره نشد"
        default: return "—"
        }
    }
}
