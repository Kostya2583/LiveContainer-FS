//
//  FlekGeneralView.swift
//  LiveContainerSwiftUI
//
//  The "General" page, first in the Settings category list. It is where
//  FlekDeck is given what it needs to install and launch apps: a signing
//  certificate, or JIT instead. While no certificate is imported the page opens
//  with a setup card, and the row leading here and the Settings icon on the
//  home screen carry a red mark.
//
//  Importing a certificate has a page of its own, FlekCertificateImportView.
//  A FlekDeck that is not signed with a Development certificate cannot use one
//  at all, so there the card says so instead, and explains why in
//  FlekCertificateUnavailableView. Once a certificate is imported the card
//  shows whose it is and whether it still works, and offers its removal —
//  with a stronger warning while it still works. On a build whose Info.plist
//  carries a FlekSt0re device ID, it only shows whether it works.
//

import SwiftUI

struct FlekGeneralView<JITPage: View>: View {
    /// Whether this copy of FlekDeck can import or remove a certificate. One
    /// that is not the primary signs with the primary's.
    let managesCertificate: Bool
    /// Forgets the stored certificate. The page asks first.
    let onRemoveCertificate: () -> Void
    /// Where "Set Up JIT" leads: the JIT category's own page.
    @ViewBuilder let jitPage: () -> JITPage

    @EnvironmentObject private var sharedModel: SharedModel
    @State private var unavailableExplanationShown = false
    /// The imported certificate as the card shows it; nil while none is.
    @State private var certificate: FlekImportedCertificate?
    @State private var removalConfirmationShown = false

    /// Whether the Info.plist carries a FlekSt0re device ID, as the builds
    /// FlekSt0re signs do. Their certificate is one bought through FlekSt0re:
    /// the card says only whether it works, naming no holder, and it stays.
    private var isFlekStoreBuild: Bool {
        Bundle.main.flekStoreDeviceID != nil
    }

    /// Whether the card offers to remove the certificate.
    private var offersRemoval: Bool {
        managesCertificate && !isFlekStoreBuild
    }

