import SwiftUI
import PhotosUI
import HesabCore

// MARK: - model: cards, budgets, quotes, home widgets

extension AppModel {
    func saveCard(_ id: String?, _ i: CardInput) -> Bool { change { try SettingsOps.saveCard(state, editingId: id, i) } }
    func deleteCard(_ id: String) -> Bool { change({ try SettingsOps.deleteCard(state, id: id) }, undoMessage: "کارت حذف شد") }
    func setCardArchived(_ id: String, _ archived: Bool) -> Bool {
        change {
            var st = state
            var cards = st["cards"]?.arrayValue ?? []
            guard let i = cards.firstIndex(where: { $0["id"]?.idString == id }), var c = cards[i].objectValue else { throw LedgerError.notFound }
            c["archived"] = .bool(archived)
            cards[i] = .object(c)
            st["cards"] = .array(cards)
            return st
        }
    }
    func setAccountBudget(_ id: String, _ amount: Int) -> Bool { change { try SettingsOps.setAccountBudget(state, accountId: id, budget: amount) } }
    func setPersonalBudget(_ amount: Int) -> Bool { change { SettingsOps.setPersonalBudget(state, budget: amount) } }

    var customQuotes: [Quote] {
        (state["customQuotes"]?.arrayValue ?? []).compactMap { q in
            guard let id = q["id"]?.idString else { return nil }
            return Quote(id: id, text: q["text"]?.stringValue ?? "", author: q["author"]?.stringValue ?? "")
        }
    }
    func addQuote(_ text: String, _ author: String) -> Bool { change { try SettingsOps.addQuote(state, text: text, author: author) } }
    func editQuote(_ id: String, _ text: String, _ author: String) -> Bool { change { try SettingsOps.editQuote(state, id: id, text: text, author: author) } }
    func deleteQuote(_ id: String) -> Bool { change({ SettingsOps.deleteQuote(state, id: id) }, undoMessage: "جمله حذف شد") }
    var quoteTypewriter: Bool { state["quoteTypewriterEnabled"]?.boolValue ?? true }
    func setQuoteTypewriter(_ on: Bool) { _ = change { var st = state; st["quoteTypewriterEnabled"] = .bool(on); return st } }
    func setWidgets(order: [String], visible: [String: Bool]) { _ = change { SettingsOps.setWidgets(state, order: order, visible: visible) } }

    var accountTypeChoices: [String] {
        let saved = (state["cwAccountTypes"]?.arrayValue ?? []).compactMap(\.stringValue)
        return saved.isEmpty ? SettingsOps.defaultAccountTypes : saved
    }
}

// MARK: - card form

struct CardFormView: View {
    @ObservedObject var model: AppModel
    let editingId: String?
    @Environment(\.dismiss) private var dismiss
    @State private var bankKey: String?
    @State private var bankName = ""
    @State private var number = ""
    @State private var accountNumber = ""
    @State private var iban = ""
    @State private var accountType = ""
    @State private var hasExpiry = false
    @State private var expiryYear = 1405
    @State private var expiryMonth = 1
    @State private var holder = ""
    @State private var useColor = false
    @State private var color = Color.blue
    @State private var image: String?
    @State private var photo: PhotosPickerItem?
    @State private var archived = false
    @State private var loaded = false
    @State private var confirmDelete = false

