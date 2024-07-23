//
//  HomeBrewManager.swift
//  Brewster
//
//  Created by Shmoopi LLC
//

import Foundation

enum HomebrewError: Error, LocalizedError {
    case commandFailed(String)
    case homebrewNotFound
    
    var errorDescription: String? {
        switch self {
        case .homebrewNotFound:
            return "Homebrew not found on this system."
        case .commandFailed(let message):
            return message
        }
    }
}

class HomebrewManager {
    
    private var brewPath: String?
    
    init() {
        // Get the brew path
        self.brewPath = findHomebrewPath()
    }
    
    private func findHomebrewPath() -> String? {
        let potentialPaths = [
            "/opt/homebrew/bin/brew",
            "/usr/local/bin/brew"
        ]
        
        for path in potentialPaths {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }
        
        // Try to find brew in the PATH
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["which", "brew"]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            if let output = try? pipe.fileHandleForReading.readToEnd(), process.terminationStatus == 0 {
                let path = String(data: output, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                if let path = path, !path.isEmpty {
                    return path
                }
            }
        } catch {
            print("Error finding Homebrew path: \(error)")
        }
        
        return nil
    }
    
    private func runBrewCommand(arguments: [String]) -> Result<String, HomebrewError> {
        guard let brewPath = brewPath else {
            return .failure(.homebrewNotFound)
        }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: brewPath)
        process.arguments = arguments
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            if process.terminationStatus == 0 {
                if let output = try pipe.fileHandleForReading.readToEnd() {
                    return .success(String(data: output, encoding: .utf8) ?? "")
                } else {
                    return .success("")
                }
            } else if let errorOutput = try pipe.fileHandleForReading.readToEnd() {
                return .failure(.commandFailed(String(data: errorOutput, encoding: .utf8) ?? "Unknown error"))
            }
        } catch {
            return .failure(.commandFailed(error.localizedDescription))
        }
        
        return .failure(.commandFailed("Unknown error"))
    }
    
    func getHomebrewUpdates() -> Result<[String], HomebrewError> {
        switch runBrewCommand(arguments: ["outdated", "--json"]) {
        case .success(let output):
            guard let jsonStartIndex = output.firstIndex(of: "{") else {
                return .failure(.commandFailed("Invalid JSON: No opening brace found"))
            }
            
            let jsonDataString = String(output[jsonStartIndex...])
            
            if let jsonData = jsonDataString.data(using: .utf8) {
                if let dataModel = parseJSON(jsonData: jsonData) {
                    var output : [String] = [String]()
                    for formula in dataModel.formulae {
                        output.append("\(formula.name) (\(formula.installedVersions.joined(separator: ", "))) < \(formula.currentVersion)")
                    }
                    for cask in dataModel.casks {
                        output.append("\(cask.name) (\(cask.installedVersions.joined(separator: ", "))) != \(cask.currentVersion)")
                    }
                    return .success(output)
                } else {
                    return .failure(.commandFailed("Unable to parse json data into object"))
                }
            } else {
                return .failure(.commandFailed("Unable to parse 'brew outdated --json'"))
            }
        case .failure(let error):
            return .failure(error)
        }
    }
    
    func upgradePackage(package: String) -> Result<Void, HomebrewError> {
        switch runBrewCommand(arguments: ["upgrade", package]) {
        case .success:
            return .success(())
        case .failure(let error):
            return .failure(error)
        }
    }
    
    func upgradeAllPackages() -> Result<Void, HomebrewError> {
        switch runBrewCommand(arguments: ["upgrade"]) {
        case .success:
            return .success(())
        case .failure(let error):
            return .failure(error)
        }
    }
}
