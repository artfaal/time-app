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
    private var hapticsTask: Task<Void, Never>?

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
            playHaptics(.success, count: 2, gap: .seconds(1))
        } else {
            WKInterfaceDevice.current().play(.click)
            let start = Date()
            let end = start.addingTimeInterval(restDuration)
            phase = .resting(start: start, end: end)
            warningPlayed = false
            cancelHaptics()
            NotificationManager.shared.scheduleRestEnd(at: end)
        }
    }

    // Свайп на экране работы: скорректировать номер текущего подхода
    // (часть подходов могла быть сделана вне аппа)
    func adjustCurrentSet(by delta: Int) {
        guard phase == .working else { return }
        let newValue = min(totalSets, max(1, currentSet + delta))
        guard newValue != currentSet else { return }
        currentSet = newValue
        WKInterfaceDevice.current().play(.click)
    }

    // Колесо во время отдыха: подкрутить время текущего отдыха (±15 сек)
    func adjustRest(by delta: TimeInterval) {
        guard case .resting(let start, let end) = phase else { return }
        let newEnd = max(Date().addingTimeInterval(5), end.addingTimeInterval(delta))
        phase = .resting(start: start, end: newEnd)
        // Предупреждение перевзводится, если до конца снова больше 10 сек
        warningPlayed = newEnd.timeIntervalSinceNow <= 10
        NotificationManager.shared.scheduleRestEnd(at: newEnd)
        WKInterfaceDevice.current().play(.click)
    }

    // Тап на экране отдыха: скип
    func skipRest() {
        guard case .resting = phase else { return }
        WKInterfaceDevice.current().play(.click)
        NotificationManager.shared.cancelAll()
        cancelHaptics()
        startNextSet()
    }

    func abort() {
        NotificationManager.shared.cancelAll()
        cancelHaptics()
    }

    // Дедлайн из SessionView: срабатывает только пока апп активен,
    // в моменты end-10 и end. Вибрируем сами — delegate в активном
    // состоянии глушит дубли-уведомления.
    func restDeadlineTick(now: Date = Date()) {
        guard case .resting(_, let end) = phase else { return }
        let remaining = end.timeIntervalSince(now)
        if remaining <= 0 {
            // Дедлайн мог «доспать» после разморозки раньше, чем придёт
            // catchUp: если ноль прошёл давно, уведомления уже отвибрировали
            finishRest(playHaptics: remaining > -1.0)
        } else if remaining <= 10, !warningPlayed {
            warningPlayed = true
            // Паттерн предупреждения отличается от финального —
            // различимо не глядя и не считая
            WKInterfaceDevice.current().play(.directionUp)
        }
    }

    // Возврат сцены в .active: пока апп спал, границы могли пройти без него —
    // системные уведомления уже отвибрировали, догоняем состояние молча
    func catchUp(now: Date = Date()) {
        guard case .resting(_, let end) = phase else { return }
        let remaining = end.timeIntervalSince(now)
        if remaining <= 0 {
            finishRest(playHaptics: false)
        } else if remaining <= 10 {
            warningPlayed = true
        }
    }

    private func finishRest(playHaptics shouldPlay: Bool) {
        NotificationManager.shared.cancelAll()
        startNextSet()
        if shouldPlay {
            playHaptics(.notification, count: 3, gap: .seconds(2))
        }
    }

    private func startNextSet() {
        currentSet += 1
        phase = .working
    }

    // Серия вибраций отменяемой задачей: скип, новый подход или выход
    // обрывают недоигранные buzzes
    private func playHaptics(_ type: WKHapticType, count: Int, gap: Duration) {
        hapticsTask?.cancel()
        hapticsTask = Task { @MainActor in
            for index in 0..<count {
                guard !Task.isCancelled else { return }
                WKInterfaceDevice.current().play(type)
                if index < count - 1 {
                    do { try await Task.sleep(for: gap) } catch { return }
                }
            }
        }
    }

    private func cancelHaptics() {
        hapticsTask?.cancel()
        hapticsTask = nil
    }
}
