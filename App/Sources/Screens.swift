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


// MARK: - root

struct RootView: View {
    @ObservedObject var model: AppModel
    @AppStorage("appearance") private var appearanceRaw = Appearance.system.rawValue
    @State private var showImporter = false
    @State private var exportFile: ExportFile?
    @State private var tab: AppTab = .home
    @AppStorage(AppLock.enabledKey) private var lockEnabled = true
    @State private var ledgerSheet: LedgerSheet?
    @StateObject private var lock = AppLock()
    @Environment(\.scenePhase) private var phase
    #if DEBUG
    @State private var uiTestCategories = ProcessInfo.processInfo.environment["UITEST_OPEN"] == "categories"
    #endif

    var body: some View {
        Themed {
            Group {
                if model.hasData {
                    AppShell(model: model, tab: $tab, ledgerSheet: $ledgerSheet, exportFile: $exportFile, showImporter: $showImporter)
                } else {
                    WelcomeView(showImporter: $showImporter)
                }
            }
            .overlay {
                if model.hasData && lock.locked {
                    LockScreen(lock: lock).transition(.opacity)
                } else if phase != .active && model.hasData && lockEnabled {
                    // hide the content in the app switcher only when the Face ID lock is on
                    PrivacyCover()
                }
            }
        }
        .onChange(of: phase) { _, p in
            if p == .background { lock.didEnterBackground() }
            if p == .active { lock.didBecomeActive(); model.backupToday(); if model.hasData { Notifier.sync(model.state) } }
        }
        .modifier(DueCheckPrompt(model: model, blocked: lock.locked || !model.hasData))
        .preferredColorScheme(Appearance(rawValue: appearanceRaw)?.scheme)
        #if DEBUG
        .sheet(isPresented: $uiTestCategories) {
            NavigationStack { CategoryManagerView(model: model) }
        }
        #endif
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
        .alert("انجام شد", isPresented: Binding(get: { model.infoMessage != nil && model.errorMessage == nil },
                                                 set: { if !$0 { model.infoMessage = nil } })) {
            Button("باشه", role: .cancel) { model.infoMessage = nil }
        } message: {
            Text(model.infoMessage ?? "")
        }
    }
}

