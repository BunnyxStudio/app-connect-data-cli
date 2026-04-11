// Copyright 2026 BunnyxStudio
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import XCTest
import Foundation
@testable import ACDCore

final class PTDateWindowTests: XCTestCase {
    func testLastDayPresetUsesLatestCompleteDayBeforeDailyRollover() throws {
        let reference = try makePacificDate(year: 2026, month: 4, day: 7, hour: 4)
        let window = try XCTUnwrap(resolvePTDateWindow(rangePreset: "last day", defaultPreset: nil, reference: reference))
        XCTAssertEqual(window.startDatePT, "2026-04-05")
        XCTAssertEqual(window.endDatePT, "2026-04-05")
    }

    func testLastDayPresetUsesYesterdayAfterDailyRollover() throws {
        let reference = try makePacificDate(year: 2026, month: 4, day: 7, hour: 5)
        let window = try XCTUnwrap(resolvePTDateWindow(rangePreset: "last day", defaultPreset: nil, reference: reference))
        XCTAssertEqual(window.startDatePT, "2026-04-06")
        XCTAssertEqual(window.endDatePT, "2026-04-06")
    }

    func testLastWeekPresetResolvesToPreviousCompleteWeek() throws {
        let reference = try makePacificDate(year: 2026, month: 4, day: 10, hour: 5)
        let window = try XCTUnwrap(resolvePTDateWindow(rangePreset: "last-week", defaultPreset: nil, reference: reference))
        XCTAssertEqual(window.startDatePT, "2026-03-30")
        XCTAssertEqual(window.endDatePT, "2026-04-05")
    }

    func testThisWeekPresetUsesWeekToDateFromLatestCompleteDay() throws {
        let reference = try makePacificDate(year: 2026, month: 4, day: 10, hour: 5)
        let window = try XCTUnwrap(resolvePTDateWindow(rangePreset: "this-week", defaultPreset: nil, reference: reference))
        XCTAssertEqual(window.startDatePT, "2026-04-06")
        XCTAssertEqual(window.endDatePT, "2026-04-09")
    }

    func testThisMonthPresetUsesMonthToDateFromLatestCompleteDay() throws {
        let reference = try makePacificDate(year: 2026, month: 4, day: 7, hour: 5)
        let window = try XCTUnwrap(resolvePTDateWindow(rangePreset: "this-month", defaultPreset: nil, reference: reference))
        XCTAssertEqual(window.startDatePT, "2026-04-01")
        XCTAssertEqual(window.endDatePT, "2026-04-06")
    }

    func testFullFiscalMonthsAndDailyDatesSplitWindow() throws {
        let start = try XCTUnwrap(DateFormatter.ptDateFormatter.date(from: "2026-03-01"))
        let end = try XCTUnwrap(DateFormatter.ptDateFormatter.date(from: "2026-04-03"))
        let window = PTDateWindow(startDate: start, endDate: end)

        XCTAssertEqual(fullFiscalMonthsContained(in: window), ["2026-03"])
        XCTAssertEqual(fiscalMonthsOverlapping(window: window), ["2026-03", "2026-04"])

        let dates = ptDates(in: window, excludingFullMonths: true).map(\.ptDateString)
        XCTAssertEqual(dates, ["2026-04-01", "2026-04-02", "2026-04-03"])
    }

    private func makePacificDate(year: Int, month: Int, day: Int, hour: Int) throws -> Date {
        let date = Calendar.pacific.date(from: DateComponents(year: year, month: month, day: day, hour: hour))
        return try XCTUnwrap(date)
    }
}
