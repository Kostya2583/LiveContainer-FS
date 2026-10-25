//
//  FlekPairingDownload.swift
//  LiveContainerSwiftUI
//
//  Collects the pairing file FlekPair sent for this device, so that a file
//  made on a computer does not have to be carried over by hand.
//
//  FlekPair leaves what it exports on FlekSt0re's server under the device's
//  UDID, and the server hands it to whoever asks by that UDID. FlekDeck asks
//  as the JIT page comes up, when the user is back from the computer, and
//  when told to with Refresh.
//

import CryptoKit
import Foundation

enum FlekPairingDownload {
    enum Failure: LocalizedError {
        /// Which device to ask for is not known.
        case unknownDevice
        /// Nothing has been sent for this device.
        case nothingSent
        case unreachable
        /// The server answered with an error other than having no file.
        case refused(Int)
        /// The server holds a file for this device with nothing in it.
        case empty
        /// The server answered with something that is no property list: a
        /// network's sign-in page, say.
        case notAFile
        /// What was sent names another device.
        case otherDevice
        /// What was sent is no pairing file built-in JIT can use.
        case unusable

        var errorDescription: String? {
            switch self {
            case .unknownDevice: return "lc.flek.jit.pair.fetch.unknownDevice".loc
            case .nothingSent: return "lc.flek.jit.pair.fetch.nothingSent".loc
            case .unreachable: return "lc.flek.jit.pair.fetch.unreachable".loc
            case .refused(let status): return String(format: "lc.flek.jit.pair.fetch.refused %lld".loc, status)
            case .empty: return "lc.flek.jit.pair.fetch.empty".loc
            case .notAFile: return "lc.flek.jit.pair.fetch.notAFile".loc
            case .otherDevice: return "lc.flek.jit.pair.fetch.otherDevice".loc
            case .unusable: return "lc.flek.jit.pairingFile.wrongKind".loc
            }
        }
    }

    /// Where FlekPair leaves the files, each under its device's UDID.
    private static let server = "\(FlekStoreAPI.base)/pairing-files"

    /// What was taken last, by its digest.
    private static let takenKey = "FlekPairingDownloadTaken"

    /// A wait that ends: this runs behind a spinner, or with nothing shown.
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        configuration.waitsForConnectivity = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }()

    /// The pairing file waiting for this device, checked to be one built-in
    /// JIT can use and to be this device's.
    static func fetch() async throws -> Data {
        let udid = try await deviceUDID()
        // The server tells UDIDs apart by the case of their letters, and
        // FlekPair files a pairing file under the UDID as the device spells
        // it. That spelling is asked for first, and the one FlekDeck was told
        // after it, where the two differ.
        let spelled = udid.count == 40 ? udid.lowercased() : udid.uppercased()
        var sent = try await sentFile(for: spelled)
        if sent == nil, spelled != udid {
            sent = try await sentFile(for: udid)
        }
        // The server answers the same for a device it has never heard of as
        // for one nothing was sent for, and either way nothing was sent.
        guard let body = sent else {
            throw Failure.nothingSent
        }
        guard !body.isEmpty else {
            throw Failure.empty
        }

        guard let file = try? PropertyListSerialization.propertyList(from: body, format: nil) as? [String: Any] else {
            throw Failure.notAFile
        }
        // A pairing file FlekPair exports names its device. The server files
        // whatever it is sent under whatever UDID it is sent with.
        if let named = file["UDID"] as? String, named.caseInsensitiveCompare(udid) != .orderedSame {
            throw Failure.otherDevice
        }
        guard FlekBuiltInJIT.isUsablePairingFile(file) else {
            throw Failure.unusable
        }
        return body
    }

    /// What the server holds under a UDID, or nil where it holds nothing.
    private static func sentFile(for udid: String) async throws -> Data? {
        guard let address = URL(string: "\(server)/\(udid)") else {
            throw Failure.unknownDevice
        }
        let body: Data
        let response: URLResponse
        do {
            (body, response) = try await session.data(from: address)
        } catch {
            throw Failure.unreachable
        }
        guard let status = (response as? HTTPURLResponse)?.statusCode else {
            throw Failure.unreachable
        }
        switch status {
        case 200...299: return body
        case 404: return nil
        default: throw Failure.refused(status)
        }
    }

    /// Whether `file` is what was taken last. The server keeps a file until
    /// the next is sent, so one the user has since removed is still there, and
    /// looking unasked must not bring it back.
    static func wasTaken(_ file: Data) -> Bool {
        UserDefaults.standard.string(forKey: takenKey) == digest(of: file)
    }

    static func noteTaken(_ file: Data) {
        UserDefaults.standard.set(digest(of: file), forKey: takenKey)
    }

    private static func digest(of file: Data) -> String {
        SHA256.hash(data: file).map { String(format: "%02x", $0) }.joined()
    }

    /// This device's UDID, which an app is told and cannot read: by the UDID
    /// profile, or by the status service, which names the device a copy that
    /// FlekSt0re signed was signed for.
    private static func deviceUDID() async throws -> String {
        let shared = LCUtils.appGroupUserDefault
        for stored in [shared.string(forKey: "LCDeviceUDID"), UserDefaults.standard.string(forKey: "FSDeviceUDID")] {
            if let udid = stored?.trimmingCharacters(in: .whitespacesAndNewlines), udid.isDeviceUDID {
                return udid
            }
        }
        guard let deviceID = FlekPremium.deviceID else {
            throw Failure.unknownDevice
        }
        switch await AccessVerificationService.fetchStatus(encryptedUDID: deviceID) {
        case .answered(let status):
            let udid = status.udid.trimmingCharacters(in: .whitespacesAndNewlines)
            guard udid.isDeviceUDID else {
                throw Failure.unknownDevice
            }
            // Where General keeps it when it asks the same.
            shared.set(udid, forKey: "LCDeviceUDID")
            return udid
        case .unreachable:
            // Not knowing for want of a connection is another thing to tell
            // the user than not being able to know.
            throw Failure.unreachable
        case .serviceError:
            throw Failure.unknownDevice
        }
    }
}
