//
//  MockHomebrewManager.swift
//  BrewsterTests
//
//  Created by Shmoopi LLC
//

import Foundation
@testable import Brewster

class MockHomebrewManager: HomebrewExecutable {

    // Configuration for mock behavior
    var mockCommandResult: Result<String, HomebrewError> = .success("")
    var mockUpdatesResult: Result<[String], HomebrewError> = .success([])
    var mockUpgradeResult: Result<Void, HomebrewError> = .success(())

    // Tracking calls for verification
    var runCommandCallCount = 0
    var lastCommandArguments: [String]?
    var lastCommandTimeout: TimeInterval?

    var getUpdatesCallCount = 0
    var lastRunUpdateFirst: Bool?

    var upgradePackageCallCount = 0
    var lastUpgradedPackage: String?

    var upgradeAllCallCount = 0

    func runCommand(arguments: [String], timeout: TimeInterval) -> Result<String, HomebrewError> {
        runCommandCallCount += 1
        lastCommandArguments = arguments
        lastCommandTimeout = timeout
        return mockCommandResult
    }

    func getHomebrewUpdates(runUpdateFirst: Bool) -> Result<[String], HomebrewError> {
        getUpdatesCallCount += 1
        lastRunUpdateFirst = runUpdateFirst
        return mockUpdatesResult
    }

    func upgradePackage(package: String) -> Result<Void, HomebrewError> {
        upgradePackageCallCount += 1
        lastUpgradedPackage = package
        return mockUpgradeResult
    }

    func upgradeAllPackages() -> Result<Void, HomebrewError> {
        upgradeAllCallCount += 1
        return mockUpgradeResult
    }

    // Helper to reset tracking
    func reset() {
        runCommandCallCount = 0
        lastCommandArguments = nil
        lastCommandTimeout = nil
        getUpdatesCallCount = 0
        lastRunUpdateFirst = nil
        upgradePackageCallCount = 0
        lastUpgradedPackage = nil
        upgradeAllCallCount = 0
    }
}
