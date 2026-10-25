//
//  FlekUDIDProfile.swift
//  LiveContainerSwiftUI
//
//  Gets this device's UDID, which no app can read for itself, the way UDID
//  websites do: with a configuration profile of the Profile Service kind.
//  Installing one has iOS post the device's attributes, the UDID among them,
//  to the address the profile names.
//
//  That address cannot be FlekDeck's own. Since iOS 12 the installer only
//  posts over HTTPS with a certificate iOS trusts, and refuses plain HTTP
//  before connecting, the loopback address included. So FlekSt0re's server
//  does for FlekDeck what it does for its own site: it hands out the profile
//  under an ID the asker makes up, files the device that answers under that
//  ID, and tells whoever asks with the ID which device that was. FlekDeck
//  asks each time the user is back in it.
//
//  The ID is this device's own, the same on every download, as the site's
//  is for a browser. See deviceRequestID.
//
//  The answer is the number FlekSt0re files the device under, which Premium
//  is paid for by, and with it the UDID, which Premium is looked up by on a
//  copy FlekSt0re did not sign. Both are kept, see FlekPremium.
//
//  A server can also bring the user straight back, by answering the device
//  with a redirect to <scheme>://udid, which iOS opens at once; FlekDeck then
//  asks as on any return. FlekSt0re's redirects to
//  flekdeck://device-registered?udid=<UDID>, taken the same way. Its profile
//  does not carry the scheme on to where the device answers, so a second
//  copy of FlekDeck is not the one brought back; it is sent all the same.
//

import Combine
import Foundation
import UIKit

enum FlekUDIDProfile {
    /// The Developer Mode setting that points FlekDeck at a page other than
    /// FlekSt0re's, to try a server out. Such a server has to send the UDID
    /// back by redirect: only FlekSt0re's can be asked for it.
    static let pageAddressKey = "FlekUDIDProfilePageAddress"

    /// Each UDID that arrives, once it is stored where the rest of FlekDeck
    /// reads it. On the main queue.
    static let udidReceived = PassthroughSubject<String, Never>()

    /// The purchase the device is added for: false for none, as FlekSt0re's
    /// site sends.
    private static let dealID = "false"

    /// The ID the profile downloaded last was asked for under, and when.
    private static let requestIDKey = "FlekUDIDProfileRequestID"
    private static let requestDateKey = "FlekUDIDProfileRequestDate"

    /// How long FlekDeck goes on asking after a download. iOS drops a
    /// downloaded profile within minutes, and after a Security Delay the
    /// download is started again.
    private static let requestLifetime: TimeInterval = 2 * 60 * 60

    /// The ID this device asks for its UDID under, the same on every download
    /// and after FlekDeck has been deleted and installed again, so that the
    /// device can be found again with no profile: see restoreDevice. iOS lets
    /// no app read a hardware ID, and nothing it does give outlives the app
    /// but the keychain, so the ID is kept there. The first one is the vendor
    /// ID iOS gives FlekDeck, as 32 hex digits.
    ///
    /// It is kept under FlekDeck's own app ID: the keychain group the apps
    /// inside FlekDeck are given is FlekDeck's default one, and an app that
    /// clears its keychain would take the ID with it. So a copy signed by
    /// another team or under another bundle ID has an ID of its own, and an
    /// erased device starts afresh. Where the keychain will not have it, it is
    /// kept with the settings, for as long as this copy stays installed.
    @MainActor
    static var deviceRequestID: String {
        if let kept = keptDeviceRequestID() {
            return kept
        }
        // iOS has no vendor ID to give for a moment after the device starts,
        // before it is first unlocked.
        let id = UIDevice.current.identifierForVendor.map {
            $0.uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        } ?? (0..<32).map { _ in String(Int.random(in: 0..<16), radix: 16) }.joined()
        var item = deviceRequestIDQuery
        item[kSecValueData as String] = Data(id.utf8)
        // Never carried to another device, by iCloud or a backup.
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        switch SecItemAdd(item as CFDictionary, nil) {
        case errSecSuccess:
            return id
        case errSecDuplicateItem:
            return keptDeviceRequestID() ?? id
        default:
            UserDefaults.standard.set(id, forKey: deviceRequestIDKey)
            return id
        }
    }

