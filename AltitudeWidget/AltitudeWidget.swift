import SwiftUI
import WidgetKit

/// Home Screen / Lock Screen / StandBy / CarPlay widget showing the last known altitude.
/// CarPlay shows the `systemSmall` family with the background removed, so that
/// family is required and the container background is left removable (the default).
struct AltitudeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: SharedStore.widgetKind, provider: AltitudeProvider()) { entry in
            AltitudeWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    Color(.systemBackground)
                }
        }
        .configurationDisplayName("Altitude")
        .description("Last known altitude from the Altitude app.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct AltitudeEntry: TimelineEntry {
    let date: Date
    let reading: AltitudeReading?
    let unit: AltitudeUnit
    var isTracking: Bool = true
}

struct AltitudeProvider: TimelineProvider {
    func placeholder(in context: Context) -> AltitudeEntry {
        AltitudeEntry(date: .now, reading: .sample, unit: .feet)
    }

    func getSnapshot(in context: Context, completion: @escaping (AltitudeEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : current())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<AltitudeEntry>) -> Void) {
        let entry = current()
        completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(30 * 60))))
    }

    private func current() -> AltitudeEntry {
        AltitudeEntry(date: .now, reading: SharedStore.lastReading(), unit: SharedStore.unit,
                      isTracking: SharedStore.isTracking)
    }
}

struct AltitudeWidgetView: View {
    @Environment(\.widgetFamily) private var family
    /// CarPlay (and StandBy) strip the container background. That is the only
    /// signal WidgetKit gives for "this is rendering in the car", so the layout
    /// keys off it: the car gets the hourly outlook, the phone keeps it simpler.
    @Environment(\.showsWidgetContainerBackground) private var showsBackground
    let entry: AltitudeEntry

    private var isCarPlay: Bool { !showsBackground }

    private var unit: AltitudeUnit { entry.unit }

    var body: some View {
        switch family {
        case .accessoryInline:
            inline
        case .accessoryCircular:
            circular
        case .accessoryRectangular:
            rectangular
        case .systemMedium:
            medium
        default:
            small
        }
    }

    // MARK: Families

    private var small: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Label("Altitude", systemImage: "mountain.2.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                if let reading = entry.reading, reading.hasFix {
                    // Top right and small so the body rows get the room.
                    updatedLabel(reading)
                        .font(.system(size: 7, weight: .medium))
                }
            }
            Spacer(minLength: 0)
            if let reading = entry.reading, reading.hasFix {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(AltitudeFormat.altitude(reading.altitudeMeters, in: unit))
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                    Text(unit.symbol)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                // CarPlay renders the widget on a dark, busy background; secondary and
                // tertiary colours wash out there, so body text stays in the main colour.
                if let place = reading.placeName {
                    Text(place)
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                }
                if let weather = reading.weather {
                    HStack(spacing: 4) {
                        Image(systemName: weather.symbolName)
                            .symbolRenderingMode(.multicolor)
                        Text(AltitudeFormat.temperature(weather.temperatureCelsius, in: unit))
                            .monospacedDigit()
                        Text(weather.conditionText).lineLimit(1)
                    }
                    // The phone widget is read up close: conditions only, a size up.
                    // The car gets the hourly outlook underneath as columns.
                    .font(isCarPlay ? .caption.weight(.medium) : .footnote.weight(.medium))
                    if isCarPlay, !weather.hourly.isEmpty {
                        WeatherHourlyColumns(hours: Array(weather.hourly.prefix(3)), unit: unit)
                            .font(.caption2.weight(.medium))
                    }
                }
                Spacer(minLength: 0)
            } else {
                Text("—")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundStyle(.tertiary)
                Text("Open Altitude to start")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var medium: some View {
        HStack(alignment: .center, spacing: 16) {
            small
            if let reading = entry.reading, reading.hasFix {
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    CompassLabel(courseDegrees: reading.courseDegrees)
                        .font(.headline)
                    Label {
                        Text("\(AltitudeFormat.climb(reading.climbRateMetersPerMinute, in: unit)) \(unit.climbSymbol)")
                    } icon: {
                        Image(systemName: AltitudeFormat.trendSymbol(reading.climbRateMetersPerMinute))
                    }
                    .font(.headline)
                    .monospacedDigit()
                    Text(reading.source.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(AltitudeFormat.accuracy(reading.verticalAccuracyMeters, in: unit))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private var inline: some View {
        if let reading = entry.reading, reading.hasFix {
            Text("▲ \(AltitudeFormat.altitude(reading.altitudeMeters, in: unit)) \(unit.symbol)")
        } else {
            Text("▲ —")
        }
    }

    private var circular: some View {
        VStack(spacing: 0) {
            Image(systemName: "mountain.2.fill").font(.caption2)
            if let reading = entry.reading, reading.hasFix {
                Text(AltitudeFormat.altitude(reading.altitudeMeters, in: unit))
                    .font(.system(.body, design: .rounded).weight(.bold))
                    .monospacedDigit()
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                Text(unit.symbol).font(.system(size: 9))
            } else {
                Text("—").font(.body.weight(.bold))
            }
        }
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label("Altitude", systemImage: "mountain.2.fill").font(.caption.weight(.semibold))
            if let reading = entry.reading, reading.hasFix {
                Text("\(AltitudeFormat.altitude(reading.altitudeMeters, in: unit)) \(unit.symbol)")
                    .font(.title3.weight(.bold))
                    .monospacedDigit()
                updatedLabel(reading).font(.caption2)
            } else {
                Text("No reading yet").font(.caption)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Helpers

    /// While tracking: "3:29 ago", ticking on its own (the system renders timer text
    /// without a reload). Stopped: a fixed "Stopped 3:42 PM" so the widget sits still.
    @ViewBuilder
    private func updatedLabel(_ reading: AltitudeReading) -> some View {
        if entry.isTracking {
            HStack(spacing: 3) {
                Text(reading.timestamp, style: .timer)
                    .monospacedDigit()
                Text("ago")
            }
        } else {
            let sameDay = Calendar.current.isDate(reading.timestamp, inSameDayAs: entry.date)
            HStack(spacing: 3) {
                Text("Stopped")
                if sameDay {
                    Text(reading.timestamp, format: .dateTime.hour().minute())
                } else {
                    Text(reading.timestamp, format: .dateTime.month(.abbreviated).day().hour().minute())
                }
            }
            .monospacedDigit()
        }
    }
}

/// Hourly outlook as columns: conditions on top, hour label underneath.
private struct WeatherHourlyColumns: View {
    let hours: [WeatherSnapshot.Hour]
    let unit: AltitudeUnit

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ForEach(Array(hours.enumerated()), id: \.offset) { _, hour in
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 3) {
                        Image(systemName: hour.symbolName)
                            .symbolRenderingMode(.multicolor)
                        Text(AltitudeFormat.temperature(hour.temperatureCelsius, in: unit))
                            .monospacedDigit()
                    }
                    Text(AltitudeFormat.hourLabel(hour.date))
                }
            }
        }
        .lineLimit(1)
    }
}

#Preview("Small", as: .systemSmall) {
    AltitudeWidget()
} timeline: {
    AltitudeEntry(date: .now, reading: .sample, unit: .feet)
    AltitudeEntry(date: .now, reading: .sample, unit: .feet, isTracking: false)
    AltitudeEntry(date: .now, reading: nil, unit: .feet)
}

#Preview("Medium", as: .systemMedium) {
    AltitudeWidget()
} timeline: {
    AltitudeEntry(date: .now, reading: .sample, unit: .meters)
}
