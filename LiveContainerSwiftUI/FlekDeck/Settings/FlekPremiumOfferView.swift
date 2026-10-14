//
//  FlekPremiumOfferView.swift
//  LiveContainerSwiftUI
//
//  The sheet that offers Premium Access, wherever the user asks for it: what
//  it gives, what it costs, and the button that leads to subscribing.
//
//  Premium is FlekSt0re's to sell and to grant, by the device's UDID. So the
//  button opens FlekSt0re, and FlekDeck learns of a subscription from the
//  status service afterwards, as it does of any other. Where the UDID is not
//  known yet, on a copy FlekSt0re did not sign, the button leads to getting it
//  first: there is nothing to subscribe for without one.
//

import SwiftUI

struct FlekPremiumOfferView: View {
    /// Where Premium is subscribed to.
    private static let storeURL = URL(string: "https://flekstore.com")!
    /// The pages the last line names, as links. One without an address would
    /// be named without a link.
    private static let termsURL = URL(string: "https://fleksign.com/terms-and-conditions/")
    private static let privacyURL = URL(string: "https://fleksign.com/privacy-policy/")
    private static let refundURL = URL(string: "https://fleksign.com/refund-policy/")

    @Environment(\.dismiss) private var dismiss

    @AppStorage("LCDeviceUDID", store: LCUtils.appGroupUserDefault) private var deviceUDID: String = ""
    /// Set to get the UDID with the profile.
    @State private var asksForUDID = false
    /// The UDID came in while this was up, by the way it offered.
    @State private var udidJustAdded = false

    /// Whether the UDID has to be got before subscribing. A copy FlekSt0re
    /// signed is one FlekSt0re already knows the device of.
    private var needsUDID: Bool {
        FlekPremium.deviceID == nil && !deviceUDID.trimmingCharacters(in: .whitespacesAndNewlines).isDeviceUDID
    }

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
                    }
                    // Set in on the left only: the rule between them runs to
                    // the edge the price's card ends at.
                    .padding(.leading, 16)
                    .padding(.top, 28)

                    plan
                        .padding(.top, 18)

                    if udidJustAdded {
                        Label("lc.flek.premium.offer.udidAdded".loc, systemImage: "checkmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.green)
                            .padding(.top, 16)
                    }

                    Button {
                        if needsUDID {
                            asksForUDID = true
                        } else {
                            UIApplication.shared.open(Self.storeURL)
                        }
                    } label: {
                        FlekCapsuleLabel(title: "lc.flek.premium.offer.subscribe".loc)
                    }
                    .buttonStyle(FlekCardPressStyle())
                    .padding(.top, 18)
                    .flekUDIDRetrieval(isAsked: $asksForUDID)

                    Text("lc.flek.premium.offer.renews".loc)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
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
            udidJustAdded = true
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
