//
//  HomebrewManagerTests.swift
//  BrewsterTests
//
//  Created by Shmoopi LLC
//

import XCTest
@testable import Brewster

final class HomebrewManagerTests: XCTestCase {

    // MARK: - HomebrewError Tests

    func testHomebrewNotFoundErrorDescription() {
        let error = HomebrewError.homebrewNotFound
        XCTAssertEqual(error.errorDescription, "Homebrew not found on this system.")
    }

    func testCommandFailedErrorDescription() {
        let error = HomebrewError.commandFailed("Custom error message")
        XCTAssertEqual(error.errorDescription, "Custom error message")
    }

    func testTimeoutErrorDescription() {
        let error = HomebrewError.timeout
        XCTAssertEqual(error.errorDescription, "Homebrew command timed out.")
    }

    // MARK: - Mock HomebrewManager Tests

    func testMockReturnsConfiguredUpdates() {
        let mock = MockHomebrewManager()
        mock.mockUpdatesResult = .success(["git (2.40.0) < 2.41.0", "node (18.0.0) < 20.0.0"])

        let result = mock.getHomebrewUpdates(runUpdateFirst: false)

        switch result {
        case .success(let updates):
            XCTAssertEqual(updates.count, 2)
            XCTAssertTrue(updates.contains("git (2.40.0) < 2.41.0"))
            XCTAssertTrue(updates.contains("node (18.0.0) < 20.0.0"))
        case .failure:
            XCTFail("Expected success")
        }

        XCTAssertEqual(mock.getUpdatesCallCount, 1)
        XCTAssertEqual(mock.lastRunUpdateFirst, false)
    }

    func testMockReturnsConfiguredError() {
        let mock = MockHomebrewManager()
        mock.mockUpdatesResult = .failure(.homebrewNotFound)

        let result = mock.getHomebrewUpdates(runUpdateFirst: true)

        switch result {
        case .success:
            XCTFail("Expected failure")
        case .failure(let error):
            XCTAssertEqual(error, .homebrewNotFound)
        }

        XCTAssertEqual(mock.lastRunUpdateFirst, true)
    }

    func testMockTracksUpgradePackageCalls() {
        let mock = MockHomebrewManager()
        mock.mockUpgradeResult = .success(())

        _ = mock.upgradePackage(package: "git")
        _ = mock.upgradePackage(package: "node")

        XCTAssertEqual(mock.upgradePackageCallCount, 2)
        XCTAssertEqual(mock.lastUpgradedPackage, "node")
    }

    func testMockTracksUpgradeAllCalls() {
        let mock = MockHomebrewManager()
        mock.mockUpgradeResult = .success(())

        _ = mock.upgradeAllPackages()

        XCTAssertEqual(mock.upgradeAllCallCount, 1)
    }

    func testMockRunCommandTracking() {
        let mock = MockHomebrewManager()
        mock.mockCommandResult = .success("output")

        _ = mock.runCommand(arguments: ["outdated", "--json"], timeout: 120)

        XCTAssertEqual(mock.runCommandCallCount, 1)
        XCTAssertEqual(mock.lastCommandArguments, ["outdated", "--json"])
        XCTAssertEqual(mock.lastCommandTimeout, 120)
    }

    func testMockReset() {
        let mock = MockHomebrewManager()

        _ = mock.getHomebrewUpdates(runUpdateFirst: true)
        _ = mock.upgradePackage(package: "test")
        _ = mock.upgradeAllPackages()

        mock.reset()

        XCTAssertEqual(mock.getUpdatesCallCount, 0)
        XCTAssertEqual(mock.upgradePackageCallCount, 0)
        XCTAssertEqual(mock.upgradeAllCallCount, 0)
        XCTAssertNil(mock.lastUpgradedPackage)
        XCTAssertNil(mock.lastRunUpdateFirst)
    }

    // MARK: - HomebrewError Equatable Tests

    func testHomebrewErrorEquality() {
        XCTAssertEqual(HomebrewError.homebrewNotFound, HomebrewError.homebrewNotFound)
        XCTAssertEqual(HomebrewError.timeout, HomebrewError.timeout)
        XCTAssertEqual(HomebrewError.commandFailed("test"), HomebrewError.commandFailed("test"))
        XCTAssertNotEqual(HomebrewError.commandFailed("test1"), HomebrewError.commandFailed("test2"))
        XCTAssertNotEqual(HomebrewError.homebrewNotFound, HomebrewError.timeout)
    }
}

// MARK: - HomebrewError Equatable Extension for Testing

extension HomebrewError: Equatable {
    public static func == (lhs: HomebrewError, rhs: HomebrewError) -> Bool {
        switch (lhs, rhs) {
        case (.homebrewNotFound, .homebrewNotFound):
            return true
        case (.timeout, .timeout):
            return true
        case (.commandFailed(let lhsMsg), .commandFailed(let rhsMsg)):
            return lhsMsg == rhsMsg
        default:
            return false
        }
    }
}
