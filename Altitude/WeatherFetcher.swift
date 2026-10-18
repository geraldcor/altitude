import CoreLocation
import Foundation
import WeatherKit

/// Throttled WeatherKit lookups. Weather changes slowly, and WeatherKit calls
/// count against the daily allowance, so refetch only after an interval or a
/// meaningful move.
@MainActor
final class WeatherFetcher {
    private var lastLocation: CLLocation?
    private var lastFetch = Date.distantPast
    private var inFlight = false

    private let interval: TimeInterval = 15 * 60
    private let retryInterval: TimeInterval = 60
    private let distanceMeters: CLLocationDistance = 10_000
    private let hoursAhead = 3

    /// Last failure, for display on the phone.
    private(set) var lastErrorDescription: String?

    func isDue(for location: CLLocation, now: Date = .now) -> Bool {
        guard !inFlight else { return false }
        guard let previous = lastLocation else { return true }
        return now.timeIntervalSince(lastFetch) >= interval
            || location.distance(from: previous) >= distanceMeters
    }

    func fetch(for location: CLLocation) async -> WeatherSnapshot? {
        inFlight = true
        defer { inFlight = false }
        lastLocation = location
        lastFetch = .now
        do {
            let (current, hourly) = try await WeatherService.shared.weather(
                for: location, including: .current, .hourly
            )
            let now = Date()
            let upcoming = hourly.forecast
                .filter { $0.date > now }
                .prefix(hoursAhead)
                .map {
                    WeatherSnapshot.Hour(
                        date: $0.date,
                        temperatureCelsius: $0.temperature.converted(to: .celsius).value,
                        symbolName: $0.symbolName
                    )
                }
            lastErrorDescription = nil
            return WeatherSnapshot(
                temperatureCelsius: current.temperature.converted(to: .celsius).value,
                symbolName: current.symbolName,
                conditionText: current.condition.description,
                fetchedAt: now,
                hourly: Array(upcoming)
            )
        } catch {
            lastErrorDescription = String(describing: error)
            // Retry soon rather than waiting out the full interval.
            lastFetch = Date().addingTimeInterval(retryInterval - interval)
            return nil
        }
    }
}
