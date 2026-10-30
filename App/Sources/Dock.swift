import SwiftUI
import HesabCore

// Two-part Liquid Glass dock (like the web app): four main pages in one capsule, «گزارش‌ها» as its own round
// button. Minimal icons, no labels.
//
// Touch handling is done once, by position, for the whole capsule (no per-button hit areas that can overlap):
//   • the slot under the finger lights up while pressing, and you can slide across to another one;
//   • lifting the finger selects that slot; tapping the page you are already on scrolls it to the top;
//   • holding ~0.4 s opens that slot's mini dock (home → کیف کارت, دفتر حساب → switch ledger) with haptics.
// «گزارش‌ها» opens the report that matches the page you came from (home → overall, ledger → that ledger,
// personal → personal, reminders → reminders).
// Pages stay alive and cross-fade over the same background (no white flash). The dock sits over the content;
// every scroll view gets a bottom margin so the last rows can always be scrolled above it.

enum AppTab: Hashable { case home, ledger, personal, reminders, reports, cards }

/// «scroll to top» requests per page (dock re-tap)
final class ScrollTopCenter: ObservableObject {
    @Published var ticks: [AppTab: Int] = [:]
    func fire(_ t: AppTab) { ticks[t, default: 0] += 1 }
}

struct ScrollTopOnDockTap: ViewModifier {
    let tab: AppTab
    @EnvironmentObject private var center: ScrollTopCenter
    @State private var position = ScrollPosition(edge: .top)
    func body(content: Content) -> some View {
        content
            .scrollPosition($position)
            .onChange(of: center.ticks[tab] ?? 0) { _, _ in
                withAnimation(.smooth(duration: 0.45)) { position.scrollTo(edge: .top) }
            }
    }
}

extension View {
    func scrollsToTopOnDockTap(_ tab: AppTab) -> some View { modifier(ScrollTopOnDockTap(tab: tab)) }
}

struct AppShell: View {
    @ObservedObject var model: AppModel
    @Binding var tab: AppTab
    @Binding var ledgerSheet: LedgerSheet?
    @Binding var exportFile: ExportFile?
    @Binding var showImporter: Bool
    @StateObject private var scrollTop = ScrollTopCenter()
    @State private var visited: Set<AppTab> = [.home]
    @State private var reportScope = 0
    @State private var reportsFrom: AppTab?

    private let pages: [AppTab] = [.home, .ledger, .personal, .reminders, .reports, .cards]
    static let dockClearance: CGFloat = 70

    var body: some View {
        ZStack(alignment: .bottom) {
            AppBackground()
            ForEach(pages, id: \.self) { p in
                if visited.contains(p) {
                    page(p)
                        .contentMargins(.bottom, Self.dockClearance, for: .scrollContent)
                        .opacity(tab == p ? 1 : 0)
                        .allowsHitTesting(tab == p)
                        .accessibilityHidden(tab != p)
                        .zIndex(tab == p ? 1 : 0)
                }
            }
            Dock(model: model, tab: $tab, reportsFrom: reportsFrom, onReselect: { scrollTop.fire($0) }, onReports: openReports)
                .zIndex(10)
        }
        .environmentObject(scrollTop)
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .onChange(of: tab) { _, t in visited.insert(t) }
        .animation(.easeInOut(duration: 0.28), value: tab)
    }

    /// web: the reports page opens on the section of the page you were on
    private func openReports() {
        switch tab {
        case .ledger: reportScope = 1
        case .personal: reportScope = 2
        case .reminders: reportScope = 4
        case .reports: scrollTop.fire(.reports); return
        default: reportScope = 0
        }
        reportsFrom = tab
        visited.insert(.reports)
        tab = .reports
    }

    @ViewBuilder
    private func page(_ p: AppTab) -> some View {
        switch p {
        case .home:
            NavigationStack {
                HomeView(model: model, tab: $tab, ledgerSheet: $ledgerSheet, exportFile: $exportFile, showImporter: $showImporter)
            }
        case .ledger: NavigationStack { LedgerHomeView(model: model, sheet: $ledgerSheet) }
        case .personal: NavigationStack { PersonalView(model: model) }
        case .reminders: NavigationStack { RemindersView(model: model) }
        case .reports: NavigationStack { ReportsView(model: model, scope: $reportScope) }
        case .cards: NavigationStack { CardsView(model: model) }
        }
    }
}

