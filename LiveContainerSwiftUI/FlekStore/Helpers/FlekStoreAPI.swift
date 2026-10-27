//
//  FlekStoreAPI.swift
//  LiveContainerSwiftUI
//
//  Where FlekDeck reaches FlekSt0re's API: the catalog and its app pages,
//  the device's status and record, the UDID profile, the pairing files.
//
//  The production server. The test one, nestapitest.flekstore.com, reads the
//  same database and gets what is new on the server first. The UDID lookup,
//  findDeviceByFp, is on flekstore.com itself and reads that same database.
//

enum FlekStoreAPI {
    static let base = "https://nestapi.flekstore.com"
}
