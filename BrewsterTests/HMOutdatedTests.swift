//
//  HMOutdatedTests.swift
//  BrewsterTests
//
//  Created by Shmoopi LLC
//

import XCTest
@testable import Brewster

final class HMOutdatedTests: XCTestCase {

    // MARK: - Valid JSON Tests

    func testParseValidJSONWithFormulaeAndCasks() {
        let json = """
        {
            "formulae": [
                {
                    "name": "git",
                    "installed_versions": ["2.40.0"],
                    "current_version": "2.41.0",
                    "pinned": false,
                    "pinned_version": null
                }
            ],
            "casks": [
                {
                    "name": "visual-studio-code",
                    "installed_versions": ["1.78.0"],
                    "current_version": "1.79.0"
                }
            ]
        }
        """

        let data = json.data(using: .utf8)!
        let result = parseJSON(jsonData: data)

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.formulae.count, 1)
        XCTAssertEqual(result?.casks.count, 1)

        XCTAssertEqual(result?.formulae[0].name, "git")
        XCTAssertEqual(result?.formulae[0].installedVersions, ["2.40.0"])
        XCTAssertEqual(result?.formulae[0].currentVersion, "2.41.0")
        XCTAssertFalse(result?.formulae[0].pinned ?? true)

        XCTAssertEqual(result?.casks[0].name, "visual-studio-code")
        XCTAssertEqual(result?.casks[0].installedVersions, ["1.78.0"])
        XCTAssertEqual(result?.casks[0].currentVersion, "1.79.0")
    }

    func testParseEmptyFormulaeAndCasks() {
        let json = """
        {
            "formulae": [],
            "casks": []
        }
        """

        let data = json.data(using: .utf8)!
        let result = parseJSON(jsonData: data)

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.formulae.count, 0)
        XCTAssertEqual(result?.casks.count, 0)
    }

    func testParseMultipleInstalledVersions() {
        let json = """
        {
            "formulae": [
                {
                    "name": "python",
                    "installed_versions": ["3.9.0", "3.10.0", "3.11.0"],
                    "current_version": "3.12.0",
                    "pinned": false,
                    "pinned_version": null
                }
            ],
            "casks": []
        }
        """

        let data = json.data(using: .utf8)!
        let result = parseJSON(jsonData: data)

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.formulae[0].installedVersions.count, 3)
        XCTAssertEqual(result?.formulae[0].installedVersions, ["3.9.0", "3.10.0", "3.11.0"])
    }

    func testParsePinnedFormula() {
        let json = """
        {
            "formulae": [
                {
                    "name": "node",
                    "installed_versions": ["18.0.0"],
                    "current_version": "20.0.0",
                    "pinned": true,
                    "pinned_version": "18.0.0"
                }
            ],
            "casks": []
        }
        """

        let data = json.data(using: .utf8)!
        let result = parseJSON(jsonData: data)

        XCTAssertNotNil(result)
        XCTAssertTrue(result?.formulae[0].pinned ?? false)
        XCTAssertEqual(result?.formulae[0].pinnedVersion, "18.0.0")
    }

    // MARK: - Invalid JSON Tests

    func testParseInvalidJSON() {
        let json = "not valid json"
        let data = json.data(using: .utf8)!
        let result = parseJSON(jsonData: data)

        XCTAssertNil(result)
    }

    func testParseMissingRequiredFields() {
        let json = """
        {
            "formulae": [
                {
                    "name": "git"
                }
            ],
            "casks": []
        }
        """

        let data = json.data(using: .utf8)!
        let result = parseJSON(jsonData: data)

        XCTAssertNil(result)
    }

    func testParseEmptyData() {
        let data = Data()
        let result = parseJSON(jsonData: data)

        XCTAssertNil(result)
    }

    func testParseMalformedJSON() {
        let json = """
        {
            "formulae": [
                {
                    "name": "git",
        """

        let data = json.data(using: .utf8)!
        let result = parseJSON(jsonData: data)

        XCTAssertNil(result)
    }

    // MARK: - Edge Cases

    func testParseSpecialCharactersInNames() {
        let json = """
        {
            "formulae": [
                {
                    "name": "package@1.0",
                    "installed_versions": ["1.0.0-beta"],
                    "current_version": "1.0.0+build.123",
                    "pinned": false,
                    "pinned_version": null
                }
            ],
            "casks": []
        }
        """

        let data = json.data(using: .utf8)!
        let result = parseJSON(jsonData: data)

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.formulae[0].name, "package@1.0")
        XCTAssertEqual(result?.formulae[0].installedVersions, ["1.0.0-beta"])
        XCTAssertEqual(result?.formulae[0].currentVersion, "1.0.0+build.123")
    }

    func testParseLargeNumberOfPackages() {
        var formulaeArray: [String] = []
        for i in 0..<100 {
            formulaeArray.append("""
            {
                "name": "package\(i)",
                "installed_versions": ["1.0.\(i)"],
                "current_version": "2.0.\(i)",
                "pinned": false,
                "pinned_version": null
            }
            """)
        }

        let json = """
        {
            "formulae": [\(formulaeArray.joined(separator: ","))],
            "casks": []
        }
        """

        let data = json.data(using: .utf8)!
        let result = parseJSON(jsonData: data)

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.formulae.count, 100)
    }
}
