//
//  TimeIntervalOptionTests.swift
//  BrewsterTests
//
//  Created by Shmoopi LLC
//

import XCTest
@testable import Brewster

final class TimeIntervalOptionTests: XCTestCase {

    typealias TimeIntervalOption = StatusBarController.TimeIntervalOption

    // MARK: - Time Interval Value Tests

    func testOneHourInterval() {
        let option = TimeIntervalOption.oneHour
        XCTAssertEqual(option.timeInterval, 3600) // 60 * 60
        XCTAssertEqual(option.rawValue, "1h")
    }

    func testSixHoursInterval() {
        let option = TimeIntervalOption.sixHours
        XCTAssertEqual(option.timeInterval, 21600) // 6 * 60 * 60
        XCTAssertEqual(option.rawValue, "6h")
    }

    func testTwelveHoursInterval() {
        let option = TimeIntervalOption.twelveHours
        XCTAssertEqual(option.timeInterval, 43200) // 12 * 60 * 60
        XCTAssertEqual(option.rawValue, "12h")
    }

    func testOneDayInterval() {
        let option = TimeIntervalOption.oneDay
        XCTAssertEqual(option.timeInterval, 86400) // 24 * 60 * 60
        XCTAssertEqual(option.rawValue, "1d")
    }

    func testSevenDaysInterval() {
        let option = TimeIntervalOption.sevenDays
        XCTAssertEqual(option.timeInterval, 604800) // 7 * 24 * 60 * 60
        XCTAssertEqual(option.rawValue, "7d")
    }

    // MARK: - Raw Value Initialization Tests

    func testInitFromRawValueOneHour() {
        let option = TimeIntervalOption(rawValue: "1h")
        XCTAssertNotNil(option)
        XCTAssertEqual(option, .oneHour)
    }

    func testInitFromRawValueSixHours() {
        let option = TimeIntervalOption(rawValue: "6h")
        XCTAssertNotNil(option)
        XCTAssertEqual(option, .sixHours)
    }

    func testInitFromRawValueTwelveHours() {
        let option = TimeIntervalOption(rawValue: "12h")
        XCTAssertNotNil(option)
        XCTAssertEqual(option, .twelveHours)
    }

    func testInitFromRawValueOneDay() {
        let option = TimeIntervalOption(rawValue: "1d")
        XCTAssertNotNil(option)
        XCTAssertEqual(option, .oneDay)
    }

    func testInitFromRawValueSevenDays() {
        let option = TimeIntervalOption(rawValue: "7d")
        XCTAssertNotNil(option)
        XCTAssertEqual(option, .sevenDays)
    }

    func testInitFromInvalidRawValue() {
        let option = TimeIntervalOption(rawValue: "invalid")
        XCTAssertNil(option)
    }

    func testInitFromEmptyRawValue() {
        let option = TimeIntervalOption(rawValue: "")
        XCTAssertNil(option)
    }

    // MARK: - CaseIterable Tests

    func testAllCasesCount() {
        XCTAssertEqual(TimeIntervalOption.allCases.count, 5)
    }

    func testAllCasesContainsExpectedValues() {
        let allCases = TimeIntervalOption.allCases
        XCTAssertTrue(allCases.contains(.oneHour))
        XCTAssertTrue(allCases.contains(.sixHours))
        XCTAssertTrue(allCases.contains(.twelveHours))
        XCTAssertTrue(allCases.contains(.oneDay))
        XCTAssertTrue(allCases.contains(.sevenDays))
    }

    // MARK: - Interval Ordering Tests

    func testIntervalsAreInIncreasingOrder() {
        let intervals = TimeIntervalOption.allCases.map { $0.timeInterval }

        for i in 0..<intervals.count - 1 {
            XCTAssertLessThan(intervals[i], intervals[i + 1],
                             "Interval at index \(i) should be less than interval at index \(i + 1)")
        }
    }

    // MARK: - Human Readable Duration Tests

    func testOneHourInSeconds() {
        let oneHourInSeconds: TimeInterval = 60 * 60
        XCTAssertEqual(TimeIntervalOption.oneHour.timeInterval, oneHourInSeconds)
    }

    func testOneDayInHours() {
        let oneDayInHours = TimeIntervalOption.oneDay.timeInterval / 3600
        XCTAssertEqual(oneDayInHours, 24)
    }

    func testSevenDaysInDays() {
        let sevenDaysInDays = TimeIntervalOption.sevenDays.timeInterval / 86400
        XCTAssertEqual(sevenDaysInDays, 7)
    }
}
