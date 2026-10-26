//
//  FlekPremium.swift
//  LiveContainerSwiftUI
//
//  Whether this device has Premium, for a feature that is asked about every
//  time it is used rather than once.
//
//  The status service's last answer is kept where Settings and the installer
//  keep theirs, so that all of them agree, and it is good until the
//  subscription's end date. A feature can then be checked at every use with no
//  request made, and with no one locked out for being offline. Once the date
//  has passed, or with no answer kept, the server is asked.
//
//  A copy FlekSt0re signed is asked about by the device ID in its Info.plist.
//  Any other has none, and once the UDID profile has been through it is
//  asked about by the UDID FlekSt0re filed it under, which the status
//  service answers the same way, the device's number included.
//
//  Premium is bought at FlekSign's checkout by that number, whoever signed
//  the copy; see Buying below for how a purchase is waited on.
//

import Combine
import Foundation

enum FlekPremium {
    enum Answer {
        case active
        case inactive
        /// What is kept says no, and the server could not be asked.
        case unconfirmed
    }

    private enum Key {
        // Settings and the installer read and write these two as well.
        static let status = "FSSubscriptionStatus"
        static let endDate = "FSSubscriptionEndDate"
        static let checkedAt = "FSSubscriptionCheckedAt"
        static let deviceID = "FSEncryptedUDID"
        static let deviceNumber = "FSDeviceNumber"
        static let filedUDID = "FlekPremiumUDID"
        /// The end of Premium the user has looked at in General.
        static let endSeen = "FlekPremiumEndSeen"
        // A purchase under way: when the checkout was opened, and when
        // Premium ended then, in seconds since 1970.
        static let purchaseStartedAt = "FlekPremiumPurchaseStartedAt"
        static let endBeforePurchase = "FlekPremiumEndBeforePurchase"
        // In the app group, for a guest. LCBootstrap reads them by these names.
        static let until = "FlekPremiumUntil"
        static let confirmedAt = "FlekPremiumConfirmedAt"
#if DEBUG
        static let debugOverride = "FlekDebugPremium"
#endif
    }

    /// The ID the status service knows this device by. A build FlekSt0re did
    /// not sign has none, and so has no Premium to show.
    static var deviceID: String? {
        let stored = UserDefaults.standard.string(forKey: Key.deviceID)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let stored, !stored.isEmpty {
            return stored
        }
        return Bundle.main.flekStoreDeviceID
    }

    /// The number FlekSt0re's database files this device under: told by the
    /// status service to a copy FlekSt0re signed, and learnt from the UDID
    /// profile by any other. Premium is paid for by it, and looked up by it
    /// where there is no device ID.
    static var deviceNumber: Int? {
        let number = UserDefaults.standard.integer(forKey: Key.deviceNumber)
        return number > 0 ? number : nil
    }

    static func keepDeviceNumber(_ number: Int) {
        UserDefaults.standard.set(number, forKey: Key.deviceNumber)
    }

    /// The UDID FlekSt0re has filed this device under, as its answers name it:
    /// what a copy FlekSt0re did not sign is asked about by. Not the UDID the
    /// rest of FlekDeck shows, which can also be typed in for JIT: asked about
    /// by one typed in, another device's Premium would be this one's.
    static var filedUDID: String? {
        let udid = (UserDefaults.standard.string(forKey: Key.filedUDID) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return udid.isDeviceUDID ? udid : nil
    }

    /// Whether FlekDeck knows this device by anything the server can be asked
    /// about it by. A number alone is enough: the device's record names the
    /// UDID to ask by.
    static var isDeviceKnown: Bool {
        deviceID != nil || filedUDID != nil || deviceNumber != nil
    }

    /// Whether Premium is active by what is kept, with nothing asked.
    static var isActive: Bool {
        guard let end = keptEnd else {
            return false
        }
        return AccessVerdictStore.trustedNow() < end
    }

    /// When Premium ends by what is kept: nil without it, and the distant
    /// future for a subscription the server gave no end for.
    private static var keptEnd: Date? {
#if DEBUG
        if UserDefaults.standard.bool(forKey: Key.debugOverride) {
            return .distantFuture
        }
#endif
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: Key.status) else {
            return nil
        }
        let end = defaults.string(forKey: Key.endDate) ?? ""
        return DateFormatter.deviceServiceDate(from: end) ?? .distantFuture
    }

