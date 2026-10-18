import ActivityKit
import Foundation

/// Live Activity payload. Static attributes are fixed for the activity's life;
/// `ContentState` is what each update carries (must stay under 4 KB).
struct AltitudeAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var reading: AltitudeReading
        var unit: AltitudeUnit
    }

    var startedAt: Date
}
