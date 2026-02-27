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

    private enum CodingKeys: String, CodingKey {
        case status
        case endDate
        case udid
        case isBanned
        case banReason
        case message
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        status = try container.decodeIfPresent(Bool.self, forKey: .status) ?? false
        endDate = try container.decodeIfPresent(String.self, forKey: .endDate) ?? ""
        udid = try container.decodeIfPresent(String.self, forKey: .udid) ?? ""
        isBanned = try container.decodeIfPresent(Bool.self, forKey: .isBanned) ?? false
        banReason = try container.decodeIfPresent(String.self, forKey: .banReason)
        message = try container.decodeIfPresent(String.self, forKey: .message)
    }
}
