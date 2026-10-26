//
//  FlekPremiumOfferView.swift
//  LiveContainerSwiftUI
//
//  The sheet that offers Premium Access, wherever the user asks for it: what
//  it gives, what it costs, and the button that leads to subscribing.
//
//  Premium is paid for at FlekSign's checkout, in Safari inside FlekDeck, by
//  the number FlekSt0re files the device under. FlekDeck learns of it from
//  the server afterwards, as of any other Premium: once the checkout is
//  closed this asks for up to half a minute, with the screen kept from
//  locking, as PayPal tells the server in its own time. FlekDeck goes on
//  asking each time it is back, for a day after, and the sheet opened again
//  in that time waits on that purchase rather than offer another.
//
//  Where the checkout sends the user back by <scheme>://premium, it closes
//  by itself, and one that says the user cancelled is not waited on at all.
//  No answer at all while asking is told apart from no purchase yet.
//
//  Premium paid for anywhere else, on the website or another device say,
//  shows only by asking: the link under Subscribe asks, and so does FlekDeck
//  coming back while the sheet is up, without a word where none is found.
//
//  There is nothing to subscribe for without the number. A copy FlekSt0re
//  signed is told it by the status service, and is asked for it first where
//  it has not been yet. Any other learns it from the UDID profile, and so
//  does one whose server gives none: there the button leads to that first.
//

import SwiftUI

struct FlekPremiumOfferView: View {
    /// The longest the sheet asks after the purchase, in seconds, an answer
    /// still awaited included.
    private static let paymentCheckLimit: UInt64 = 30
    /// How long to wait before each ask, within that.
    private static let paymentCheckDelays: [UInt64] = [0, 2, 3, 5, 5, 5, 10]
    /// The pages the last line names, as links. One without an address would
    /// be named without a link.
    private static let termsURL = URL(string: "https://fleksign.com/terms-and-conditions/")
    private static let privacyURL = URL(string: "https://fleksign.com/privacy-policy/")
    private static let refundURL = URL(string: "https://fleksign.com/refund-policy/")

    /// Where paying stands, from the checkout being opened on.
    private enum Payment {
        case notStarted
        /// The checkout is closed, and the server is being asked.
        case confirming
        /// The server answered while it was asked, and the purchase has not
        /// shown.
        case notConfirmed
        /// No answer came while it was asked.
        case unreachable
        /// The checkout said the user cancelled.
        case cancelled
        /// The device's number is being asked for before the checkout opens.
        case preparing
        /// It could not be asked for, with no answer from the server.
        case noConnection
        /// The server is being asked whether Premium is there already.
        case checking
        /// It answered, and Premium is not there.
        case notFound
        /// Premium is active, until the day given or with no end.
        case active(until: String?)
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    /// Set to get the UDID with the profile.
    @State private var asksForUDID = false
    /// The UDID came in while this was up, by the way it offered.
    @State private var udidJustAdded = false
    @State private var payment = Payment.notStarted
    /// When Premium ended as the checkout was opened, which the purchase is
    /// told by: see FlekPremium.notePurchaseStarted.
    @State private var endBeforePurchase: TimeInterval = 0
    /// The checkout sent the user back saying they cancelled, for when it is
    /// closed.
    @State private var checkoutCancelled = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 0) {
                    // A full-bleed square, given an app icon's squircle.
                    Image("premiumLogo")
                        .resizable()
                        .scaledToFill()
                        .frame(width: 84, height: 84)
                        .clipShape(RoundedRectangle(cornerRadius: (84 * 0.2237).rounded(), style: .continuous))
                    Text("lc.flek.premium.title".loc)
                        .font(.system(size: 26, weight: .bold))
                        .padding(.top, 14)
                    Text("lc.flek.premium.unlock".loc)
                        .font(.system(size: 17))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        // Narrow, to break where the design breaks it.
                        .frame(maxWidth: 190)
                        .padding(.top, 8)

                    VStack(spacing: 0) {
                        feature(symbol: FlekSymbol.jit,
                                title: "lc.flek.premium.offer.jit.title".loc,
                                detail: String(format: "lc.flek.premium.offer.jit.detail %@".loc, UIDevice.current.model))
                        Divider()
                            .padding(.leading, 32 + 10)
                        feature(symbol: "slider.horizontal.3",
                                title: "lc.flek.premium.offer.trainer.title".loc,
                                detail: "lc.flek.premium.offer.trainer.detail".loc)
                        // Offered only where an app can have it; the tweak
                        // needs iOS 16.
                        if #available(iOS 16.0, *), FlekLocationSpoofer.isBundled {
                            Divider()
                                .padding(.leading, 32 + 10)
                            feature(symbol: "location.fill",
                                    title: "lc.flek.premium.offer.location.title".loc,
                                    detail: "lc.flek.premium.offer.location.detail".loc)
                        }
                    }
                    // Set in on the left only: the rule between them runs to
                    // the edge the price's card ends at.
                    .padding(.leading, 16)
                    .padding(.top, 28)

