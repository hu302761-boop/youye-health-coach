import SwiftUI
import YouyeHealthCoach

/// Desktop companion for planning, reviewing and locally recording private coach data.
/// HealthKit and the camera stay device-specific; the shared UI never invents their data.
@main
struct YouyeHealthCoachMacApp: App {
    var body: some Scene {
        WindowGroup("私人健康教练") {
            CoachAppShell()
                .tint(Color(red: 0.043, green: 0.431, blue: 0.384))
                .frame(minWidth: 860, minHeight: 620)
        }
        .windowResizability(.contentMinSize)
    }
}
