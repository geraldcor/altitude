import CoreLocation
import CoreMotion
import Foundation
import MapKit
import Observation

/// Reads GPS altitude (Core Location) and barometric absolute altitude (Core Motion),
/// fuses them, derives a climb rate, and publishes `AltitudeReading`s.
///
/// Fusion: the barometer is smooth but drifts with weather; GPS is noisy but anchored.
/// We keep a slowly-adapting offset (GPS − barometer) and report barometer + offset.
@Observable
@MainActor
final class AltitudeService {
    private(set) var reading: AltitudeReading?
    private(set) var isTracking = false
    private(set) var statusMessage = "Idle"

    private(set) var gpsAltitudeMeters: Double?
    private(set) var gpsVerticalAccuracyMeters: Double?
    private(set) var barometerAltitudeMeters: Double?
    private(set) var barometerAccuracyMeters: Double?
    private(set) var placeName: String?

    let barometerAvailable = CMAltimeter.isAbsoluteAltitudeAvailable()

    /// Called on the main actor for every published reading.
    var onReading: ((AltitudeReading) -> Void)?

    private let authorizationManager = CLLocationManager()
    private let altimeter = CMAltimeter()
    private var backgroundSession: CLBackgroundActivitySession?
    private var locationTask: Task<Void, Never>?
    private var lastLocation: CLLocation?
    private var barometerOffsetMeters: Double?
    private var history: [(time: Date, altitude: Double)] = []
    private var lastPublish = Date.distantPast
    private var lastGeocodedLocation: CLLocation?
    private var lastGeocodeTime = Date.distantPast
    private var geocodeInFlight = false

    /// Reverse geocoding is a network call; only redo it after this much time
    /// and this much movement.
    private let geocodeInterval: TimeInterval = 60
    private let geocodeDistanceMeters: CLLocationDistance = 500

    var authorizationStatus: CLAuthorizationStatus {
        authorizationManager.authorizationStatus
    }

    func start() {
        guard !isTracking else { return }
        isTracking = true
        statusMessage = "Starting"
        history.removeAll()
        barometerOffsetMeters = nil
        lastGeocodedLocation = nil
        geocodeInFlight = false

        authorizationManager.requestWhenInUseAuthorization()

        // Keeps location updates flowing after the app leaves the foreground
        // (together with the `location` background mode in Info.plist).
        backgroundSession = CLBackgroundActivitySession()

        locationTask = Task { [weak self] in
            do {
                for try await update in CLLocationUpdate.liveUpdates(.automotiveNavigation) {
                    guard let self, self.isTracking else { break }
                    self.handle(update)
                }
            } catch {
                self?.statusMessage = "Location stream ended: \(error.localizedDescription)"
            }
        }

        startBarometer()
    }

    func stop() {
        guard isTracking else { return }
        isTracking = false
        locationTask?.cancel()
        locationTask = nil
        backgroundSession?.invalidate()
        backgroundSession = nil
        if barometerAvailable {
            altimeter.stopAbsoluteAltitudeUpdates()
        }
        statusMessage = "Stopped"
    }

    // MARK: - Location

    private func handle(_ update: CLLocationUpdate) {
        if update.authorizationDenied || update.authorizationDeniedGlobally {
            statusMessage = "Location access denied. Enable it in Settings."
            return
        }
        if update.authorizationRequestInProgress {
            statusMessage = "Waiting for location permission"
            return
        }
        if update.locationUnavailable {
            statusMessage = "Waiting for GPS fix"
            return
        }
        guard let location = update.location else { return }
        ingest(location)
    }

    private func ingest(_ location: CLLocation) {
        lastLocation = location
        reverseGeocodeIfDue(location)
        let altitude = location.altitude
        let accuracy = location.verticalAccuracy

        // verticalAccuracy <= 0 means the altitude is invalid.
        // Exactly 0.0 with a positive accuracy is a known bogus fix from some
        // CarPlay head units that feed the phone vehicle GPS without altitude.
        let valid = accuracy > 0 && altitude != 0
        if valid {
            gpsAltitudeMeters = altitude
            gpsVerticalAccuracyMeters = accuracy
            if let baro = barometerAltitudeMeters {
                let delta = altitude - baro
                // Trust an accurate GPS fix more (alpha up to 0.2), a poor one less (down to 0.02).
                let alpha = max(0.02, min(0.2, 10 / max(accuracy, 1)))
                if let current = barometerOffsetMeters {
                    barometerOffsetMeters = current + alpha * (delta - current)
                } else {
                    barometerOffsetMeters = delta
                }
            }
        }
        publish()
    }