    var body: some View {
        Form {
            Section("بانک") {
                Picker("بانک", selection: $bankKey) {
                    Text("سایر / دستی").tag(String?.none)
                    ForEach(SettingsOps.banks, id: \.key) { b in Text(b.name).tag(Optional(b.key)) }
                }
                if bankKey == nil { TextField("نام بانک", text: $bankName) }
            }
            Section("شماره‌ها") {
                TextField("شماره کارت ۱۶ رقمی", text: $number)
                    .keyboardType(.numberPad)
                    .environment(\.layoutDirection, .leftToRight)
                    .onChange(of: number) { _, n in
                        if let b = SettingsOps.bank(forCardNumber: n) { bankKey = b.key }
                    }
                TextField("شماره حساب", text: $accountNumber).keyboardType(.numbersAndPunctuation)
                TextField("شبا (IR…)", text: $iban)
                    .textInputAutocapitalization(.characters)
                    .environment(\.layoutDirection, .leftToRight)
                SuggestField(title: "نوع حساب", text: $accountType, suggestions: model.accountTypeChoices)
                TextField("نام دارنده", text: $holder)
            }
            Section("تاریخ انقضا") {
                Toggle("دارد", isOn: $hasExpiry)
                if hasExpiry {
                    Picker("سال", selection: $expiryYear) {
                        ForEach(1395...1425, id: \.self) { y in Text(Money.persianDigits(String(y))).tag(y) }
                    }
                    Picker("ماه", selection: $expiryMonth) {
                        ForEach(1...12, id: \.self) { m in Text(Money.persianDigits(String(format: "%02d", m))).tag(m) }
                    }
                }
            }
            Section("ظاهر کارت") {
                Toggle("رنگ دلخواه", isOn: $useColor)
                if useColor { ColorPicker("رنگ", selection: $color, supportsOpacity: false) }
                PhotosPicker(selection: $photo, matching: .images) {
                    Label(image == nil ? "انتخاب عکس پس‌زمینه" : "تغییر عکس پس‌زمینه", systemImage: "photo")
                }
                if image != nil {
                    Button("حذف عکس", role: .destructive) { image = nil }
                }
            }
            Section {
                Text("رمز دوم و CVV2 در این اپ ذخیره نمی‌شود.").font(AppFont.caption).foregroundStyle(.secondary)
            }
            if editingId != nil {
                Section {
                    Toggle("بایگانی", isOn: $archived)
                    Button("حذف کارت", role: .destructive) { confirmDelete = true }
                }
            }
        }
        .navigationTitle(editingId == nil ? "کارت جدید" : "ویرایش کارت")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("انصراف") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("ذخیره") { save() }.bold() }
        }
        .confirmationDialog("این کارت حذف شود؟", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("حذف", role: .destructive) {
                if let id = editingId, model.deleteCard(id) { dismiss() }
            }
        }
        .onChange(of: photo) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let ui = UIImage(data: data) {
                    image = Self.dataURL(ui)
                }
            }
        }
        .onAppear(perform: load)
    }

    /// Small JPEG so the backup stays light (web also stores a data URL).
    static func dataURL(_ img: UIImage) -> String? {
        let maxSide: CGFloat = 900
        let scale = min(1, maxSide / max(img.size.width, img.size.height))
        let size = CGSize(width: img.size.width * scale, height: img.size.height * scale)
        let resized = UIGraphicsImageRenderer(size: size).image { _ in img.draw(in: CGRect(origin: .zero, size: size)) }
        guard let jpg = resized.jpegData(compressionQuality: 0.75) else { return nil }
        return "data:image/jpeg;base64," + jpg.base64EncodedString()
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let id = editingId, let c = model.record("cards", id) else { return }
        let key = c["bankKey"]?.stringValue
        bankKey = SettingsOps.banks.contains { $0.key == key } ? key : nil
        bankName = c["bankName"]?.stringValue ?? ""
        if bankKey == nil, let b = SettingsOps.banks.first(where: { $0.name == bankName }) { bankKey = b.key }
        number = c["cardNumber"]?.idString ?? ""
        accountNumber = c["accountNumber"]?.idString ?? ""
        iban = c["iban"]?.stringValue ?? ""
        accountType = c["accountType"]?.stringValue ?? ""
        if let y = c["expiry"]?["ey"]?.intValue, let m = c["expiry"]?["em"]?.intValue, y > 0, (1...12).contains(m) {
            hasExpiry = true; expiryYear = y; expiryMonth = m
        }
        holder = c["holderName"]?.stringValue ?? ""
        if let col = Color.web(c["bgColor"]?.stringValue) { useColor = true; color = col }
        image = c["bgImage"]?.stringValue
        archived = c["archived"]?.isTruthy ?? false
    }

    private func save() {
        let bank = SettingsOps.banks.first { $0.key == bankKey }
        let input = CardInput(bankName: bank?.name ?? bankName.trimmingCharacters(in: .whitespaces), bankKey: bank?.key,
                              cardNumber: number, accountNumber: accountNumber, iban: iban,
                              accountType: accountType.trimmingCharacters(in: .whitespaces),
                              expiryYear: hasExpiry ? expiryYear : nil, expiryMonth: hasExpiry ? expiryMonth : nil,
                              holderName: holder.trimmingCharacters(in: .whitespaces),
                              bgColor: useColor ? color.hexString : nil, bgImage: image, archived: archived)
        if model.saveCard(editingId, input) { Haptics.success(); dismiss() }
    }
}

