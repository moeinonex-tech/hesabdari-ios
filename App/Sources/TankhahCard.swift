import SwiftUI
import HesabCore

// Tankhah by party: one colour per party (the same in the ledger card and in the PDF). The four largest parties get the
// four main report colours (the first four of the category report); every party after that gets its own colour picked
// from its name (looks random, but the same person always keeps the same colour), kept apart from the colours already
// used. Rows without a party are grey.

enum TankhahPalette {
    static let main = ["#2F5D8A", "#3E8E7E", "#D08C3A", "#8A5A9E"]
    static let none = "#AEB6C2"
    static let noParty = "بدون طرف حساب"

    /// colours for parties in rank order (biggest first)
    static func hexes(_ names: [String]) -> [String] {
        var out: [String] = []
        var usedHues: [Double] = [210, 168, 33, 284]          // the four main colours, roughly
        var rank = 0
        for n in names {
            if n == noParty { out.append(none); continue }
            if rank < main.count { out.append(main[rank]); rank += 1; continue }
            rank += 1
            var h = Double(fnv(n) % 360)
            var tries = 0
            while tries < 12, usedHues.contains(where: { min(abs($0 - h), 360 - abs($0 - h)) < 30 }) {
                h = (h + 47).truncatingRemainder(dividingBy: 360); tries += 1
            }
            usedHues.append(h)
            let f = fnv(n + "·")
            out.append(hsl(h, 0.42 + Double(f % 16) / 100, 0.40 + Double((f / 16) % 10) / 100))
        }
        return out
    }

    static func color(_ hex: String) -> Color { Color.hex(UInt32(hex.dropFirst(), radix: 16) ?? 0x8A8F99) }

    /// stable string hash (Swift's own hash changes on every launch)
    private static func fnv(_ s: String) -> UInt32 {
        var h: UInt32 = 2_166_136_261
        for u in s.unicodeScalars { h = (h ^ u.value) &* 16_777_619 }
        return h
    }

    private static func hsl(_ h: Double, _ s: Double, _ l: Double) -> String {
        let c = (1 - abs(2 * l - 1)) * s
        let x = c * (1 - abs((h / 60).truncatingRemainder(dividingBy: 2) - 1))
        let m = l - c / 2
        let (r, g, b): (Double, Double, Double)
        switch h {
        case ..<60: (r, g, b) = (c, x, 0)
        case ..<120: (r, g, b) = (x, c, 0)
        case ..<180: (r, g, b) = (0, c, x)
        case ..<240: (r, g, b) = (0, x, c)
        case ..<300: (r, g, b) = (x, 0, c)
        default: (r, g, b) = (c, 0, x)
        }
        func hx(_ v: Double) -> String { String(format: "%02X", Int(((v + m) * 255).rounded())) }
        return "#" + hx(r) + hx(g) + hx(b)
    }

    /// how a tankhah was received, in a few words
    static func method(_ r: [String: JSONValue], state st: [String: JSONValue]) -> String {
        switch r["payMethod"]?.stringValue {
        case "transfer":
            let card = (st["cards"]?.arrayValue ?? []).first { $0["id"]?.idString == r["cardId"]?.idString && r["cardId"]?.idString != nil }
            let bank = card?["bankName"]?.stringValue ?? ""
            return bank.isEmpty ? "حواله" : "حواله · " + bank
        case "check":
            let chk = (st["reminderChecks"]?.arrayValue ?? []).first { $0["id"]?.idString == r["checkId"]?.idString && r["checkId"]?.idString != nil }
            let num = chk?["checkNumber"]?.idString ?? ""
            return num.isEmpty ? "چک" : "چک · " + Money.persianDigits(num)
        default:
            return "نقدی"
        }
    }
}

private func pct(_ v: Int, _ of: Int) -> String {
    let p = of > 0 ? Double(v) / Double(of) * 100 : 0
    return p > 0 && p < 1 ? "زیر ۱٪" : Money.persianDigits(Money.jsRound(p)) + "٪"
}

// MARK: - ledger card

/// Folded: the total, one bar split by party, and the largest parties. A tap unfolds the party list: five parties
/// visible, the rest scroll inside the card; a party opens its own tankhah rows in place.
struct TankhahPartyCard: View {
    @ObservedObject var model: AppModel
    let accountId: String
    var onFull: () -> Void = {}
    @State private var open = false
    @State private var party: String?
    @Environment(\.theme) private var t
    private let visible = 5
    private let rowH: CGFloat = 58
    private let entryH: CGFloat = 40