/// Dock icon packs — chosen in Settings › ظاهر (with a live preview).
enum DockIcons: String, CaseIterable, Identifiable {
    case project, ledgerBook, finance, minimal
    var id: String { rawValue }
    static let key = "look.dockIcons"
    var title: String {
        switch self {
        case .project: return "پروژه و ساختمان"
        case .ledgerBook: return "دفتر و سند"
        case .finance: return "مالی"
        case .minimal: return "مینیمال"
        }
    }
    /// home, ledger, personal, cards, reminders, reports
    func icon(_ t: AppTab) -> String {
        switch self {
        case .project:
            return [.home: "house", .ledger: "building.2", .personal: "person", .cards: "creditcard",
                    .reminders: "bell", .reports: "chart.pie"][t] ?? "circle"
        case .ledgerBook:
            return [.home: "house", .ledger: "book.closed", .personal: "person.text.rectangle", .cards: "wallet.pass",
                    .reminders: "calendar.badge.clock", .reports: "chart.bar.xaxis"][t] ?? "circle"
        case .finance:
            return [.home: "square.grid.2x2", .ledger: "list.bullet.rectangle", .personal: "person.crop.circle",
                    .cards: "creditcard", .reminders: "clock", .reports: "chart.line.uptrend.xyaxis"][t] ?? "circle"
        case .minimal:
            return [.home: "circle.grid.2x2", .ledger: "doc.text", .personal: "person", .cards: "rectangle.stack",
                    .reminders: "bell", .reports: "chart.bar"][t] ?? "circle"
        }
    }
}

struct Dock: View {
    @ObservedObject var model: AppModel
    @Binding var tab: AppTab
    /// the page «گزارش‌ها» was opened from — stays lit and joined to the reports button
    let reportsFrom: AppTab?
    let onReselect: (AppTab) -> Void
    let onReports: () -> Void
    @Environment(\.theme) private var t
    @AppStorage(DockIcons.key) private var packRaw = DockIcons.project.rawValue
    @Namespace private var glassNS

    private let items: [AppTab] = [.home, .ledger, .personal, .cards, .reminders]
    @State private var pressed: Int?
    @State private var menu: AppTab?
    @State private var holdTask: Task<Void, Never>?
    @State private var menuOpenedByHold = false
    @State private var reportsPressed = false
    @State private var holdHaptic = UIImpactFeedbackGenerator(style: .medium)

    private let height: CGFloat = 62
    private let reportsSide: CGFloat = 62
    private var pack: DockIcons { DockIcons(rawValue: packRaw) ?? .project }

