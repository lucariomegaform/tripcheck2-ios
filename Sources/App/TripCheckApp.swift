import SwiftUI
import UserNotifications

@main
struct TripCheckApp: App {
    @StateObject private var model = AppModel()

    init() {
        // Shortcut result banners show even while TripCheck is on screen.
        UNUserNotificationCenter.current().delegate = BannerPresenter.shared
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .environmentObject(model.history)
                .preferredColorScheme(.dark)
        }
    }
}
