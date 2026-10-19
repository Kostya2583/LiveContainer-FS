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
        /// The end of Premium the user has looked at in General.
        static let endSeen = "FlekPremiumEndSeen"
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
        return DateFormatter.deviceServiceFormatter.date(from: end) ?? .distantFuture
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
        guard let date = DateFormatter.deviceServiceFormatter.date(from: end), date <= AccessVerdictStore.trustedNow() else {
            return nil
        }
        return (end, date)
    }

    /// Whether the kept end of Premium has passed with the server not asked
    /// since, which a renewal may have moved on.
    static var needsCheckAfterEnd: Bool {
        guard deviceID != nil, let (_, date) = keptEndPassed else {
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

    /// Keeps an answer from the status service, whoever asked for it.
    static func keep(_ response: DeviceStatusResponse) {
        let defaults = UserDefaults.standard
        defaults.set(response.status, forKey: Key.status)
        defaults.set(response.endDate, forKey: Key.endDate)
        defaults.set(Date().timeIntervalSince1970, forKey: Key.checkedAt)
        publish()
    }

    /// Asks the status service. Nil where it gave no answer, or there is no
    /// device ID to ask about.
    @discardableResult
    static func refresh() async -> Bool? {
        guard let deviceID,
              case .answered(let response) = await AccessVerificationService.fetchStatus(encryptedUDID: deviceID) else {
            return nil
        }
        // An answer is one for the access check as well, and sets the clock
        // that end dates are measured against right again.
        AccessVerdictStore.save(response, for: deviceID)
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
            return deviceID == nil ? .inactive : .unconfirmed
        }
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