    /// When Premium ended, as kept and as the server has said since that day
    /// came: nil while it is active, where there was none to end, and while
    /// the server has not been asked since. A subscription that renews is
    /// extended on the server, which this copy hears of only when it asks.
    private static var endedOn: String? {
        guard let (end, date) = keptEndPassed,
              UserDefaults.standard.double(forKey: Key.checkedAt) >= date.timeIntervalSince1970 else {
            return nil
        }
        return end
    }

    /// The kept end of Premium where it has passed by the clock, as text and
    /// as a date.
    private static var keptEndPassed: (String, Date)? {
        guard !isActive else {
            return nil
        }
        let end = UserDefaults.standard.string(forKey: Key.endDate) ?? ""
        guard let date = DateFormatter.deviceServiceDate(from: end), date <= AccessVerdictStore.trustedNow() else {
            return nil
        }
        return (end, date)
    }

    /// Whether the kept end of Premium has passed with the server not asked
    /// since, which a renewal may have moved on.
    static var needsCheckAfterEnd: Bool {
        guard isDeviceKnown, let (_, date) = keptEndPassed else {
            return false
        }
        return UserDefaults.standard.double(forKey: Key.checkedAt) < date.timeIntervalSince1970
    }

    /// Whether Premium has ended and the user has not opened General since,
    /// which the Settings icon and General's row are marked for.
    static var isEndUnseen: Bool {
        guard let end = endedOn else {
            return false
        }
        return UserDefaults.standard.string(forKey: Key.endSeen) != end
    }

    /// Notes that the user has seen how Premium stands, as General shows it.
    /// An end looked at once is not marked again; one after Premium has been
    /// bought again and run out is.
    static func markEndSeen() {
        guard let end = endedOn, UserDefaults.standard.string(forKey: Key.endSeen) != end else {
            return
        }
        UserDefaults.standard.set(end, forKey: Key.endSeen)
    }

    /// The day Premium ends by what is kept, nil where it is not active or
    /// has no end.
    static var endDay: String? {
        guard isActive, let end = keptEnd, end != .distantFuture else {
            return nil
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: end)
    }

    /// Keeps an answer from the status service, whoever asked for it, and the
    /// device's number where it gives one: a copy FlekSt0re signed is told it
    /// there, with no profile to install.
    static func keep(_ response: DeviceStatusResponse) {
        keep(status: response.status, endDate: response.endDate)
        if let number = response.deviceNumber, number != deviceNumber {
            keepDeviceNumber(number)
        }
    }

    /// Keeps what a device record says of Premium, as an answer from the
    /// status service would have said it.
    static func keep(_ record: FlekDeviceRecord) {
        let end = record.premiumEnd.flatMap(DateFormatter.deviceServiceDate(from:))
        keep(status: end.map { AccessVerdictStore.trustedNow() < $0 } ?? false,
             endDate: record.premiumEnd ?? "")
    }

    private static func keep(status: Bool, endDate: String) {
        let defaults = UserDefaults.standard
        defaults.set(status, forKey: Key.status)
        defaults.set(endDate, forKey: Key.endDate)
        defaults.set(Date().timeIntervalSince1970, forKey: Key.checkedAt)
        publish()
    }

    /// Keeps the UDID FlekSt0re names for this device: as the one it is asked
    /// about by, and where the rest of FlekDeck reads it. What the server says
    /// wins over one typed in for JIT.
    static func keepUDID(_ udid: String) {
        let udid = udid.trimmingCharacters(in: .whitespacesAndNewlines)
        if udid.isDeviceUDID {
            UserDefaults.standard.set(udid, forKey: Key.filedUDID)
            LCUtils.appGroupUserDefault.set(udid, forKey: "LCDeviceUDID")
        }
    }

