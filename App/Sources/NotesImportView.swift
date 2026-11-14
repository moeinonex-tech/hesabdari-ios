import SwiftUI
import HesabCore

// web «وارد کردن از یادداشت», three steps:
//   1. paste the text (any number of rows; inside a row the amount and the description can be in any order)
//   2. one quick question per row — «با چه روشی پرداخت شد؟» — the two methods this ledger uses most as big buttons,
//      one tap answers and moves to the next row
//   3. review: category / subcategory guessed by the learning engine, every row editable; a row that could not be read
//      for sure is shown in red with its original text, and nothing is saved while one is still incomplete.

struct NotesImportView: View {
    @ObservedObject var model: AppModel
    /// nil = personal ledger
    let ledgerAccountId: String?
    var onDone: () -> Void = {}
    @Environment(\.theme) private var t
    @State private var text = ""
    @State private var entries: [NotesEntry] = []
    @State private var orphans: [String] = []
    @State private var stage = 0          // 0 text, 1 pay methods, 2 review
    @State private var asking = 0         // row being asked in stage 1
    @State private var note: String?

    private var personal: Bool { ledgerAccountId == nil }
    private var ctx: LearnContext { personal ? .personal : .ledger }
    private var listKey: String { personal ? "personalExpenses" : "expenses" }
    private var blocking: Int { entries.filter(\.blocking).count }
    private var allMethods: [(String, String)] {
        personal ? [("hamrahbank", "همراه‌بانک"), ("card", "پوز"), ("cash", "نقدی"), ("transfer", "حواله"), ("branch", "شعبه بانک")]
                 : [("hamrahbank", "همراه‌بانک"), ("pos", "پوز"), ("cash", "نقدی"), ("transfer", "حواله"), ("branch", "شعبه بانک")]
    }

    var body: some View {
        Group {
            switch stage {
            case 0: textStage
            case 1: payStage
            default: reviewStage
            }
        }
        .navigationTitle("ورود گروهی از یادداشت")
        .navigationBarTitleDisplayMode(.inline)
        .animation(.snappy, value: stage)
    }

    // MARK: 1 — text

