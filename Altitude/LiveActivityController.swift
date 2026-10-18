import ActivityKit
import Foundation
import Observation

/// Owns the single altitude Live Activity. Updates are throttled so a 1 Hz
/// sensor feed does not turn into a 1 Hz Live Activity update stream.
@Observable
@MainActor
final class LiveActivityController {
    private(set) var isActive = false
    private(set) var lastError: String?

    private var activity: Activity<AltitudeAttributes>?
    private var lastUpdate = Date.distantPast
    private var lastAltitudeMeters: Double?

    /// How often the Live Activity is allowed to refresh, and how much the
    /// altitude must move to justify a refresh before the slow interval elapses.
    private let minimumInterval: TimeInterval = 2
    private let slowInterval: TimeInterval = 15
    private let minimumChangeMeters: Double = 1
    private let staleAfter: TimeInterval = 90

    var areActivitiesEnabled: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    func start(reading: AltitudeReading, unit: AltitudeUnit) {
        guard areActivitiesEnabled else {
            lastError = "Live Activities are disabled for this app in Settings."
            return
        }
        // Clear leftovers from a previous run (crash, force-quit).
        for stale in Activity<AltitudeAttributes>.activities {
            Task { await stale.end(nil, dismissalPolicy: .immediate) }
        }
        let state = AltitudeAttributes.ContentState(reading: reading, unit: unit)
        do {
            activity = try Activity.request(
                attributes: AltitudeAttributes(startedAt: .now),
                content: ActivityContent(state: state, staleDate: .now.addingTimeInterval(staleAfter)),
                pushType: nil
            )
            isActive = true
            lastError = nil
            lastUpdate = .now
            lastAltitudeMeters = reading.altitudeMeters
        } catch {
            lastError = "Could not start Live Activity: \(error.localizedDescription)"
            isActive = false
        }
    }

    func update(reading: AltitudeReading, unit: AltitudeUnit, force: Bool = false) {
        guard let activity else { return }
        let now = Date()
        let elapsed = now.timeIntervalSince(lastUpdate)
        if !force {
            guard elapsed >= minimumInterval else { return }
            let moved = abs(reading.altitudeMeters - (lastAltitudeMeters ?? -.infinity)) >= minimumChangeMeters
            guard moved || elapsed >= slowInterval else { return }
        }
        lastUpdate = now
        lastAltitudeMeters = reading.altitudeMeters
        let state = AltitudeAttributes.ContentState(reading: reading, unit: unit)
        let content = ActivityContent(state: state, staleDate: now.addingTimeInterval(staleAfter))
        Task { await activity.update(content) }
    }

    func end(finalReading: AltitudeReading?, unit: AltitudeUnit) {
        guard let activity else { return }
        let content = finalReading.map {
            ActivityContent(state: AltitudeAttributes.ContentState(reading: $0, unit: unit), staleDate: nil)
        }
        Task { await activity.end(content, dismissalPolicy: .immediate) }
        self.activity = nil
        isActive = false
    }
}
