//
//  FlekDeviceRecord.swift
//  LiveContainerSwiftUI
//
//  A device as FlekSt0re's database files it, under the number the UDID
//  profile's lookup gives: its UDID, and the services it has, Premium among
//  them with the day it ends.
//
//  A copy FlekSt0re did not sign knows its device and Premium by this alone,
//  as it has no device ID for the status service to be asked by. The record
//  is answered for by number with nothing else asked, so anyone with the
//  number can read it. The number a copy goes by is the one its own profile
//  request was answered with, and nothing else sets it.
//

import Foundation

struct FlekDeviceRecord: Decodable {
    let udid: String
    /// When Premium ends, as the status service writes its end dates, or nil
    /// without Premium. The latest of the record's Premium entries, where it
    /// has more than one.
    let premiumEnd: String?
    /// The PayPal subscription that Premium comes from, nil for Premium
    /// granted or bought once.
    let subscriptionID: String?

    private enum CodingKeys: String, CodingKey {
        case udid
        case service
    }

    /// One of the services on the record. Premium is the one named "premium".
    /// Each field is taken only where it is text, so that one of another
    /// kind does not cost the whole list.
    private struct Service: Decodable {
        let name: String?
        let endDate: String?
        /// "false" where there is none.
        let subscriptionID: String?

        private enum CodingKeys: String, CodingKey {
            case name
            case endDate = "end_date"
            case subscriptionID = "subscription_id"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            name = try? container.decode(String.self, forKey: .name)
            endDate = try? container.decode(String.self, forKey: .endDate)
            subscriptionID = try? container.decode(String.self, forKey: .subscriptionID)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        udid = ((try? container.decode(String.self, forKey: .udid)) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // The Premium entry that ends last. One whose end cannot be read is no
        // Premium rather than Premium without end, and so is a list that
        // cannot be read.
        let services = (try? container.decode([Service].self, forKey: .service)) ?? []
        let latest = services
            .filter { $0.name == "premium" }
            .compactMap { service in
                service.endDate.flatMap(DateFormatter.deviceServiceDate(from:)).map { (service: service, end: $0) }
            }
            .max { $0.end < $1.end }
        premiumEnd = latest.map { DateFormatter.deviceServiceFormatter.string(from: $0.end) }
        subscriptionID = latest?.service.subscriptionID
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .flatMap { $0.isEmpty || $0 == "false" ? nil : $0 }
    }

    /// The record of the device filed under `number`, or nil where there is
    /// no answer.
    static func fetch(number: Int) async -> FlekDeviceRecord? {
        guard let url = URL(string: "\(FlekStoreAPI.base)/device/status/\(number)") else {
            return nil
        }
        // Never from a cache: Premium bought a moment ago has to show.
        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            return nil
        }
        return try? JSONDecoder().decode(FlekDeviceRecord.self, from: data)
    }
}