    private static var certificatePoints: [String] {
        [
            "lc.flek.setup.certificate.point1".loc,
            "lc.flek.setup.certificate.point2".loc,
            "lc.flek.setup.certificate.point3".loc,
        ]
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                if sharedModel.needsCertificate {
                    setupCard
                }
                certificateCard
                NavigationLink {
                    jitPage()
                } label: {
                    FlekSetupOption(
                        icon: .symbol(FlekSymbol.jitConnection, .black),
                        title: "lc.flek.setup.jit.title".loc,
                        subtitle: "lc.flek.setup.jit.desc".loc,
                        showsChevron: true
                    ) {
                        FlekSetupPoints(points: [
                            "lc.flek.setup.jit.point1".loc,
                            "lc.flek.setup.jit.point2".loc,
                            "lc.flek.setup.jit.point3".loc,
                        ])
                    }
                }
                .buttonStyle(FlekCardPressStyle())
                footnote
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 32)
        }
        .background(Color(UIColor.systemGroupedBackground).ignoresSafeArea())
        .sheet(isPresented: $unavailableExplanationShown) {
            FlekCertificateUnavailableView()
        }
        .onAppear { loadCertificate() }
        .onChange(of: sharedModel.isCertificateImported) { _ in loadCertificate() }
        .alert(removalTitle, isPresented: $removalConfirmationShown) {
            Button("lc.common.cancel".loc, role: .cancel) {}
            Button("lc.common.remove".loc, role: .destructive) {
                onRemoveCertificate()
            }
        } message: {
            Text(removalMessage)
        }
    }

    // MARK: - Cards

    private var setupCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            FlekSetupTile(color: .orange, size: 44) {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 22))
                    // An orange mark on a white disc, rather than the white
                    // glyph every other tile carries.
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(Color.orange, Color.white)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("lc.flek.setup.title".loc)
                    .font(.system(size: 17))
                Text("lc.flek.setup.desc".loc)
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(FlekSetupCardBackground())
        .accessibilityElement(children: .combine)
    }

    /// An imported certificate gets a card of its own. Without one the whole
    /// card leads to the import page — or, on a FlekDeck that could not use a
    /// certificate anyway, says so and offers the reason — and a copy that
    /// cannot import one gets the card with neither.
    @ViewBuilder
    private var certificateCard: some View {
        if sharedModel.isCertificateImported {
            importedCertificateCard
        } else if managesCertificate && !LCProvisioningProfile.isAppDevelopmentSigned {
            certificateOption(isDimmed: true, showsChevron: true) {
                unavailableTray
            }
        } else if managesCertificate {
            NavigationLink {
                FlekCertificateImportView()
            } label: {
                certificateOption(showsChevron: true) {
                    FlekSetupPoints(points: Self.certificatePoints)
                }
            }
            .buttonStyle(FlekCardPressStyle())
        } else {
            certificateOption {
                FlekSetupPoints(points: Self.certificatePoints)
            }
        }
    }

    private func certificateOption<Tray: View>(
        isDimmed: Bool = false,
        showsChevron: Bool = false,
        @ViewBuilder tray: @escaping () -> Tray
    ) -> FlekSetupOption<Tray> {
        FlekSetupOption(
            icon: .symbol(FlekSymbol.certificate, .blue),
            title: "lc.settings.importCertificate".loc,
            subtitle: "lc.flek.setup.certificate.desc".loc,
            isDimmed: isDimmed,
            showsChevron: showsChevron,
            tray: tray
        )
    }

    /// The imported certificate: whose it is and whether it still works. Its
    /// details are on the JIT-less diagnosis page. On a FlekSt0re build the
    /// card leaves out whose it is.
    private var importedCertificateCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            NavigationLink {
                LCJITLessDiagnoseView()
            } label: {
                FlekSetupHeader(
                    icon: .symbol(FlekSymbol.certificate, .blue),
                    title: "lc.flek.certificate".loc,
                    showsChevron: true
                ) {
                    if !isFlekStoreBuild, let holder = certificate?.holder {
                        Text(holder)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    certificateStatus
                }
            }
            .buttonStyle(FlekCardPressStyle())

            if let certificate, certificate.isKnownValid {
                Text("lc.flek.certStatus.ready".loc)
                    .font(.system(size: 15))
                    .foregroundStyle(.green)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.green.opacity(0.12))
                    )
            }

            if let certificate, certificate.isInvalid {
                Text(invalidText(for: certificate))
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(UIColor.tertiarySystemFill))
                    )
            }

            if offersRemoval, certificate != nil {
                Button {
                    removalConfirmationShown = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "trash")
                        Text("lc.settings.removeCertificate".loc)
                    }
                    .font(.system(size: 17))
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .background(Capsule().fill(Color(UIColor.tertiarySystemFill)))
                }
                .buttonStyle(FlekCardPressStyle())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(FlekSetupCardBackground())
    }

    /// Revoked, expired, or valid until when. The expiry is known at once, from
    /// the file; a revocation only once Apple has answered, so until then — or
    /// when it cannot be asked — the card goes by the expiry alone.
    @ViewBuilder
    private var certificateStatus: some View {
        if let certificate {
            if certificate.revocation == .revoked {
                Text("lc.flek.certStatus.revoked".loc)
                    .foregroundStyle(.red)
            } else if let expiry = certificate.expirationDate {
                if certificate.isExpired {
                    Text(String(format: "lc.flek.certStatus.expired".loc, Self.dateText(expiry)))
                        .foregroundStyle(.red)
                } else {
                    Text(String(format: "lc.flek.certStatus.expires".loc, Self.dateText(expiry)))
                        .foregroundStyle(.green)
                }
            } else {
                Text("lc.flek.certificate.imported".loc)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// What the card says of a certificate that no longer works. It points to
    /// Remove only where the card offers it.
    private func invalidText(for certificate: FlekImportedCertificate) -> String {
        if certificate.isFromFlekStore {
            return "lc.flek.certStatus.invalidFlekStore".loc
        }
        return offersRemoval
            ? "lc.flek.certStatus.invalid".loc
            : "lc.flek.certStatus.invalidNoRemoval".loc
    }

    /// Removing a certificate that still works is most likely a mistake, so it
    /// gets its own title and says what will be lost; one that no longer works
    /// gets the usual question.
    private var removalTitle: String {
        certificate?.isKnownValid == true
            ? "lc.flek.certRemove.validTitle".loc
            : "lc.settings.removeCertificate".loc
    }

    private var removalMessage: String {
        guard let certificate, certificate.isKnownValid, let expiry = certificate.expirationDate else {
            return "lc.settings.removeCertificateDesc".loc
        }
        var message = String(format: "lc.flek.certRemove.validWarning".loc, Self.dateText(expiry))
        if certificate.isFromFlekStore {
            // The launch import takes the bundled certificate whenever none is
            // stored, so FlekSt0re's comes back unless another replaces it.
            message += "\n\n" + "lc.flek.certRemove.flekStoreNote".loc
        }
        return message
    }

    /// Takes the place of the certificate's points when this FlekDeck cannot
    /// use a certificate: what is wrong, and a way to find out why.
    private var unavailableTray: some View {
        VStack(spacing: 6) {
            Text("lc.flek.setup.certificate.unavailable".loc)
                .font(.system(size: 15))
                .foregroundStyle(.orange)
            Button {
                unavailableExplanationShown = true
            } label: {
                Text("lc.flek.setup.certificate.why".loc)
                    .font(.system(size: 17))
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(FlekCardPressStyle())
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(UIColor.tertiarySystemFill))
        )
    }

    private var footnote: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "info.circle")
            Text("lc.flek.setup.footer".loc)
        }
        .font(.system(size: 15))
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 2)
    }

    // MARK: - Certificate

    /// Reads the stored certificate, then asks Apple whether it has been
    /// revoked. The first is instant and works offline; the answer to the
    /// second arrives later, if at all.
    private func loadCertificate() {
        guard sharedModel.isCertificateImported, let stored = FlekImportedCertificate.stored() else {
            certificate = nil
            return
        }
        certificate = stored
        LCUtils.validateCertificate { status, _, _, _ in
            DispatchQueue.main.async {
                // An answer about a certificate replaced meanwhile is dropped.
                guard certificate?.data == stored.data else { return }
                certificate?.revocation = FlekImportedCertificate.Revocation(ocspStatus: status)
            }
        }
    }

    /// A date the way the device writes one, "3 Mar 2027" or "3 мар. 2027 г.".
    private static func dateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}

