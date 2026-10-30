import SwiftUI
import HesabCore

// Web «تعداد اقلام» (multi-item invoice, 1–20) and «تعداد چک» (multi-check, 1–10), plus bank logos.
// Same data as the web app: one row with items[] for an invoice; one record per check, tagged with one group.

// MARK: - count row (web compact tactile stepper)

struct CountRow: View {
    let title: String
    @Binding var count: Int
    let max: Int
    var disabled = false
    @Environment(\.theme) private var t

    var body: some View {
        HStack(spacing: 10) {
            Text(title).font(AppFont.medium(15))
            Spacer()
            Button { step(-1) } label: { Image(systemName: "minus").frame(width: 30, height: 30) }
                .buttonStyle(.glass).disabled(disabled || count <= 1)
            Text(Money.persianDigits(count))
                .font(AppFont.heavy(20)).monospacedDigit().frame(minWidth: 30)
                .contentTransition(.numericText(value: Double(count)))
            Button { step(1) } label: { Image(systemName: "plus").frame(width: 30, height: 30) }
                .buttonStyle(.glass).disabled(disabled || count >= max)
        }
        .sensoryFeedback(.selection, trigger: count)
    }

    private func step(_ d: Int) {
        withAnimation(.snappy) { count = Swift.min(max, Swift.max(1, count + d)) }
    }
}

private func amountBinding(_ get: @escaping () -> Int, _ set: @escaping (Int) -> Void) -> Binding<String> {
    Binding(get: { let n = get(); return n > 0 ? Money.persianDigits(Money.format(n)) : "" },
            set: { set(Fmt.parseAmount($0)) })
}

// MARK: - multi-item invoice

/// The form sections for items 1…n (web multi-item-row: optional desc, category, subcategory, amount) + the total line.
struct MultiItemSections: View {
    @ObservedObject var model: AppModel
    let ctx: LearnContext
    let mainDesc: String
    @Binding var items: [ExpenseItem]
    let categories: [String]
    let subcategories: (String) -> [String]
    @Environment(\.theme) private var t

    var body: some View {
        ForEach(items.indices, id: \.self) { i in
            Section {
                TextField("شرح این قلم (اختیاری)", text: $items[i].desc)
                SuggestField(title: "نوع هزینه", text: $items[i].category, suggestions: categories)
                LearnChips(model: model, ctx: ctx, desc: items[i].desc.isEmpty ? mainDesc : items[i].desc,
                           category: $items[i].category, subcategory: $items[i].subcategory, sub: false)
                SuggestField(title: "زیردسته", text: $items[i].subcategory, suggestions: subcategories(items[i].category))
                LearnChips(model: model, ctx: ctx, desc: items[i].desc.isEmpty ? mainDesc : items[i].desc,
                           category: $items[i].category, subcategory: $items[i].subcategory, sub: true)
                AmountField(title: "مبلغ (تومان)", text: amountBinding({ i < items.count ? items[i].toman : 0 },
                                                                      { v in if i < items.count { items[i].toman = v } }))
            } header: {
                Text("قلم " + Money.persianDigits(i + 1)).font(AppFont.bold(13))
            }
        }
        Section {
            HStack {
                Text("جمع اقلام").font(AppFont.medium(15))
                Spacer()
                Text(Fmt.toman(items.reduce(0) { $0 + $1.toman })).font(AppFont.heavy(17)).foregroundStyle(t.accent)
            }
        }
    }
}

/// web readSingleIntoItem0 / writeItem0IntoSingle when the count crosses 1
struct MultiItemState {
    static func resize(_ items: inout [ExpenseItem], to n: Int, from oldCount: Int,
                       single: (cat: String, sub: String, toman: Int)) {
        if oldCount <= 1 && n > 1 {
            var first = items.first ?? ExpenseItem()
            if !single.cat.isEmpty { first.category = single.cat }
            if !single.sub.isEmpty { first.subcategory = single.sub }
            if single.toman > 0 { first.toman = single.toman }
            if items.isEmpty { items = [first] } else { items[0] = first }
        }
        if items.count < n { items += Array(repeating: ExpenseItem(), count: n - items.count) }
        if items.count > n { items = Array(items.prefix(n)) }
    }
}

// MARK: - multi-check

