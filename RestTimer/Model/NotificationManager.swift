import Foundation
import UserNotifications

// Вибрация при опущенной руке: апп в этот момент заморожен системой,
// поэтому вибрируем запланированными локальными уведомлениями.
final class NotificationManager {
    static let shared = NotificationManager()

    private let center = UNUserNotificationCenter.current()

    private init() {}

    func requestAuthorization() {
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    // Разрешение могли не дать или отозвать — тогда вибрации при опущенной
    // руке не будет вовсе; SetupView показывает предупреждение
    func authorizationDenied() async -> Bool {
        let settings = await center.notificationSettings()
        return settings.authorizationStatus == .denied
    }

    // Предупреждение за 10 сек + серия из трёх в конце отдыха
    func scheduleRestEnd(at end: Date) {
        cancelAll()
        let untilEnd = end.timeIntervalSinceNow

        schedule(
            id: "rest-warning",
            title: "10 секунд",
            body: "Готовься к подходу",
            fireIn: untilEnd - 10
        )
        for (index, offset) in [0.0, 2.5, 5.0].enumerated() {
            schedule(
                id: "rest-end-\(index + 1)",
                title: "Отдых закончен",
                body: "Погнали 💪",
                fireIn: untilEnd + offset
            )
        }
    }

    // Апп не шлёт никаких других уведомлений, поэтому сносим всё своё
    // целиком — без ручного списка идентификаторов
    func cancelAll() {
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
    }

    private func schedule(id: String, title: String, body: String, fireIn interval: TimeInterval) {
        guard interval > 1 else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }
}
