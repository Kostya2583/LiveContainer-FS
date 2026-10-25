//
//  FlekLocationSpoofer.swift
//  LiveContainerSwiftUI
//
//  The Location Spoofer FlekDeck ships in its Frameworks, turned on per app in
//  the app's settings and loaded into the app by TweakLoader. It is a Premium
//  feature, checked where FlekJIT is: when it is turned on, before a launch
//  from FlekDeck, and in the app as it starts.
//

import Foundation

enum FlekLocationSpoofer {
    /// In the bundle for devices only (xcconfigs/LiveContainer.xcconfig).
    static let isBundled = FileManager.default.fileExists(atPath: Bundle.main.bundleURL.appendingPathComponent("Frameworks/LocationSpoofer.dylib").path)

    /// A launch refused because Premium is not active, which the home offers
    /// to buy.
    struct PremiumNeeded: LocalizedError {
        var errorDescription: String? { "lc.flek.locationSpoofer.premium.needed".loc }
    }

    /// Before a launch with it on. TweakLoader goes by what this publishes,
    /// and loads it only where that says Premium is active.
    @MainActor
    static func ensurePremium() async throws {
        // What the app goes by where it starts without this having been asked.
        FlekPremium.publish()
        switch await FlekPremium.confirm() {
        case .active:
            FlekPremium.noteConfirmedForLaunch()
        case .inactive:
            throw PremiumNeeded()
        case .unconfirmed:
            throw "lc.flek.jit.premium.unconfirmed".loc
        }
    }
}
