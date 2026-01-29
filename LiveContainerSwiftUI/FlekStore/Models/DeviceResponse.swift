//
//  DeviceResponse.swift
//  LiveContainer
//
//  Created by Alexander Grigoryev on 29.01.2026.
//


import Foundation

struct DeviceStatusResponse: Codable {
    let service: [Service]?
}

struct Service: Codable {
    let end_date: String
}
