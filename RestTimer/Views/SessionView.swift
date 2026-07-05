import SwiftUI
import WatchKit

struct SessionView: View {
    let model: WorkoutModel
    let onExit: () -> Void

    @Environment(\.scenePhase) private var scenePhase
    @State private var showExitDialog = false

    var body: some View {
        content
            // Дедлайны отдыха вместо поллинга: пока апп активен, просыпаемся
            // ровно в end-10 и end. Пока апп спит, таск не работает —
            // вибрируют уведомления, а состояние догоняет catchUp
            .task(id: model.phase) {
                guard case .resting(_, let end) = model.phase else { return }
                do {
                    let untilWarning = end.timeIntervalSinceNow - 10
                    if untilWarning > 0 {
                        try await Task.sleep(for: .seconds(untilWarning))
                        model.restDeadlineTick()
                    }
                    try await Task.sleep(for: .seconds(max(end.timeIntervalSinceNow, 0)))
                    model.restDeadlineTick()
                } catch {
                    // Фаза сменилась (скип/выход) — таск отменён, ничего не делаем
                }
            }
            .onChange(of: scenePhase) { _, newPhase in
                // После сна догоняем состояние по фактическому времени
                if newPhase == .active { model.catchUp() }
            }
            .onLongPressGesture(minimumDuration: 0.8) {
                showExitDialog = true
            }
            .confirmationDialog("Тренировка", isPresented: $showExitDialog) {
                Button("Заблокировать экран") {
                    // Water Lock: экран не реагирует на касания,
                    // разблокировка — нажать и удерживать Digital Crown
                    WKInterfaceDevice.current().enableWaterLock()
                }
                Button("Закончить", role: .destructive) { endSession() }
                Button("Продолжить", role: .cancel) {}
            }
    }

    // Единая точка выхода: гасит уведомления и недоигранные вибрации
    private func endSession() {
        model.abort()
        onExit()
    }

    @ViewBuilder
    private var content: some View {
        ZStack {
            switch model.phase {
            case .working:
                WorkingView(model: model)
                    .transition(phaseTransition)
            case .resting(let start, let end):
                RestingView(model: model, start: start, end: end)
                    .transition(phaseTransition)
            case .finished:
                FinishedView(totalSets: model.totalSets, onExit: endSession)
                    .transition(phaseTransition)
            }
        }
        .animation(.spring(duration: 0.35), value: model.phase)
    }

    private var phaseTransition: AnyTransition {
        .opacity.combined(with: .scale(scale: 0.92))
    }
}

// Мягкий градиент в цвет фазы: работа — зелёный, отдых — оранжевый.
// Фазу видно боковым зрением, не читая текст. В AOD гаснет.
private struct PhaseBackground: View {
    let color: Color
    let dimmed: Bool

    var body: some View {
        RadialGradient(
            colors: [color.opacity(dimmed ? 0 : 0.35), .black],
            center: .center,
            startRadius: 10,
            endRadius: 150
        )
        .ignoresSafeArea()
    }
}

// Прогресс тренировки: капсула на каждый подход, сделанные заполнены
private struct SetSegments: View {
    let total: Int
    let done: Int
    let tint: Color

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<total, id: \.self) { index in
                Capsule()
                    .fill(index < done ? tint : tint.opacity(0.25))
                    .frame(height: 5)
            }
        }
        .animation(.spring(duration: 0.4), value: done)
    }
}

private struct WorkingView: View {
    let model: WorkoutModel
    @Environment(\.isLuminanceReduced) private var dimmed

