//
//  HMOutdated.swift
//  Brewster
//
//  Created by Shmoopi LLC
//

import Foundation

// MARK: - Formulae
struct Formulae: Codable {
    let name: String
    let installedVersions: [String]
    let currentVersion: String
    let pinned: Bool
    let pinnedVersion: String?
    
    enum CodingKeys: String, CodingKey {
        case name
        case installedVersions = "installed_versions"
        case currentVersion = "current_version"
        case pinned
        case pinnedVersion = "pinned_version"
    }
}

// MARK: - Cask
struct Cask: Codable {
    let name: String
    let installedVersions: [String]
    let currentVersion: String
    
    enum CodingKeys: String, CodingKey {
        case name
        case installedVersions = "installed_versions"
        case currentVersion = "current_version"
    }
}

// MARK: - DataModel
struct DataModel: Codable {
    let formulae: [Formulae]
    let casks: [Cask]
}

func parseJSON(jsonData: Data) -> DataModel? {
    let decoder = JSONDecoder()
    do {
        let dataModel = try decoder.decode(DataModel.self, from: jsonData)
        return dataModel
    } catch {
        print("Error decoding JSON: \(error)")
        return nil
    }
}