extension Color {
    var hexString: String {
        let c = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getRed(&r, green: &g, blue: &b, alpha: &a)
        func h(_ v: CGFloat) -> String { String(format: "%02x", Int((max(0, min(1, v)) * 255).rounded())) }
        return "#" + h(r) + h(g) + h(b)
    }
}

// MARK: - budget editor

struct BudgetEditor: View {
    let title: String
    let current: Int
    let onSave: (Int) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    var body: some View {
        Form {
            Section {
                AmountField(title: "مبلغ بودجه (تومان)", text: $text)
            } footer: {
                Text("صفر یعنی بدون بودجه.")
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("انصراف") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("ذخیره") { onSave(Fmt.parseAmount(text)); dismiss() }.bold()
            }
        }
        .onAppear { if current > 0 { text = Money.persianDigits(Money.format(current)) } }
    }
}

// MARK: - quotes settings

struct QuotesSettingsView: View {
    @ObservedObject var model: AppModel
    @State private var editing: QuoteEdit?
    @State private var showBulk = false
    @State private var confirmClear = false
    @Environment(\.theme) private var t

    struct QuoteEdit: Identifiable {
        let id: String       // "" = new
        var text: String
        var author: String
    }

    var body: some View {
        List {
            Section {
                Toggle("نمایش تایپی در خانه", isOn: Binding(get: { model.quoteTypewriter }, set: { model.setQuoteTypewriter($0) }))
                if model.quoteTypewriter {
                    Picker("سرعت تایپ", selection: Binding(get: { model.state["quoteTypewriterSpeed"]?.stringValue ?? "normal" },
                                                          set: { model.setTypewriterSpeed($0) })) {
                        Text("آهسته").tag("slow")
                        Text("معمولی").tag("normal")
                        Text("سریع").tag("fast")
                    }
                }
            } footer: {
                Text("هر نیم‌روز یک جمله نشان داده می‌شود و تا همه دیده نشوند تکرار نمی‌شود.")
            }
            Section("جمله‌ها") {
                if model.customQuotes.isEmpty {
                    Text("هنوز جمله‌ای اضافه نشده").foregroundStyle(.secondary)
                }
                ForEach(model.customQuotes, id: \.id) { q in
                    Button {
                        editing = QuoteEdit(id: q.id, text: q.text, author: q.author)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(q.text).font(AppFont.regular(15)).foregroundStyle(t.ink)
                            if !q.author.isEmpty { Text("— " + q.author).font(AppFont.caption).foregroundStyle(t.soft) }
                        }
                    }
                    .swipeActions {
                        Button("حذف", role: .destructive) { _ = model.deleteQuote(q.id) }
                    }
                }
            }
        }
        .navigationTitle("جمله‌های انگیزشی")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button { editing = QuoteEdit(id: "", text: "", author: "") } label: { Label("جمله جدید", systemImage: "plus") }
                    Button { showBulk = true } label: { Label("ورود انبوه", systemImage: "text.badge.plus") }
                    if !model.customQuotes.isEmpty {
                        Button(role: .destructive) { confirmClear = true } label: { Label("حذف همه", systemImage: "trash") }
                    }
                } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showBulk) { NavigationStack { QuoteBulkView(model: model) } }
        .confirmationDialog("همه‌ی \(Money.persianDigits(String(model.customQuotes.count))) جمله حذف شوند؟", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("بله، همه رو حذف کن", role: .destructive) { _ = model.clearAllQuotes() }
        } message: {
            Text("بعد از آن کارت «جمله‌ی امروز» در خانه نمایش داده نمی‌شود.")
        }
        .sheet(item: $editing) { e in
            NavigationStack { QuoteFormView(model: model, edit: e) }
                .presentationDetents([.medium])
        }
    }
}

struct QuoteFormView: View {
    @ObservedObject var model: AppModel
    let edit: QuotesSettingsView.QuoteEdit
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var author = ""

