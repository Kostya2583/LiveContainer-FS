//
//  DeviceResponse.swift
//  LiveContainer
//
//  Created by Alexander Grigoryev on 29.01.2026.
//


import Foundation

struct DeviceStatusResponse: Codable {
    let status: Bool
    let endDate: String
    let udid: String
    let isBanned: Bool
    let banReason: String?
    let message: String?
    /// Optional server-side override for how long a clean verdict keeps opening
    /// the app offline. Absent from current responses; `AccessVerdictStore`
    /// falls back to its own default and clamps whatever arrives.
    let offlineGraceDays: Int?
    /// The number FlekSt0re's database files the device under, which Premium
    /// is paid for by: see FlekPremium.deviceNumber. Taken as a number or as
    /// text, and nil where the answer has none.
    let deviceNumber: Int?

    private enum CodingKeys: String, CodingKey {
        case status
        case endDate
        case udid
        case isBanned
        case banReason
        case message
        case offlineGraceDays
        case deviceNumber = "deviceId"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        status = try container.decodeIfPresent(Bool.self, forKey: .status) ?? false
        endDate = try container.decodeIfPresent(String.self, forKey: .endDate) ?? ""
        udid = try container.decodeIfPresent(String.self, forKey: .udid) ?? ""
        isBanned = try container.decodeIfPresent(Bool.self, forKey: .isBanned) ?? false
        banReason = try container.decodeIfPresent(String.self, forKey: .banReason)
        message = try container.decodeIfPresent(String.self, forKey: .message)
        offlineGraceDays = try container.decodeIfPresent(Int.self, forKey: .offlineGraceDays)
        if let number = try? container.decode(Int.self, forKey: .deviceNumber) {
            deviceNumber = number > 0 ? number : nil
        } else if let text = try? container.decode(String.self, forKey: .deviceNumber), let number = Int(text), number > 0 {
            deviceNumber = number
        } else {
            deviceNumber = nil
        }
    }
}
