import Foundation

/// Locale-aware formatting helpers shared by cards and widgets.
nonisolated enum Fmt {
    static func integer(_ value: Double?) -> String {
        guard let value else { return "–" }
        return Int(value.rounded()).formatted()
    }

    static func integer(_ value: Int?) -> String {
        guard let value else { return "–" }
        return value.formatted()
    }

    static func decimal(_ value: Double?, digits: Int = 1) -> String {
        guard let value else { return "–" }
        return value.formatted(.number.precision(.fractionLength(digits)))
    }

    /// 7 h 42 → "7h42", 42 min → "42 min".
    static func duration(seconds: Int?) -> String {
        guard let seconds, seconds > 0 else { return "–" }
        let minutes = Int((Double(seconds) / 60).rounded())
        let (h, m) = (minutes / 60, minutes % 60)
        if h == 0 { return "\(m) min" }
        return m == 0 ? "\(h) h" : "\(h)h\(String(format: "%02d", m))"
    }

    static func duration(seconds: Double?) -> String {
        duration(seconds: seconds.map { Int($0.rounded()) })
    }

    /// Race / activity times: "21:34", "1:39:05".
    static func clock(seconds: Double?) -> String {
        guard let seconds, seconds > 0 else { return "–" }
        let total = Int(seconds.rounded())
        let (h, m, s) = (total / 3600, (total % 3600) / 60, total % 60)
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    static func distance(meters: Double?, imperial: Bool) -> String {
        guard let meters, meters > 0 else { return "–" }
        let measurement = Measurement(value: meters, unit: UnitLength.meters)
            .converted(to: imperial ? .miles : .kilometers)
        return measurement.formatted(
            .measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(measurement.value < 10 ? 2 : 1)))
        )
    }

    /// Pace from a speed in m/s: "4:52 /km" (or "/mi").
    static func pace(metersPerSecond speed: Double?, imperial: Bool) -> String {
        guard let speed, speed > 0.3 else { return "–" }
        let seconds = (imperial ? 1609.344 : 1000) / speed
        return clock(seconds: seconds) + (imperial ? " /mi" : " /km")
    }

    static func speed(metersPerSecond speed: Double?, imperial: Bool) -> String {
        guard let speed, speed > 0 else { return "–" }
        let measurement = Measurement(value: speed, unit: UnitSpeed.metersPerSecond)
            .converted(to: imperial ? .milesPerHour : .kilometersPerHour)
        return measurement.formatted(.measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(1))))
    }

    static func time(_ date: Date?) -> String {
        guard let date else { return "–" }
        return date.formatted(date: .omitted, time: .shortened)
    }

    static func weekday(_ day: String) -> String {
        guard let date = LocalDay.date(from: day) else { return "" }
        return date.formatted(.dateTime.weekday(.narrow))
    }
}