    // MARK: - Place name

    private func reverseGeocodeIfDue(_ location: CLLocation) {
        guard !geocodeInFlight else { return }
        let now = Date()
        if let previous = lastGeocodedLocation,
           now.timeIntervalSince(lastGeocodeTime) < geocodeInterval,
           location.distance(from: previous) < geocodeDistanceMeters {
            return
        }
        geocodeInFlight = true
        lastGeocodedLocation = location
        lastGeocodeTime = now
        Task { [weak self] in
            let name = await Self.placeName(for: location)
            guard let self else { return }
            self.geocodeInFlight = false
            if let name, name != self.placeName {
                self.placeName = name
                self.publish(force: true)
            }
        }
    }

    /// City name only (road-trip use). Falls back to the shortest address MapKit offers.
    private static func placeName(for location: CLLocation) async -> String? {
        guard let request = MKReverseGeocodingRequest(location: location) else { return nil }
        guard let item = try? await request.mapItems.first else { return nil }
        if let city = item.addressRepresentations?.cityName, !city.isEmpty {
            return city
        }
        if let short = item.address?.shortAddress, !short.isEmpty {
            return short
        }
        return nil
    }

    // MARK: - Barometer

    private func startBarometer() {
        guard barometerAvailable else { return }
        altimeter.startAbsoluteAltitudeUpdates(to: .main) { [weak self] data, _ in
            guard let data else { return }
            let altitude = data.altitude
            let accuracy = data.accuracy
            Task { @MainActor in
                self?.ingestBarometer(altitudeMeters: altitude, accuracyMeters: accuracy)
            }
        }
    }

    private func ingestBarometer(altitudeMeters: Double, accuracyMeters: Double) {
        guard isTracking else { return }
        barometerAltitudeMeters = altitudeMeters
        barometerAccuracyMeters = accuracyMeters
        publish()
    }

    // MARK: - Fusion and publishing

    private func publish(force: Bool = false) {
        let altitude: Double
        let accuracy: Double
        let source: AltitudeSource

        if let baro = barometerAltitudeMeters, let offset = barometerOffsetMeters {
            altitude = baro + offset
            // Core Motion sometimes reports 0 for barometer accuracy; treat non-positive as unknown.
            let baroAccuracy = (barometerAccuracyMeters ?? 0) > 0 ? barometerAccuracyMeters! : .infinity
            accuracy = min(gpsVerticalAccuracyMeters ?? .infinity, baroAccuracy)
            source = .fused
        } else if let gps = gpsAltitudeMeters {
            altitude = gps
            accuracy = gpsVerticalAccuracyMeters ?? 0
            source = .gps
        } else if let baro = barometerAltitudeMeters {
            altitude = baro
            accuracy = barometerAccuracyMeters ?? 0
            source = .barometer
        } else {
            return
        }

        let now = Date()
        history.append((time: now, altitude: altitude))
        history.removeAll { now.timeIntervalSince($0.time) > 30 }

        // Publish at most once per second; the barometer alone ticks ~1 Hz.
        guard force || now.timeIntervalSince(lastPublish) >= 1 else { return }
        lastPublish = now

        var climbRate = 0.0
        if let first = history.first, let last = history.last {
            let span = last.time.timeIntervalSince(first.time)
            if span >= 5 {
                climbRate = (last.altitude - first.altitude) / span * 60
            }
        }

        var next = AltitudeReading(
            altitudeMeters: altitude,
            climbRateMetersPerMinute: climbRate,
            verticalAccuracyMeters: accuracy.isFinite ? accuracy : 0,
            source: source,
            timestamp: now
        )
        if let location = lastLocation {
            next.latitude = location.coordinate.latitude
            next.longitude = location.coordinate.longitude
            next.speedMetersPerSecond = location.speed >= 0 ? location.speed : nil
            next.courseDegrees = location.course >= 0 ? location.course : nil
        }
        next.placeName = placeName

        reading = next
        statusMessage = "Tracking"
        SharedStore.save(next)
        onReading?(next)
    }
}
