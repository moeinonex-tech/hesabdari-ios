import SwiftUI
import HesabCore

// Edit-lock password, learning history, factory reset, bulk quotes — web: passwordSettingsModal,
// factoryResetMenu (clear-learning / wipe-all), quoteBulkPreview, clearCustomQuotesConfirm.

extension AppModel {
    var hasEditPassword: Bool { !(state["editLockPassword"]?.stringValue ?? "").isEmpty }
    func setEditPassword(_ p: String) -> Bool {
        let v = p.trimmingCharacters(in: .whitespaces)
        guard v.count >= 4 else { errorMessage = "رمز باید حداقل ۴ کاراکتر باشه"; return false }
        let ok = change { var st = state; st["editLockPassword"] = .string(v); return st }
        if ok { _ = unlock(password: v) }       // web: don't lock out the person who just set it
        return ok
    }
    func removeEditPassword() -> Bool { change { var st = state; st["editLockPassword"] = .string(""); return st } }
    func clearLearning() -> Bool { change { QuoteBulk.clearLearning(state) } }
    func addBulkQuotes(_ items: [BulkQuote]) -> (added: Int, skipped: Int) {
        var res = (0, 0)
        _ = change {
            let r = QuoteBulk.add(state, items)
            res = (r.added, r.skipped)
            if r.added == 0 { throw LedgerError.message("چیزی برای افزودن نبود — متن‌های خیلی کوتاه رد شدند") }
            return r.state
        }
        return res
    }
    func clearAllQuotes() -> Bool { change({ var st = state; st["customQuotes"] = .array([]); return st }, undoMessage: "همه‌ی جمله‌ها حذف شد") }
}

// MARK: - edit-lock password

struct EditPasswordView: View {
    @ObservedObject var model: AppModel
    @State private var current = ""
    @State private var newPass = ""
    @State private var message: String?

    var body: some View {
        Form {
            if model.hasEditPassword {
                Section {
                    SecureField("رمز فعلی", text: $current).keyboardType(.numberPad)
                    SecureField("رمز جدید (حداقل ۴ رقم)", text: $newPass).keyboardType(.numberPad)
                    Button("تغییر رمز") {
                        guard model.unlock(password: current) else { message = "رمز فعلی اشتباهه"; return }
                        if model.setEditPassword(newPass) { message = "رمز عوض شد"; current = ""; newPass = "" }
                    }
                    Button("حذف رمز (غیرفعال‌کردن قفل)", role: .destructive) {
                        guard model.unlock(password: current) else { message = "برای حذف، رمز فعلی رو درست وارد کن"; return }
                        if model.removeEditPassword() { message = "قفل غیرفعال شد"; current = "" }
                    }
                } footer: {
                    Text("برای تغییر یا حذف، اول رمز فعلی رو وارد کن.")
                }
            } else {
                Section {
                    SecureField("رمز جدید (حداقل ۴ رقم)", text: $newPass).keyboardType(.numberPad)
                    Button("تنظیم رمز") { if model.setEditPassword(newPass) { message = "رمز تنظیم شد — قفل فعال شد"; newPass = "" } }
                } footer: {
                    Text("با رمز، ویرایش و حذف ردیف‌هایی که بیش از ۸ روز از تاریخشان گذشته، رمز می‌خواهد. هر بار باز کردن قفل ۱۵ دقیقه اعتبار دارد.")
                }
            }
            if let m = message { Section { Text(m).foregroundStyle(.secondary) } }
        }
        .navigationTitle("رمز ردیف‌های قدیمی")
    }
}

// MARK: - danger zone

struct DangerZoneView: View {
    @ObservedObject var model: AppModel
    @State private var confirmLearning = false
    @State private var confirmWipe = false
    @State private var wipeText = ""
    @State private var done: String?