/// today in the Jalali calendar, usable outside the main actor
func jalaliToday() -> JalaliDate {
    let c = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: Date())
    return Jalali.toJalali(c.year ?? 2000, c.month ?? 1, c.day ?? 1)
}

struct CheckSlot: Equatable {
    var amount = 0
    var due = jalaliToday()
    var number = ""
    var sayad = ""
}

/// web mc-card: the variable fields of each check (amount, due date, number, sayad) + the optional total and the diff line
struct MultiCheckSections: View {
    @Binding var slots: [CheckSlot]
    @Binding var total: String
    var showSayad = true
    @Environment(\.theme) private var t

    var body: some View {
        ForEach(slots.indices, id: \.self) { i in
            Section {
                AmountField(title: "مبلغ چک (تومان)", text: amountBinding({ i < slots.count ? slots[i].amount : 0 },
                                                                          { v in if i < slots.count { slots[i].amount = v } }))
                JalaliDateField(title: "تاریخ سررسید", date: $slots[i].due)
                TextField("شماره چک (سریال)", text: $slots[i].number).keyboardType(.numberPad)
                if showSayad { TextField("شناسه صیاد (اختیاری)", text: $slots[i].sayad).keyboardType(.numberPad) }
            } header: {
                Text("چک " + Money.persianDigits(i + 1) + " از " + Money.persianDigits(slots.count)).font(AppFont.bold(13))
            }
        }
        Section {
            let sum = slots.reduce(0) { $0 + $1.amount }
            HStack {
                Text("جمع چک‌ها").font(AppFont.medium(15))
                Spacer()
                Text(Fmt.toman(sum)).font(AppFont.heavy(17)).foregroundStyle(t.accent)
            }
            AmountField(title: "مبلغ کل (اختیاری)", text: $total)
            let tot = Fmt.parseAmount(total)
            if tot > 0 {
                let d = tot - sum
                Text(d == 0 ? "برابر مبلغ کل ✓" : d > 0 ? "مانده تا مبلغ کل: " + Fmt.toman(d) : "بیشتر از مبلغ کل: " + Fmt.toman(-d))
                    .font(AppFont.medium(13))
                    .foregroundStyle(d == 0 ? t.success : d > 0 ? t.soft : .red)
            }
        }
    }

    /// keep slot 1 = the single fields when switching modes
    static func resize(_ slots: inout [CheckSlot], to n: Int, first: CheckSlot) {
        if slots.isEmpty { slots = [first] }
        if slots.count < n {
            // the next check starts a month after the previous one (common for a run of checks); still editable
            while slots.count < n {
                var s = CheckSlot()
                let prev = slots[slots.count - 1].due
                let m = prev.jm == 12 ? 1 : prev.jm + 1
                s.due = JalaliDate(jy: prev.jm == 12 ? prev.jy + 1 : prev.jy, jm: m, jd: min(prev.jd, m <= 6 ? 31 : m <= 11 ? 30 : 29))
                slots.append(s)
            }
        }
        if slots.count > n { slots = Array(slots.prefix(n)) }
    }
}

extension AppModel {
    /// web multi-check: every check is its own record (and its own linked row), all tagged with one group
    func addChecks(_ base: CheckInput, slots: [CheckSlot], total: Int) -> Bool {
        change {
            var st = state
            let gid = CheckGroup.newId()
            for (i, s) in slots.enumerated() {
                var input = base
                input.amount = s.amount; input.dueDate = s.due; input.checkNumber = s.number; input.sayadId = s.sayad
                let missing = input.missingFields
                if !missing.isEmpty {
                    throw LedgerError.invalid(missing.map { $0 + " (چک " + Money.persianDigits(i + 1) + ")" })
                }
                st = try ReminderOps.saveCheck(st, editingId: nil, input,
                                               group: CheckGroup(groupId: gid, index: i + 1, count: slots.count, total: total),
                                               today: Self.today).state
            }
            return st
        }
    }

    func items(ofRow key: String, _ id: String) -> [ExpenseItem] {
        record(key, id).map(MultiItem.items(of:)) ?? []
    }
}

// MARK: - bank logos (web CW_BANK_LOGOS, same 29 banks)

struct BankLogo: View {
    let bank: Bank?
    var name: String = ""
    var size: CGFloat = 24
    /// a white tile behind the mark (on coloured cards)
    var tile = false

