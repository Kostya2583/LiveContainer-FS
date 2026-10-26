//
//  FlekDeviceRecord.swift
//  LiveContainerSwiftUI
//
//  A device as FlekSt0re's database files it, under the number the UDID
//  profile's lookup gives: its UDID, and the services it has, Premium among
//  them with the day it ends.
//
//  A copy FlekSt0re did not sign reads it after the UDID profile's lookup,
//  for the UDID its Premium is then asked about by. The record is answered
//  for by number with nothing else asked, so anyone with the number can read
//  it. The number a copy goes by is the one its own profile request was
//  answered with, and nothing else sets it.
//

import Foundation

struct FlekDeviceRecord: Decodable {
    let udid: String
    /// When Premium ends, as the status service writes its end dates, or nil
    /// without Premium. The latest of the record's Premium entries, where it
    /// has more than one.
    let premiumEnd: String?

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

        private enum CodingKeys: String, CodingKey {
            case name
            case endDate = "end_date"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            name = try? container.decode(String.self, forKey: .name)
            endDate = try? container.decode(String.self, forKey: .endDate)
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
            .compactMap { $0.endDate.flatMap(DateFormatter.deviceServiceDate(from:)) }
            .max()
        premiumEnd = latest.map { DateFormatter.deviceServiceFormatter.string(from: $0) }
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
