//
//  FlekStoreAPI.swift
//  LiveContainerSwiftUI
//
//  Where FlekDeck reaches FlekSt0re's API: the catalog and its app pages,
//  the device's status and record, the UDID profile, the pairing files.
//
//  The test server for now. It reads the same database as the production
//  one, nestapi.flekstore.com, and what is new on the server, such as the
//  device's number in the status answer, comes there first. The UDID lookup,
//  findDeviceByFp, is on flekstore.com itself, which has no test server, and
//  reads that same database.
//

enum FlekStoreAPI {
    static let base = "https://nestapitest.flekstore.com"
}
