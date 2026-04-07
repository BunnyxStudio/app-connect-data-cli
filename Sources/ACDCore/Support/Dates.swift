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

import Foundation

public struct PTDate: Hashable, Codable, Sendable {
    public var rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public var date: Date? {
        DateFormatter.ptDateFormatter.date(from: rawValue)
    }
}

public extension Date {
    var ptDateString: String {
        DateFormatter.ptDateFormatter.string(from: self)
    }

    var fiscalMonthString: String {
        DateFormatter.fiscalMonthFormatter.string(from: self)
    }
}

public extension Calendar {
    static var pacific: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = pacificTimeZone
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }
}

extension DateFormatter {
    public static let ptDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = pacificTimeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    public static let fiscalMonthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = pacificTimeZone
        formatter.dateFormat = "yyyy-MM"
        return formatter
    }()
}

public enum PTDateWindowError: LocalizedError, Equatable, Sendable {
    case conflictingSelectors
    case invalidPreset(String)
    case invalidDate(String)

    public var errorDescription: String? {
        switch self {
        case .conflictingSelectors:
            return "Use only one of --date, --from/--to, or --range."
        case .invalidPreset(let value):
            return "Unsupported range preset: \(value)"
        case .invalidDate(let value):
            return "Invalid PT date: \(value)"
        }
    }
}

public enum PTDateRangePreset: String, CaseIterable, Codable, Sendable {
    case lastDay = "last-day"
    case lastWeek = "last-week"
    case last7d = "last-7d"
    case last30d = "last-30d"
    case lastMonth = "last-month"
    case yearToDate = "year-to-date"
    case previousWeek = "previous-week"
    case previousMonth = "previous-month"

    public init?(userInput: String) {
        let normalized = userInput
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")
            .replacingOccurrences(of: " ", with: "-")
        switch normalized {
        case "last-day", "lastday", "yesterday":
            self = .lastDay
        case "last-week", "lastweek":
            self = .lastWeek
        case "last-7d", "7d", "last7d":
            self = .last7d
        case "last-30d", "30d", "last30d":
            self = .last30d
        case "last-month", "lastmonth":
            self = .lastMonth
        case "year-to-date", "ytd", "year2date":
            self = .yearToDate
        case "previous-week", "prev-week":
            self = .previousWeek
        case "previous-month", "prev-month":
            self = .previousMonth
        default:
            return nil
        }
    }

    public func resolve(reference: Date = Date()) -> PTDateWindow {
        let calendar = Calendar.pacific
        let today = calendar.startOfDay(for: reference)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        let currentWeek = calendar.dateInterval(of: .weekOfYear, for: today)
        let currentMonth = calendar.dateInterval(of: .month, for: today)

        switch self {
        case .lastDay:
            return PTDateWindow(startDate: yesterday, endDate: yesterday)
        case .lastWeek, .previousWeek:
            let currentWeekStart = currentWeek?.start ?? today
            let previousWeekEnd = calendar.date(byAdding: .day, value: -1, to: currentWeekStart) ?? yesterday
            let previousWeekStart = calendar.dateInterval(of: .weekOfYear, for: previousWeekEnd)?.start ?? previousWeekEnd
            return PTDateWindow(startDate: previousWeekStart, endDate: previousWeekEnd)
        case .last7d:
            let end = yesterday
            let start = calendar.date(byAdding: .day, value: -6, to: end) ?? end
            return PTDateWindow(startDate: start, endDate: end)
        case .last30d:
            let end = yesterday
            let start = calendar.date(byAdding: .day, value: -29, to: end) ?? end
            return PTDateWindow(startDate: start, endDate: end)
        case .lastMonth, .previousMonth:
            let currentMonthStart = currentMonth?.start ?? today
            let lastMonthReference = calendar.date(byAdding: .day, value: -1, to: currentMonthStart) ?? today
            let monthInterval = calendar.dateInterval(of: .month, for: lastMonthReference)
            let start = monthInterval?.start ?? lastMonthReference
            let end = calendar.date(byAdding: .day, value: -1, to: monthInterval?.end ?? currentMonthStart) ?? lastMonthReference
            return PTDateWindow(startDate: start, endDate: end)
        case .yearToDate:
            let start = calendar.date(from: calendar.dateComponents([.year], from: today)) ?? today
            let end = max(start, yesterday)
            return PTDateWindow(startDate: start, endDate: end)
        }
    }
}

public struct PTDateWindow: Codable, Equatable, Sendable {
    public var startDate: Date
    public var endDate: Date