    private var selectedIndex: Int? {
        if tab == .reports, let f = reportsFrom { return items.firstIndex(of: f) }
        return items.firstIndex(of: tab)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            if menu != nil {
                Color.black.opacity(0.001)
                    .ignoresSafeArea()
                    .onTapGesture { closeMenu() }
            }
            VStack(spacing: 10) {
                if let m = menu { miniDock(m).transition(.scale(scale: 0.85, anchor: .bottom).combined(with: .opacity)) }
                GlassEffectContainer(spacing: 8) {
                    HStack(spacing: 0) {
                        mainCapsule
                        Color.clear.frame(width: 12, height: 1)
                        reportsButton
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 4)
        }
        .animation(.spring(duration: 0.32, bounce: 0.25), value: menu)
        .animation(.spring(duration: 0.5, bounce: 0.3), value: tab == .reports)
    }

    // MARK: main capsule — one gesture, slot chosen by position

    private var mainCapsule: some View {
        GeometryReader { g in
            let slotW = (g.size.width - 10) / CGFloat(items.count)
            let lensIndex = pressed ?? selectedIndex
            ZStack(alignment: .topLeading) {
                if let li = lensIndex {
                    Capsule()
                        .fill(t.accent.opacity(pressed != nil ? 0.20 : (tab == .reports ? 0.22 : 0.14)))
                        .frame(width: slotW, height: height - 10)
                        .offset(x: 5 + CGFloat(items.count - 1 - li) * slotW, y: 5)
                        .animation(.spring(duration: 0.3, bounce: 0.22), value: li)
                }
                HStack(spacing: 0) {
                    ForEach(Array(items.enumerated().reversed()), id: \.offset) { i, item in
                        let on = i == selectedIndex
                        Image(systemName: pack.icon(item))
                            .symbolVariant(on ? .fill : .none)
                            // the page «گزارش‌ها» was opened from breathes in step with the reports button
                            .symbolEffect(.breathe.plain.wholeSymbol, options: .repeating.speed(0.8), isActive: on && tab == .reports)
                            .font(.system(size: 20, weight: on ? .semibold : .regular))
                            .foregroundStyle(on ? t.accent : t.ink.opacity(0.72))
                            .scaleEffect(pressed == i ? 1.18 : 1)
                            .animation(.spring(duration: 0.25, bounce: 0.4), value: pressed)
                            .frame(width: slotW, height: height - 10)
                            .accessibilityElement()
                            .accessibilityLabel(Self.title(item))
                            .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
                            .accessibilityAction { select(item) }
                    }
                }
                .padding(5)
            }
            .environment(\.layoutDirection, .leftToRight)
            .contentShape(Capsule())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { v in
                        if v.location.y < -40 || v.location.y > height + 30 { pressed = nil; holdTask?.cancel(); return }
                        let i = slot(at: v.location.x, slotW: slotW)
                        if pressed == nil {
                            holdHaptic.prepare()
                            UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.6)
                            startHold(for: i)
                        } else if i != pressed {
                            UISelectionFeedbackGenerator().selectionChanged()
                            startHold(for: i)
                        }
                        pressed = i
                    }
                    .onEnded { _ in
                        holdTask?.cancel()
                        defer { pressed = nil }
                        if menuOpenedByHold { menuOpenedByHold = false; return }
                        guard let i = pressed else { return }
                        if menu != nil { closeMenu() }
                        select(items[i])
                    }
            )
        }
        .frame(height: height)
        .glassEffect(.regular, in: Capsule())
        .glassEffectID("main", in: glassNS)
    }

    private func slot(at x: CGFloat, slotW: CGFloat) -> Int {
        let fromLeft = Int(((x - 5) / max(1, slotW)).rounded(.down))
        let clamped = min(items.count - 1, max(0, fromLeft))
        return items.count - 1 - clamped          // RTL
    }

    private func startHold(for i: Int) {
        holdTask?.cancel()
        guard items[i] == .ledger, model.accounts.count > 1 else { return }
        holdTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled, pressed == i else { return }
            holdHaptic.impactOccurred()
            menuOpenedByHold = true
            menu = .ledger
        }
    }

    private func select(_ new: AppTab) {
        guard new != tab else { onReselect(new); return }
        UISelectionFeedbackGenerator().selectionChanged()
        tab = new
    }

    private func closeMenu() { menu = nil }

    static func title(_ t: AppTab) -> String {
        switch t {
        case .home: return "خانه"
        case .ledger: return "دفتر حساب"
        case .personal: return "شخصی"
        case .reminders: return "یادآوری‌ها"
        case .reports: return "گزارش‌ها"
        case .cards: return "کیف کارت"
        }
    }

    // MARK: reports — separate round button

    private var reportsButton: some View {
        let on = tab == .reports
        return Image(systemName: pack.icon(.reports))
            .symbolVariant(on ? .fill : .none)
            .symbolEffect(.breathe.plain.wholeSymbol, options: .repeating.speed(0.8), isActive: on && reportsFrom != nil)
            .font(.system(size: 20, weight: on ? .semibold : .regular))
            .foregroundStyle(on ? t.accent : t.ink.opacity(0.72))
            .scaleEffect(reportsPressed ? 1.15 : 1)
            .frame(width: reportsSide, height: reportsSide)
            .background { if on { Circle().fill(t.accent.opacity(0.18)).padding(5) } }
            .contentShape(Circle())
            .glassEffect(.regular, in: Circle())
            .glassEffectID("reports", in: glassNS)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !reportsPressed { reportsPressed = true; UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.6) }
                    }
                    .onEnded { v in
                        reportsPressed = false
                        guard abs(v.translation.width) < 40, abs(v.translation.height) < 40 else { return }
                        if menu != nil { closeMenu() }
                        UISelectionFeedbackGenerator().selectionChanged()
                        onReports()
                    }
            )
            .animation(.spring(duration: 0.25, bounce: 0.4), value: reportsPressed)
            .accessibilityElement()
            .accessibilityLabel("گزارش‌ها")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { onReports() }
    }

    // MARK: mini dock (hold on «دفتر حساب»: switch ledger)

    @ViewBuilder
    private func miniDock(_ m: AppTab) -> some View {
        let active = model.activeAccountId
        HStack(spacing: 6) {
            ForEach(model.accounts) { a in
                Button {
                    Haptics.tap()
                    model.selectAccount(a.id)
                    closeMenu()
                    if tab != .ledger { tab = .ledger }
                } label: {
                    Text(a.name)
                        .font(AppFont.bold(13))
                        .foregroundStyle(a.id == active ? t.onAccent : t.ink)
                        .lineLimit(1)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background { if a.id == active { Capsule().fill(t.accent) } }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .glassEffect(.regular, in: Capsule())
    }
}