    /// Asks the server about this device: the status service by its device
    /// ID, or by the UDID it is filed under on a copy that has no device ID.
    /// Keeps what it says, Premium, the device's number and the UDID. Nil
    /// where it gave no answer, or there is nothing to ask by.
    @discardableResult
    static func refresh() async -> Bool? {
        if let deviceID {
            guard case .answered(let response) = await AccessVerificationService.fetchStatus(encryptedUDID: deviceID) else {
                return nil
            }
            // An answer is one for the access check as well, and sets the clock
            // that end dates are measured against right again.
            AccessVerdictStore.save(response, for: deviceID)
            keep(response)
            keepUDID(response.udid)
            return response.status
        }
        // Filed through the profile before FlekDeck kept the UDID for this:
        // the device's record names it, once.
        if filedUDID == nil, let deviceNumber, let record = await FlekDeviceRecord.fetch(number: deviceNumber) {
            keepUDID(record.udid)
        }
        guard let udid = filedUDID else {
            return nil
        }
        guard case .answered(let response) = await AccessVerificationService.fetchStatus(udid: udid) else {
            return nil
        }
        keep(response)
        return response.status
    }

    /// Whether Premium is active, asking the server only where what is kept
    /// does not already say so.
    static func confirm() async -> Answer {
        if isActive {
            // Ended early, by a refund say, shows only in a new answer, which
            // is fetched behind whatever was waiting on this one.
            let checkedAt = Date(timeIntervalSince1970: UserDefaults.standard.double(forKey: Key.checkedAt))
            if Date().timeIntervalSince(checkedAt) > AccessVerdictStore.refreshInterval {
                Task { await refresh() }
            }
            return .active
        }
        switch await refresh() {
        case true?:
            return .active
        case false?:
            return .inactive
        case nil:
            return isDeviceKnown ? .unconfirmed : .inactive
        }
    }

    // MARK: Buying

    /// FlekSign's checkout, which takes the device's number, and the monthly
    /// membership's product there: FlekSign's development host for now, to
    /// be changed for the real one.
    private static let checkoutAddress = "https://dev7481.fleksign.com/api/paypal/checkout"
    private static let checkoutProductID = "3"

    /// How long after the checkout was opened FlekDeck goes on asking after
    /// the purchase each time it is back: PayPal tells the server about a
    /// payment in its own time, and the user may come back much later.
    private static let purchaseLifetime: TimeInterval = 24 * 60 * 60

    /// What asking after a purchase found.
    enum PurchaseCheck {
        /// Premium ends later than it did as the checkout was opened.
        case shows
        /// The server answered, and Premium is as it was.
        case notYet
        /// The server gave no answer.
        case unreachable
    }

    /// How the checkout came back to FlekDeck, where it says.
    enum CheckoutResult {
        case success
        case cancelled
    }

    /// A purchase shown on FlekDeck coming back, with no sheet asking after
    /// it. On the main queue.
    static let purchaseConfirmed = PassthroughSubject<Void, Never>()
    /// The checkout's way back, as it was taken. On the main queue.
    static let checkoutReturned = PassthroughSubject<CheckoutResult, Never>()

    /// The checkout for this device, nil where FlekDeck has no number for it.
    static func checkoutURL() -> URL? {
        guard let deviceNumber else {
            return nil
        }
        var components = URLComponents(string: checkoutAddress)
        components?.queryItems = [
            URLQueryItem(name: "productId", value: checkoutProductID),
            URLQueryItem(name: "deviceId", value: String(deviceNumber)),
        ]
        return components?.url
    }

    /// Notes the checkout being opened, and returns when Premium ended then,
    /// in seconds since 1970 and 0 for none: the purchase is told apart from
    /// Premium the device already had by ending later.
    static func notePurchaseStarted() -> TimeInterval {
        let endBefore = isActive ? (keptEnd?.timeIntervalSince1970 ?? 0) : 0
        let defaults = UserDefaults.standard
        defaults.set(Date().timeIntervalSince1970, forKey: Key.purchaseStartedAt)
        defaults.set(endBefore, forKey: Key.endBeforePurchase)
        return endBefore
    }