/// What General shows of the imported certificate.
private struct FlekImportedCertificate {
    /// Apple's answer on whether the certificate has been revoked.
    enum Revocation {
        case checking, good, revoked, unknown

        /// From the status ZSign's OCSP check reports: 0 good, 1 revoked, and
        /// anything else no answer.
        init(ocspStatus: Int32) {
            switch ocspStatus {
            case 0: self = .good
            case 1: self = .revoked
            default: self = .unknown
            }
        }
    }

    /// The stored certificate itself, which tells an answer about it from one
    /// about a certificate that has replaced it.
    let data: Data
    /// Who the certificate belongs to, as it names them.
    let holder: String?
    let expirationDate: Date?
    /// Whether it is the certificate FlekSt0re put in this build, rather than
    /// one imported by hand.
    let isFromFlekStore: Bool
    var revocation = Revocation.checking

    var isExpired: Bool {
        expirationDate.map { $0 < Date() } ?? false
    }

    var isInvalid: Bool {
        isExpired || revocation == .revoked
    }

    /// Whether it is known to still work: not expired, not revoked as far as
    /// Apple has said, and with an expiry to go by at all.
    var isKnownValid: Bool {
        expirationDate != nil && !isInvalid
    }

    /// The certificate FlekSt0re puts in the builds it signs. A stored one that
    /// matches it came from FlekSt0re; any other was imported by hand.
    private static let bundledFlekStoreCertificate: Data? = Bundle.main
        .url(forResource: "fs_cert", withExtension: "p12")
        .flatMap { try? Data(contentsOf: $0) }

    /// The stored certificate as far as the file itself tells: its holder and
    /// its expiry. Whether it has been revoked is Apple's to answer.
    static func stored() -> FlekImportedCertificate? {
        guard let data = LCUtils.certificateData(),
              let password = LCSharedUtils.certificatePassword() else {
            return nil
        }
        let info = LCUtils.getCertInfo(withKeyData: data, password: password)
        return FlekImportedCertificate(
            data: data,
            holder: (info?["commonName"] as? String).map(holderName),
            expirationDate: info?["notAfter"] as? Date,
            isFromFlekStore: data == bundledFlekStoreCertificate
        )
    }

    /// The holder without the certificate's kind in front: "Jane Appleseed
    /// (ABCDE12345)" out of "Apple Development: Jane Appleseed (ABCDE12345)".
    private static func holderName(_ commonName: String) -> String {
        guard let separator = commonName.range(of: ": ") else { return commonName }
        return String(commonName[separator.upperBound...])
    }
}

