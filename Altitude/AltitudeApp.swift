import SwiftUI

@main
struct AltitudeApp: App {
    @State private var service = AltitudeService()
    @State private var liveActivity = LiveActivityController()

    var body: some Scene {
        WindowGroup {
            ContentView(service: service, liveActivity: liveActivity)
        }
    }
}
