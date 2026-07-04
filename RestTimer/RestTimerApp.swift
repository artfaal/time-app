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
        // Процесс могли убить посреди отдыха — гасим уведомления мёртвой сессии
        NotificationManager.shared.cancelAll()
    }

    // Пока апп действительно активен, вибрируем сами через WKInterfaceDevice —
    // баннер уведомления глушим. Но в always-on апп frontmost и НЕ активен:
    // willPresent всё равно вызывается, и глушить тут нельзя — системная
    // вибрация уведомления в этот момент единственная.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        let isActive = await MainActor.run {
            WKApplication.shared().applicationState == .active
        }
        return isActive ? [] : [.banner, .sound]
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
