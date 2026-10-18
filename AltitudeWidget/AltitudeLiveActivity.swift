import ActivityKit
import SwiftUI
import WidgetKit

/// Live Activity: Lock Screen, Dynamic Island, and (via the `.small` activity family)
/// the CarPlay Dashboard and Apple Watch Smart Stack. CarPlay is non-interactive.
struct AltitudeLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AltitudeAttributes.self) { context in
            AltitudeActivityView(context: context)
                .activityBackgroundTint(Color.black.opacity(0.55))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Label("Altitude", systemImage: "mountain.2.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(altitudeText(context))
                            .font(.title.weight(.bold))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Climb")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        climbLabel(context)
                            .font(.title3.weight(.semibold))
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    footer(context)
                }
            } compactLeading: {
                Image(systemName: "mountain.2.fill")
            } compactTrailing: {
                Text(compactAltitudeText(context))
                    .monospacedDigit()
                    .contentTransition(.numericText())
            } minimal: {
                Image(systemName: AltitudeFormat.trendSymbol(context.state.reading.climbRateMetersPerMinute))
            }
        }
        .supplementalActivityFamilies([.small])
    }

    // MARK: Shared pieces

    private func altitudeText(_ context: ActivityViewContext<AltitudeAttributes>) -> String {
        let state = context.state
        guard state.reading.hasFix else { return "—" }
        return "\(AltitudeFormat.altitude(state.reading.altitudeMeters, in: state.unit)) \(state.unit.symbol)"
    }

    private func compactAltitudeText(_ context: ActivityViewContext<AltitudeAttributes>) -> String {
        let state = context.state
        guard state.reading.hasFix else { return "—" }
        return AltitudeFormat.altitude(state.reading.altitudeMeters, in: state.unit)
    }

    private func climbLabel(_ context: ActivityViewContext<AltitudeAttributes>) -> some View {
        let state = context.state
        return Label {
            Text("\(AltitudeFormat.climb(state.reading.climbRateMetersPerMinute, in: state.unit)) \(state.unit.climbSymbol)")
                .monospacedDigit()
        } icon: {
            Image(systemName: AltitudeFormat.trendSymbol(state.reading.climbRateMetersPerMinute))
        }
    }

    private func footer(_ context: ActivityViewContext<AltitudeAttributes>) -> some View {
        let state = context.state
        return HStack {
            if let place = state.reading.placeName {
                Text(place).lineLimit(1)
                Text("·")
            }
            if let weather = state.reading.weather {
                Image(systemName: weather.symbolName)
                Text(AltitudeFormat.temperature(weather.temperatureCelsius, in: state.unit))
                Text("·")
            }
            Text(state.reading.source.label)
            Text("·")
            Text(AltitudeFormat.accuracy(state.reading.verticalAccuracyMeters, in: state.unit))
            if context.isStale {
                Text("·")
                Text("Stale").foregroundStyle(.orange)
            }
            Spacer()
            Text(state.reading.timestamp, style: .time)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

/// Lock Screen presentation. The `.small` activity family is what CarPlay and
/// Apple Watch show, so it gets a denser layout with the number as the hero.
struct AltitudeActivityView: View {
    @Environment(\.activityFamily) private var family
    let context: ActivityViewContext<AltitudeAttributes>

    private var reading: AltitudeReading { context.state.reading }
    private var unit: AltitudeUnit { context.state.unit }

    var body: some View {
        switch family {
        case .small:
            smallBody
        default:
            fullBody
        }
    }

    private var smallBody: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: "mountain.2.fill")
                Text(reading.placeName ?? "Altitude")
                    .lineLimit(1)
                Spacer()
                if context.isStale {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)

            if reading.hasFix {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(AltitudeFormat.altitude(reading.altitudeMeters, in: unit))
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                        .contentTransition(.numericText())
                    Text(unit.symbol)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 4) {
                    Image(systemName: AltitudeFormat.trendSymbol(reading.climbRateMetersPerMinute))
                    Text("\(AltitudeFormat.climb(reading.climbRateMetersPerMinute, in: unit)) \(unit.climbSymbol)")
                        .monospacedDigit()
                    if let weather = reading.weather {
                        Spacer(minLength: 8)
                        Image(systemName: weather.symbolName)
                            .symbolRenderingMode(.multicolor)
                        Text(AltitudeFormat.temperature(weather.temperatureCelsius, in: unit))
                            .monospacedDigit()
                        Text(weather.conditionText)
                            .lineLimit(1)
                    }
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                if let weather = reading.weather, !weather.hourly.isEmpty {
                    WeatherHourlyRow(hours: weather.hourly, unit: unit)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            } else {
                Text("Acquiring…")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // CarPlay draws the small family edge to edge; give the card some air.
        .padding(.vertical, 10)
        .padding(.horizontal, 8)
    }

    private var fullBody: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Label(reading.placeName ?? "Altitude", systemImage: "mountain.2.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if reading.hasFix {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(AltitudeFormat.altitude(reading.altitudeMeters, in: unit))
                            .font(.system(size: 48, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .minimumScaleFactor(0.5)
                            .lineLimit(1)
                            .contentTransition(.numericText())
                        Text(unit.symbol)
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("Acquiring…")
                        .font(.title.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if reading.hasFix {
                VStack(alignment: .trailing, spacing: 6) {
                    HStack(spacing: 4) {
                        Image(systemName: AltitudeFormat.trendSymbol(reading.climbRateMetersPerMinute))
                        Text("\(AltitudeFormat.climb(reading.climbRateMetersPerMinute, in: unit)) \(unit.climbSymbol)")
                            .monospacedDigit()
                    }
                    .font(.headline)
                    Text(reading.source.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(AltitudeFormat.accuracy(reading.verticalAccuracyMeters, in: unit))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if context.isStale {
                        Text("Stale")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
        .padding()
        .padding(.bottom, 18)
        .overlay(alignment: .bottomLeading) {
            if reading.hasFix, let weather = reading.weather {
                HStack(spacing: 6) {
                    Image(systemName: weather.symbolName)
                        .symbolRenderingMode(.multicolor)
                    Text(AltitudeFormat.temperature(weather.temperatureCelsius, in: unit))
                        .monospacedDigit()
                    Text(weather.conditionText)
                    if !weather.hourly.isEmpty {
                        Text("·")
                        WeatherHourlyRow(hours: weather.hourly, unit: unit)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
                .padding(.bottom, 6)
            }
        }
    }
}

#Preview("Lock Screen", as: .content, using: AltitudeAttributes(startedAt: .now)) {
    AltitudeLiveActivity()
} contentStates: {
    AltitudeAttributes.ContentState(reading: .sample, unit: .feet)
    AltitudeAttributes.ContentState(reading: .placeholder, unit: .feet)
}

#Preview("Island", as: .dynamicIsland(.expanded), using: AltitudeAttributes(startedAt: .now)) {
    AltitudeLiveActivity()
} contentStates: {
    AltitudeAttributes.ContentState(reading: .sample, unit: .feet)
}
