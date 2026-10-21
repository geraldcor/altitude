import SwiftUI

/// Hourly outlook as columns: conditions on top, hour label underneath.
struct WeatherHourlyColumns: View {
    let hours: [WeatherSnapshot.Hour]
    let unit: AltitudeUnit
    /// The hour label sits a step below the conditions; callers pick the step.
    var hourFont: Font = .system(size: 8, weight: .medium)
    /// Where the hour label sits under its conditions. CarPlay reads better
    /// left-justified; the Lock Screen centres it.
    var alignment: HorizontalAlignment = .leading

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ForEach(Array(hours.enumerated()), id: \.offset) { _, hour in
                VStack(alignment: alignment, spacing: 1) {
                    HStack(spacing: 3) {
                        Text(AltitudeFormat.temperature(hour.temperatureCelsius, in: unit))
                            .monospacedDigit()
                        Image(systemName: hour.symbolName)
                            .symbolRenderingMode(.multicolor)
                    }
                    Text(AltitudeFormat.hourLabel(hour.date))
                        .font(hourFont)
                }
            }
        }
        .lineLimit(1)
    }
}