/// one topic row of the settings hub: icon in a coloured tile, title, and a short status line
struct SettingsRow: View {
    let icon: String
    let tint: Color
    let title: String
    let detail: String?
    @Environment(\.theme) private var t
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(tint.gradient, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(AppFont.medium(15)).foregroundStyle(t.ink)
                if let d = detail, !d.isEmpty {
                    Text(d).font(AppFont.caption).foregroundStyle(t.soft).lineLimit(1)
                }
            }
        }
        .padding(.vertical, 2)
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
    @AppStorage(QuoteDay.offsetKey) private var quoteOffset = 0
    @ObservedObject var model: AppModel
    @Binding var tab: AppTab
    @Binding var ledgerSheet: LedgerSheet?
    @Binding var exportFile: ExportFile?
    @Binding var showImporter: Bool
    @Environment(\.theme) private var t
    @State private var appeared = false
    @State private var showSettings = false
    @State private var showSearch = false
    @State private var showShortcutEditor = false
    @State private var showAppointment = false
    @State private var editingWidgets = false
    @State private var attentionOpen = false
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
        case "reports": tab = .reports
        case "appointments": showAppointment = true
        default: break
        }
    }

    var body: some View {
        let greet = AppModel.greeting(hour: Calendar.current.component(.hour, from: Date()))
        let order = SettingsOps.widgetOrder(model.state).filter { SettingsOps.widgetVisible(model.state, $0) }
        PageScrollView(tab: .home) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    ScreenHeader(title: "خانه", subtitle: "نمای کلی و امروز")
                    HStack(spacing: 8) {
                        HeaderIconButton(icon: "magnifyingglass") { Haptics.tap(); showSearch = true }
                        HeaderIconButton(icon: "gearshape.fill") { Haptics.tap(); showSettings = true }
                            .accessibilityIdentifier("settings")
                    }
                    .padding(.top, 8)
                }

                HStack(spacing: 8) {
                    Image(systemName: greet.icon).foregroundStyle(t.accent).symbolEffect(.pulse, options: .repeating)
                    Text(greet.text + "، " + AppModel.ownerName).font(AppFont.bold(19)).foregroundStyle(t.ink)
                }

                if let q = QuoteDay.today(model.state, offset: quoteOffset) {
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
                           onDragging: { draggingWidget = $0 },
                           blocks: ["attention": attentionHeight]) { key, size, frame in
                    WidgetCard(size: frame) { widget(key, size, inner(frame)) }
                        .entrance(order.firstIndex(of: key) ?? 0)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
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
        .scrollsToTopOnDockTap(.home)
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
        .navigationDestination(isPresented: $showSearch) {
            SearchView(model: model)
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
    private static let tileMargin: CGFloat = 6
    /// how many rows of height `rowH` (with `spacing`) fit under the title
    private func fit(_ inner: CGSize, rowH: CGFloat, spacing: CGFloat = 6) -> Int {
        max(1, Int((inner.height - Self.titleH - 6 + spacing) / (rowH + spacing)))
    }
    private func shortcutTiles(_ s: WidgetSize, _ inner: CGSize, count: Int) -> (WidgetLayout.Tiles, top: CGFloat) {
        let top: CGFloat = s == .small ? 0 : Self.titleH + 6
        // tiles keep a soft margin inside the card so the glass edge/shadow is never cut by the card's clip
        let m = Self.tileMargin
        return (WidgetLayout.tiles(count: count, width: Double(inner.width - 2 * m), height: Double(inner.height - top - 2 * m)), top)
    }

    private func tapWidget(_ key: String, _ point: CGPoint, _ frame: CGSize) {
        switch key {
        case "attention":
            let items = model.attentionItems
            // the «همه / بستن» bar at the bottom unfolds / folds the list
            if items.count > 3 && point.y > frame.height - WidgetCard<EmptyView>.padding - Self.attMoreH - 4 {
                Haptics.tap()
                withAnimation(.spring(duration: 0.45, bounce: 0.25)) { attentionOpen.toggle() }
                return
            }
            // otherwise the row under the finger decides where to go
            let top = WidgetCard<EmptyView>.padding + Self.titleH + Self.attGap
            var y = top, item = items.first
            for it in items.prefix(attentionOpen ? items.count : 3) {
                let h = Self.rowH(it)
                if point.y < y + h + Self.attGap { item = it; break }
                y += h + Self.attGap
            }
            tab = item?.id.hasPrefix("budget") == true ? .ledger : .reminders
        case "financial", "activity": tab = .ledger
        case "shortcuts":
            let keys = SettingsOps.homeShortcuts(model.state)
            guard !keys.isEmpty else { showShortcutEditor = true; return }
            let size = HomeWidgetPrefs.decode(UserDefaults.standard.string(forKey: HomeWidgetPrefs.key) ?? "{}")["shortcuts"]
                ?? HomeWidgetPrefs.defaults["shortcuts"]!
            let inn = inner(frame)
            let (t, top) = shortcutTiles(size, inn, count: keys.count)
            let p = WidgetCard<EmptyView>.padding
            let m = Self.tileMargin
            if let i = WidgetLayout.tileIndex(at: Double(point.x - p - m), Double(point.y - p - top - m), count: keys.count, t,
                                               areaWidth: Double(inn.width - 2 * m), rtl: true) {
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
        // typography only — no box inside the card: month in the accent gradient, the day number big
        VStack(spacing: -side * 0.04) {
            Text(BackupExporter.months[today.jm - 1])
                .font(AppFont.heavy(max(12, side * 0.2)))
                .foregroundStyle(LinearGradient(colors: [t.accent, t.accent2], startPoint: .leading, endPoint: .trailing))
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(Money.persianDigits(String(today.jd)))
                .font(AppFont.heavy(side * 0.68))
                .foregroundStyle(t.ink)
                .lineLimit(1).minimumScaleFactor(0.5)
        }
        .frame(width: side, height: side)
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
            // text only, filling the square: month · big day · weekday · year
            let h = inn.height
            VStack(spacing: 0) {
                Text(BackupExporter.months[today.jm - 1])
                    .font(AppFont.heavy(h * 0.13))
                    .foregroundStyle(LinearGradient(colors: [t.accent, t.accent2], startPoint: .leading, endPoint: .trailing))
                    .lineLimit(1).minimumScaleFactor(0.6)
                Text(Money.persianDigits(String(today.jd)))
                    .font(AppFont.heavy(h * 0.46))
                    .foregroundStyle(t.ink)
                    .lineLimit(1).minimumScaleFactor(0.5)
                    .frame(height: h * 0.5)
                Text(title.weekday)
                    .font(AppFont.heavy(h * 0.115)).foregroundStyle(t.ink).lineLimit(1).minimumScaleFactor(0.6)
                Text(Money.persianDigits(String(today.jy)))
                    .font(AppFont.medium(h * 0.075)).foregroundStyle(t.soft)
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

    // MARK: «نیازمند توجه» — 4 automatic heights: 1, 2 or 3 rows, or 3 rows + «همه» (more unfold with a spring)

    private static let attRowH: CGFloat = 40, attGap: CGFloat = 6, attMoreH: CGFloat = 30
    private var attentionHeight: CGFloat {
        let n = model.attentionItems.count
        let pad = WidgetCard<EmptyView>.padding * 2 + Self.titleH + 6
        if n == 0 { return pad + 24 }
        let shown = model.attentionItems.prefix(attentionOpen ? n : 3)
        let rows = shown.reduce(CGFloat(0)) { $0 + Self.rowH($1) }
        return pad + rows + CGFloat(shown.count - 1) * Self.attGap + (n > 3 ? Self.attGap + Self.attMoreH : 0)
    }

    /// one line for a short notice, two for a long one (the card stays slim)
    private static func rowH(_ it: AttentionItem) -> CGFloat {
        let oneLine = (UIScreen.main.bounds.width - 32 - 28 - 50) / 6.6
        return CGFloat(it.text.count) > oneLine ? 58 : attRowH
    }

    @ViewBuilder
    private func attentionWidget(_ s: WidgetSize, _ inn: CGSize) -> some View {
        let items = model.attentionItems
        VStack(alignment: .leading, spacing: Self.attGap) {
            HStack {
                widgetTitle("نیازمند توجه", .medium)
                Spacer(minLength: 0)
                if !items.isEmpty {
                    Text(Money.persianDigits(String(items.count))).font(AppFont.bold(13)).foregroundStyle(.white)
                        .frame(minWidth: 22, minHeight: 22).background(t.warning, in: Capsule())
                }
            }
            if items.isEmpty {
                Label("فعلاً موردی نیست", systemImage: "checkmark.circle").font(AppFont.regular(13)).foregroundStyle(t.soft)
                    .frame(height: 24)
            }
            ForEach(Array(items.prefix(attentionOpen ? items.count : 3).enumerated()), id: \.element.id) { i, it in
                attentionRow(it, lines: 2, font: 13)
                    .frame(height: Self.rowH(it))
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity)
                            .animation(.spring(duration: 0.45, bounce: 0.25).delay(Double(max(0, i - 3)) * 0.04)),
                        removal: .opacity.animation(.easeOut(duration: 0.15))))
            }
            if items.count > 3 {
                HStack(spacing: 6) {
                    Text(attentionOpen ? "بستن" : "همه (" + Money.persianDigits(String(items.count)) + ")").font(AppFont.bold(13))
                    Image(systemName: "chevron.down").font(.system(size: 12, weight: .bold))
                        .rotationEffect(.degrees(attentionOpen ? 180 : 0))
                }
                .foregroundStyle(t.accent)
                .frame(maxWidth: .infinity)
                .frame(height: Self.attMoreH)
                .background(t.accent.opacity(0.08), in: Capsule())
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
            FxNumber(a.expenseTotal) { Money.persianDigits(Money.format($0)) }.font(AppFont.heavy(compact ? 17 : 18)).foregroundStyle(t.accent)
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
                        let r = WidgetLayout.tileRect(i, tiles, areaWidth: Double(inn.width - 2 * Self.tileMargin), rtl: true)
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
                        .position(x: r.x + r.w / 2, y: r.y + r.h / 2)
                    }
                }
                .frame(width: inn.width - 2 * Self.tileMargin, height: inn.height - top - 2 * Self.tileMargin, alignment: .topLeading)
                .padding(Self.tileMargin)
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
    let typewriter: Bool                // kept for the call site; the effect now comes from Settings (QuoteFx)
    var msPerChar = 32
    @Environment(\.theme) private var t
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.pageActive) private var active
    @AppStorage(QuoteFx.key) private var fxRaw = QuoteFx.auto.rawValue
    @AppStorage(PageFx.key) private var pageFxRaw = PageFx.rise.rawValue
    @State private var shown = Int.max
    @State private var progress: Double = 1
    @State private var job: Task<Void, Never>?
    nonisolated(unsafe) static var typedOnce = false

    private var fx: QuoteFx {
        if reduceMotion { return .none }
        let f = QuoteFx(rawValue: fxRaw) ?? .auto
        return f == .auto ? QuoteFx.matching(PageFx(rawValue: pageFxRaw) ?? .rise) : f
    }

    var body: some View {
        let words = quote.text.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: "quote.opening").foregroundStyle(t.accent2)
            Group {
                if fx == .typewriter {
                    let chars = Array(quote.text)
                    Text(String(chars.prefix(shown)))
                } else {
                    // every word is its own run, so the renderer can move words (Persian letters stay joined)
                    words.enumerated().reduce(Text("")) { acc, w in
                        acc + Text(w.element + (w.offset < words.count - 1 ? " " : "")).customAttribute(WordTag(i: w.offset))
                    }
                    .textRenderer(WordReveal(progress: progress, count: words.count, style: fx, glow: t.accent))
                }
            }
            .font(AppFont.medium(16)).foregroundStyle(t.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            if !quote.author.isEmpty {
                Text("— " + quote.author).font(AppFont.caption).foregroundStyle(t.soft)
                    .opacity(fx == .typewriter || fx == .none ? 1 : min(1, max(0, progress * 1.6 - 0.6)))
            }
        }
        .glassCard(effect: true)
        .onAppear { if active { play(words.count) } }
        .onChange(of: active) { _, now in if now { play(words.count) } else { job?.cancel() } }
        .onChange(of: quote.id) { _, _ in play(words.count) }
        .onChange(of: fxRaw) { _, _ in play(words.count) }
        .onDisappear { job?.cancel() }
    }

    private func play(_ n: Int) {
        job?.cancel()
        switch fx {
        case .none, .auto:
            shown = .max; progress = 1
        case .typewriter:
            // web: the typewriter plays once per app session
            progress = 1
            guard !QuoteCard.typedOnce else { shown = .max; return }
            QuoteCard.typedOnce = true
            let count = quote.text.count
            shown = 0
            job = Task { @MainActor in
                for i in 1...max(1, count) {
                    try? await Task.sleep(nanoseconds: UInt64(msPerChar) * 1_000_000)
                    if Task.isCancelled { shown = .max; return }
                    shown = i
                }
            }
        default:
            shown = .max
            Motion.instantly { progress = 0 }
            // starts as the card lands; about 70 ms between words, never longer than ~2.6 s in all
            let dur = min(2.6, 0.55 + Double(n) * 0.07)
            withAnimation(.linear(duration: dur).delay(0.25)) { progress = 1 }
        }
    }
}

/// how the home quote appears; «auto» follows the page-entrance style, any other choice pairs freely with it
enum QuoteFx: String, CaseIterable, Identifiable {
    case auto, none, typewriter, rise, spring, flip, blur, slide, neon
    var id: String { rawValue }
    static let key = "quote.fx"
    var title: String {
        switch self {
        case .auto: return "هماهنگ با انیمیشن صفحه"
        case .none: return "بدون انیمیشن"
        case .typewriter: return "تایپی (حرف به حرف)"
        case .rise: return "کلمه به کلمه از پایین"
        case .spring: return "کلمه‌ها فنری"
        case .flip: return "کلمه‌ها ورقی"
        case .blur: return "کلمه‌ها از مه"
        case .slide: return "کلمه‌ها موجی از کنار"
        case .neon: return "کلمه‌ها با نور نئونی"
        }
    }
    static func matching(_ p: PageFx) -> QuoteFx {
        switch p {
        case .none: return .none
        case .rise: return .rise
        case .spring: return .spring
        case .flip: return .flip
        case .blur: return .blur
        case .slide: return .slide
        case .neon: return .neon
        }
    }
}

struct WordTag: TextAttribute { let i: Int }

/// draws the quote word by word; `progress` 0 → 1 runs a soft wave through the words (each takes ~3 words' time)
struct WordReveal: TextRenderer, Animatable {
    var progress: Double
    let count: Int
    let style: QuoteFx
    let glow: Color
    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func draw(layout: Text.Layout, in ctx: inout GraphicsContext) {
        let spread = 3.0
        for line in layout {
            for run in line {
                let i = Double(run[WordTag.self]?.i ?? 0)
                let t = max(0, min(1, (progress * (Double(count) + spread) - i) / spread))
                let e = 1 - pow(1 - t, 3)                    // ease-out
                var c = ctx
                let b = run.typographicBounds.rect
                switch style {
                case .rise:
                    c.opacity = e
                    c.translateBy(x: 0, y: (1 - e) * 10)
                case .spring:
                    c.opacity = min(1, t * 2.5)
                    let s = 0.55 + 0.45 * e + 0.14 * sin(t * .pi) * (1 - t * 0.5)
                    c.translateBy(x: b.midX, y: b.midY); c.scaleBy(x: s, y: s); c.translateBy(x: -b.midX, y: -b.midY)
                case .flip:
                    c.opacity = min(1, t * 2)
                    c.translateBy(x: 0, y: b.midY); c.scaleBy(x: 1, y: max(0.02, e)); c.translateBy(x: 0, y: -b.midY)
                case .blur:
                    c.opacity = e
                    if t < 1 { c.addFilter(.blur(radius: (1 - e) * 6)) }
                case .slide:
                    c.opacity = e
                    c.translateBy(x: (1 - e) * 22, y: 0)
                case .neon:
                    c.opacity = min(1, t * 3)
                    let g = sin(t * .pi)
                    if g > 0.02 { c.addFilter(.shadow(color: glow.opacity(0.5 * g), radius: 4)) }
                default: break
                }
                c.draw(run)
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
            FxNumber(account.expenseTotal, Fmt.toman).font(AppFont.heavy(20)).foregroundStyle(t.accent)
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
            LedgerHero(account: a, budget: model.budget(accountId: a.id), commission: commission, onBudget: { budgetAccount = a.id },
                       budgetPDF: { await model.budgetPDF(accountId: a.id) }) { sheet = .new }
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
    var budgetPDF: (() async -> ExportFile?)? = nil
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
                HStack {
                    Text("\(Money.persianDigits(Money.jsRound(pct * 100)))٪ از بودجه · مانده " + Fmt.toman(max(0, budget - account.expenseTotal)))
                        .font(AppFont.caption).foregroundStyle(t.soft)
                    Spacer()
                    if let budgetPDF { CardPDFButton(make: budgetPDF) }
                }
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

// MARK: - cards

struct CardsView: View {
    @State private var cardsPDF: ExportFile?
    @State private var makingCardsPDF = false
    @ObservedObject var model: AppModel
    @State private var showArchived = false
    @State private var editing: IdBox?
    @State private var confirmDelete: String?
    @State private var shareFile: ExportFile?
    @Environment(\.theme) private var t

    /// web cwShareAsPng: a clean picture of the card
    @MainActor private func shareImage(_ c: WalletCard) {
        // the card alone, edge to edge, at ~3000 px wide (more than a 300 dpi print of a real card)
        let w: CGFloat = 1000
        let r = ImageRenderer(content: BankCardView(card: c, forSharing: true)
            .frame(width: w, height: w / 1.586)
            .environment(\.layoutDirection, .rightToLeft)
            .environment(\.theme, t))
        r.scale = 3
        r.isOpaque = true
        guard let img = r.uiImage, let data = img.pngData() else { return }
        let name = (c.bankName.isEmpty ? "کارت" : c.bankName) + ".png"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do { try data.write(to: url); shareFile = ExportFile(url: url) } catch { model.errorMessage = error.localizedDescription }
    }

    var body: some View {
        let cards = model.walletCards.filter { $0.archived == showArchived }
        PageScrollView(tab: .cards) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    ScreenHeader(title: "کیف کارت", subtitle: "برای کپی شماره، روی آن بزنید؛ برای ویرایش، نگه دارید")
                    HeaderIconButton(icon: makingCardsPDF ? "hourglass" : "square.and.arrow.up") {
                        guard !makingCardsPDF else { return }
                        Haptics.tap()
                        makingCardsPDF = true
                        Task { @MainActor in cardsPDF = await model.cardsPDF(); makingCardsPDF = false }
                    }
                    .padding(.top, 8)
                    .accessibilityLabel("PDF کیف کارت‌ها")
                    HeaderIconButton(icon: "plus") { Haptics.tap(); editing = IdBox(id: "") }
                        .padding(.top, 8)
                }
                Segmented(selection: $showArchived, [(false, "کارت‌های فعال"), (true, "بایگانی‌شده")])
                if cards.isEmpty {
                    Text("کارتی نیست").font(AppFont.regular(14)).foregroundStyle(t.soft).frame(maxWidth: .infinity).padding(40)
                }
                ForEach(Array(cards.enumerated()), id: \.element.id) { idx, c in
                    BankCardView(card: c)
                        .neonEdge(radius: 22)
                        .modifier(FloatingCard(index: idx))
                        .entrance(idx)
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
            .padding(.bottom, 12)
        }
        .background(AppBackground())
        .scrollsToTopOnDockTap(.cards)
        .pageSwipe(.cards, $showArchived, [false, true])
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $editing) { e in
            NavigationStack { CardFormView(model: model, editingId: e.id.isEmpty ? nil : e.id) }
        }
        .sheet(item: $shareFile) { f in ActivityView(items: [f.url]) }
        .sheet(item: $cardsPDF) { f in ActivityView(items: [f.url]) }
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
    /// the picture sent to someone else: only bank + logo, card number, IBAN, account number and holder; no
    /// account type, expiry, shadow or rounded corners (full-bleed, so no frame appears in any messenger)
    var forSharing = false
    @State private var copied: String?

    var body: some View {
        // the card's size and shape come only from this clear 1.586 box (ID-1 bank card); the photo or design is laid
        // over it, fills it and is cropped — it can never stretch or reshape the card
        Color.clear
            .aspectRatio(1.586, contentMode: .fit)
            .overlay { background }
            .overlay { LinearGradient(colors: [.black.opacity(0.08), .black.opacity(0.18), .black.opacity(0.5)], startPoint: .top, endPoint: .bottom) }
            .overlay { GeometryReader { g in face(g.size.width / 340) } }
            .clipShape(RoundedRectangle(cornerRadius: forSharing ? 0 : 22, style: .continuous))
            .shadow(color: .black.opacity(forSharing ? 0 : 0.25), radius: forSharing ? 0 : 14, y: forSharing ? 0 : 8)
    }

    /// layout in card units (u = 1 at a 340 pt wide card), so the app card and the large shared picture are identical:
    /// header · card number in the upper half · IBAN in the middle · account number in the lower half · holder at the bottom
    private func face(_ u: CGFloat) -> some View {
        ZStack {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 9 * u) {
                    BankLogo(bank: card.bank, name: card.bankName, size: 32 * u, tile: true)
                    Text(card.bankName).font(AppFont.heavy(17 * u)).lineLimit(1).minimumScaleFactor(0.6)
                    Spacer(minLength: 4 * u)
                    if !forSharing && !card.accountType.isEmpty {
                        Text(card.accountType).font(AppFont.medium(11.5 * u)).opacity(0.85).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                number(grouped(card.number), size: 23, weight: .bold, label: nil, copyLabel: "شماره کارت", value: card.number, u: u)
                Spacer(minLength: 0)
                if !card.iban.isEmpty {
                    number(groupedIban(card.iban), size: 13.5, weight: .medium, label: "شبا", copyLabel: "شبا", value: card.iban, u: u)
                }
                Spacer(minLength: 0)
                if !card.accountNumber.isEmpty {
                    number(card.accountNumber, size: 15, weight: .medium, label: "حساب", copyLabel: "شماره حساب", value: card.accountNumber, u: u)
                }
                Spacer(minLength: 0)
                HStack(alignment: .lastTextBaseline) {
                    Text(card.holder).font(AppFont.heavy(18 * u)).lineLimit(1).minimumScaleFactor(0.6)
                    Spacer(minLength: 6 * u)
                    if !forSharing && !card.expiry.isEmpty {
                        Text(Money.persianDigits(card.expiry)).font(AppFont.medium(12.5 * u)).opacity(0.9)
                    }
                }
            }
            .foregroundStyle(.white)
            // embossed print: a thin light edge above, a crisp dark edge below and a soft drop under the letters
            .shadow(color: .white.opacity(0.35), radius: 0, x: 0, y: -0.6 * u)
            .shadow(color: .black.opacity(0.55), radius: 0, x: 0, y: 0.9 * u)
            .shadow(color: .black.opacity(0.35), radius: 2.5 * u, x: 0, y: 1.6 * u)
            .padding(.horizontal, 18 * u)
            .padding(.vertical, 15 * u)
            if let c = copied {
                Text(c + " کپی شد")
                    .font(AppFont.bold(13))
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .glassEffect(.regular, in: Capsule())
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.scale.combined(with: .opacity))
            }
        }
    }

    /// one centred number line; a small label («شبا» / «حساب») sits in front of it, the number always left-to-right
    private func number(_ text: String, size: CGFloat, weight: Font.Weight, label: String?, copyLabel: String, value: String, u: CGFloat) -> some View {
        let line = HStack(spacing: 6 * u) {
            if let label {
                Text(label).font(AppFont.bold(10.5 * u)).opacity(0.85)
            }
            Text(Money.persianDigits(text))
                .font(weight == .bold ? AppFont.heavy(size * u) : AppFont.bold(size * u))
                .environment(\.layoutDirection, .leftToRight)
                .lineLimit(1).minimumScaleFactor(0.55)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        // in the shared picture there is nothing to tap (a disabled button would print faded)
        return Group {
            if forSharing {
                line
            } else {
                Button { copy(value, label: copyLabel) } label: { line }.buttonStyle(.plain)
            }
        }
    }

    /// IR12 3456 7890 … in groups of four, easier to read aloud
    private func groupedIban(_ s: String) -> String {
        let clean = s.replacingOccurrences(of: " ", with: "")
        var out = ""
        for (i, ch) in clean.enumerated() {
            if i > 0 && i % 4 == 0 { out.append(" ") }
            out.append(ch)
        }
        return out
    }

    @ViewBuilder private var background: some View {
        if let img = card.image {
            GeometryReader { g in
                Image(uiImage: img).resizable().scaledToFill()
                    .frame(width: g.size.width, height: g.size.height)
                    .clipped()
            }
        } else if let art = card.preset.flatMap(CardArt.init(rawValue:)) {
            CardArtView(art: art)
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

/// Settings hub: a short list of topics (like the phone's own Settings), each opening its own page.
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
                NavigationLink { appearancePage } label: {
                    SettingsRow(icon: "paintbrush.fill", tint: .indigo, title: "ظاهر",
                                detail: (Palette(rawValue: paletteRaw)?.title ?? "") + " · " + (Appearance(rawValue: appearanceRaw)?.title ?? ""))
                }
                NavigationLink { homePage } label: {
                    SettingsRow(icon: "house.fill", tint: .blue, title: "صفحه‌ی خانه", detail: "ویجت‌ها و جمله‌های انگیزشی")
                }
            }

            Section {
                NavigationLink { PartiesView(model: model) } label: {
                    SettingsRow(icon: "person.2.fill", tint: .teal, title: "طرف‌های حساب", detail: nil)
                }
                NavigationLink { CategoryManagerView(model: model) } label: {
                    SettingsRow(icon: "tag.fill", tint: .orange, title: "دسته‌ها و زیردسته‌ها", detail: "مرور، حذف و جایگزینی")
                }
                .accessibilityIdentifier("settings.categories")
            }

            Section {
                NavigationLink { securityPage } label: {
                    SettingsRow(icon: "lock.fill", tint: .gray, title: "امنیت",
                                detail: (lockEnabled ? "Face ID روشن" : "Face ID خاموش") + (model.hasEditPassword ? " · رمز ردیف‌ها دارد" : ""))
                }
                NavigationLink { notificationsPage } label: {
                    SettingsRow(icon: "bell.badge.fill", tint: .red, title: "اعلان‌ها", detail: notifyEnabled ? "روشن" : "خاموش")
                }
            }

            Section {
                NavigationLink { dataPage } label: {
                    SettingsRow(icon: "externaldrive.fill.badge.icloud", tint: .green, title: "پشتیبان و داده‌ها",
                                detail: lastBackupAt > 0 ? "آخرین پشتیبان: " + Backups.describeLast() : "هنوز پشتیبانی گرفته نشده")
                }
            }

            Section {
            } footer: {
                Text("نسخه‌ی " + Money.persianDigits((Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""))
                     + " (" + Money.persianDigits(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "") + ")")
                    .font(AppFont.caption).frame(maxWidth: .infinity)
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppBackground())
        .navigationTitle("تنظیمات")
    }

    // MARK: pages

    private func page<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        Form { content() }
            .scrollContentBackground(.hidden)
            .background(AppBackground())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
    }

    private var appearancePage: some View {
        page("ظاهر") {
            Section {
                ForEach(Palette.allCases) { p in
                    let c = p.colors(scheme)
                    Button {
                        Haptics.tap()
                        withAnimation(.smooth) { paletteRaw = p.rawValue }
                    } label: {
                        HStack(spacing: 12) {
                            // the palette's colors in their own order, main → secondary
                            HStack(spacing: -7) {
                                ForEach(Array(p.swatches.enumerated()), id: \.offset) { _, col in
                                    Circle().fill(col).frame(width: 22, height: 22)
                                        .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 1.5))
                                }
                            }
                            .environment(\.layoutDirection, .leftToRight)
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
            MotionSettingsSection()
        }
    }

    private var homePage: some View {
        page("صفحه‌ی خانه") {
            Section {
                NavigationLink { WidgetsSettingsView(model: model) } label: {
                    Label("ویجت‌های خانه", systemImage: "square.grid.2x2")
                }
                NavigationLink { QuotesSettingsView(model: model) } label: {
                    Label("جمله‌های انگیزشی", systemImage: "quote.bubble")
                }
            } footer: {
                Text("برای جابه‌جا کردن یا تغییر اندازه‌ی ویجت‌ها، روی یک ویجت در صفحه‌ی خانه انگشت نگه دارید.").font(AppFont.caption)
            }
        }
    }

    private var securityPage: some View {
        page("امنیت") {
            Section {
                Toggle(isOn: $lockEnabled) { Label("قفل با Face ID", systemImage: "faceid") }
            } footer: {
                Text("وقتی بیش از یک دقیقه از اپ بیرون باشید، Face ID (یا رمز گوشی) خواسته می‌شود.").font(AppFont.caption)
            }
            Section {
                NavigationLink { EditPasswordView(model: model) } label: {
                    Label("رمز ویرایش ردیف‌های قدیمی", systemImage: "lock.rectangle")
                }
            } footer: {
                Text("با رمز، ویرایش و حذف ردیف‌هایی که بیش از ۸ روز از تاریخشان گذشته رمز می‌خواهد.").font(AppFont.caption)
            }
        }
    }

    private var notificationsPage: some View {
        page("اعلان‌ها") {
            Section {
                Toggle(isOn: $notifyEnabled) { Label("اعلان سررسید چک، قسط و قرار", systemImage: "bell.badge") }
                    .onChange(of: notifyEnabled) { _, _ in Notifier.sync(model.state) }
            } footer: {
                Text("شب قبل از سررسید چک و قسط ساعت ۲۰، و قرارها ۳ ساعت قبل (قرار بدون ساعت: ۹ صبح همان روز). برای فرستادن یک چک یا قرار به Reminders گوشی، در «یادآوری‌ها» انگشت را روی آن نگه دارید.").font(AppFont.caption)
            }
        }
    }

    private var dataPage: some View {
        page("پشتیبان و داده‌ها") {
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
                Text("بعد از هر تغییر، پشتیبان امروز به‌روز می‌شود: در iCloud Drive › دفتر حساب › پشتیبان‌ها و یک نسخه در Files › On My iPhone › دفتر حساب.").font(AppFont.caption)
            }
            Section {
                Button { exportFile = model.makeExportFile() } label: {
                    Label("خروجی پشتیبان کامل", systemImage: "square.and.arrow.up")
                }
                Button { showImporter = true } label: {
                    Label("ورود دوباره‌ی پشتیبان", systemImage: "square.and.arrow.down")
                }
            } header: {
                Text("فایل پشتیبان").font(AppFont.medium(13))
            } footer: {
                Text(model.lastImportText ?? "قالب فایل همان پشتیبان کامل اپ وب است.").font(AppFont.caption)
            }
            Section {
                NavigationLink { DangerZoneView(model: model) } label: {
                    Label("پاک‌سازی (هیستوری یادگیری / همه‌ی اطلاعات)", systemImage: "trash").foregroundStyle(t.danger)
                }
            }
        }
    }

    private var iCloudText: String {
        switch lastICloud {
        case 1: return "ذخیره شد ✓"
        case 0: return "گوشی به iCloud Drive وصل نیست"
        case -2: return "این نسخه‌ی اپ مجوز آیکلود ندارد"
        case -3: return "پوشه‌ی آیکلود اپ هنوز آماده نشده — دوباره امتحان کنید"
        case -1: return "ذخیره نشد"
        default: return "—"
        }
    }
}