    var body: some View {
        Form {
            Section {
                Button("پاک کردن هیستوری یادگیری", role: .destructive) { confirmLearning = true }
            } footer: {
                Text("فقط پیشنهادهای خودکارِ یادگرفته‌شده برای دسته و زیردسته پاک می‌شوند؛ خودِ ردیف‌ها و دسته‌ها دست نمی‌خورند.")
            }
            Section {
                TextField("برای تایید بنویسید: پاک کن", text: $wipeText)
                Button("پاک کردن تمامی اطلاعات اپ", role: .destructive) { confirmWipe = true }
                    .disabled(wipeText.trimmingCharacters(in: .whitespaces) != "پاک کن")
            } footer: {
                Text("همه‌ی حساب‌ها، هزینه‌ها، درآمدها، یادآوری‌ها، کارت‌ها، رمز و تنظیمات اپ پاک می‌شوند. قبلش یک نسخه‌ی پشتیبان کامل در «پشتیبان‌ها» ذخیره می‌شود؛ اگر ساخته نشود، هیچ چیزی پاک نمی‌شود.")
            }
            if let d = done { Section { Text(d).foregroundStyle(.secondary) } }
        }
        .navigationTitle("پاک‌سازی")
        .confirmationDialog("هیستوری یادگیری پاک شود؟", isPresented: $confirmLearning, titleVisibility: .visible) {
            Button("بله، پاک کن", role: .destructive) { if model.clearLearning() { Haptics.warning(); done = "هیستوری یادگیری پاک شد" } }
        }
        .confirmationDialog("همه‌چیز پاک شود؟ این کار برگشت‌ناپذیر است.", isPresented: $confirmWipe, titleVisibility: .visible) {
            Button("بله، همه‌چیز رو پاک کن", role: .destructive) { if model.factoryReset() { Haptics.warning() } }
        }
    }
}

// MARK: - bulk quotes

struct QuoteBulkView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var raw = ""
    @State private var items: [BulkQuote]?
    @State private var result: String?

    var body: some View {
        Form {
            if let list = items {
                let susp = list.filter(\.suspicious).count
                Section {
                    Text(Money.persianDigits(String(list.count)) + " مورد شناسایی شد" +
                         (susp > 0 ? " — " + Money.persianDigits(String(susp)) + " موردِ مشکوک نیاز به بررسی دارد" : "") +
                         ". قبل از تایید، می‌تونی هر مورد رو ویرایش یا حذف کنی؛ چیزی هنوز ذخیره نشده.")
                        .font(AppFont.caption)
                }
                ForEach(Array(list.indices), id: \.self) { i in
                    Section {
                        if list[i].suspicious { Text("نیاز به بررسی").font(AppFont.caption).foregroundStyle(.orange) }
                        TextField("متن جمله", text: Binding(get: { items?[i].text ?? "" }, set: { items?[i].text = $0 }), axis: .vertical)
                        TextField("نویسنده (اختیاری)", text: Binding(get: { items?[i].author ?? "" }, set: { items?[i].author = $0 }))
                        Button("حذف از پیش‌نمایش", role: .destructive) { items?.remove(at: i) }
                    }
                }
            } else {
                Section {
                    TextEditor(text: $raw).frame(minHeight: 220)
                } footer: {
                    Text("فرمت‌ها: «متن» و خط بعد «— نویسنده»، یا «نویسنده:» و خط بعد متن، یا چند جمله که با خط خالی از هم جدا شده‌اند.")
                }
            }
        }
        .navigationTitle(items == nil ? "ورود انبوه جمله‌ها" : "پیش‌نمایش")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("انصراف") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                if let list = items {
                    Button("افزودن به مجموعه") {
                        let r = model.addBulkQuotes(list)
                        if r.added > 0 { Haptics.success(); dismiss() }
                    }
                    .bold()
                    .disabled(list.isEmpty)
                } else {
                    Button("بررسی") { items = QuoteBulk.parse(raw) }
                        .bold()
                        .disabled(raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
