import Foundation
import Observation
import WatchKit

@Observable
final class WorkoutModel {
    enum Phase: Equatable {
        case working
        case resting(start: Date, end: Date)
        case finished
    }

    let totalSets: Int
    let restDuration: TimeInterval
    private(set) var currentSet = 1
    private(set) var phase: Phase = .working

    // Предупреждение за 10 сек играем один раз за отдых
    private var warningPlayed = false

    init(totalSets: Int, restDuration: TimeInterval) {
        self.totalSets = totalSets
        self.restDuration = restDuration
    }

    // Тап на экране «работаем»: подход закончен
    func finishSet() {
        guard phase == .working else { return }
        if currentSet >= totalSets {
            phase = .finished
            NotificationManager.shared.cancelAll()
            playFinishHaptics()
        } else {
            let start = Date()
            let end = start.addingTimeInterval(restDuration)
            phase = .resting(start: start, end: end)
            warningPlayed = false
            NotificationManager.shared.scheduleRestEnd(at: end)
        }
    }

    // Тап на экране отдыха: скип
    func skipRest() {
        guard case .resting = phase else { return }
        NotificationManager.shared.cancelAll()
        startNextSet()
    }

    func abort() {
        NotificationManager.shared.cancelAll()
    }

    // Тик от UI-таймера. Работает только пока апп активен;
    // после сна догоняет состояние по endDate.
    func tick(now: Date = Date()) {
        guard case .resting(_, let end) = phase else { return }
        let remaining = end.timeIntervalSince(now)

        if remaining <= 10, remaining > 0.5, !warningPlayed {
            warningPlayed = true
            WKInterfaceDevice.current().play(.notification)
        }

        if remaining <= 0 {
            // Если ноль пересекли только что — апп был активен, уведомления
            // не показывались (delegate их гасит), вибрируем сами.
            // Если проснулись сильно позже — уже отвибрировали уведомления, молчим.
            let justCrossedZero = remaining > -1.5
            NotificationManager.shared.cancelAll()
            startNextSet()
            if justCrossedZero {
                playRestEndHaptics()
            }
        }
    }

    private func startNextSet() {
        currentSet += 1
        phase = .working
    }

    // Три сильных вибрации с интервалом ~2 сек
    private func playRestEndHaptics() {
        Task { @MainActor in
            for i in 0..<3 {
                WKInterfaceDevice.current().play(.notification)
                if i < 2 {
                    try? await Task.sleep(for: .seconds(2))
                }
            }
        }
    }

    private func playFinishHaptics() {
        Task { @MainActor in
            WKInterfaceDevice.current().play(.success)
            try? await Task.sleep(for: .seconds(1))
            WKInterfaceDevice.current().play(.success)
        }
    }
}
