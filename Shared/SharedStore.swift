import Foundation

/// App Group storage shared between the app and the widget extension.
/// The widget reads the last reading from here; the app writes it.
enum SharedStore {
    static let appGroupID = "group.com.gregcorey.altitude"
    static let widgetKind = "AltitudeWidget"
    static let unitKey = "unit"
    private static let readingKey = "lastReading"

    static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }

    static func save(_ reading: AltitudeReading) {
        guard let data = try? JSONEncoder().encode(reading) else { return }
        defaults.set(data, forKey: readingKey)
    }

    static func lastReading() -> AltitudeReading? {
        guard let data = defaults.data(forKey: readingKey) else { return nil }
        return try? JSONDecoder().decode(AltitudeReading.self, from: data)
    }

    static var unit: AltitudeUnit {
        get { defaults.string(forKey: unitKey).flatMap(AltitudeUnit.init(rawValue:)) ?? .feet }
        set { defaults.set(newValue.rawValue, forKey: unitKey) }
    }
}
