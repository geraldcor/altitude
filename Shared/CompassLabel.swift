import SwiftUI

/// Arrow rotated to the course of travel plus its compass name, e.g. "↗ NE".
/// Course is only meaningful while moving; callers pass nil when it is not.
struct CompassLabel: View {
    let courseDegrees: Double?

    var body: some View {
        HStack(spacing: 3) {
            if let course = courseDegrees {
                Image(systemName: "location.north.fill")
                    .rotationEffect(.degrees(course))
                Text(AltitudeFormat.compassName(course))
            } else {
                Image(systemName: "location.north.fill")
                Text("—")
            }
        }
        .monospacedDigit()
    }
}
