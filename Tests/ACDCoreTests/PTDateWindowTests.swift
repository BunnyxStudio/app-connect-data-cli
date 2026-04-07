import XCTest
import Foundation
@testable import ACDCore

final class PTDateWindowTests: XCTestCase {
    func testLastDayPresetResolvesToYesterdayInPacificTime() throws {
        let reference = try XCTUnwrap(DateFormatter.ptDateFormatter.date(from: "2026-04-07"))
        let window = try XCTUnwrap(resolvePTDateWindow(rangePreset: "last day", defaultPreset: nil, reference: reference))
        XCTAssertEqual(window.startDatePT, "2026-04-06")
        XCTAssertEqual(window.endDatePT, "2026-04-06")
    }

    func testLastWeekPresetResolvesToPreviousSevenDays() throws {
        let reference = try XCTUnwrap(DateFormatter.ptDateFormatter.date(from: "2026-04-07"))
        let window = try XCTUnwrap(resolvePTDateWindow(rangePreset: "last-week", defaultPreset: nil, reference: reference))
        XCTAssertEqual(window.startDatePT, "2026-03-31")
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
}
