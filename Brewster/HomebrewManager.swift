//
//  HomeBrewManager.swift
//  Brewster
//
//  Created by Shmoopi LLC
//

import Foundation
import os.log

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.shmoopi.Brewster", category: "HomebrewManager")

enum HomebrewError: Error, LocalizedError {
    case commandFailed(String)
    case homebrewNotFound
    case timeout

    var errorDescription: String? {
        switch self {
        case .homebrewNotFound:
            return "Homebrew not found on this system."
        case .commandFailed(let message):
            return message
        case .timeout:
            return "Homebrew command timed out."
        }
    }
}

// MARK: - Protocol for testability

protocol HomebrewExecutable {
    func runCommand(arguments: [String], timeout: TimeInterval) -> Result<String, HomebrewError>
    func getHomebrewUpdates(runUpdateFirst: Bool) -> Result<[String], HomebrewError>
    func upgradePackage(package: String) -> Result<Void, HomebrewError>
    func upgradeAllPackages() -> Result<Void, HomebrewError>
}

// Default timeout values
private let defaultCommandTimeout: TimeInterval = 120 // 2 minutes for most commands
private let updateCommandTimeout: TimeInterval = 300 // 5 minutes for brew update
private let upgradeCommandTimeout: TimeInterval = 600 // 10 minutes for upgrades

// UserDefaults keys
private let cachedBrewPathKey = "cachedBrewPath"
private let runUpdateFirstKey = "runUpdateFirstKey"

class HomebrewManager: HomebrewExecutable {

    private var brewPath: String?

    // User preference: run brew update before checking outdated
    var runUpdateFirst: Bool {
        get {
            return UserDefaults.standard.bool(forKey: runUpdateFirstKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: runUpdateFirstKey)
        }
    }

    init() {
        // Try to load cached path first
        if let cachedPath = UserDefaults.standard.string(forKey: cachedBrewPathKey),
           FileManager.default.fileExists(atPath: cachedPath) {
            logger.debug("Using cached brew path: \(cachedPath)")
            self.brewPath = cachedPath
        } else {
            // Find and cache the brew path
            self.brewPath = findHomebrewPath()
            if let path = self.brewPath {
                UserDefaults.standard.set(path, forKey: cachedBrewPathKey)
                logger.info("Cached brew path: \(path)")
            }
        }
    }

    private func findHomebrewPath() -> String? {
        let potentialPaths = [
            "/opt/homebrew/bin/brew",
            "/usr/local/bin/brew"
        ]

        for path in potentialPaths {
            if FileManager.default.fileExists(atPath: path) {
                logger.debug("Found Homebrew at: \(path)")
                return path
            }
        }

        // Try to find brew in the PATH
        logger.debug("Searching for Homebrew in PATH")
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
                    logger.debug("Found Homebrew via which: \(path)")
                    return path
                }
            }
        } catch {
            logger.error("Error finding Homebrew path: \(error.localizedDescription)")
        }

        logger.warning("Homebrew not found")
        return nil
    }

    func runCommand(arguments: [String], timeout: TimeInterval = defaultCommandTimeout) -> Result<String, HomebrewError> {
        guard let brewPath = brewPath else {
            return .failure(.homebrewNotFound)
        }

        logger.info("Running brew \(arguments.joined(separator: " "))")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: brewPath)
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        // Create a dispatch group for timeout handling
        let group = DispatchGroup()
        var didTimeout = false
        var processOutput: Data?
        var processError: Error?
        var exitStatus: Int32 = -1

        group.enter()

        DispatchQueue.global().async {
            do {
                try process.run()

                // Set up timeout
                let timeoutWorkItem = DispatchWorkItem {
                    if process.isRunning {
                        logger.warning("Command timed out after \(timeout) seconds, terminating")
                        didTimeout = true
                        process.terminate()
                    }
                }

                DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timeoutWorkItem)

                process.waitUntilExit()
                timeoutWorkItem.cancel()

                exitStatus = process.terminationStatus
                processOutput = try? pipe.fileHandleForReading.readToEnd()
            } catch {
                processError = error
            }
            group.leave()
        }

        // Wait for process to complete
        group.wait()

        if didTimeout {
            return .failure(.timeout)
        }

        if let error = processError {
            logger.error("Command failed with error: \(error.localizedDescription)")
            return .failure(.commandFailed(error.localizedDescription))
        }

        if exitStatus == 0 {
            let output = processOutput.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            logger.debug("Command completed successfully")
            return .success(output)
        } else {
            let errorOutput = processOutput.flatMap { String(data: $0, encoding: .utf8) } ?? "Unknown error"
            logger.error("Command failed with exit code \(exitStatus): \(errorOutput)")
            return .failure(.commandFailed(errorOutput))
        }
    }

    func getHomebrewUpdates(runUpdateFirst: Bool = false) -> Result<[String], HomebrewError> {
        // Optionally run brew update first to get fresh data
        let shouldUpdate = runUpdateFirst || self.runUpdateFirst
        if shouldUpdate {
            logger.info("Running brew update first")
            let updateResult = runCommand(arguments: ["update"], timeout: updateCommandTimeout)
            if case .failure(let error) = updateResult {
                // Log but don't fail - we can still check outdated
                logger.warning("brew update failed: \(error.localizedDescription)")
            }
        }

        switch runCommand(arguments: ["outdated", "--json"], timeout: defaultCommandTimeout) {
        case .success(let output):
            guard let jsonStartIndex = output.firstIndex(of: "{") else {
                logger.error("Invalid JSON: No opening brace found")
                return .failure(.commandFailed("Invalid JSON: No opening brace found"))
            }

            let jsonDataString = String(output[jsonStartIndex...])

            if let jsonData = jsonDataString.data(using: .utf8) {
                if let dataModel = parseJSON(jsonData: jsonData) {
                    var output: [String] = [String]()
                    for formula in dataModel.formulae {
                        output.append("\(formula.name) (\(formula.installedVersions.joined(separator: ", "))) < \(formula.currentVersion)")
                    }
                    for cask in dataModel.casks {
                        output.append("\(cask.name) (\(cask.installedVersions.joined(separator: ", "))) != \(cask.currentVersion)")
                    }
                    logger.info("Found \(output.count) outdated packages")
                    return .success(output)
                } else {
                    logger.error("Unable to parse JSON data into object")
                    return .failure(.commandFailed("Unable to parse json data into object"))
                }
            } else {
                logger.error("Unable to parse 'brew outdated --json'")
                return .failure(.commandFailed("Unable to parse 'brew outdated --json'"))
            }
        case .failure(let error):
            return .failure(error)
        }
    }

    func upgradePackage(package: String) -> Result<Void, HomebrewError> {
        logger.info("Upgrading package: \(package)")
        switch runCommand(arguments: ["upgrade", package], timeout: upgradeCommandTimeout) {
        case .success:
            logger.info("Successfully upgraded \(package)")
            return .success(())
        case .failure(let error):
            logger.error("Failed to upgrade \(package): \(error.localizedDescription)")
            return .failure(error)
        }
    }

    func upgradeAllPackages() -> Result<Void, HomebrewError> {
        logger.info("Upgrading all packages")
        switch runCommand(arguments: ["upgrade"], timeout: upgradeCommandTimeout) {
        case .success:
            logger.info("Successfully upgraded all packages")
            return .success(())
        case .failure(let error):
            logger.error("Failed to upgrade all packages: \(error.localizedDescription)")
            return .failure(error)
        }
    }
}
