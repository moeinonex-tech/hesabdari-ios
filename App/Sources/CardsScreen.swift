import SwiftUI
import UIKit
import Charts
import UniformTypeIdentifiers
import HesabCore

// MARK: - cards

struct CardsView: View {
    @ObservedObject var model: AppModel
    @State private var showArchived = false
    @State private var editing: IdBox?
    @State private var confirmDelete: String?
    @State private var shareFile: ExportFile?
    @Environment(\.theme) private var t

    /// web cwShareAsPng: a clean picture of the card
    @MainActor private func shareImage(_ c: WalletCard) {
        // the card alone, edge to edge, at ~3000 px wide (more than a 300 dpi print of a real card)
        let w: CGFloat = 1000
        let r = ImageRenderer(content: BankCardView(card: c, forSharing: true)
            .frame(width: w, height: w / 1.586)
            .environment(\.layoutDirection, .rightToLeft)
            .environment(\.theme, t))
        r.scale = 3
        r.isOpaque = true
        guard let img = r.uiImage, let data = img.pngData() else { return }
        let name = (c.bankName.isEmpty ? "کارت" : c.bankName) + ".png"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do { try data.write(to: url); shareFile = ExportFile(url: url) } catch { model.errorMessage = error.localizedDescription }
    }

    var body: some View {
        let cards = model.walletCards.filter { $0.archived == showArchived }
        PageScrollView(tab: .cards) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    ScreenHeader(title: "کیف کارت", subtitle: "برای کپی شماره، روی آن بزنید؛ برای ویرایش، نگه دارید")
                    HeaderIconButton(icon: "plus") { Haptics.tap(); editing = IdBox(id: "") }
                        .padding(.top, 8)
                }
                Segmented(selection: $showArchived, [(false, "کارت‌های فعال"), (true, "بایگانی‌شده")])
                if cards.isEmpty {
                    Text("کارتی نیست").font(AppFont.regular(14)).foregroundStyle(t.soft).frame(maxWidth: .infinity).padding(40)
                }
                ForEach(Array(cards.enumerated()), id: \.element.id) { idx, c in
                    BankCardView(card: c)
                        .neonEdge(radius: 22)
                        .modifier(FloatingCard(index: idx))
                        .entrance(idx)
                        .contextMenu {
                            Button { editing = IdBox(id: c.id) } label: { Label("ویرایش", systemImage: "pencil") }
                            if let text = model.record("cards", c.id).flatMap(SettingsOps.cardCopyText) {
                                Button {
                                    UIPasteboard.general.string = text
                                    Haptics.success()
                                } label: { Label("کپی همه‌ی اطلاعات", systemImage: "doc.on.doc") }
                                ShareLink(item: text) { Label("اشتراک به صورت متن", systemImage: "text.bubble") }
                            }
                            Button { shareImage(c) } label: { Label("اشتراک به صورت عکس", systemImage: "photo") }
                            Button {
                                _ = model.setCardArchived(c.id, !c.archived)
                            } label: {
                                Label(c.archived ? "خروج از بایگانی" : "بایگانی", systemImage: c.archived ? "tray.and.arrow.up" : "archivebox")
                            }
                            Button(role: .destructive) { confirmDelete = c.id } label: { Label("حذف", systemImage: "trash") }
                        }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .background(AppBackground())
        .scrollsToTopOnDockTap(.cards)
        .pageSwipe(.cards, $showArchived, [false, true])
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $editing) { e in
            NavigationStack { CardFormView(model: model, editingId: e.id.isEmpty ? nil : e.id) }
        }
        .sheet(item: $shareFile) { f in ActivityView(items: [f.url]) }
        .confirmationDialog("این کارت حذف شود؟", isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } }),
                            titleVisibility: .visible) {
            Button("حذف", role: .destructive) {
                if let id = confirmDelete { _ = model.deleteCard(id) }
                confirmDelete = nil
            }
        }
    }
}

struct IdBox: Identifiable, Hashable { let id: String }

struct BankCardView: View {
    let card: WalletCard
    /// the picture sent to someone else: only bank + logo, card number, IBAN, account number and holder; no
    /// account type, expiry, shadow or rounded corners (full-bleed, so no frame appears in any messenger)
    var forSharing = false
    @State private var copied: String?

    var body: some View {
        // the card's size and shape come only from this clear 1.586 box (ID-1 bank card); the photo or design is laid
        // over it, fills it and is cropped — it can never stretch or reshape the card
        Color.clear
            .aspectRatio(1.586, contentMode: .fit)
            .overlay { background }
            .overlay { LinearGradient(colors: [.black.opacity(0.08), .black.opacity(0.18), .black.opacity(0.5)], startPoint: .top, endPoint: .bottom) }
            .overlay { GeometryReader { g in face(g.size.width / 340) } }
            .clipShape(RoundedRectangle(cornerRadius: forSharing ? 0 : 22, style: .continuous))
            .shadow(color: .black.opacity(forSharing ? 0 : 0.25), radius: forSharing ? 0 : 14, y: forSharing ? 0 : 8)
    }