    var body: some View {
        // Кнопка на весь экран: тап и системный Double Tap (сжать пальцы)
        // заканчивают подход
        Button {
            model.finishSet()
        } label: {
            VStack(spacing: 0) {
                SetSegments(total: model.totalSets, done: model.currentSet - 1, tint: .green)
                    .opacity(dimmed ? 0.5 : 1)
                Spacer()
                Text("ПОДХОД \(model.currentSet)/\(model.totalSets)")
                    .font(.title2.weight(.black))
                    .foregroundStyle(.green)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.system(size: 44))
                    .foregroundStyle(dimmed ? Color.green.opacity(0.5) : .green)
                    .padding(.top, 10)
                Spacer()
                Text("начать отдых")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .opacity(dimmed ? 0 : 1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .handGestureShortcut(.primaryAction)
        .background(PhaseBackground(color: .green, dimmed: dimmed))
        // Свайп: поправить номер текущего подхода (влево — вперёд,
        // вправо — назад), если часть подходов сделана вне аппа.
        // highPriority — чтобы свайп не срабатывал заодно как тап по кнопке
        .highPriorityGesture(
            DragGesture(minimumDistance: 25)
                .onEnded { value in
                    let dx = value.translation.width
                    guard abs(dx) > abs(value.translation.height) else { return }
                    model.adjustCurrentSet(by: dx < 0 ? 1 : -1)
                }
        )
    }
}

private struct RestingView: View {
    let model: WorkoutModel
    let start: Date
    let end: Date
    @Environment(\.isLuminanceReduced) private var dimmed

    // Колесо во время отдыха: один щелчок = ±15 сек к текущему отдыху.
    // @State живёт в пределах одного отдыха (view пересоздаётся на фазу)
    @State private var crownSteps = 0.0

    var body: some View {
        // Кнопка на весь экран: тап и системный Double Tap — скип отдыха
        Button {
            model.skipRest()
        } label: {
            // ZStack: цифры строго по центру экрана, сегменты и полоса —
            // по краям, независимо друг от друга
            ZStack {
                VStack(spacing: 4) {
                    SetSegments(total: model.totalSets, done: model.currentSet, tint: .orange)
                        .opacity(dimmed ? 0.5 : 1)
                    Text("подход \(model.currentSet + 1)/\(model.totalSets)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                // Системный таймер: тикает даже в always-on, когда апп заморожен
                Text(timerInterval: start...end, countsDown: true)
                    .font(.system(size: 68, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .foregroundStyle(.orange)
                if !dimmed {
                    VStack {
                        Spacer()
                        // Полоса отдыха «сгорает» к нулю. Рисуем сами, поэтому
                        // только при активном аппе; в AOD остаются системные цифры
                        TimelineView(.periodic(from: start, by: 1)) { context in
                            RestBar(progress: progress(at: context.date))
                        }
                        .frame(height: 8)
                        Text("пропустить")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .padding(.top, 2)
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .handGestureShortcut(.primaryAction)
        .background(PhaseBackground(color: .orange, dimmed: dimmed))
        .focusable(true)
        .digitalCrownRotation(
            $crownSteps,
            from: -40,
            through: 40,
            by: 1,
            sensitivity: .medium,
            isContinuous: false,
            isHapticFeedbackEnabled: true
        )
        .onChange(of: crownSteps) { oldValue, newValue in
            let delta = Int(newValue.rounded()) - Int(oldValue.rounded())
            guard delta != 0 else { return }
            model.adjustRest(by: TimeInterval(delta * 15))
        }
    }

    private func progress(at date: Date) -> Double {
        let total = end.timeIntervalSince(start)
        guard total > 0 else { return 1 }
        return min(1, max(0, date.timeIntervalSince(start) / total))
    }
}

private struct RestBar: View {
    let progress: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.orange.opacity(0.2))
                Capsule()
                    .fill(Color.orange)
                    .frame(width: max(8, geo.size.width * (1 - progress)))
                    .animation(.linear(duration: 1), value: progress)
            }
        }
        .frame(height: 8)
    }
}

private struct FinishedView: View {
    let totalSets: Int
    let onExit: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(.green)
            Text("Готово!")
                .font(.title3.weight(.bold))
            Text(setsLabel)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button("Завершить", action: onExit)
                .handGestureShortcut(.primaryAction)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PhaseBackground(color: .green, dimmed: false))
    }

    private var setsLabel: String {
        let mod10 = totalSets % 10
        let mod100 = totalSets % 100
        let word: String
        if mod10 == 1 && mod100 != 11 {
            word = "подход"
        } else if (2...4).contains(mod10) && !(12...14).contains(mod100) {
            word = "подхода"
        } else {
            word = "подходов"
        }
        return "\(totalSets) \(word)"
    }
}
