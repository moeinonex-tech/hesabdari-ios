import SwiftUI
import UIKit
import Charts
import UniformTypeIdentifiers
import HesabCore

// MARK: - theming wrapper (also used inside sheets)

struct Themed<Content: View>: View {
    @AppStorage("palette") private var paletteRaw = Palette.web.rawValue
    @ViewBuilder let content: Content

    var body: some View {
        ThemeHost(palette: Palette(rawValue: paletteRaw) ?? .web) { content }
            .environment(\.layoutDirection, .rightToLeft)
            .environment(\.locale, Locale(identifier: "fa_IR"))
            .environment(\.font, AppFont.body)
    }
}


// MARK: - root

struct RootView: View {
    @ObservedObject var model: AppModel
    @AppStorage("appearance") private var appearanceRaw = Appearance.system.rawValue
    @State private var showImporter = false
    @State private var exportFile: ExportFile?
    @State private var tab: AppTab = .home
    @AppStorage(AppLock.enabledKey) private var lockEnabled = true
    @State private var ledgerSheet: LedgerSheet?
    @StateObject private var lock = AppLock()
    @Environment(\.scenePhase) private var phase
    #if DEBUG
    @State private var uiTestCategories = ProcessInfo.processInfo.environment["UITEST_OPEN"] == "categories"
    @State private var uiTestBackup = ProcessInfo.processInfo.environment["UITEST_OPEN"] == "backup"
    #endif

    var body: some View {
        Themed {
            Group {
                if model.hasData {
                    AppShell(model: model, tab: $tab, ledgerSheet: $ledgerSheet, exportFile: $exportFile, showImporter: $showImporter)
                } else {
                    WelcomeView(showImporter: $showImporter)
                }
            }
            .overlay {
                if model.hasData && lock.locked {
                    LockScreen(lock: lock).transition(.opacity)
                } else if phase != .active && model.hasData && lockEnabled {
                    // hide the content in the app switcher only when the Face ID lock is on
                    PrivacyCover()
                }
            }
        }
        .onChange(of: phase) { _, p in
            if p == .background { lock.didEnterBackground() }
            if p == .active { lock.didBecomeActive(); model.backupToday(); if model.hasData { Notifier.sync(model.state) } }
        }
        .modifier(DueCheckPrompt(model: model, blocked: lock.locked || !model.hasData))
        .preferredColorScheme(Appearance(rawValue: appearanceRaw)?.scheme)
        #if DEBUG
        .sheet(isPresented: $uiTestCategories) {
            NavigationStack { CategoryManagerView(model: model) }
        }
        .sheet(isPresented: $uiTestBackup) {
            NavigationStack { SectionBackupView(model: model) }
        }
        #endif
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json, .plainText, .data]) { result in
            switch result {
            case .success(let url): model.openFile(url)
            case .failure(let error): model.errorMessage = error.localizedDescription
            }
        }
        .sheet(isPresented: Binding(get: { model.pending != nil }, set: { if !$0 { model.pending = nil } })) {
            if let report = model.pending {
                Themed {
                    NavigationStack {
                        ImportReportView(report: report, replacesExisting: model.hasData,
                                         onConfirm: { model.confirmImport(); Haptics.success() },
                                         onCancel: { model.pending = nil })
                    }
                }
            }
        }
        .sheet(item: $exportFile) { file in
            ActivityView(items: [file.url])
        }
        .alert("پیام", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("باشه", role: .cancel) { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
        .alert("انجام شد", isPresented: Binding(get: { model.infoMessage != nil && model.errorMessage == nil },
                                                 set: { if !$0 { model.infoMessage = nil } })) {
            Button("باشه", role: .cancel) { model.infoMessage = nil }
        } message: {
            Text(model.infoMessage ?? "")
        }
    }
}

/// one topic row of the settings hub: icon in a coloured tile, title, and a short status line
struct SettingsRow: View {
    let icon: String
    let tint: Color
    let title: String
    let detail: String?
    @Environment(\.theme) private var t
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(tint.gradient, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(AppFont.medium(15)).foregroundStyle(t.ink)
                if let d = detail, !d.isEmpty {
                    Text(d).font(AppFont.caption).foregroundStyle(t.soft).lineLimit(1)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - welcome

struct WelcomeView: View {
    @Binding var showImporter: Bool
    @Environment(\.theme) private var t

    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 22) {
                Spacer()
                Image(systemName: "book.pages.fill")
                    .font(.system(size: 60, weight: .medium))
                    .foregroundStyle(LinearGradient(colors: [t.accent, t.accent2], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .padding(26)
                    .glassEffect(.regular, in: Circle())
                Text("دفتر حساب").font(AppFont.heavy(34)).foregroundStyle(t.ink)
                Text("برای شروع، فایل «پشتیبان کامل» اپ وب را انتخاب کنید. قبل از ورود، گزارش کامل آن را می‌بینید و تا تأیید نکنید چیزی ذخیره نمی‌شود.")
                    .font(AppFont.regular(15))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(t.soft)
                    .padding(.horizontal, 34)
                Button {
                    showImporter = true
                } label: {
                    Label("انتخاب فایل پشتیبان", systemImage: "doc.badge.plus")
                        .font(AppFont.bold(17))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.glassProminent)
                .padding(.horizontal, 34)
                Spacer()
                Spacer()
            }
        }
    }
}
