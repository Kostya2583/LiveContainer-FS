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
//  From iOS 26 a certificate is what apps launch with, JIT or no JIT: nothing
//  starts without one there, see invokeAppMain in LCBootstrap. So on those
//  systems the page words the certificate as needed and JIT as what comes on
//  top of it, for the apps that want it, rather than the two as a choice.
//
//  The JIT card is the way to set JIT up until that has been started, and from
//  then on says how it stands: how far the setup has got, that it is ready and
//  for how many apps, or what is in its way. Either way it leads to the JIT
//  page.
//
//  The page opens with the device itself: which model it is and its UDID, and
//  under them whether Premium is active for it. Settings has no other place
//  for these. A build FlekSt0re signed learns the UDID and Premium from
//  FlekSt0re's status service, and shows them from the start. One it did not
//  sign cannot know the UDID by itself, and offers to add it: that downloads a
//  profile reporting it, FlekUDIDProfile, and walks through installing that in
//  FlekUDIDProfileView. Premium is FlekSt0re's to grant, so such a build has
//  none to show and says where to get it. It shows the device once a
//  certificate is imported: until then getting one is all its page is about.
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
    /// Set to get the UDID with the profile.
    @State private var asksForUDID = false
    @State private var statusUnreachableShown = false
    @State private var premiumSheetShown = false
    /// While FlekSt0re's status service is asked about this device.
    @State private var isCheckingStatus = false
    /// For a moment after the UDID has been copied.
    @State private var udidCopied = false
    /// The UDID the profile has just reported, while the page says so.
    @State private var importedUDID: String?
    /// Where the JIT setup stands, and how many apps use it. Read as the page
    /// comes up, which it also does on the way back from the JIT page.
    @State private var jitStanding = FlekJITSetup.Standing.notStarted
    @State private var jitAppCount = 0
    @ObservedObject private var vpn = FlekLoopbackVPN.shared

    /// This device's UDID, once FlekDeck knows it: from FlekSt0re, typed in for
    /// JIT, or reported by the UDID profile.
    @AppStorage("LCDeviceUDID", store: LCUtils.appGroupUserDefault) private var deviceUDID: String = ""
    /// What is kept of Premium, read here so that the page follows a change
    /// of it. Whether it is active is FlekPremium's to say, from the same.
    @AppStorage("FSSubscriptionStatus") private var keptPremiumStatus = false
    @AppStorage("FSSubscriptionEndDate") private var keptPremiumEnd = ""

    /// Whether the Info.plist carries a FlekSt0re device ID, as the builds
    /// FlekSt0re signs do. Their certificate is one bought through FlekSt0re:
    /// the card says only whether it works, naming no holder, and it stays.
    private var isFlekStoreBuild: Bool {
        Bundle.main.flekStoreDeviceID != nil
    }

    /// Whether the page shows the device and its Premium. A copy FlekSt0re
    /// signed has them looked up for it, and shows them whatever else is set
    /// up. Any other shows them once a certificate is imported.
    private var showsDevice: Bool {
        FlekPremium.deviceID != nil || !sharedModel.needsCertificate
    }

    /// The UDID, where FlekDeck knows it.
    private var knownUDID: String? {
        let udid = deviceUDID.trimmingCharacters(in: .whitespacesAndNewlines)
        return udid.isDeviceUDID ? udid : nil
    }

    /// Whether the card offers to remove the certificate.
    private var offersRemoval: Bool {
        managesCertificate && !isFlekStoreBuild
    }

    /// Whether apps launch with a certificate only, whatever JIT is set up,
    /// which is so from iOS 26. Before that JIT is another way to launch
    /// them, and the page offers the two side by side.
    private var isCertificateRequired: Bool {
        if #available(iOS 26.0, *) {
            return true
        }
        return false
    }

    /// What the JIT card adds where its setup is under way or done and there
    /// is no certificate to launch anything with: ready or not, JIT alone
    /// starts no app there.
    private var missingCertificateNote: String? {
        isCertificateRequired && sharedModel.needsCertificate ? "lc.flek.setup.jit.needsCertificate".loc : nil
    }

    private var jitDescription: String {
        (isCertificateRequired ? "lc.flek.setup.jit.desc.extra" : "lc.flek.setup.jit.desc").loc
    }

    private var jitPoints: [String] {
        isCertificateRequired
            ? ["lc.flek.setup.jit.extra.point1".loc, "lc.flek.setup.jit.extra.point2".loc, "lc.flek.setup.jit.extra.point3".loc]
            : ["lc.flek.setup.jit.point1".loc, "lc.flek.setup.jit.point2".loc, "lc.flek.setup.jit.point3".loc]
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
                if showsDevice {
                    deviceCard
                }
                if sharedModel.needsCertificate {
                    setupCard
                }
                certificateCard
                NavigationLink {
                    jitPage()
                } label: {
                    jitCard
                }
                .buttonStyle(FlekCardPressStyle())
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 32)
            // On the page rather than the device's card, which has an alert of
            // its own.
            .alert(
                "lc.flek.udidProfile.importedTitle".loc,
                isPresented: Binding(get: { importedUDID != nil }, set: { if !$0 { importedUDID = nil } }),
                presenting: importedUDID
            ) { udid in
                Button("lc.common.copy".loc) {
                    UIPasteboard.general.string = udid
                }
                Button("lc.common.ok".loc, role: .cancel) {}
            } message: { udid in
                Text(String(format: "lc.flek.udidProfile.importedMessage".loc, udid))
            }
        }
        .onReceive(FlekUDIDProfile.udidReceived) { udid in
            // Where the Premium sheet was what asked for it, it says so itself.
            guard !premiumSheetShown else { return }
            // Once the sheet has gone, which the alert would otherwise race.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                importedUDID = udid
            }
        }
        .background(Color(UIColor.systemGroupedBackground).ignoresSafeArea())
        .sheet(isPresented: $unavailableExplanationShown) {
            FlekCertificateUnavailableView()
        }
        .onAppear {
            loadCertificate()
            loadJITStanding()
        }
        .onChange(of: sharedModel.isCertificateImported) { _ in loadCertificate() }
        .task {
            // What the VPN's model last noted may be from before the VPN was
            // removed in the Settings app.
            if FlekLoopbackVPN.isAvailable {
                await vpn.refresh()
                loadJITStanding()
            }
        }
        .task {
            // Without being asked only where there is something to learn: the
            // UDID, or a Premium bought since.
            if knownUDID == nil || !FlekPremium.isActive {
                await refreshDeviceStatus(isAsked: false)
            }
        }
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
                Text((isCertificateRequired ? "lc.flek.setup.desc.required" : "lc.flek.setup.desc").loc)
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

    /// JIT's card. Until its setup has been started it is the way to start it,
    /// like the certificate's; from then on it says how the setup stands.
    @ViewBuilder
    private var jitCard: some View {
        switch jitStanding {
        case .notStarted:
            FlekSetupOption(
                icon: .symbol(FlekSymbol.jit, .black),
                title: "lc.flek.setup.jit.title".loc,
                subtitle: jitDescription,
                showsChevron: true
            ) {
                FlekSetupPoints(points: jitPoints)
            }
        case .underWay(let stepsDone):
            jitStatusCard(title: "lc.flek.setup.jit.title".loc,
                          status: String(format: "lc.flek.setup.jit.progress %lld".loc, stepsDone), color: .orange,
                          note: missingCertificateNote ?? "lc.flek.setup.jit.progress.note".loc)
        case .ready:
            // Ready for no app is ready for nothing, so the card says which.
            if jitAppCount > 0 {
                jitStatusCard(title: "lc.flek.setup.jit.name".loc,
                              status: "lc.flek.jit.ready".loc, color: .green,
                              detail: String(format: "lc.flek.jit.step4.caption.count %lld".loc, jitAppCount),
                              note: missingCertificateNote ?? "lc.flek.setup.jit.ready.note".loc,
                              isGood: missingCertificateNote == nil)
            } else {
                jitStatusCard(title: "lc.flek.setup.jit.name".loc,
                              status: "lc.flek.jit.ready".loc, color: .green,
                              detail: "lc.flek.setup.jit.noApps".loc,
                              note: missingCertificateNote ?? "lc.flek.setup.jit.noApps.note".loc)
            }
        case .needsPremium:
            jitStatusCard(title: "lc.flek.setup.jit.name".loc,
                          status: "lc.flek.setup.jit.premium".loc, color: .red,
                          note: "lc.flek.setup.jit.premium.note".loc)
        case .unavailable(let reason):
            // As the certificate's card is where this FlekDeck cannot use
            // one: the heading faded, and what is wrong in the tray.
            FlekSetupOption(
                icon: .symbol(FlekSymbol.jit, .black),
                title: "lc.flek.setup.jit.title".loc,
                subtitle: jitDescription,
                isDimmed: true,
                showsChevron: true
            ) {
                VStack(spacing: 6) {
                    Text("lc.flek.setup.jit.unavailable".loc)
                        .foregroundStyle(.orange)
                    Text(reason)
                        .foregroundStyle(.secondary)
                }
                .font(.system(size: 15))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(UIColor.tertiarySystemFill))
                )
            }
        case .external(let enabler):
            jitStatusCard(title: "lc.flek.setup.jit.name".loc,
                          status: String(format: "lc.flek.setup.jit.external %@".loc, enabler), color: .secondary,
                          note: missingCertificateNote)
        }
    }

    /// The JIT card once there is something to say of the setup: how it
    /// stands, in the colour that goes with that, a line of detail, and a note
    /// in plain words beneath. Laid out as the imported certificate's card is.
    private func jitStatusCard(title: String, status: String, color: Color, detail: String? = nil,
                               note: String? = nil, isGood: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            FlekSetupHeader(
                icon: .symbol(FlekSymbol.jit, .black),
                title: title,
                showsChevron: true
            ) {
                Text(status)
                    .foregroundStyle(color)
                if let detail {
                    Text(detail)
                        .foregroundStyle(.secondary)
                }
            }
            if let note {
                Text(note)
                    .font(.system(size: 15))
                    .foregroundStyle(isGood ? Color.green : Color.secondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(isGood ? Color.green.opacity(0.12) : Color(UIColor.tertiarySystemFill))
                    )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(FlekSetupCardBackground())
        // The whole card is the link, not just the parts of it that are drawn.
        .contentShape(RoundedRectangle(cornerRadius: FlekSetupCardBackground.cornerRadius, style: .continuous))
    }

    private func loadJITStanding() {
        jitStanding = FlekJITSetup.standing
        jitAppCount = FlekJITAppsView.countUsingJIT
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
            subtitle: (isCertificateRequired ? "lc.flek.setup.certificate.desc.required"
                                             : "lc.flek.setup.certificate.desc").loc,
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

    // MARK: - Device

    /// The device and its Premium, first on the page: which model it is, its
    /// UDID once FlekDeck knows it, and under them whether Premium is active
    /// for it.
    private var deviceCard: some View {
        VStack(spacing: 0) {
            deviceRow
            Divider()
                // From where the text starts, as between two Settings rows.
                .padding(.leading, 16 + 56 + 8)
            premiumRow
        }
        .background(FlekSetupCardBackground())
        .sheet(isPresented: $premiumSheetShown) {
            FlekPremiumOfferView()
        }
        .alert("lc.flek.premium.title".loc, isPresented: $statusUnreachableShown) {
            Button("lc.common.ok".loc, role: .cancel) {}
        } message: {
            Text("lc.flek.jit.premium.unconfirmed".loc)
        }
    }

    /// The model, which FlekDeck can read for itself, and the UDID, which it
    /// has to be told. What getting it shows hangs from the row rather than
    /// the page, which already has an alert and a sheet of its own.
    private var deviceRow: some View {
        HStack(alignment: .center, spacing: 8) {
            FlekSetupTile(color: .blue, size: 56) {
                Image(systemName: FlekDeviceModel.isPad ? "apps.ipad" : "apps.iphone")
                    // Larger than the other tiles' glyphs: a thin outline, which
                    // reads smaller at their size.
                    .font(.system(size: 32))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(FlekDeviceModel.name)
                    .font(.system(size: 17))
                Text("lc.flek.general.udid".loc)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    if let udid = knownUDID {
                        Text(Self.shortened(udid))
                            .font(.system(size: 15, design: .monospaced))
                            .foregroundStyle(Color.primary.opacity(0.75))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Spacer(minLength: 0)
                        copyButton(for: udid)
                    } else {
                        Text("lc.flek.general.udid.unknown".loc)
                            .font(.system(size: 15))
                            .foregroundStyle(.orange)
                        Spacer(minLength: 0)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if knownUDID == nil {
                udidRetrieval
            }
        }
        .padding(16)
        .flekUDIDRetrieval(isAsked: $asksForUDID)
    }

    /// How an unknown UDID is got. A build FlekSt0re signed asks the status
    /// service, which knows the device it was signed for. Any other has it
    /// reported by a profile, which the user installs.
    @ViewBuilder
    private var udidRetrieval: some View {
        if FlekPremium.deviceID == nil {
            Button("lc.flek.general.udid.add".loc) {
                asksForUDID = true
            }
            .font(.system(size: 15, weight: .semibold))
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.small)
        } else if isCheckingStatus {
            ProgressView()
        } else {
            refreshButton
        }
    }

    /// The UDID is shown with its middle left out, and copied whole.
    private func copyButton(for udid: String) -> some View {
        Button {
            UIPasteboard.general.string = udid
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            udidCopied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                udidCopied = false
            }
        } label: {
            Image(systemName: udidCopied ? "checkmark" : "square.on.square")
                .font(.system(size: 18))
                .foregroundStyle(Color.accentColor)
                .frame(width: 24, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(FlekCardPressStyle())
        .accessibilityLabel("lc.flek.general.udid.copy".loc)
    }

    private var refreshButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            Task { await refreshDeviceStatus(isAsked: true) }
        } label: {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 18))
                .foregroundStyle(Color.accentColor)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(FlekCardPressStyle())
        .accessibilityLabel("lc.flek.premium.refresh".loc)
    }

    /// Where Premium stands by what is kept of it.
    private enum PremiumStanding {
        case checking
        /// Until this day, or with no end given.
        case active(until: String?)
        case ended(String)
        case none
    }

    private var premiumStanding: PremiumStanding {
        // Read so that the page follows what is kept.
        _ = keptPremiumStatus
        let end = Self.dayText(keptPremiumEnd)
        if isCheckingStatus {
            return .checking
        }
        if FlekPremium.isActive {
            return .active(until: end)
        }
        if let end {
            return .ended(end)
        }
        return .none
    }

    /// Premium for this device. Active, it says until when and can be asked
    /// about again. Otherwise the row leads to how Premium is got, which is
    /// also all there is to say on a build FlekSt0re did not sign.
    @ViewBuilder
    private var premiumRow: some View {
        switch premiumStanding {
        case .checking:
            premiumRowContent {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text("lc.flek.premium.checking".loc)
                        .foregroundStyle(.secondary)
                }
            } accessory: {
                EmptyView()
            }
        case .active(let until):
            premiumRowContent {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                    Text(until.map { String(format: "lc.flek.premium.validTill %@".loc, $0) } ?? "lc.flek.premium.active".loc)
                }
                .foregroundStyle(.green)
            } accessory: {
                if FlekPremium.deviceID != nil {
                    refreshButton
                }
            }
        case .ended(let day):
            premiumOffer {
                Text(String(format: "lc.flek.premium.ended %@".loc, day))
                    .foregroundStyle(.red)
            }
        case .none:
            premiumOffer {
                Text("lc.flek.premium.unlock".loc)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// The row as the way to getting Premium.
    private func premiumOffer<Status: View>(@ViewBuilder status: () -> Status) -> some View {
        Button {
            premiumSheetShown = true
        } label: {
            premiumRowContent(status: status) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(UIColor.tertiaryLabel))
            }
        }
        .buttonStyle(FlekCardPressStyle())
    }

    private func premiumRowContent<Status: View, Accessory: View>(
        @ViewBuilder status: () -> Status,
        @ViewBuilder accessory: () -> Accessory
    ) -> some View {
        HStack(alignment: .center, spacing: 8) {
            // A full-bleed square, given the tiles' squircle.
            Image("premiumLogo")
                .resizable()
                .scaledToFill()
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: (56 * 0.2237).rounded(), style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text("lc.flek.premium.title".loc)
                    .font(.system(size: 17))
                    .foregroundStyle(.primary)
                status()
            }
            .font(.system(size: 15))
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            accessory()
        }
        .padding(16)
        .contentShape(Rectangle())
    }

    /// Asks FlekSt0re's status service about this device, where there is an
    /// ID to ask by, and keeps what it says: Premium, and the UDID of the
    /// device this copy was signed for. A failure is only said where the user
    /// asked.
    private func refreshDeviceStatus(isAsked: Bool) async {
        guard !isCheckingStatus, let deviceID = FlekPremium.deviceID else {
            return
        }
        isCheckingStatus = true
        defer { isCheckingStatus = false }
        guard case .answered(let response) = await AccessVerificationService.fetchStatus(encryptedUDID: deviceID) else {
            if isAsked {
                statusUnreachableShown = true
            }
            return
        }
        // An answer is one for the access check as well.
        AccessVerdictStore.save(response, for: deviceID)
        FlekPremium.keep(response)
        let udid = response.udid.trimmingCharacters(in: .whitespacesAndNewlines)
        if udid.isDeviceUDID {
            deviceUDID = udid
        }
    }

    /// The UDID with its middle left out: its ends are what it is told apart
    /// by, and the whole of it has no room here.
    private static func shortened(_ udid: String) -> String {
        guard udid.count > 16 else {
            return udid
        }
        return udid.prefix(8) + "......" + udid.suffix(8)
    }

    /// The day of an end date as the status service writes one, or nil for
    /// none.
    private static func dayText(_ end: String) -> String? {
        let end = end.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !end.isEmpty else {
            return nil
        }
        if let date = DateFormatter.deviceServiceFormatter.date(from: end) {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.locale = Locale(identifier: "en_US_POSIX")
            return formatter.string(from: date)
        }
        return end.split(separator: " ").first.map(String.init)
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