    private var textStage: some View {
        Form {
            Section {
                TextEditor(text: $text)
                    .font(AppFont.regular(15))
                    .frame(minHeight: 220)
                    .overlay(alignment: .topLeading) {
                        if text.isEmpty {
                            Text("۱۴۰۵/۸/۷\n۵۱۸.۱۰۰\nخرید قند و چای خشک برای کارگران…")
                                .font(AppFont.regular(15)).foregroundStyle(t.soft.opacity(0.6))
                                .padding(.top, 8).padding(.leading, 5).allowsHitTesting(false)
                        }
                    }
                Button {
                    if let s = UIPasteboard.general.string { text = s; Haptics.tap() }
                } label: { Label("چسباندن از کلیپ‌بورد", systemImage: "doc.on.clipboard") }
            } header: {
                Text("متن یادداشت")
            } footer: {
                Text("هر ردیف با تاریخ شروع می‌شود؛ مبلغ و شرح زیر آن به هر ترتیبی باشند درست خوانده می‌شوند. خط خالی و شرح چندخطی اشکالی ندارد. ردیفی که کامل خوانده نشود حذف نمی‌شود و با علامت قرمز نشان داده می‌شود.")
            }
            Section {
                Button { process() } label: {
                    Label("پردازش و پیش‌نمایش", systemImage: "sparkles").font(AppFont.bold(15)).frame(maxWidth: .infinity)
                }
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if let n = note { Section { Text(n).foregroundStyle(.orange) } }
        }
    }

    // MARK: 2 — one quick question per row

    private var payStage: some View {
        let top = SmartDefaults.topPayMethods(model.state, listKey: listKey, accountId: ledgerAccountId)
        let i = min(asking, max(0, entries.count - 1))
        return VStack(spacing: 18) {
            // progress
            HStack {
                Text("ردیف " + Money.persianDigits(i + 1) + " از " + Money.persianDigits(entries.count)).font(AppFont.bold(14)).foregroundStyle(t.soft)
                Spacer()
                if i > 0 {
                    Button { Haptics.tap(); withAnimation(.snappy) { asking -= 1 } } label: {
                        Label("ردیف قبل", systemImage: "chevron.right").font(AppFont.medium(13))
                    }
                    .buttonStyle(.plain).foregroundStyle(t.accent)
                }
            }
            ProgressView(value: Double(i), total: Double(max(1, entries.count))).tint(t.accent)

            if entries.indices.contains(i) {
                let e = entries[i]
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(BackupExporter.formatJalali(e.date)).font(AppFont.medium(13)).foregroundStyle(t.soft)
                        Spacer()
                        Text(e.toman > 0 ? Fmt.toman(e.toman) : "مبلغ؟").font(AppFont.heavy(20)).foregroundStyle(e.toman > 0 ? t.ink : t.danger)
                    }
                    Text(e.desc.isEmpty ? "—" : e.desc).font(AppFont.medium(16)).foregroundStyle(t.ink).lineLimit(3)
                    if !e.problems.isEmpty {
                        Label(e.problems.joined(separator: " · "), systemImage: "exclamationmark.triangle.fill")
                            .font(AppFont.caption).foregroundStyle(t.danger)
                    }
                }
                .glassCard()
                .id(e.id)
                .transition(.asymmetric(insertion: .move(edge: .leading).combined(with: .opacity), removal: .opacity))

                Text("با چه روشی پرداخت شد؟").font(AppFont.bold(17)).foregroundStyle(t.ink)

                // the two methods used most: big, one tap each
                HStack(spacing: 12) {
                    ForEach(top, id: \.self) { m in
                        Button { answer(m) } label: {
                            VStack(spacing: 8) {
                                Image(systemName: PayGlyph.icon(m)).font(.system(size: 26, weight: .semibold))
                                Text(payTitle(m) ?? m).font(AppFont.bold(16))
                            }
                            .frame(maxWidth: .infinity).frame(height: 96)
                        }
                        .buttonStyle(.glassProminent)
                    }
                }
                // the rest, small
                HScroll {
                    HStack(spacing: 8) {
                        ForEach(allMethods.filter { !top.contains($0.0) }, id: \.0) { m in
                            Button { answer(m.0) } label: {
                                Label(m.1, systemImage: PayGlyph.icon(m.0)).font(AppFont.medium(13)).padding(.horizontal, 4)
                            }
                            .buttonStyle(.glass)
                        }
                    }
                }
                if let prev = entries[..<i].last?.payMethod, entries.count - i > 1 {
                    Button {
                        Haptics.success()
                        for k in i..<entries.count { entries[k].payMethod = prev }
                        withAnimation(.snappy) { stage = 2 }
                    } label: {
                        Text("بقیه‌ی ردیف‌ها هم «" + (payTitle(prev) ?? prev) + "»").font(AppFont.medium(13))
                    }
                    .buttonStyle(.plain).foregroundStyle(t.accent)
                }
            }
            Spacer()
        }
        .padding(16)
        .background(AppBackground())
    }

    private func answer(_ m: String?) {
        TactileClick.play()
        guard entries.indices.contains(asking) else { return }
        entries[asking].payMethod = m
        withAnimation(.spring(duration: 0.35, bounce: 0.15)) {
            if asking + 1 < entries.count { asking += 1 } else { stage = 2 }
        }
    }

    // MARK: 3 — review

    private var reviewStage: some View {
        Form {
            Section {
                HStack {
                    Text(Money.persianDigits(entries.count) + " ردیف").font(AppFont.bold(15))
                    Spacer()
                    Text(Fmt.toman(entries.reduce(0) { $0 + $1.toman })).font(AppFont.heavy(16)).foregroundStyle(t.accent)
                }
                if blocking > 0 {
                    Label(Money.persianDigits(blocking) + " ردیف هنوز کامل نیست (قرمز) — اول کاملشان کن یا حذفشان کن", systemImage: "exclamationmark.triangle.fill")
                        .font(AppFont.medium(13)).foregroundStyle(t.danger)
                } else {
                    Label("همه‌ی ردیف‌ها کامل‌اند", systemImage: "checkmark.seal.fill").font(AppFont.medium(13)).foregroundStyle(t.success)
                }
            } footer: {
                Text("دسته و زیردسته از روی ثبت‌های قبلی پیشنهاد شده و همه چیز قابل تغییر است. برای حذف یک ردیف، آن را به چپ بکشید.")
            }
            if !orphans.isEmpty {
                Section {
                    Text(orphans.joined(separator: "\n")).font(AppFont.regular(13)).foregroundStyle(t.ink)
                } header: {
                    Label("این خط‌ها قبل از اولین تاریخ بودند و به هیچ ردیفی وصل نشدند", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(t.danger)
                } footer: {
                    Text("اگر هزینه‌اند، تاریخشان را در متن بالایشان بنویس و دوباره پردازش کن.")
                }
            }
            ForEach($entries) { $e in
                Section {
                    NotesEntryEditor(model: model, ctx: ctx, methods: allMethods, entry: $e)
                } header: {
                    HStack(spacing: 6) {
                        Text("ردیف " + Money.persianDigits(e.id + 1)).font(AppFont.bold(12))
                        if e.blocking { Text("ناقص").font(AppFont.bold(11)).foregroundStyle(.white).padding(.horizontal, 6).background(t.danger, in: Capsule()) }
                    }
                }
            }
            .onDelete { entries.remove(atOffsets: $0) }
            Section {
                Button { confirm() } label: {
                    Text("افزودن " + Money.persianDigits(entries.count) + " ردیف هزینه").font(AppFont.bold(16)).frame(maxWidth: .infinity)
                }
                .disabled(entries.isEmpty || blocking > 0)
                Button("پرسیدن دوباره‌ی روش پرداخت") { asking = 0; withAnimation { stage = 1 } }
                Button("برگشت به متن") { withAnimation { stage = 0 } }
            }
        }
    }

    private func process() {
        let r = NotesImport.parse(text)
        guard !r.entries.isEmpty else {
            note = "هیچ تاریخی پیدا نشد — هر ردیف باید با تاریخ (مثل ۱۴۰۵/۸/۷) شروع شود"
            Haptics.warning(); return
        }
        note = nil
        entries = NotesImport.classify(model.state, r.entries, ctx: ctx)
        orphans = r.orphans
        asking = 0
        Haptics.success()
        withAnimation { stage = 1 }
    }

    private func confirm() {
        let list = entries
        let card = personal ? SmartDefaults.mostUsedCard(model.state, listKey: "personalExpenses", accountId: nil) ?? model.activeCards.first?.id
                            : ledgerAccountId.flatMap { model.defaultCard(accountId: $0) }
        if model.change({ NotesImport.add(model.state, list, ledgerAccountId: ledgerAccountId, cardId: card) },
                        undoMessage: Money.persianDigits(list.count) + " ردیف از یادداشت اضافه شد") {
            Haptics.success()
            onDone()
        }
    }
}

