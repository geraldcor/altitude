import SwiftUI

/// "3pm 51° · 4pm 49° · 5pm 47°"
struct WeatherHourlyRow: View {
    let hours: [WeatherSnapshot.Hour]
    let unit: AltitudeUnit

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(hours.enumerated()), id: \.offset) { index, hour in
                if index > 0 { Text("·") }
                Text(AltitudeFormat.hourLabel(hour.date))
                Image(systemName: hour.symbolName)
                Text(AltitudeFormat.temperature(hour.temperatureCelsius, in: unit))
                    .monospacedDigit()
            }
        }
        .lineLimit(1)
    }
}