    /// When Premium ended as the checkout was opened, while a purchase from it
    /// is still waited on: nil with none, or one too old to wait for.
    static var pendingPurchaseEndBefore: TimeInterval? {
        let defaults = UserDefaults.standard
        let startedAt = defaults.double(forKey: Key.purchaseStartedAt)
        guard startedAt > 0, Date().timeIntervalSince1970 - startedAt < purchaseLifetime else {
            return nil
        }
        return defaults.double(forKey: Key.endBeforePurchase)
    }

    /// Asks the server whether the purchase shows: Premium active and ending
    /// later than `endBefore`. Once it does, there is no purchase left to ask
    /// after.
    static func checkPurchase(endingAfter endBefore: TimeInterval) async -> PurchaseCheck {
        let answered = await refresh() != nil
        guard isActive, let end = keptEnd, end.timeIntervalSince1970 > endBefore else {
            return answered ? .notYet : .unreachable
        }
        endPurchase()
        return .shows
    }

    /// Asks after a purchase still under way, for FlekDeck coming back: from
    /// a checkout left by switching apps, say, or the PayPal app.
    static func confirmPendingPurchase() async {
        guard let endBefore = pendingPurchaseEndBefore else {
            // None, or one too old to wait for.
            endPurchase()
            return
        }
        if await checkPurchase(endingAfter: endBefore) == .shows {
            DispatchQueue.main.async {
                purchaseConfirmed.send()
            }
        }
    }

    /// The checkout's way back, <scheme>://premium?result=success or
    /// result=cancelled. A link can be opened by anyone, so it only ever
    /// leads to the server being asked, and a cancellation only to no longer
    /// waiting: it grants nothing. On the main queue.
    static func handleCheckoutReturn(from url: URL) {
        let result = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "result" }?.value
        let outcome: CheckoutResult = result == "cancelled" ? .cancelled : .success
        checkoutReturned.send(outcome)
        // The sheet that opened the checkout carries on once it is closed.
        // With none showing, this is the place to.
        guard !FlekInAppSafari.close() else {
            return
        }
        switch outcome {
        case .cancelled:
            endPurchase()
        case .success:
            Task { await confirmPendingPurchase() }
        }
    }

    /// No longer waits on the purchase, which the checkout said was cancelled.
    static func abandonPurchase() {
        endPurchase()
    }

    private static func endPurchase() {
        UserDefaults.standard.removeObject(forKey: Key.purchaseStartedAt)
        UserDefaults.standard.removeObject(forKey: Key.endBeforePurchase)
    }

    /// Forgets all that is kept of this device and its Premium, as FlekDeck
    /// installed afresh has it: see FlekUDIDProfile.forgetDevice.
    static func forgetDevice() {
        let defaults = UserDefaults.standard
        for key in [Key.status, Key.endDate, Key.checkedAt, Key.deviceID, Key.deviceNumber, Key.filedUDID,
                    Key.endSeen, Key.purchaseStartedAt, Key.endBeforePurchase] {
            defaults.removeObject(forKey: key)
        }
        LCUtils.appGroupUserDefault.removeObject(forKey: Key.confirmedAt)
        publish()
    }

    // MARK: For guests

    /// Tells guests how long Premium lasts. A guest that starts without the
    /// app having been asked first, from a link opened in another guest say,
    /// has only this to go by: it cannot read the app's own settings from a
    /// window, and cannot ask the server.
    static func publish() {
        LCUtils.appGroupUserDefault.set(keptEnd?.timeIntervalSince1970 ?? 0, forKey: Key.until)
    }

    /// Tells the guest about to start that Premium has just been confirmed,
    /// which covers an answer the kept end date does not bear out: the server
    /// goes by its own clock.
    static func noteConfirmedForLaunch() {
        publish()
        LCUtils.appGroupUserDefault.set(Date().timeIntervalSince1970, forKey: Key.confirmedAt)
    }
}