    var body: some View {
        Form {
            TextField("متن جمله", text: $text, axis: .vertical).lineLimit(3...8)
            TextField("گوینده (اختیاری)", text: $author)
        }
        .navigationTitle(edit.id.isEmpty ? "جمله جدید" : "ویرایش جمله")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("انصراف") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("ذخیره") {
                    let ok = edit.id.isEmpty ? model.addQuote(text, author) : model.editQuote(edit.id, text, author)
                    if ok { dismiss() }
                }
                .bold()
            }
        }
        .onAppear { text = edit.text; author = edit.author }
    }
}

// MARK: - home widgets settings

struct WidgetsSettingsView: View {
    @ObservedObject var model: AppModel
    @State private var order: [String] = []
    @State private var visible: [String: Bool] = [:]

    static let titles = ["date": "تاریخ امروز", "attention": "نیازمند توجه", "financial": "خلاصه دفترها",
                         "shortcuts": "میانبرها", "activity": "فعالیت اخیر"]

    var body: some View {
        List {
            Section {
                ForEach(order, id: \.self) { k in
                    Toggle(Self.titles[k] ?? k, isOn: Binding(get: { visible[k] ?? true }, set: { visible[k] = $0; persist() }))
                }
                .onMove { from, to in
                    order.move(fromOffsets: from, toOffset: to)
                    persist()
                }
            } footer: {
                Text("برای تغییر ترتیب، ردیف را از دستگیره‌ی کنارش بکشید.")
            }
        }
        .environment(\.editMode, .constant(.active))
        .navigationTitle("ویجت‌های خانه")
        .onAppear {
            order = SettingsOps.widgetOrder(model.state)
            visible = Dictionary(uniqueKeysWithValues: order.map { ($0, SettingsOps.widgetVisible(model.state, $0)) })
        }
    }

    private func persist() { model.setWidgets(order: order, visible: visible) }
}


// MARK: - home shortcuts (web openHomeShortcutPicker)

enum HomeShortcut {
    static func info(_ k: String) -> (title: String, icon: String) {
        switch k {
        case "ledger": return ("دفتر حساب", "book.closed.fill")
        case "personal": return ("دفتر شخصی", "note.text")
        case "income": return ("درآمد", "chart.line.uptrend.xyaxis")
        case "cards": return ("کیف کارت", "creditcard.fill")
        case "reminders": return ("یادآوری‌ها", "bell.fill")
        case "reports": return ("گزارش‌ها", "chart.bar.xaxis")
        case "appointments": return ("ثبت قرار", "calendar.badge.plus")
        default: return (k, "square")
        }
    }
}

extension AppModel {
    func setHomeShortcuts(_ keys: [String]) { _ = change { SettingsOps.setHomeShortcuts(state, keys) } }
    func setTypewriterSpeed(_ id: String) { _ = change { var st = state; st["quoteTypewriterSpeed"] = .string(id); return st } }
}

struct ShortcutsEditorView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var keys: [String] = []

    var body: some View {
        List {
            Section("روی صفحه‌ی خانه") {
                if keys.isEmpty { Text("هیچ میان‌بری نیست").foregroundStyle(.secondary) }
                ForEach(keys, id: \.self) { k in
                    Label(HomeShortcut.info(k).title, systemImage: HomeShortcut.info(k).icon)
                }
                .onMove { keys.move(fromOffsets: $0, toOffset: $1); model.setHomeShortcuts(keys) }
                .onDelete { keys.remove(atOffsets: $0); model.setHomeShortcuts(keys) }
            }
            let rest = SettingsOps.shortcutKeys.filter { !keys.contains($0) }
            if !rest.isEmpty {
                Section("افزودن") {
                    ForEach(rest, id: \.self) { k in
                        Button {
                            keys.append(k); model.setHomeShortcuts(keys); Haptics.tap()
                        } label: {
                            Label(HomeShortcut.info(k).title, systemImage: "plus.circle.fill")
                        }
                    }
                }
            }
        }
        .environment(\.editMode, .constant(.active))
        .navigationTitle("میان‌برهای خانه")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("تمام") { dismiss() } } }
        .onAppear { keys = SettingsOps.homeShortcuts(model.state) }
    }
}