    /// Where the ID is kept with the settings, where the keychain will not
    /// have it.
    private static let deviceRequestIDKey = "FlekUDIDProfileDeviceID"

    private static var deviceRequestIDQuery: [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "FlekDeck UDID Profile",
            kSecAttrAccount as String: "fp_id",
        ]
        if let appIdentifier = ownAppIdentifier {
            query[kSecAttrAccessGroup as String] = appIdentifier
        }
        return query
    }

    /// The ID as kept, from this install or one before it; nil where none is.
    private static func keptDeviceRequestID() -> String? {
        var query = deviceRequestIDQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
           let data = result as? Data,
           let id = String(data: data, encoding: .utf8), isDeviceRequestID(id) {
            return id
        }
        let stored = UserDefaults.standard.string(forKey: deviceRequestIDKey) ?? ""
        return isDeviceRequestID(stored) ? stored : nil
    }

    private static func isDeviceRequestID(_ id: String) -> Bool {
        id.count == 32 && id.allSatisfy(\.isHexDigit)
    }

    /// FlekDeck's own app ID, <team>.<bundle ID>, which is a keychain group
    /// of its own that only FlekDeck itself uses.
    private static let ownAppIdentifier: String? = {
        let task = SecTaskCreateFromSelf(nil)
        return SecTaskCopyValueForEntitlement(task, "application-identifier" as CFString, nil)?
            .takeRetainedValue() as? String
    }()

    @MainActor private static var isCollecting = false

    /// The address to open for the download, which starts a request for the
    /// UDID. Nil when no address can be made.
    @MainActor
    static func startRequest() -> URL? {
        // Which URL scheme to send the user back to, for a server that does:
        // a second copy of FlekDeck answers to its own.
        let scheme = URLQueryItem(name: "scheme", value: LCUtils.appUrlScheme() ?? "flekdeck")
        let defaults = UserDefaults.standard
        endRequest()

        let override = defaults.string(forKey: pageAddressKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if let page = URL(string: override), page.scheme?.lowercased() == "https", page.host != nil,
           var components = URLComponents(url: page, resolvingAgainstBaseURL: false) {
            components.queryItems = (components.queryItems ?? []) + [scheme]
            return components.url
        }

        let id = deviceRequestID
        // FlekSt0re's endpoint for FlekDeck, whose profile answers to
        // registerDeviceFlekdeck/<id>/<deal_id>.
        var components = URLComponents(string: "\(FlekStoreAPI.base)/device/get-udid-flekdeck/\(id)")
        components?.queryItems = [URLQueryItem(name: "deal_id", value: dealID), scheme]
        guard let url = components?.url else {
            return nil
        }
        defaults.set(id, forKey: requestIDKey)
        defaults.set(Date(), forKey: requestDateKey)
        return url
    }

    /// Asks FlekSt0re which device answered the profile downloaded last, and
    /// takes its number, Premium and UDID. There is none until the profile is
    /// installed, which happens in Settings: this is for when the user is
    /// back from there.
    @MainActor
    static func collectUDID() async {
        let defaults = UserDefaults.standard
        guard !isCollecting, let id = defaults.string(forKey: requestIDKey) else {
            return
        }
        guard let asked = defaults.object(forKey: requestDateKey) as? Date,
              Date().timeIntervalSince(asked) < requestLifetime else {
            endRequest()
            return
        }
        isCollecting = true
        defer { isCollecting = false }
        // More than once: the network may not be up yet as FlekDeck comes
        // back, nor the device filed.
        for attempt in 0..<3 {
            if attempt > 0 {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
            guard defaults.string(forKey: requestIDKey) == id else {
                return
            }
            if let device = await reportedDevice(forRequest: id) {
                await adopt(device)
                return
            }
        }
    }

    /// Finds the device again as FlekDeck starts, with no profile, by the ID
    /// kept from an earlier install: FlekSt0re still has the device filed
    /// under it, unless another copy has filed it since. Asked only where
    /// this copy knows no device yet, as one FlekSt0re did not sign does once
    /// installed afresh, and no download is under way, which is collected
    /// instead.
    @MainActor
    static func restoreDevice() async {
        guard !isCollecting, !FlekPremium.isDeviceKnown,
              UserDefaults.standard.string(forKey: requestIDKey) == nil,
              let id = keptDeviceRequestID() else {
            return
        }
        isCollecting = true
        defer { isCollecting = false }
        if let device = await reportedDevice(forRequest: id) {
            await adopt(device)
        }
    }

    /// Forgets the device, to try getting it again, from Diagnostics: its
    /// UDID, number and Premium as kept, and with `andID` the ID kept in the
    /// keychain as well, which deleting FlekDeck leaves. A copy FlekSt0re
    /// signed knows it again at once, by the ID in its Info.plist.
    @MainActor
    static func forgetDevice(andID: Bool) {
        endRequest()
        FlekPremium.forgetDevice()
        LCUtils.appGroupUserDefault.removeObject(forKey: "LCDeviceUDID")
        if andID {
            SecItemDelete(deviceRequestIDQuery as CFDictionary)
            UserDefaults.standard.removeObject(forKey: deviceRequestIDKey)
        }
    }

    /// Whether an ID is kept, from this install or one before it.
    static var hasKeptID: Bool {
        keptDeviceRequestID() != nil
    }

    /// Takes the device FlekSt0re reported: its number, its UDID and its
    /// Premium.
    @MainActor
    private static func adopt(_ device: (number: Int, record: FlekDeviceRecord)) async {
        FlekPremium.keepDeviceNumber(device.number)
        FlekPremium.keep(device.record)
        FlekPremium.keepUDID(device.record.udid)
        store(device.record.udid)
        // Premium as the status service has it, now that the UDID to ask by
        // is known.
        await FlekPremium.refresh()
    }

    /// What the way back from the profile, <scheme>://udid or
    /// flekdeck://device-registered, sets off. A link can be opened by anyone,
    /// so the UDID it carries is not taken: Premium is looked up by the UDID,
    /// and one typed into a link would be another device's Premium. The
    /// device is asked for by its ID instead, as on any return to FlekDeck:
    /// the download's, or the one kept from an earlier install where the
    /// download is no longer waited on. Only a page tried out in Developer
    /// Mode, which cannot be asked, hands the UDID over in the link itself.
    @MainActor
    static func handleReturn(from url: URL) async {
        let defaults = UserDefaults.standard
        if defaults.string(forKey: requestIDKey) != nil {
            await collectUDID()
        } else if !(defaults.string(forKey: pageAddressKey) ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            importUDID(from: url)
        } else {
            await restoreDevice()
        }
    }

    /// Takes the UDID from the address a server's redirect opens,
    /// <scheme>://udid?udid=<UDID>.
    private static func importUDID(from url: URL) {
        guard let udid = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "udid" })?.value?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              udid.isDeviceUDID else {
            return
        }
        store(udid)
    }

    private static func store(_ udid: String) {
        endRequest()
        LCUtils.appGroupUserDefault.set(udid, forKey: "LCDeviceUDID")
        udidReceived.send(udid)
    }

    private static func endRequest() {
        UserDefaults.standard.removeObject(forKey: requestIDKey)
        UserDefaults.standard.removeObject(forKey: requestDateKey)
    }

    /// What FlekSt0re's site asks after its own profile: the number of the
    /// device filed under the ID, then that device's record, UDID included.
    private static func reportedDevice(forRequest id: String) async -> (number: Int, record: FlekDeviceRecord)? {
        var lookup = URLComponents(string: "https://flekstore.com/rest/device/findDeviceByFp")
        lookup?.queryItems = [URLQueryItem(name: "fp_id", value: id)]
        guard let lookupURL = lookup?.url,
              let filed: FiledDevice = await answer(from: lookupURL),
              let number = filed.number,
              let record = await FlekDeviceRecord.fetch(number: number),
              record.udid.isDeviceUDID else {
            return nil
        }
        return (number, record)
    }

    private static func answer<Answer: Decodable>(from url: URL) async -> Answer? {
        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            return nil
        }
        return try? JSONDecoder().decode(Answer.self, from: data)
    }

    /// `data` is the device's number once one is filed under the ID, and
    /// false until then.
    private struct FiledDevice: Decodable {
        let number: Int?

        private enum CodingKeys: String, CodingKey {
            case data
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            if let number = try? container.decode(Int.self, forKey: .data) {
                self.number = number
            } else if let text = try? container.decode(String.self, forKey: .data) {
                number = Int(text)
            } else {
                number = nil
            }
        }
    }
}