    public init(startDate: Date, endDate: Date) {
        let lower = Calendar.pacific.startOfDay(for: min(startDate, endDate))
        let upper = Calendar.pacific.startOfDay(for: max(startDate, endDate))
        self.startDate = lower
        self.endDate = upper
    }

    public var startDatePT: String { startDate.ptDateString }
    public var endDatePT: String { endDate.ptDateString }
}

public func resolvePTDateWindow(
    datePT: String? = nil,
    startDatePT: String? = nil,
    endDatePT: String? = nil,
    rangePreset: String? = nil,
    defaultPreset: PTDateRangePreset? = nil,
    reference: Date = Date()
) throws -> PTDateWindow? {
    let hasDate = datePT?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    let hasRange = rangePreset?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    let hasFromTo = startDatePT?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        || endDatePT?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    let selectedModes = [hasDate, hasRange, hasFromTo].filter { $0 }.count
    if selectedModes > 1 {
        throw PTDateWindowError.conflictingSelectors
    }

    if let datePT, datePT.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
        guard let day = PTDate(datePT).date else { throw PTDateWindowError.invalidDate(datePT) }
        return PTDateWindow(startDate: day, endDate: day)
    }

    if hasFromTo {
        let rawStart = startDatePT ?? endDatePT ?? ""
        let rawEnd = endDatePT ?? startDatePT ?? ""
        guard let start = PTDate(rawStart).date else { throw PTDateWindowError.invalidDate(rawStart) }
        guard let end = PTDate(rawEnd).date else { throw PTDateWindowError.invalidDate(rawEnd) }
        return PTDateWindow(startDate: start, endDate: end)
    }

    if let rangePreset, rangePreset.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
        guard let preset = PTDateRangePreset(userInput: rangePreset) else {
            throw PTDateWindowError.invalidPreset(rangePreset)
        }
        return preset.resolve(reference: reference)
    }

    if let defaultPreset {
        return defaultPreset.resolve(reference: reference)
    }
    return nil
}

public func calendarYearWindow(year: Int) -> PTDateWindow {
    let calendar = Calendar.pacific
    let start = DateFormatter.ptDateFormatter.date(from: String(format: "%04d-01-01", year)) ?? Date()
    let end = DateFormatter.ptDateFormatter.date(from: String(format: "%04d-12-31", year)) ?? start
    return PTDateWindow(startDate: calendar.startOfDay(for: start), endDate: calendar.startOfDay(for: end))
}

public func fiscalYearMonths(_ fiscalYear: Int) -> [String] {
    (1...12).map { month in
        String(format: "%04d-%02d", fiscalYear, month)
    }
}

public func fullFiscalMonthsContained(in window: PTDateWindow) -> [String] {
    var result: [String] = []
    let calendar = Calendar.pacific
    var cursor = calendar.date(from: calendar.dateComponents([.year, .month], from: window.startDate)) ?? window.startDate
    while cursor <= window.endDate {
        guard let monthInterval = calendar.dateInterval(of: .month, for: cursor) else { break }
        let monthStart = calendar.startOfDay(for: monthInterval.start)
        let monthEnd = calendar.startOfDay(for: calendar.date(byAdding: .day, value: -1, to: monthInterval.end) ?? monthInterval.end)
        if window.startDate <= monthStart, window.endDate >= monthEnd {
            result.append(monthStart.fiscalMonthString)
        }
        guard let next = calendar.date(byAdding: .month, value: 1, to: monthStart) else { break }
        cursor = next
    }
    return result
}

public func fiscalMonthsOverlapping(window: PTDateWindow) -> [String] {
    var result: [String] = []
    let calendar = Calendar.pacific
    var cursor = calendar.date(from: calendar.dateComponents([.year, .month], from: window.startDate)) ?? window.startDate
    while cursor <= window.endDate {
        let monthStart = calendar.startOfDay(for: cursor)
        result.append(monthStart.fiscalMonthString)
        guard let next = calendar.date(byAdding: .month, value: 1, to: monthStart) else { break }
        cursor = next
    }
    return Array(Set(result)).sorted()
}

public func ptDates(in window: PTDateWindow, excludingFullMonths: Bool = false) -> [Date] {
    let calendar = Calendar.pacific
    let excludedMonths = excludingFullMonths ? Set(fullFiscalMonthsContained(in: window)) : []
    var dates: [Date] = []
    var cursor = window.startDate
    while cursor <= window.endDate {
        if excludedMonths.contains(cursor.fiscalMonthString) == false {
            dates.append(cursor)
        }
        guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
        cursor = next
    }
    return dates
}
