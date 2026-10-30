import SwiftUI
import HesabCore

// Two-part Liquid Glass dock (like the web app): the four main pages in one capsule, «گزارش‌ها» as its own
// round button beside it. Hold «خانه» → کیف کارت; hold «دفتر حساب» → switch ledger (with haptics).
// Pages stay alive in a ZStack and cross-fade into each other (the old one fades out while the new one
// fades in, over the same background — no white flash).

enum AppTab: Hashable { case home, ledger, personal, reminders, reports, cards }

struct AppShell: View {
    @ObservedObject var model: AppModel
    @Binding var tab: AppTab
    @Binding var ledgerSheet: LedgerSheet?
    @Binding var exportFile: ExportFile?
    @Binding var showImporter: Bool
    @State private var visited: Set<AppTab> = [.home]

    private let pages: [AppTab] = [.home, .ledger, .personal, .reminders, .reports, .cards]

    var body: some View {
        ZStack {
            AppBackground()
            ForEach(pages, id: \.self) { p in
                if visited.contains(p) {
                    page(p)
                        .opacity(tab == p ? 1 : 0)
                        .allowsHitTesting(tab == p)
                        .accessibilityHidden(tab != p)
                        .zIndex(tab == p ? 1 : 0)
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Dock(model: model, tab: $tab)
        }
        .onChange(of: tab) { _, t in visited.insert(t) }
        .animation(.easeInOut(duration: 0.3), value: tab)
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
        case .reports: NavigationStack { ReportsView(model: model) }
        case .cards: NavigationStack { CardsView(model: model) }
        }
    }
}

struct Dock: View {
    @ObservedObject var model: AppModel
    @Binding var tab: AppTab
    @Environment(\.theme) private var t
    @Namespace private var lens

    private let main: [(AppTab, String, String)] = [
        (.home, "خانه", "house.fill"), (.ledger, "دفتر حساب", "book.pages.fill"),
        (.personal, "شخصی", "person.crop.circle.fill"), (.reminders, "یادآوری‌ها", "bell.fill")
    ]

    var body: some View {
        GlassEffectContainer(spacing: 14) {
            HStack(spacing: 12) {
                HStack(spacing: 0) {
                    ForEach(main, id: \.0) { item in
                        dockButton(item.0, item.1, item.2)
                    }
                }
                .padding(5)
                .glassEffect(.regular.interactive(), in: Capsule())

                // reports: its own round button, apart from the rest
                Button {
                    select(.reports)
                } label: {
                    Image(systemName: "chart.bar.xaxis")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(tab == .reports ? t.accent : t.ink)
                        .frame(width: 62, height: 62)
                        .background {
                            if tab == .reports { Circle().fill(t.accent.opacity(0.14)).padding(5) }
                        }
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: Circle())
                .accessibilityLabel("گزارش‌ها")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 2)
    }

    private func select(_ new: AppTab) {
        guard new != tab else { return }
        UISelectionFeedbackGenerator().selectionChanged()
        tab = new
    }

    @ViewBuilder
    private func dockButton(_ item: AppTab, _ title: String, _ icon: String) -> some View {
        if item == .home || item == .ledger {
            dockButtonBody(item, title, icon).contextMenu { menu(for: item) }
        } else {
            dockButtonBody(item, title, icon)
        }
    }

    private func dockButtonBody(_ item: AppTab, _ title: String, _ icon: String) -> some View {
        let on = tab == item || (item == .home && tab == .cards)
        Button {
            select(item)
        } label: {
            VStack(spacing: 3) {
                Image(systemName: icon).font(.system(size: 19, weight: .semibold))
                Text(title).font(AppFont.medium(11)).lineLimit(1).minimumScaleFactor(0.8)
            }
            .foregroundStyle(on ? t.accent : t.ink)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background {
                if on {
                    Capsule().fill(t.accent.opacity(0.13))
                        .matchedGeometryEffect(id: "lens", in: lens)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .animation(.spring(duration: 0.35, bounce: 0.2), value: tab)
    }

    @ViewBuilder
    private func menu(for item: AppTab) -> some View {
        switch item {
        case .home:
            Button { select(.cards) } label: { Label("کیف کارت", systemImage: "creditcard.fill") }
        case .ledger:
            let active = model.activeAccountId
            ForEach(model.accounts) { a in
                Button {
                    model.selectAccount(a.id)
                    select(.ledger)
                } label: {
                    if a.id == active { Label(a.name, systemImage: "checkmark") } else { Text(a.name) }
                }
            }
        default:
            EmptyView()
        }
    }
}
