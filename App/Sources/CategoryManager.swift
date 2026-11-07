import SwiftUI
import HesabCore

extension AppModel {
    func removeCategory(_ scope: CategoryScope, _ name: String, replaceWith: String?) -> Bool {
        change({ try CategoryOps.removeCategory(state, scope, name, replaceWith: replaceWith) }, undoMessage: "دسته حذف شد")
    }
    func removeSubcategory(_ scope: CategoryScope, category: String, _ name: String, replaceWith: String?) -> Bool {
        change({ try CategoryOps.removeSubcategory(state, scope, category: category, name, replaceWith: replaceWith) },
               undoMessage: "زیردسته حذف شد")
    }
}

/// Settings › «دسته‌ها و زیردسته‌ها»
struct CategoryManagerView: View {
    @ObservedObject var model: AppModel
    @State private var scope: CategoryScope = .ledger
    @State private var removing: Removal?

    var body: some View {
        let cats = CategoryOps.categories(model.state, scope)
        List {
            Section {
                Segmented(selection: $scope, CategoryScope.allCases.map { ($0, $0.title) })
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
            }
            Section {
                if cats.isEmpty { Text("دسته‌ای ثبت نشده").foregroundStyle(.secondary) }
                ForEach(cats, id: \.self) { c in
                    NavigationLink {
                        SubcategoryManagerView(model: model, scope: scope, category: c)
                    } label: {
                        CategoryLine(name: c, count: CategoryOps.usage(model.state, scope, category: c),
                                     subs: CategoryOps.subcategories(model.state, scope, category: c).count,
                                     locked: CategoryOps.isProtected(scope, c))
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if !CategoryOps.isProtected(scope, c) {
                            // not role: .destructive — that makes the list animate the row away although nothing is
                            // deleted yet (the replacement sheet asks first), which breaks the list update
                            Button { ask(Removal(scope: scope, category: c, sub: nil)) } label: { Label("حذف", systemImage: "trash") }
                                .tint(.red)
                        }
                    }
                }
            } header: {
                Text("دسته‌های " + scope.title)
            } footer: {
                Text("برای حذف، روی دسته به چپ بکشید. اگر تراکنشی از آن استفاده کرده باشد، اول جایگزین را انتخاب می‌کنید و همه‌ی آن تراکنش‌ها (و آنچه برنامه یاد گرفته) به جایگزین منتقل می‌شوند. مبلغ‌ها دست نمی‌خورند.")
            }
        }
        .navigationTitle("دسته‌ها و زیردسته‌ها")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $removing) { r in NavigationStack { RemoveCategorySheet(model: model, removal: r) } }
    }

    /// the swipe row closes first, then the sheet opens (presenting while the row animates is what crashed)
    private func ask(_ r: Removal) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { removing = r }
    }
}

struct Removal: Identifiable {
    let scope: CategoryScope
    let category: String
    let sub: String?
    var id: String { scope.rawValue + "|" + category + "|" + (sub ?? "") }
}

struct CategoryLine: View {
    let name: String
    let count: Int
    var subs: Int? = nil
    var locked = false
    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(name).font(AppFont.medium(15))
                    if locked { Image(systemName: "lock.fill").font(.caption2).foregroundStyle(.secondary) }
                }
                if let subs { Text(Money.persianDigits(String(subs)) + " زیردسته").font(AppFont.caption).foregroundStyle(.secondary) }
            }
            Spacer()
            Text(count == 0 ? "بدون تراکنش" : Money.persianDigits(String(count)) + " تراکنش")
                .font(AppFont.caption)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Capsule().fill(count == 0 ? Color.secondary.opacity(0.12) : Color.orange.opacity(0.18)))
        }
    }
}

