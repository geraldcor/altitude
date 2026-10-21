import CoreLocation
import SwiftUI

struct ContentView: View {
    var service: AltitudeService
    var liveActivity: LiveActivityController

    @AppStorage(SharedStore.unitKey, store: SharedStore.defaults)
    private var unitRaw = AltitudeUnit.feet.rawValue

    private var unit: AltitudeUnit { AltitudeUnit(rawValue: unitRaw) ?? .feet }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    headline
                    sensors
                    controls
                }
                .padding()
            }
            .navigationTitle("Altitude")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Picker("Unit", selection: $unitRaw) {
                        ForEach(AltitudeUnit.allCases) { unit in
                            Text(unit.symbol).tag(unit.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 110)
                }
            }
        }
        .onAppear(perform: wire)
        .onChange(of: unitRaw) {
            if let reading = service.reading {
                liveActivity.update(reading: reading, unit: unit, force: true)
            }
            WidgetRefresher.reloadNow()
        }
        .onChange(of: service.isTracking) {
            UIApplication.shared.isIdleTimerDisabled = service.isTracking
        }
    }

    // MARK: - Sections

    private var headline: some View {
        VStack(spacing: 8) {
            if let reading = service.reading {
                Text(AltitudeFormat.altitude(reading.altitudeMeters, in: unit))
                    .font(.system(size: 88, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .contentTransition(.numericText())
                Text(unit.symbol)
                    .font(.title2)
                    .foregroundStyle(.secondary)
                HStack(spacing: 16) {
                    HStack(spacing: 6) {
                        Image(systemName: AltitudeFormat.trendSymbol(reading.climbRateMetersPerMinute))
                        Text("\(AltitudeFormat.climb(reading.climbRateMetersPerMinute, in: unit)) \(unit.climbSymbol)")
                            .monospacedDigit()
                    }
                    CompassLabel(courseDegrees: reading.courseDegrees)
                }
                .font(.title3)
                .foregroundStyle(.secondary)
                Text("\(reading.source.label) · \(AltitudeFormat.accuracy(reading.verticalAccuracyMeters, in: unit))")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                if let place = reading.placeName {
                    Label(place, systemImage: "mappin.and.ellipse")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                }
                if let weather = reading.weather {
                    HStack(spacing: 6) {
                        Text(AltitudeFormat.temperature(weather.temperatureCelsius, in: unit))
                            .monospacedDigit()
                        Text(weather.conditionText)
                    }
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    if !weather.hourly.isEmpty {
                        WeatherHourlyColumns(hours: weather.hourly, unit: unit,
                                             hourFont: .caption.weight(.medium))
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Text("—")
                    .font(.system(size: 88, weight: .bold, design: .rounded))
                    .foregroundStyle(.tertiary)
                Text(service.statusMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private var sensors: some View {
        GroupBox("Sensors") {
            VStack(alignment: .leading, spacing: 10) {
                row("GPS altitude", gpsText)
                row("Barometer", barometerText)
                row("Status", service.statusMessage)
                row("Location permission", authorizationText)
                row("Live Activity", liveActivity.isActive ? "Running" : (liveActivity.areActivitiesEnabled ? "Off" : "Disabled in Settings"))
                if let position = positionText {
                    row("Position", position)
                }
                if let weather = service.weather {
                    row("Weather fetched", weather.fetchedAt.formatted(date: .omitted, time: .shortened))
                }
                if let error = service.weatherError {
                    Text(error).font(.footnote).foregroundStyle(.orange)
                }
                if let error = liveActivity.lastError {
                    Text(error).font(.footnote).foregroundStyle(.red)
                }
            }
            .font(.callout)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var controls: some View {
        VStack(spacing: 12) {
            Button {
                if service.isTracking { stop() } else { start() }
            } label: {
                Label(service.isTracking ? "Stop tracking" : "Start tracking",
                      systemImage: service.isTracking ? "stop.fill" : "location.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(service.isTracking ? .red : .accentColor)

            Text("Tracking keeps running in the background and feeds the Live Activity shown on the CarPlay Dashboard. The widget shows the last known altitude.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Link("Weather data by  Weather", destination: URL(string: "https://weatherkit.apple.com/legal-attribution.html")!)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Actions

    private func wire() {
        service.onReading = { reading in
            liveActivity.update(reading: reading, unit: SharedStore.unit)
            WidgetRefresher.reloadIfDue()
        }
        // A crash or force-quit leaves the shared flag set; the widget would keep
        // ticking as if tracking. Reconcile it with reality on every launch.
        if SharedStore.isTracking != service.isTracking {
            SharedStore.isTracking = service.isTracking
            WidgetRefresher.reloadNow()
        }
    }

    private func start() {
        service.start()
        liveActivity.start(reading: service.reading ?? .placeholder, unit: unit)
        WidgetRefresher.reloadNow()
    }

    private func stop() {
        service.stop()
        liveActivity.end(finalReading: service.reading, unit: unit)
        WidgetRefresher.reloadNow()
    }

    // MARK: - Helpers

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).monospacedDigit().multilineTextAlignment(.trailing)
        }
    }

    private var gpsText: String {
        guard let altitude = service.gpsAltitudeMeters else { return "—" }
        let accuracy = service.gpsVerticalAccuracyMeters ?? 0
        return "\(AltitudeFormat.altitude(altitude, in: unit)) \(unit.symbol) \(AltitudeFormat.accuracy(accuracy, in: unit))"
    }

    private var barometerText: String {
        guard service.barometerAvailable else { return "Not available on this device" }
        guard let altitude = service.barometerAltitudeMeters else { return "—" }
        let accuracy = service.barometerAccuracyMeters ?? 0
        return "\(AltitudeFormat.altitude(altitude, in: unit)) \(unit.symbol) \(AltitudeFormat.accuracy(accuracy, in: unit))"
    }

    private var authorizationText: String {
        switch service.authorizationStatus {
        case .notDetermined: return "Not asked yet"
        case .restricted: return "Restricted"
        case .denied: return "Denied"
        case .authorizedAlways: return "Always"
        case .authorizedWhenInUse: return "While using"
        @unknown default: return "Unknown"
        }
    }

    private var positionText: String? {
        guard let reading = service.reading, let lat = reading.latitude, let lon = reading.longitude else { return nil }
        var text = String(format: "%.4f, %.4f", lat, lon)
        if let speed = reading.speedMetersPerSecond {
            let mph = speed * 2.236_936
            text += String(format: " · %.0f mph", mph)
        }
        return text
    }
}

#Preview {
    ContentView(service: AltitudeService(), liveActivity: LiveActivityController())
}