    var body: some View {
        let rep = AccountOps.tankhahPartyReport(model.state, accountId: accountId)
        let colors = TankhahPalette.hexes(rep.groups.map(\.name)).map(TankhahPalette.color)
        let rows = rep.groups.reduce(0) { $0 + $1.rows.count }
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    SectionTitle(text: "تنخواه به تفکیک طرف حساب")
                    Text(Fmt.count(rep.groups.count) + " طرف حساب · " + Fmt.count(rows) + " ردیف")
                        .font(AppFont.caption).foregroundStyle(t.soft)
                }
                Spacer()
                CardPDFButton(id: "tankhah.pdf") { await model.tankhahPartyPDF(accountId: accountId) }
                if !rep.groups.isEmpty {
                    Image(systemName: "chevron.down").font(.system(size: 12, weight: .bold)).foregroundStyle(t.soft)
                        .rotationEffect(.degrees(open ? 180 : 0))
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(Money.persianDigits(Money.format(rep.total))).font(AppFont.heavy(26)).foregroundStyle(t.success)
                        .contentTransition(.numericText(value: Double(rep.total)))
                    Text("تومان تنخواه دریافتی").font(AppFont.caption).foregroundStyle(t.soft)
                }
                strip(rep.groups, colors, total: rep.total)
                if !open { topParties(rep.groups, colors, total: rep.total) }
            }
            .contentShape(Rectangle())
            .onTapGesture { toggle(rep.groups.isEmpty) }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("tankhah.card")

            if open { list(rep.groups, colors, total: rep.total) }
        }
        .glassCard()
    }

    private func toggle(_ empty: Bool) {
        guard !empty else { return }
        Haptics.tap()
        withAnimation(.spring(duration: 0.45, bounce: 0.22)) {
            open.toggle()
            if !open { party = nil }
        }
    }

    /// one bar for the whole, a segment per party in its colour
    private func strip(_ gs: [TankhahPartyGroup], _ colors: [Color], total: Int) -> some View {
        GeometryReader { g in
            let parts = gs.filter { $0.total > 0 }
            let gaps = CGFloat(max(0, parts.count - 1)) * 2
            HStack(spacing: 2) {
                ForEach(Array(gs.enumerated()), id: \.element.name) { i, p in
                    if p.total > 0 {
                        RoundedRectangle(cornerRadius: 3, style: .continuous).fill(colors[i])
                            .frame(width: max(3, (g.size.width - gaps) * CGFloat(p.total) / CGFloat(max(1, total))))
                    }
                }
            }
        }
        .frame(height: 12)
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
    }

    private func topParties(_ gs: [TankhahPartyGroup], _ colors: [Color], total: Int) -> some View {
        HStack(spacing: 12) {
            ForEach(Array(gs.prefix(3).enumerated()), id: \.element.name) { i, p in
                HStack(spacing: 5) {
                    Circle().fill(colors[i]).frame(width: 8, height: 8)
                    Text(p.name).font(AppFont.medium(12)).foregroundStyle(t.ink).lineLimit(1)
                    Text(pct(p.total, total)).font(AppFont.bold(11)).foregroundStyle(t.soft)
                }
            }
            if gs.count > 3 {
                Text("+" + Fmt.count(gs.count - 3)).font(AppFont.bold(11)).foregroundStyle(t.soft)
            }
            Spacer(minLength: 0)
        }
    }

    private func listHeight(_ gs: [TankhahPartyGroup]) -> CGFloat {
        let extra = gs.first { $0.name == party }.map { CGFloat($0.rows.count) * entryH + 8 } ?? 0
        return min(CGFloat(gs.count) * rowH + extra, CGFloat(visible) * rowH + (gs.count > visible ? rowH * 0.45 : 0))
    }

    private func list(_ gs: [TankhahPartyGroup], _ colors: [Color], total: Int) -> some View {
        let mx = max(1, gs.map(\.total).max() ?? 1)
        let scrolls = CGFloat(gs.count) * rowH > CGFloat(visible) * rowH || party != nil
        return VStack(spacing: 6) {
            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    ForEach(Array(gs.enumerated()), id: \.element.name) { i, p in
                        partyRow(p, colors[i], total: total, max: mx)
                        if party == p.name { entries(p, colors[i]) }
                    }
                }
            }
            .scrollIndicators(scrolls ? .visible : .hidden)
            .frame(height: listHeight(gs))
            if gs.count > visible {
                Text("برای دیدن بقیه‌ی طرف حساب‌ها داخل کارت بکشید").font(AppFont.caption).foregroundStyle(t.soft.opacity(0.8))
                    .frame(maxWidth: .infinity)
            }
            Button { Haptics.tap(); onFull() } label: {
                Label("گزارش کامل", systemImage: "list.bullet.rectangle").font(AppFont.medium(13)).frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)
        }
        .transition(.asymmetric(insertion: .move(edge: .top).combined(with: .opacity), removal: .opacity.animation(.easeOut(duration: 0.15))))
    }

    private func partyRow(_ p: TankhahPartyGroup, _ c: Color, total: Int, max mx: Int) -> some View {
        Button {
            Haptics.tap()
            withAnimation(.spring(duration: 0.4, bounce: 0.2)) { party = party == p.name ? nil : p.name }
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Circle().fill(c).frame(width: 9, height: 9)
                    Text(p.name).font(AppFont.medium(14)).foregroundStyle(t.ink).lineLimit(1)
                    Text(Fmt.count(p.rows.count) + " مورد").font(AppFont.caption).foregroundStyle(t.soft)
                    Spacer(minLength: 6)
                    Text(Money.persianDigits(Money.format(p.total))).font(AppFont.bold(13)).foregroundStyle(t.ink)
                    Text(pct(p.total, total)).font(AppFont.bold(11)).foregroundStyle(t.soft).frame(minWidth: 32, alignment: .trailing)
                    Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold)).foregroundStyle(t.soft)
                        .rotationEffect(.degrees(party == p.name ? 180 : 0))
                }
                GeometryReader { g in
                    Capsule().fill(t.ink.opacity(0.06)).overlay(alignment: .leading) {
                        Capsule().fill(LinearGradient(colors: [c.opacity(0.6), c], startPoint: .leading, endPoint: .trailing))
                            .frame(width: Swift.max(6, g.size.width * Swift.max(0.04, Double(p.total) / Double(mx))))
                    }
                }
                .frame(height: 6)
            }
            .frame(height: rowH)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("tankhah.party." + p.name)
    }

    private func entries(_ p: TankhahPartyGroup, _ c: Color) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(p.rows.reversed().enumerated()), id: \.offset) { _, r in
                let d = ImportAnalyzer.date(r["date"])
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(nonEmpty(r["desc"]?.stringValue) ?? TankhahPalette.method(r, state: model.state))
                            .font(AppFont.regular(13)).foregroundStyle(t.ink).lineLimit(1)
                        Text(Money.persianDigits("\(d.jy)/\(d.jm)/\(d.jd)") + " · " + TankhahPalette.method(r, state: model.state))
                            .font(AppFont.caption).foregroundStyle(t.soft).lineLimit(1)
                    }
                    Spacer(minLength: 6)
                    Text(Money.persianDigits(Money.format(ImportAnalyzer.toman(.object(r))))).font(AppFont.medium(13)).foregroundStyle(t.ink)
                }
                .frame(height: entryH)
            }
        }
        .padding(.leading, 10).padding(.bottom, 8)
        .overlay(alignment: .leading) { Capsule().fill(c.opacity(0.5)).frame(width: 2.5).padding(.vertical, 4) }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private func nonEmpty(_ s: String?) -> String? {
        guard let s, !s.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return s
    }
}

