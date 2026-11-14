import SwiftUI
import UIKit
import Charts
import UniformTypeIdentifiers
import HesabCore

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
                            .accessibilityIdentifier("search")
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
        let isCommission = r.kind == .commission || r.category.trimmingCharacters(in: .whitespaces) == "کمیسیون"
        let dot: Color = isCommission ? (model.categoryColor("کمیسیون") ?? .purple) : (r.kind == .tankhah ? t.success
            : (r.kind == .reward ? t.reward : (model.categoryColor(r.category) ?? t.accent)))
        let amount = Text(Money.persianDigits(Money.format(r.toman))).font(AppFont.bold(compact ? 12 : 14))
            .foregroundStyle(r.kind == .tankhah ? t.success : (r.kind == .reward ? t.reward : t.ink)).lineLimit(1).minimumScaleFactor(0.7)
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
                        if r.kind == .reward { Text("پاداش").foregroundStyle(t.reward) }
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