                    plan
                        .padding(.top, 18)

                    if udidJustAdded, case .notStarted = payment {
                        Label("lc.flek.premium.offer.udidAdded".loc, systemImage: "checkmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.green)
                            .padding(.top, 16)
                    }

                    paymentArea
                        .padding(.top, 18)
                        .flekUDIDRetrieval(isAsked: $asksForUDID)

                    // Where to cancel, as nothing in FlekDeck does it. Long
                    // enough to wrap on a narrow phone, so centred like the
                    // line under it.
                    Text("lc.flek.premium.offer.renews".loc)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 14)
                    Text(emphasizing: Self.agreement)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 10)
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 24)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("lc.common.close".loc)
                }
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .onReceive(FlekUDIDProfile.udidReceived) { _ in
            // The device may turn out to have Premium already, bought before
            // or through FlekSt0re: then there is nothing to subscribe to.
            if FlekPremium.isActive {
                payment = .active(until: FlekPremium.endDay)
            } else {
                udidJustAdded = true
            }
        }
        // Shown on FlekDeck coming back, from the PayPal app say.
        .onReceive(FlekPremium.purchaseConfirmed) { _ in
            payment = .active(until: FlekPremium.endDay)
        }
        .onReceive(FlekPremium.checkoutReturned) { result in
            if result == .cancelled {
                checkoutCancelled = true
            }
        }
        // Back in FlekDeck, from paying elsewhere say. Where a purchase from
        // here is being waited on, that has its own asking.
        .onChange(of: scenePhase) { phase in
            guard phase == .active, FlekPremium.isDeviceKnown else {
                return
            }
            switch payment {
            case .notStarted, .cancelled, .noConnection, .notFound:
                Task {
                    await FlekPremium.refresh()
                    if FlekPremium.isActive {
                        payment = .active(until: FlekPremium.endDay)
                    }
                }
            default:
                break
            }
        }
        .onAppear {
            // Paid for before and not shown yet: waited on again, rather than
            // offered to be paid twice.
            if case .notStarted = payment, let endBefore = FlekPremium.pendingPurchaseEndBefore {
                endBeforePurchase = endBefore
                payment = .notConfirmed
            }
        }
        // Closed while still asking: nothing is left on screen to stay
        // awake for.
        .onDisappear {
            FlekKeepAwake.set(false, for: .paymentCheck)
        }
        .apply { sheet in
            // The grabber the design draws. It is iOS 16 API, so the result is
            // erased: left in the static type, iOS 15 would trap resolving it
            // before the availability check ever ran.
            if #available(iOS 16.0, *) {
                AnyView(sheet.presentationDragIndicator(.visible))
            } else {
                AnyView(sheet)
            }
        }
    }

    /// One thing Premium gives: its mark, its name, and a line on it.
    private func feature(symbol: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            FlekSetupTile(color: .blue, size: 32) {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                Text(detail)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 10)
    }

    private var plan: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("lc.flek.premium.offer.plan".loc)
                .font(.system(size: 17, weight: .medium))
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("lc.flek.premium.offer.price".loc)
                    .font(.system(size: 34, weight: .bold))
                Text("lc.flek.premium.offer.period".loc)
                    .font(.system(size: 17))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: FlekSetupCardBackground.cornerRadius, style: .continuous)
                .fill(Color(UIColor.secondarySystemBackground))
        )
    }

    /// The button that leads to subscribing, and in its place, once the
    /// checkout has been opened, how paying stands.
    @ViewBuilder
    private var paymentArea: some View {
        switch payment {
        case .notStarted:
            subscribeOptions
        case .cancelled:
            VStack(spacing: 12) {
                Label("lc.flek.premium.offer.cancelled".loc, systemImage: "xmark.circle")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                subscribeButton
            }
        case .confirming:
            progress("lc.flek.premium.offer.confirming".loc)
        case .preparing:
            progress("lc.flek.premium.offer.opening".loc)
        case .noConnection:
            VStack(spacing: 12) {
                Label("lc.flek.premium.offer.noConnection".loc, systemImage: "wifi.exclamationmark")
                    .font(.system(size: 14))
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
                subscribeOptions
            }
        case .checking:
            progress("lc.flek.premium.checking".loc)
        case .notFound:
            VStack(spacing: 12) {
                Label("lc.flek.premium.notFound".loc, systemImage: "info.circle")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                subscribeOptions
            }
        case .notConfirmed:
            waitingOnPayment("lc.flek.premium.offer.notConfirmed".loc, systemImage: "clock")
        case .unreachable:
            waitingOnPayment("lc.flek.premium.offer.unreachable".loc, systemImage: "wifi.exclamationmark")
        case .active(let until):
            VStack(spacing: 12) {
                Label(until.map { String(format: "lc.flek.premium.offer.active %@".loc, $0) }
                        ?? "lc.flek.premium.offer.activeNoEnd".loc,
                      systemImage: "checkmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.green)
                Button {
                    dismiss()
                } label: {
                    FlekCapsuleLabel(title: "lc.common.done".loc)
                }
                .buttonStyle(FlekCardPressStyle())
            }
        }
    }

    private var subscribeButton: some View {
        Button(action: subscribe) {
            FlekCapsuleLabel(title: "lc.flek.premium.offer.subscribe".loc)
        }
        .buttonStyle(FlekCardPressStyle())
    }

    /// Subscribing, and under it asking whether Premium is there already,
    /// which takes something to ask the server by.
    private var subscribeOptions: some View {
        VStack(spacing: 12) {
            subscribeButton
            if FlekPremium.isDeviceKnown {
                Button("lc.flek.premium.offer.checkAgain".loc, action: checkStatus)
                    .font(.system(size: 15))
            }
        }
    }

    /// Asks the server whether this device has Premium already, paid for
    /// some other way than the checkout here.
    private func checkStatus() {
        payment = .checking
        Task {
            let answered = await FlekPremium.refresh() != nil
            if FlekPremium.isActive {
                payment = .active(until: FlekPremium.endDay)
            } else {
                payment = answered ? .notFound : .noConnection
            }
        }
    }

    /// A purchase that has not shown: why, asking again as the one filled
    /// button, and the checkout again for one that was left unfinished.
    private func waitingOnPayment(_ text: String, systemImage: String) -> some View {
        VStack(spacing: 12) {
            Label(text, systemImage: systemImage)
                .font(.system(size: 14))
                .foregroundStyle(.orange)
                .multilineTextAlignment(.center)
            Button(action: checkPayment) {
                FlekCapsuleLabel(title: "lc.flek.premium.offer.checkPayment".loc)
            }
            .buttonStyle(FlekCardPressStyle())
            Button("lc.flek.premium.offer.openCheckout".loc, action: subscribe)
                .font(.system(size: 15))
        }
    }

    /// What is under way, in place of the button and as tall as it, so that
    /// nothing under it moves.
    private func progress(_ text: String) -> some View {
        HStack(spacing: 8) {
            ProgressView()
            Text(text)
                .foregroundStyle(.secondary)
        }
        .font(.system(size: 15))
        .frame(height: 50)
    }

    /// The checkout for this device where FlekDeck has its number, and
    /// otherwise getting the number first: from the status service for a
    /// copy FlekSt0re signed, and with the UDID profile where that gives none.
    private func subscribe() {
        if let checkout = FlekPremium.checkoutURL() {
            openCheckout(checkout)
            return
        }
        guard FlekPremium.deviceID != nil else {
            asksForUDID = true
            return
        }
        payment = .preparing
        Task {
            let answered = await FlekPremium.refresh() != nil
            if let checkout = FlekPremium.checkoutURL() {
                payment = .notStarted
                openCheckout(checkout)
            } else if answered {
                payment = .notStarted
                asksForUDID = true
            } else {
                payment = .noConnection
            }
        }
    }

    private func openCheckout(_ checkout: URL) {
        checkoutCancelled = false
        endBeforePurchase = FlekPremium.notePurchaseStarted()
        FlekInAppSafari.open(checkout) {
            checkPayment()
        }
    }

    /// Asks the server after the purchase for up to half a minute, with the
    /// screen kept from locking meanwhile, then says what it found and leaves
    /// asking again to the user. Where the checkout said the user cancelled,
    /// there is nothing to ask.
    private func checkPayment() {
        if checkoutCancelled {
            checkoutCancelled = false
            FlekPremium.abandonPurchase()
            payment = .cancelled
            return
        }
        payment = .confirming
        FlekKeepAwake.set(true, for: .paymentCheck)
        Task {
            let check = await Self.checkPurchase(endingAfter: endBeforePurchase)
            FlekKeepAwake.set(false, for: .paymentCheck)
            switch check {
            case .shows:
                payment = .active(until: FlekPremium.endDay)
            case .notYet:
                payment = .notConfirmed
            case .unreachable:
                payment = .unreachable
            }
        }
    }

    /// What asking finds within the limit: asked after each delay, and given
    /// up on once the limit is reached, even with an answer still awaited.
    /// Not yet where any ask was answered, and unreachable where none was.
    private static func checkPurchase(endingAfter endBefore: TimeInterval) async -> FlekPremium.PurchaseCheck {
        let delays = paymentCheckDelays
        let limit = paymentCheckLimit
        return await withTaskGroup(of: FlekPremium.PurchaseCheck?.self) { group in
            group.addTask {
                var wasAnswered = false
                for delay in delays {
                    try? await Task.sleep(nanoseconds: delay * 1_000_000_000)
                    if Task.isCancelled {
                        break
                    }
                    switch await FlekPremium.checkPurchase(endingAfter: endBefore) {
                    case .shows:
                        return .shows
                    case .notYet:
                        wasAnswered = true
                    case .unreachable:
                        break
                    }
                }
                return wasAnswered ? .notYet : .unreachable
            }
            // The limit: nil, after which the asking above is stopped and
            // says what it found.
            group.addTask {
                try? await Task.sleep(nanoseconds: limit * 1_000_000_000)
                return nil
            }
            var found: FlekPremium.PurchaseCheck?
            for await check in group {
                group.cancelAll()
                if let check {
                    found = check
                    break
                }
            }
            return found ?? .unreachable
        }
    }

    /// What subscribing agrees to, each page named as a link where it has an
    /// address.
    private static var agreement: String {
        func named(_ key: String, _ url: URL?) -> String {
            url.map { "[\(key.loc)](\($0.absoluteString))" } ?? key.loc
        }
        return String(format: "lc.flek.premium.offer.agreement %@ %@ %@".loc,
                      named("lc.flek.premium.offer.terms", termsURL),
                      named("lc.flek.premium.offer.privacy", privacyURL),
                      named("lc.flek.premium.offer.refund", refundURL))
    }
}
