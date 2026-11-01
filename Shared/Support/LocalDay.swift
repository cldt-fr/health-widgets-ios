import Foundation

/// Calendar days as `YYYY-MM-DD` strings in the user's current time zone. That's how
/// the server (and Garmin) key daily data.
nonisolated enum LocalDay {
    static func string(from date: Date = .now, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    static func date(from string: String, calendar: Calendar = .current) -> Date? {
        let parts = string.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    static func isToday(_ string: String) -> Bool {
        string == self.string()
    }
}
