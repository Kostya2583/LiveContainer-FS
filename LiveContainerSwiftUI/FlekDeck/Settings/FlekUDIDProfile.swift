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
//  A server can also bring the user straight back, by answering the device
//  with a redirect to <scheme>://udid?udid=<UDID>, which iOS opens at once.
//  FlekSt0re's does not yet; the scheme it would need is sent all the same.
//

import Combine
import Foundation

enum FlekUDIDProfile {
    /// The Developer Mode setting that points FlekDeck at a page other than
    /// FlekSt0re's, to try a server out. Such a server has to send the UDID
    /// back by redirect: only FlekSt0re's can be asked for it.
    static let pageAddressKey = "FlekUDIDProfilePageAddress"

    /// Each UDID that arrives, once it is stored where the rest of FlekDeck
    /// reads it. On the main queue.
    static let udidReceived = PassthroughSubject<String, Never>()

    /// The ID the profile downloaded last was asked for under, and when.
    private static let requestIDKey = "FlekUDIDProfileRequestID"
    private static let requestDateKey = "FlekUDIDProfileRequestDate"

    /// How long FlekDeck goes on asking after a download. iOS drops a
    /// downloaded profile within minutes, and after a Security Delay the
    /// download is started again, under a new ID.
    private static let requestLifetime: TimeInterval = 2 * 60 * 60

    @MainActor private static var isCollecting = false

    /// The address to open for the download, which starts a request for the
    /// UDID. Nil when no address can be made.
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

        // As FlekSt0re's site makes the IDs of its browsers.
        let id = (0..<14).map { _ in String(Int.random(in: 0..<16), radix: 16) }.joined()
        var components = URLComponents(string: "https://nestapi.flekstore.com/device/get-udid/\(id)")
        // deal_id names a purchase under way; the site sends false for none.
        components?.queryItems = [URLQueryItem(name: "deal_id", value: "false"), scheme]
        guard let url = components?.url else {
            return nil
        }
        defaults.set(id, forKey: requestIDKey)
        defaults.set(Date(), forKey: requestDateKey)
        return url
    }

    /// Asks FlekSt0re which device answered the profile downloaded last, and
    /// takes its UDID. There is none until the profile is installed, which
    /// happens in Settings: this is for when the user is back from there.
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
            if let udid = await reportedUDID(forRequest: id) {
                store(udid)
                return
            }
        }
    }

    /// Takes the UDID from the address a server's redirect opens,
    /// <scheme>://udid?udid=<UDID>. False when it carries no UDID.
    @discardableResult
    static func importUDID(from url: URL) -> Bool {
        guard let udid = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "udid" })?.value?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              udid.isDeviceUDID else {
            return false
        }
        store(udid)
        return true
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
    /// device filed under the ID, then that device, UDID included.
    private static func reportedUDID(forRequest id: String) async -> String? {
        var lookup = URLComponents(string: "https://flekstore.com/rest/device/findDeviceByFp")
        lookup?.queryItems = [URLQueryItem(name: "fp_id", value: id)]
        guard let lookupURL = lookup?.url,
              let filed: FiledDevice = await answer(from: lookupURL),
              let number = filed.number,
              let deviceURL = URL(string: "https://nestapi.flekstore.com/device/status/\(number)"),
              let device: Device = await answer(from: deviceURL) else {
            return nil
        }
        let udid = device.udid.trimmingCharacters(in: .whitespacesAndNewlines)
        return udid.isDeviceUDID ? udid : nil
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

    private struct Device: Decodable {
        let udid: String
    }
}