struct SubcategoryManagerView: View {
    @ObservedObject var model: AppModel
    let scope: CategoryScope
    let category: String
    @State private var removing: Removal?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let subs = CategoryOps.subcategories(model.state, scope, category: category)
        List {
            Section {
                if subs.isEmpty { Text("زیردسته‌ای ثبت نشده").foregroundStyle(.secondary) }
                ForEach(subs, id: \.self) { s in
                    HStack(spacing: 10) {
                        CategoryLine(name: s, count: CategoryOps.usage(model.state, scope, category: category, sub: s))
                        // a plain delete button on the row as well, so deleting never depends on the swipe
                        Button { ask(Removal(scope: scope, category: category, sub: s)) } label: {
                            Image(systemName: "trash").foregroundStyle(.red)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("حذف " + s)
                        .accessibilityIdentifier("del." + s)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button { ask(Removal(scope: scope, category: category, sub: s)) } label: { Label("حذف", systemImage: "trash") }
                            .tint(.red)
                    }
                }
            } header: {
                Text("زیردسته‌های «\(category)»")
            } footer: {
                Text("برای حذف، روی زیردسته به چپ بکشید.")
            }
            if !CategoryOps.isProtected(scope, category) {
                Section {
                    Button(role: .destructive) { ask(Removal(scope: scope, category: category, sub: nil)) } label: {
                        Label("حذف خود دسته‌ی «\(category)»", systemImage: "trash")
                    }
                    .accessibilityIdentifier("del.category")
                }
            }
        }
        .navigationTitle(category)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $removing, onDismiss: {
            // the category itself was removed: leave its page (after the sheet is fully gone)
            if !CategoryOps.categories(model.state, scope).contains(category) {
                DispatchQueue.main.async { dismiss() }
            }
        }) { r in NavigationStack { RemoveCategorySheet(model: model, removal: r) } }
    }

    private func ask(_ r: Removal) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { removing = r }
    }
}

/// asks for a replacement when the name is in use: pick one of the stored names, or type a new one
struct RemoveCategorySheet: View {
    @ObservedObject var model: AppModel
    let removal: Removal
    @State private var picked: String?
    @State private var typed = ""
    @State private var manual = false
    @State private var done = false
    // read once when the sheet opens: after the removal the sheet must not re-read a name that no longer exists
    @State private var used = 0
    @State private var choices: [String] = []
    @State private var loaded = false
    @Environment(\.dismiss) private var dismiss

    private var isSub: Bool { removal.sub != nil }
    private var name: String { removal.sub ?? removal.category }
    private var replacement: String? {
        let r = manual ? typed.trimmingCharacters(in: .whitespaces) : (picked ?? "")
        return r.isEmpty ? nil : r
    }

    var body: some View {
        Form {
            Section {
                if used == 0 {
                    Label("هیچ تراکنشی از «\(name)» استفاده نکرده؛ بی‌خطر حذف می‌شود.", systemImage: "checkmark.circle")
                        .foregroundStyle(.green)
                } else {
                    Label("«\(name)» در \(Money.persianDigits(String(used))) تراکنش استفاده شده. برای حذف، جایگزینش را انتخاب کنید؛ همه‌ی این تراکنش‌ها به جایگزین منتقل می‌شوند.",
                          systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }
            if used > 0 {
                Section {
                    Picker("روش", selection: $manual) {
                        Text("انتخاب از فهرست").tag(false)
                        Text("نوشتن نام جدید").tag(true)
                    }
                    .pickerStyle(.segmented)
                    if manual {
                        TextField(isSub ? "نام زیردسته‌ی جایگزین" : "نام دسته‌ی جایگزین", text: $typed)
                    } else if choices.isEmpty {
                        Text("گزینه‌ی دیگری در فهرست نیست؛ نام جدید بنویسید.").foregroundStyle(.secondary)
                    } else {
                        ForEach(choices, id: \.self) { c in
                            Button {
                                Haptics.tap()
                                picked = c
                            } label: {
                                HStack {
                                    Text(c).foregroundStyle(.primary)
                                    Spacer()
                                    if picked == c { Image(systemName: "checkmark").foregroundStyle(.tint) }
                                }
                            }
                        }
                    }
                } header: {
                    Text(isSub ? "زیردسته‌ی جایگزین" : "دسته‌ی جایگزین")
                } footer: {
                    if !isSub { Text("زیردسته‌های «\(name)» هم به دسته‌ی جایگزین منتقل می‌شوند.") }
                }
            }
        }
        .navigationTitle("حذف «\(name)»")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard !loaded else { return }
            loaded = true
            used = CategoryOps.usage(model.state, removal.scope, category: removal.category, sub: removal.sub)
            choices = (isSub ? CategoryOps.subcategories(model.state, removal.scope, category: removal.category)
                             : CategoryOps.categories(model.state, removal.scope)).filter { $0 != name }
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("انصراف") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button(used > 0 ? "جایگزین و حذف" : "حذف", role: .destructive) { run() }
                    .bold()
                    .accessibilityIdentifier("remove.confirm")
                    .disabled(done || (used > 0 && replacement == nil))
            }
        }
    }

    private func run() {
        guard !done else { return }
        let ok: Bool
        if let s = removal.sub {
            ok = model.removeSubcategory(removal.scope, category: removal.category, s, replaceWith: replacement)
        } else {
            ok = model.removeCategory(removal.scope, removal.category, replaceWith: replacement)
        }
        if ok { done = true; Haptics.success(); dismiss() }
    }
}
