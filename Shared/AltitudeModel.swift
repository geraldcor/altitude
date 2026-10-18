import Foundation

/// Display unit for altitude and climb rate.
enum AltitudeUnit: String, Codable, CaseIterable, Identifiable {
    case feet
    case meters

    var id: String { rawValue }

    var symbol: String { self == .feet ? "ft" : "m" }
    var climbSymbol: String { self == .feet ? "ft/min" : "m/min" }

    func value(fromMeters meters: Double) -> Double {
        self == .feet ? meters * 3.280_839_895 : meters
    }
}

/// Which sensor(s) produced a reading.
enum AltitudeSource: String, Codable {
    case gps
    case barometer
    case fused
    case none

    var label: String {
        switch self {
        case .gps: return "GPS"
        case .barometer: return "Barometer"
        case .fused: return "GPS + barometer"
        case .none: return "Acquiring"
        }
    }
}

/// One altitude sample. Extra fields are optional so new data points
/// (weather, pressure, heading, ...) can be added without breaking stored readings.
struct AltitudeReading: Codable, Hashable {
    var altitudeMeters: Double
    var climbRateMetersPerMinute: Double
    var verticalAccuracyMeters: Double
    var source: AltitudeSource
    var timestamp: Date

    var latitude: Double?
    var longitude: Double?
    var speedMetersPerSecond: Double?
    var courseDegrees: Double?

    var hasFix: Bool { source != .none }

    static let placeholder = AltitudeReading(
        altitudeMeters: 0,
        climbRateMetersPerMinute: 0,
        verticalAccuracyMeters: 0,
        source: .none,
        timestamp: .now
    )

    static let sample = AltitudeReading(
        altitudeMeters: 1_712,
        climbRateMetersPerMinute: 48,
        verticalAccuracyMeters: 4,
        source: .fused,
        timestamp: .now,
        latitude: 39.74,
        longitude: -105.0,
        speedMetersPerSecond: 28,
        courseDegrees: 270
    )
}

enum AltitudeFormat {
    /// "1,712" style altitude in the chosen unit, no unit suffix.
    static func altitude(_ meters: Double, in unit: AltitudeUnit) -> String {
        let value = unit.value(fromMeters: meters)
        return value.formatted(.number.precision(.fractionLength(0)).grouping(.automatic))
    }

    /// "+48" / "-120" climb rate in the chosen unit per minute.
    static func climb(_ metersPerMinute: Double, in unit: AltitudeUnit) -> String {
        let value = unit.value(fromMeters: metersPerMinute)
        return value.formatted(
            .number.precision(.fractionLength(0)).sign(strategy: .always(includingZero: false))
        )
    }

    /// "±13 ft" accuracy string.
    static func accuracy(_ meters: Double, in unit: AltitudeUnit) -> String {
        let value = unit.value(fromMeters: meters)
        return "±" + value.formatted(.number.precision(.fractionLength(0))) + " " + unit.symbol
    }

    /// Climb trend used to pick an arrow. Threshold is ~1.5 m/min (~5 ft/min).
    enum Trend { case climbing, descending, level }

    static func trend(_ metersPerMinute: Double) -> Trend {
        if metersPerMinute > 1.5 { return .climbing }
        if metersPerMinute < -1.5 { return .descending }
        return .level
    }

    static func trendSymbol(_ metersPerMinute: Double) -> String {
        switch trend(metersPerMinute) {
        case .climbing: return "arrow.up.right"
        case .descending: return "arrow.down.right"
        case .level: return "arrow.right"
        }
    }
}
