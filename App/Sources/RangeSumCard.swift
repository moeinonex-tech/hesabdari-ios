import SwiftUI
import UIKit
import HesabCore

/// Ledger card «جمع ردیف‌ها»: the sum of the rows between two row numbers (the # shown on every row), with nothing
/// calculated on top — no commission. Ordinary expenses are the main figure; rewards are added in (they are expenses
/// too, marked); commission payments and تنخواه are shown apart and are not in the sum.
struct RangeSumCard: View {
    @ObservedObject var model: AppModel
    let accountId: String
    @Environment(\.theme) private var t
    @State private var from = 1
    @State private var to = 1
    @State private var loaded = false
    @State private var copied = false

    var body: some View {
        let count = LedgerOps.rowCount(model.state, accountId: accountId)
        let s = LedgerOps.rangeSum(model.state, accountId: accountId, from: from, to: to)
        let total = s.expenses + s.rewards
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    SectionTitle(text: "جمع ردیف‌ها")
                    Text("بدون محاسبه‌ی کمیسیون · شماره‌ها همان # کنار هر ردیف")
                        .font(AppFont.caption).foregroundStyle(t.soft)
                }
                Spacer()
                Button { copy(s, total) } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc").font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(t.accent).frame(width: 32, height: 28).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("کپی نتیجه")
                .disabled(count == 0)
            }

            if count == 0 {
                Text("هنوز ردیفی در این دفتر نیست").font(AppFont.regular(13)).foregroundStyle(t.soft)
            } else {
                HStack(spacing: 10) {
                    bound("از ردیف", value: $from, count: count, id: "range.from")
                    Image(systemName: "arrow.left").font(.system(size: 13, weight: .bold)).foregroundStyle(t.soft)
                    bound("تا ردیف", value: $to, count: count, id: "range.to")
                }

                HScroll {
                    HStack(spacing: 8) {
                        preset("همه", 1, count)
                        if let f = LedgerOps.openCommissionRows(model.state, accountId: accountId).first, f.num > 1 {
                            preset("از بعد از آخرین تسویه", f.num, count)
                        }
                        if count >= 10 { preset("۱۰ ردیف آخر", count - 9, count) }
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(rangeTitle(s))
                        .font(AppFont.regular(13)).foregroundStyle(t.soft)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(Money.persianDigits(Money.format(total)))
                            .font(AppFont.heavy(28)).foregroundStyle(t.accent2)
                            .contentTransition(.numericText(value: Double(total)))
                            .accessibilityIdentifier("range.total")
                        Text("تومان").font(AppFont.regular(13)).foregroundStyle(t.soft)
                    }
                    Text(descLine(s))
                        .font(AppFont.caption).foregroundStyle(t.soft).lineLimit(1)
                }

                VStack(spacing: 6) {
                    line("هزینه‌ها", s.expenses, s.expenseCount, t.ink, note: nil)
                    if s.rewardCount > 0 { line("پاداش", s.rewards, s.rewardCount, t.reward, note: "داخل جمع") }
                    if s.commissionCount > 0 { line("پرداخت کمیسیون", s.commissionPaid, s.commissionCount, .purple, note: "جدا، داخل جمع نیست") }
                    if s.tankhahCount > 0 { line("تنخواه دریافتی", s.tankhah, s.tankhahCount, t.success, note: "جدا، داخل جمع نیست") }
                }
                .padding(10)
                .background(t.ink.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .glassCard()
        .onAppear {
            guard !loaded else { return }
            loaded = true
            from = 1; to = max(1, count)
        }
        .onChange(of: count) { old, new in
            // a new row: a range that ended at the last row keeps ending there
            if to == old { to = max(1, new) }
            from = min(max(1, from), max(1, new)); to = min(max(1, to), max(1, new))
        }
    }

    private func bound(_ title: String, value: Binding<Int>, count: Int, id: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(AppFont.caption).foregroundStyle(t.soft)
            HStack(spacing: 6) {
                step("minus", id: id + ".minus") { value.wrappedValue = max(1, value.wrappedValue - 1) }
                TextField("", text: Binding(
                    get: { Money.persianDigits(value.wrappedValue) },
                    set: { s in
                        if let n = Int(SearchEngine.latinDigits(s).filter(\.isNumber)) { value.wrappedValue = min(max(1, n), count) }
                    }))
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.center)
                    .font(AppFont.bold(17))
                    .frame(minWidth: 44)
                    .accessibilityIdentifier(id)
                step("plus", id: id + ".plus") { value.wrappedValue = min(count, value.wrappedValue + 1) }
            }
            .padding(.horizontal, 6).padding(.vertical, 6)
            .background(t.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .frame(maxWidth: .infinity)
    }

    private func step(_ icon: String, id: String, _ action: @escaping () -> Void) -> some View {
        Button { Haptics.tap(); withAnimation(.snappy) { action() } } label: {
            Image(systemName: icon).font(.system(size: 12, weight: .bold)).foregroundStyle(t.accent)
                .frame(width: 28, height: 28).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .buttonRepeatBehavior(.enabled)
        .accessibilityIdentifier(id)
    }

    private func preset(_ title: String, _ a: Int, _ b: Int) -> some View {
        let on = from == a && to == b
        return Button {
            Haptics.tap()
            withAnimation(.snappy) { from = a; to = b }
        } label: {
            Text(title).font(AppFont.medium(12))
                .padding(.horizontal, 10).padding(.vertical, 6)
                .foregroundStyle(on ? Color.white : t.ink)
                .background(on ? AnyShapeStyle(t.accent) : AnyShapeStyle(t.accent.opacity(0.08)), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func line(_ title: String, _ v: Int, _ n: Int, _ c: Color, note: String?) -> some View {
        HStack(spacing: 6) {
            Circle().fill(c).frame(width: 7, height: 7)
            Text(title).font(AppFont.medium(13)).foregroundStyle(t.ink)
            Text(Money.persianDigits(n) + " ردیف").font(AppFont.caption).foregroundStyle(t.soft)
            if let note { Text("· " + note).font(AppFont.caption).foregroundStyle(t.soft) }
            Spacer(minLength: 6)
            Text(Money.persianDigits(Money.format(v))).font(AppFont.bold(13)).foregroundStyle(t.ink)
        }
    }

    private func rangeTitle(_ s: RowRangeSum) -> String {
        let a: String = Money.persianDigits(s.from), b: String = Money.persianDigits(s.to)
        return "جمع هزینه‌های ردیف " + a + " تا " + b
    }

    private func descLine(_ s: RowRangeSum) -> String {
        let n: String = Money.persianDigits(s.rowCount)
        let ends: String = "«" + s.firstDesc + "» تا «" + s.lastDesc + "»"
        return ends + " · " + n + " ردیف"
    }

    private func copy(_ s: RowRangeSum, _ total: Int) {
        let a: String = Money.persianDigits(s.from), b: String = Money.persianDigits(s.to)
        let sum: String = Money.persianDigits(Money.format(total))
        var lines: [String] = ["جمع ردیف " + a + " تا " + b + ": " + sum + " تومان"]
        if s.rewardCount > 0 { lines.append("شامل پاداش: " + Money.persianDigits(Money.format(s.rewards))) }
        if s.commissionCount > 0 { lines.append("پرداخت کمیسیون (جدا): " + Money.persianDigits(Money.format(s.commissionPaid))) }
        if s.tankhahCount > 0 { lines.append("تنخواه دریافتی (جدا): " + Money.persianDigits(Money.format(s.tankhah))) }
        UIPasteboard.general.string = lines.joined(separator: "\n")
        Haptics.success()
        withAnimation { copied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { withAnimation { copied = false } }
    }
}