/// What a General card leads with: a white symbol on a coloured tile, or an
/// artwork that is a tile of its own.
private enum FlekSetupIcon {
    case symbol(String, Color)
    case asset(String)
}

/// The top of a card on the General page: an icon tile, a title and the lines
/// beneath it, with a chevron in the corner for a card that leads somewhere.
private struct FlekSetupHeader<Detail: View>: View {
    let icon: FlekSetupIcon
    let title: String
    /// Fades the heading, for an option this FlekDeck cannot take.
    var isDimmed = false
    var showsChevron = false
    /// The lines under the title, set in the card's smaller size.
    @ViewBuilder var detail: () -> Detail

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            iconView
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 17))
                    .foregroundStyle(.primary)
                    // Clear of the chevron in the corner. The lines below may
                    // run under it, as the design draws them.
                    .padding(.trailing, 28)
                detail()
            }
            .font(.system(size: 15))
            .multilineTextAlignment(.leading)
            // Filling the row itself rather than beside a spacer, which would
            // cost the text another gap's worth of width.
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // In the corner rather than in a column of its own, so that the lines
        // below get the card's full width.
        .overlay(alignment: .topTrailing) {
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(UIColor.tertiaryLabel))
                    // Level with the title's line rather than the tile's top.
                    .padding(.top, 3)
            }
        }
        .opacity(isDimmed ? 0.45 : 1)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var iconView: some View {
        switch icon {
        case .symbol(let systemImage, let color):
            FlekSetupTile(color: color, size: 56) {
                Image(systemName: systemImage)
                    .font(.system(size: 27))
                    .foregroundStyle(.white)
            }
        case .asset(let name):
            // A full-bleed square, given the tiles' squircle.
            Image(name)
                .resizable()
                .scaledToFill()
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: (56 * 0.2237).rounded(), style: .continuous))
        }
    }
}

/// One way of getting FlekDeck ready: an icon, what the way is and what it
/// means, and a tray beneath — its points, or whatever stands in for them.
private struct FlekSetupOption<Tray: View>: View {
    let icon: FlekSetupIcon
    let title: String
    let subtitle: String
    /// Fades the heading, for an option this FlekDeck cannot take. The tray
    /// stays as it is, since it is what says why.
    var isDimmed = false
    /// For a card that leads to a page of its own.
    var showsChevron = false
    @ViewBuilder var tray: () -> Tray

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            FlekSetupHeader(
                icon: icon,
                title: title,
                isDimmed: isDimmed,
                showsChevron: showsChevron
            ) {
                Text(subtitle)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            tray()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(FlekSetupCardBackground())
        // The whole card is the control when it sits in a button, not just the
        // parts of it that are drawn.
        .contentShape(RoundedRectangle(cornerRadius: FlekSetupCardBackground.cornerRadius, style: .continuous))
    }
}

/// An option's points, listed in a tray.
private struct FlekSetupPoints: View {
    let points: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(points, id: \.self) { point in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(verbatim: "\u{00B7}")
                        .fontWeight(.bold)
                    Text(point)
                        .multilineTextAlignment(.leading)
                }
            }
        }
        .font(.system(size: 15))
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(UIColor.tertiarySystemFill))
        )
    }
}

/// A card on the General page and the pages it leads to, raised off the
/// grouped background the way a Settings section is.
struct FlekSetupCardBackground: View {
    static let cornerRadius: CGFloat = 24

    var body: some View {
        RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
            .fill(Color(UIColor.secondarySystemGroupedBackground))
    }
}

/// A rounded-square icon tile, with the same sheen from the top as the
/// Settings category icons. The sheen is also what keeps a black tile apart
/// from a dark card.
struct FlekSetupTile<Glyph: View>: View {
    let color: Color
    let size: CGFloat
    @ViewBuilder let glyph: () -> Glyph

    var body: some View {
        // The home screen's squircle ratio, so a tile reads as an app icon.
        let tile = RoundedRectangle(cornerRadius: (size * 0.2237).rounded(), style: .continuous)
        glyph()
            .frame(width: size, height: size)
            .background(
                tile.fill(color)
                    .overlay(
                        tile.fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.3), Color.white.opacity(0)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    )
            )
    }
}

/// Dims a card while it is held, the way a Settings row highlights, without the
/// tint a plain button would put on its text.
struct FlekCardPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.55 : 1)
    }
}