private struct NotesEntryEditor: View {
    @ObservedObject var model: AppModel
    let ctx: LearnContext
    let methods: [(String, String)]
    @Binding var entry: NotesEntry
    @Environment(\.theme) private var t

    var body: some View {
        let catList = ctx == .personal ? model.personalCategories : model.ledgerCategories
        let subList = ctx == .personal ? model.personalSubcategories(of: entry.category) : model.subcategories(of: entry.category)
        if !entry.problems.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Label(entry.problems.joined(separator: " · "), systemImage: "exclamationmark.triangle.fill")
                    .font(AppFont.medium(13)).foregroundStyle(t.danger)
                Text(entry.raw).font(AppFont.regular(12)).foregroundStyle(t.soft)
            }
        }
        HStack {
            Text(BackupExporter.formatJalali(entry.date)).font(AppFont.medium(13)).foregroundStyle(t.soft)
            Spacer()
            Picker("", selection: Binding(get: { entry.payMethod ?? "" }, set: { entry.payMethod = $0.isEmpty ? nil : $0 })) {
                Text("روش پرداخت؟").tag("")
                ForEach(methods, id: \.0) { Text($0.1).tag($0.0) }
            }
            .labelsHidden()
        }
        AmountField(title: "مبلغ (تومان)", text: Binding(
            get: { entry.toman > 0 ? Money.persianDigits(Money.format(entry.toman)) : "" },
            set: { entry.toman = Fmt.parseAmount($0) }))
        TextField("شرح", text: $entry.desc)
        HStack {
            SuggestField(title: "نوع هزینه", text: $entry.category, suggestions: catList, dedupe: true)
            if entry.guessed && !entry.category.isEmpty {
                Image(systemName: "sparkles").foregroundStyle(t.accent).font(.caption)
            }
        }
        LearnChips(model: model, ctx: ctx, desc: entry.desc, category: $entry.category, subcategory: $entry.subcategory, sub: false)
        SuggestField(title: "زیردسته", text: $entry.subcategory, suggestions: subList, dedupe: true)
        LearnChips(model: model, ctx: ctx, desc: entry.desc, category: $entry.category, subcategory: $entry.subcategory, sub: true)
    }
}

/// the entry row in the expense forms
struct NotesImportLink: View {
    @ObservedObject var model: AppModel
    let ledgerAccountId: String?
    let onDone: () -> Void
    @Environment(\.theme) private var t

    var body: some View {
        Section {
            NavigationLink {
                NotesImportView(model: model, ledgerAccountId: ledgerAccountId, onDone: onDone)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "doc.on.clipboard").foregroundStyle(t.accent)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("ورود گروهی از یادداشت").font(AppFont.medium(14))
                        Text("چند ردیف را یک‌جا بچسبان؛ دسته‌ها خودکار تشخیص داده می‌شوند").font(AppFont.caption).foregroundStyle(t.soft)
                    }
                }
            }
        }
    }
}