    /// layout in card units (u = 1 at a 340 pt wide card), so the app card and the large shared picture are identical:
    /// header · card number in the upper half · IBAN in the middle · account number in the lower half · holder at the bottom
    private func face(_ u: CGFloat) -> some View {
        ZStack {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 9 * u) {
                    BankLogo(bank: card.bank, name: card.bankName, size: 32 * u, tile: true)
                    Text(card.bankName).font(AppFont.heavy(17 * u)).lineLimit(1).minimumScaleFactor(0.6)
                    Spacer(minLength: 4 * u)
                    if !forSharing && !card.accountType.isEmpty {
                        Text(card.accountType).font(AppFont.medium(11.5 * u)).opacity(0.85).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                number(grouped(card.number), size: 23, weight: .bold, label: nil, copyLabel: "شماره کارت", value: card.number, u: u)
                Spacer(minLength: 0)
                if !card.iban.isEmpty {
                    number(groupedIban(card.iban), size: 13.5, weight: .medium, label: "شبا", copyLabel: "شبا", value: card.iban, u: u)
                }
                Spacer(minLength: 0)
                if !card.accountNumber.isEmpty {
                    number(card.accountNumber, size: 15, weight: .medium, label: "حساب", copyLabel: "شماره حساب", value: card.accountNumber, u: u)
                }
                Spacer(minLength: 0)
                HStack(alignment: .lastTextBaseline) {
                    Text(card.holder).font(AppFont.heavy(18 * u)).lineLimit(1).minimumScaleFactor(0.6)
                    Spacer(minLength: 6 * u)
                    if !forSharing && !card.expiry.isEmpty {
                        Text(Money.persianDigits(card.expiry)).font(AppFont.medium(12.5 * u)).opacity(0.9)
                    }
                }
            }
            .foregroundStyle(.white)
            // embossed print: a thin light edge above, a crisp dark edge below and a soft drop under the letters
            .shadow(color: .white.opacity(0.35), radius: 0, x: 0, y: -0.6 * u)
            .shadow(color: .black.opacity(0.55), radius: 0, x: 0, y: 0.9 * u)
            .shadow(color: .black.opacity(0.35), radius: 2.5 * u, x: 0, y: 1.6 * u)
            .padding(.horizontal, 18 * u)
            .padding(.vertical, 15 * u)
            if let c = copied {
                Text(c + " کپی شد")
                    .font(AppFont.bold(13))
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .glassEffect(.regular, in: Capsule())
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.scale.combined(with: .opacity))
            }
        }
    }

    /// one centred number line; a small label («شبا» / «حساب») sits in front of it, the number always left-to-right
    private func number(_ text: String, size: CGFloat, weight: Font.Weight, label: String?, copyLabel: String, value: String, u: CGFloat) -> some View {
        let line = HStack(spacing: 6 * u) {
            if let label {
                Text(label).font(AppFont.bold(10.5 * u)).opacity(0.85)
            }
            Text(Money.persianDigits(text))
                .font(weight == .bold ? AppFont.heavy(size * u) : AppFont.bold(size * u))
                .environment(\.layoutDirection, .leftToRight)
                .lineLimit(1).minimumScaleFactor(0.55)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        // in the shared picture there is nothing to tap (a disabled button would print faded)
        return Group {
            if forSharing {
                line
            } else {
                Button { copy(value, label: copyLabel) } label: { line }.buttonStyle(.plain)
            }
        }
    }

    /// IR12 3456 7890 … in groups of four, easier to read aloud
    private func groupedIban(_ s: String) -> String {
        let clean = s.replacingOccurrences(of: " ", with: "")
        var out = ""
        for (i, ch) in clean.enumerated() {
            if i > 0 && i % 4 == 0 { out.append(" ") }
            out.append(ch)
        }
        return out
    }

    @ViewBuilder private var background: some View {
        if let img = card.image {
            GeometryReader { g in
                Image(uiImage: img).resizable().scaledToFill()
                    .frame(width: g.size.width, height: g.size.height)
                    .clipped()
            }
        } else if let art = card.preset.flatMap(CardArt.init(rawValue:)) {
            CardArtView(art: art)
        } else {
            LinearGradient(colors: [card.color ?? Color.hex(0x1F3A5F), (card.color ?? Color.hex(0x1F3A5F)).opacity(0.6)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    private func grouped(_ s: String) -> String {
        let digits = s.filter(\.isNumber)
        guard digits.count == 16 else { return s }
        var out = ""
        for (i, ch) in digits.enumerated() {
            if i > 0 && i % 4 == 0 { out.append(" ") }
            out.append(ch)
        }
        return out
    }

    private func copy(_ text: String, label: String) {
        UIPasteboard.general.string = text.filter { !$0.isWhitespace }
        Haptics.success()
        withAnimation(.spring) { copied = label }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { withAnimation { copied = nil } }
    }
}
