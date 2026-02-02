//
//  RepoResponse.swift
//  LiveContainer
//
//  Created by Alexander Grigoryev on 28.01.2026.
//

import Foundation

struct RepoResponse: Codable {
    let apps: [RepoApp]
}

struct RepoApp: Codable {
    let name: String
    let localizedDescription: String?
    let iconURL: String?

    // Simple repos
    let version: String?
    let downloadURL: String?

    // Versioned repos
    let versions: [RepoAppVersion]?
}

struct RepoAppVersion: Codable {
    let absoluteVersion: String?
    let version: String?
    let downloadURL: String
    let date: String?
}