    var body: some View {
        Group {
            if let b = bank, UIImage(named: "bank-" + b.key) != nil {
                Image("bank-" + b.key).resizable().interpolation(.high).scaledToFit()
                    .padding(tile ? size * 0.14 : 0)
                    .frame(width: size, height: size)
                    .background { if tile { RoundedRectangle(cornerRadius: size * 0.28, style: .continuous).fill(.white) } }
            } else {
                // web cwBankMonogram fallback
                let mono = Self.monogram(bank?.name ?? name)
                Text(mono).font(AppFont.heavy(size * 0.42)).foregroundStyle(.white)
                    .frame(width: size, height: size)
                    .background(Circle().fill(Color.hex(bank?.color ?? 0x3E5C50)))
            }
        }
        .accessibilityHidden(true)
    }

    static func monogram(_ name: String) -> String {
        let s = name.replacingOccurrences(of: "بانک", with: "").replacingOccurrences(of: "موسسه اعتباری", with: "")
            .trimmingCharacters(in: .whitespaces)
        return String((s.isEmpty ? name : s).prefix(1)).isEmpty ? "؟" : String((s.isEmpty ? name : s).prefix(1))
    }
}

/// «نام بانک» text field: the logo appears inside the field as soon as the typed name matches a bank (web updateCheckBankLogo)
struct BankNameField: View {
    let title: String
    @Binding var text: String

    var body: some View {
        let bank = SettingsOps.bank(named: text)
        HStack(spacing: 8) {
            TextField(title, text: $text)
            if let b = bank {
                BankLogo(bank: b, size: 24)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.2), value: bank?.key)
    }
}

/// a card choice row: logo + «بانک • ****1234»
struct CardChoiceLabel: View {
    let label: String
    let bankName: String
    let bankKey: String?
    let cardNumber: String?

    var body: some View {
        HStack(spacing: 8) {
            BankLogo(bank: SettingsOps.resolveBank(key: bankKey, cardNumber: cardNumber, name: bankName), name: bankName, size: 22)
            Text(label)
        }
    }
}

extension AppModel {
    func cardBank(_ id: String?) -> (bank: Bank?, name: String) {
        guard let id, let c = state["cards"]?.arrayValue?.first(where: { $0["id"]?.idString == id }) else { return (nil, "") }
        let name = c["bankName"]?.stringValue ?? ""
        return (SettingsOps.resolveBank(key: c["bankKey"]?.stringValue, cardNumber: c["cardNumber"]?.idString, name: name), name)
    }
}

/// card choice with the bank logos (a menu picker can't show coloured logos): selected card in the row, list on tap
struct CardPicker: View {
    @ObservedObject var model: AppModel
    @Binding var cardId: String?
    var title = "کارت"

    var body: some View {
        NavigationLink {
            List {
                Button { cardId = nil } label: {
                    HStack { Text("بدون کارت"); Spacer(); if cardId == nil { Image(systemName: "checkmark") } }
                }
                ForEach(model.activeCards) { c in
                    Button { cardId = c.id; Haptics.tap() } label: {
                        HStack(spacing: 10) {
                            let b = model.cardBank(c.id)
                            BankLogo(bank: b.bank, name: b.name, size: 28)
                            Text(c.label)
                            Spacer()
                            if cardId == c.id { Image(systemName: "checkmark").foregroundStyle(.tint) }
                        }
                    }
                }
            }
            .navigationTitle(title)
            .tint(.primary)
        } label: {
            HStack(spacing: 8) {
                Text(title)
                Spacer()
                if let id = cardId, let c = model.activeCards.first(where: { $0.id == id }) {
                    let b = model.cardBank(id)
                    BankLogo(bank: b.bank, name: b.name, size: 22)
                    Text(c.label).foregroundStyle(.secondary)
                } else {
                    Text("بدون کارت").foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// web «چند قلم» cat-tag on an invoice row
struct InvoiceTag: View {
    let count: Int
    @Environment(\.theme) private var t
    var body: some View {
        Text(Money.persianDigits(count) + " قلم")
            .font(AppFont.bold(10)).foregroundStyle(t.accent)
            .padding(.horizontal, 6).padding(.vertical, 1)
            .background(Capsule().fill(t.accent.opacity(0.12)))
    }
}