// MARK: - PDF: summary + split bar + one row per party, then every tankhah grouped under its party

extension ReportHTML {
    static func tankhahReport(account: String, date: String, groups gs: [TankhahPartyGroup], total: Int,
                              method: ([String: JSONValue]) -> String, rowDate: (JSONValue?) -> String) -> String {
        func amt(_ v: Int) -> String { Money.persianDigits(Money.format(v)) }
        func w(_ v: Int, _ of: Int) -> String { String(format: "%.2f", max(1.5, of > 0 ? Double(v) / Double(of) * 100 : 0)) }
        let colors = TankhahPalette.hexes(gs.map(\.name))
        let rows = gs.reduce(0) { $0 + $1.rows.count }

        var h = "<!doctype html><html lang=\"fa\" dir=\"rtl\"><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=595.28, initial-scale=1, maximum-scale=1, user-scalable=no\"><style>" + css + "</style></head><body>"
        h += "<div class=\"hdr\"><div><div class=\"title\">گزارش تنخواه به تفکیک طرف حساب — «" + esc(account) + "»</div><div class=\"sub\">تنخواه دریافتی — تا تاریخ "
            + esc(date) + " — مبالغ به تومان</div></div></div>"
        guard let top = gs.first else { return h + "<div class=\"empty\">هنوز تنخواهی برای این پروژه ثبت نشده</div></body></html>" }

        h += "<div class=\"cx-kpis\"><div class=\"cx-kpi\"><div class=\"k\">جمع کل تنخواه دریافتی (تومان)</div><div class=\"v main tk\">" + amt(total) + "</div></div>"
        h += "<div class=\"cx-kpi\"><div class=\"k\">طرف حساب / ردیف</div><div class=\"v\">" + Money.persianDigits(gs.count)
            + " <small>/ " + Money.persianDigits(rows) + "</small></div></div>"
        let single = gs.count == 1
        h += single
            ? "<div class=\"cx-kpi\"><div class=\"k\">طرف حساب</div><div class=\"v nm\">" + esc(top.name) + "</div></div></div>"
            : "<div class=\"cx-kpi\"><div class=\"k\">بیشترین سهم</div><div class=\"v nm\">" + esc(top.name) + " — " + pct(top.total, total) + "</div></div></div>"

        // the split (only when there is something to split): one bar, then one row per party (the rows are the legend of the bar)
        if !single {
            h += "<div class=\"cx-mix tkmix\"><div class=\"t\">سهم هر طرف حساب از کل تنخواه</div><div class=\"cx-strip\">"
            for (i, g) in gs.enumerated() where g.total > 0 { h += "<i style=\"width:" + w(g.total, total) + "%;background:" + colors[i] + "\"></i>" }
            h += "</div></div>"
            let mx = max(1, gs.map(\.total).max() ?? 1)
            h += "<div class=\"cx-th head\"><span></span><span>طرف حساب</span><span>سهم از کل</span><span class=\"r\">مبلغ (تومان)</span><span class=\"r\">درصد</span></div>"
            for (i, g) in gs.enumerated() {
                h += "<div class=\"cx-row\"><span class=\"cx-dot\" style=\"background:" + colors[i] + "\"></span><span class=\"nm\">" + esc(g.name)
                    + " <span class=\"cnt\">" + Money.persianDigits(g.rows.count) + " مورد</span></span><div class=\"cx-bar\"><i style=\"width:" + w(g.total, mx)
                    + "%;background:" + colors[i] + "\"></i></div><span class=\"am\">" + amt(g.total) + "</span><span class=\"pc\">" + pct(g.total, total) + "</span></div>"
            }
        }

        // details: one column header for the whole list, then each party as a coloured band with its rows
        h += "<div class=\"head tk-cols\"><div class=\"c-num\">#</div><div class=\"c-date\">تاریخ</div><div class=\"c-sub\">روش دریافت</div>"
            + "<div class=\"c-desc\">توضیحات</div><div class=\"c-amt\">مبلغ (تومان)</div></div>"
        var n = 0
        for (i, g) in gs.enumerated() {
            h += "<div class=\"cx-grp head tk-band\" style=\"--c:" + colors[i] + "\"><span class=\"cx-dot\" style=\"background:" + colors[i] + "\"></span><span>"
                + esc(g.name) + "<span class=\"cnt\">" + Money.persianDigits(g.rows.count) + " مورد</span></span><span class=\"pc\">"
                + pct(g.total, total) + "</span><span class=\"am\">" + amt(g.total) + "</span></div>"
            for r in g.rows {
                n += 1
                let desc = r["desc"]?.stringValue.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 } ?? "—"
                h += "<div class=\"row" + (n % 2 == 1 ? " alt" : "") + "\"><div class=\"c-num\">" + Money.persianDigits(n) + "</div><div class=\"c-date\">"
                    + rowDate(r["date"]) + "</div><div class=\"c-sub\">" + esc(method(r)) + "</div><div class=\"c-desc\">" + esc(desc)
                    + "</div><div class=\"c-amt\">" + amt(ImportAnalyzer.toman(.object(r))) + "</div></div>"
            }
        }
        h += "<div class=\"total\"><div class=\"lbl\">جمع کل تنخواه دریافتی (تومان)</div><div class=\"amt\">" + amt(total) + "</div></div>"
        return h + "</body></html>"
    }
}
