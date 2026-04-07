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
