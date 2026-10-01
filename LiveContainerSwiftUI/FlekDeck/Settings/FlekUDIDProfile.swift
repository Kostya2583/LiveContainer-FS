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
//  before connecting, the loopback address included. So a server serves the
//  page that downloads the profile and the profile itself, takes the answer,
//  and redirects to <scheme>://udid?udid=<UDID>. iOS opens that address at
//  once, which brings the user straight back here with the UDID.
//

import Combine
import Foundation

enum FlekUDIDProfile {
    /// The Developer Mode setting that points FlekDeck at a server other than
    /// FlekSt0re's, to try one out.
    static let pageAddressKey = "FlekUDIDProfilePageAddress"

    /// FlekSt0re's page, once it has one. Until then only the Developer Mode
    /// setting gives FlekDeck a page to open.
    private static let defaultPageURL: URL? = nil

    /// Each UDID that arrives, once it is stored where the rest of FlekDeck
    /// reads it. On the main queue.
    static let udidReceived = PassthroughSubject<String, Never>()

    /// The page to open for the download, telling the server which URL scheme
    /// to send the user back to: a second copy of FlekDeck answers to its own.
    /// Nil when there is no server to open.
    static var pageURL: URL? {
        let override = UserDefaults.standard.string(forKey: pageAddressKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let configured = URL(string: override).flatMap { $0.scheme?.lowercased() == "https" && $0.host != nil ? $0 : nil }
        guard let page = configured ?? defaultPageURL,
              var components = URLComponents(url: page, resolvingAgainstBaseURL: false) else {
            return nil
        }
        let scheme = LCUtils.appUrlScheme() ?? "flekdeck"
        components.queryItems = (components.queryItems ?? []) + [URLQueryItem(name: "scheme", value: scheme)]
        return components.url
    }

    /// Takes the UDID from the address the server's redirect opens,
    /// <scheme>://udid?udid=<UDID>. False when it carries no UDID.
    @discardableResult
    static func importUDID(from url: URL) -> Bool {
        guard let udid = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "udid" })?.value?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              udid.isDeviceUDID else {
            return false
        }
        LCUtils.appGroupUserDefault.set(udid, forKey: "LCDeviceUDID")
        udidReceived.send(udid)
        return true
    }
}
