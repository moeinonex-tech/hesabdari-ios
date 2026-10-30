import SwiftUI
import HesabCore

// web «وارد کردن از یادداشت»: paste any number of rows (date → amount → description), the learning engine fills the
// category / subcategory, everything stays editable, nothing is saved until «افزودن».

struct NotesImportView: View {
    @ObservedObject var model: AppModel
    /// nil = personal ledger
    let ledgerAccountId: String?
    var onDone: () -> Void = {}
    @Environment(\.theme) private var t
    @State private var text = ""
    @State private var entries: [NotesEntry] = []
    @State private var skipped = 0
    @State private var parsed = false
    @State private var note: String?

    private var ctx: LearnContext { ledgerAccountId == nil ? .personal : .ledger }
    private var missing: Int { entries.filter { $0.category.trimmingCharacters(in: .whitespaces).isEmpty || $0.subcategory.trimmingCharacters(in: .whitespaces).isEmpty }.count }

    var body: some View {
        Form {
            if !parsed {
                Section {
                    TextEditor(text: $text)
                        .font(AppFont.regular(15))
                        .frame(minHeight: 220)
                        .overlay(alignment: .topLeading) {
                            if text.isEmpty {
                                Text("۱۴۰۵/۶/۱۹\n۸.۵۲۰.۰۰۰\nبابت خرید ۲۰۰ عدد بلوک…")
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
                    Text("برای هر ردیف به ترتیب: تاریخ، بعد مبلغ (تومان)، بعد شرح. خط خالی یا شرح چندخطی اشکالی ندارد. تعداد ردیف محدودیتی ندارد.")
                }
                Section {
                    Button { process() } label: {
                        Label("پردازش و پیش‌نمایش", systemImage: "sparkles").font(AppFont.bold(15)).frame(maxWidth: .infinity)
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                if let n = note { Section { Text(n).foregroundStyle(.orange) } }
            } else {
                Section {
                    HStack {
                        Text(Money.persianDigits(entries.count) + " ردیف").font(AppFont.bold(15))
                        Spacer()
                        Text(Fmt.toman(entries.reduce(0) { $0 + $1.toman })).font(AppFont.heavy(16)).foregroundStyle(t.accent)
                    }
                    if skipped > 0 {
                        Text(Money.persianDigits(skipped) + " خط با فرمت درست جور نبود و کنار گذاشته شد").font(AppFont.caption).foregroundStyle(.orange)
                    }
                    if missing > 0 {
                        Label(Money.persianDigits(missing) + " ردیف نوع هزینه یا زیردسته ندارد — پایین کاملش کن", systemImage: "exclamationmark.triangle.fill")
                            .font(AppFont.medium(13)).foregroundStyle(.orange)
                    } else {
                        Label("همه‌ی ردیف‌ها دسته‌بندی شدند", systemImage: "checkmark.seal.fill").font(AppFont.medium(13)).foregroundStyle(t.success)
                    }
                } footer: {
                    Text("دسته و زیردسته با یادگیری از ثبت‌های قبلی پیشنهاد شده. هر کدام را می‌توانی عوض کنی؛ برای حذف یک ردیف، آن را به چپ بکشید.")
                }
                ForEach($entries) { $e in
                    Section {
                        NotesEntryEditor(model: model, ctx: ctx, entry: $e)
                    } header: {
                        Text("ردیف " + Money.persianDigits(e.id + 1)).font(AppFont.bold(12))
                    }
                }
                .onDelete { entries.remove(atOffsets: $0) }
                Section {
                    Button { confirm() } label: {
                        Text("افزودن " + Money.persianDigits(entries.count) + " ردیف هزینه").font(AppFont.bold(16)).frame(maxWidth: .infinity)
                    }
                    .disabled(entries.isEmpty || missing > 0)
                    Button("برگشت به متن") { withAnimation { parsed = false } }
                }
            }
        }
        .navigationTitle("ورود گروهی از یادداشت")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func process() {
        let r = NotesImport.parse(text)
        guard !r.entries.isEmpty else { note = "فرمت متن درست نیست — هر ردیف: تاریخ، مبلغ، شرح"; Haptics.warning(); return }
        note = nil
        entries = NotesImport.classify(model.state, r.entries, ctx: ctx)
        skipped = r.skipped
        Haptics.success()
        withAnimation { parsed = true }
    }

    private func confirm() {
        let list = entries
        if model.change({ NotesImport.add(model.state, list, ledgerAccountId: ledgerAccountId) },
                        undoMessage: Money.persianDigits(list.count) + " ردیف از یادداشت اضافه شد") {
            Haptics.success()
            onDone()
        }
    }
}

private struct NotesEntryEditor: View {
    @ObservedObject var model: AppModel
    let ctx: LearnContext
    @Binding var entry: NotesEntry
    @Environment(\.theme) private var t

    var body: some View {
        let catList = ctx == .personal ? model.personalCategories : model.ledgerCategories
        let subList = ctx == .personal ? model.personalSubcategories(of: entry.category) : model.subcategories(of: entry.category)
        HStack {
            Text(BackupExporter.formatJalali(entry.date)).font(AppFont.medium(13)).foregroundStyle(t.soft)
            Spacer()
            Text(Fmt.toman(entry.toman)).font(AppFont.bold(15))
        }
        TextField("شرح", text: $entry.desc)
        HStack {
            SuggestField(title: "نوع هزینه", text: $entry.category, suggestions: catList)
            if entry.guessed && !entry.category.isEmpty {
                Image(systemName: "sparkles").foregroundStyle(t.accent).font(.caption)
            }
        }
        LearnChips(model: model, ctx: ctx, desc: entry.desc, category: $entry.category, subcategory: $entry.subcategory, sub: false)
        SuggestField(title: "زیردسته", text: $entry.subcategory, suggestions: subList)
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
