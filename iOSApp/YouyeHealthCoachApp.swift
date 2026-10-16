import SwiftUI
import YouyeHealthCoach

@main
struct YouyeHealthCoachApp: App {
    var body: some Scene {
        WindowGroup {
            CoachAppShell()
                .tint(Color("AccentColor"))
        }
    }
}
