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
                    .swipeActions(edge: .trailing) {
                        if !CategoryOps.isProtected(scope, c) {
                            Button(role: .destructive) { removing = Removal(scope: scope, category: c, sub: nil) } label: { Label("حذف", systemImage: "trash") }
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
                    CategoryLine(name: s, count: CategoryOps.usage(model.state, scope, category: category, sub: s))
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) { removing = Removal(scope: scope, category: category, sub: s) } label: { Label("حذف", systemImage: "trash") }
                        }
                }
            } header: {
                Text("زیردسته‌های «\(category)»")
            } footer: {
                Text("برای حذف، روی زیردسته به چپ بکشید.")
            }
            if !CategoryOps.isProtected(scope, category) {
                Section {
                    Button(role: .destructive) { removing = Removal(scope: scope, category: category, sub: nil) } label: {
                        Label("حذف خود دسته‌ی «\(category)»", systemImage: "trash")
                    }
                }
            }
        }
        .navigationTitle(category)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $removing, onDismiss: {
            if !CategoryOps.categories(model.state, scope).contains(category) { dismiss() }
        }) { r in NavigationStack { RemoveCategorySheet(model: model, removal: r) } }
    }
}

/// asks for a replacement when the name is in use: pick one of the stored names, or type a new one
struct RemoveCategorySheet: View {
    @ObservedObject var model: AppModel
    let removal: Removal
    @State private var picked: String?
    @State private var typed = ""
    @State private var manual = false
    @Environment(\.dismiss) private var dismiss

    private var isSub: Bool { removal.sub != nil }
    private var name: String { removal.sub ?? removal.category }
    private var used: Int {
        CategoryOps.usage(model.state, removal.scope, category: removal.category, sub: removal.sub)
    }
    private var choices: [String] {
        (isSub ? CategoryOps.subcategories(model.state, removal.scope, category: removal.category)
               : CategoryOps.categories(model.state, removal.scope)).filter { $0 != name }
    }
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
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("انصراف") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button(used > 0 ? "جایگزین و حذف" : "حذف", role: .destructive) { run() }
                    .bold()
                    .accessibilityIdentifier("remove.confirm")
                    .disabled(used > 0 && replacement == nil)
            }
        }
    }

    private func run() {
        let ok: Bool
        if let s = removal.sub {
            ok = model.removeSubcategory(removal.scope, category: removal.category, s, replaceWith: replacement)
        } else {
            ok = model.removeCategory(removal.scope, removal.category, replaceWith: replacement)
        }
        if ok { Haptics.success(); dismiss() }
    }
}
