import Foundation
import WidgetKit

/// WidgetKit budgets reloads (roughly 40–70 per day), so the home-screen /
/// CarPlay widget only refreshes every 5 minutes while tracking, plus once on stop.
/// That covers about a 4–6 hour drive before the system starts deferring reloads.
@MainActor
enum WidgetRefresher {
    private static var lastReload = Date.distantPast
    private static let interval: TimeInterval = 5 * 60

    static func reloadIfDue() {
        guard Date().timeIntervalSince(lastReload) >= interval else { return }
        reloadNow()
    }

    static func reloadNow() {
        lastReload = .now
        WidgetCenter.shared.reloadTimelines(ofKind: SharedStore.widgetKind)
    }
}
