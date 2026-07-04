import SwiftUI
import UserNotifications
import WatchKit

@main
struct RestTimerApp: App {
    @WKApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

final class AppDelegate: NSObject, WKApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching() {
        UNUserNotificationCenter.current().delegate = self
        NotificationManager.shared.requestAuthorization()
    }

    // Апп на экране и активен — вибрируем сами через WKInterfaceDevice,
    // баннер уведомления не показываем
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        []
    }
}

struct RootView: View {
    @State private var model: WorkoutModel?

    var body: some View {
        if let model {
            SessionView(model: model) {
                self.model = nil
            }
        } else {
            SetupView { sets, rest in
                model = WorkoutModel(totalSets: sets, restDuration: rest)
            }
        }
    }
}
