import SwiftUI

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
            .confirmationDialog("Закончить тренировку?", isPresented: $showExitDialog) {
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
        switch model.phase {
        case .working:
            WorkingView(model: model)
        case .resting(let start, let end):
            RestingView(model: model, start: start, end: end)
        case .finished:
            FinishedView(totalSets: model.totalSets, onExit: endSession)
        }
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

private struct WorkingView: View {
    let model: WorkoutModel
    @Environment(\.isLuminanceReduced) private var dimmed

    var body: some View {
        VStack(spacing: 10) {
            Text("ПОДХОД \(model.currentSet)/\(model.totalSets)")
                .font(.title2.weight(.black))
                .foregroundStyle(.green)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Image(systemName: "figure.strengthtraining.traditional")
                .font(.system(size: 46))
                .foregroundStyle(dimmed ? Color.green.opacity(0.5) : .green)
            if !dimmed {
                Text("начать отдых")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PhaseBackground(color: .green, dimmed: dimmed))
        .contentShape(Rectangle())
        .onTapGesture { model.finishSet() }
    }
}

private struct RestingView: View {
    let model: WorkoutModel
    let start: Date
    let end: Date
    @Environment(\.isLuminanceReduced) private var dimmed

    var body: some View {
        ZStack {
            // Рамка-прогресс по периметру экрана «сгорает» к концу отдыха.
            // Рисуем сами, поэтому только при активном аппе; в AOD остаются
            // системные цифры
            if !dimmed {
                TimelineView(.periodic(from: start, by: 1)) { context in
                    RestFrame(progress: progress(at: context.date))
                }
                .ignoresSafeArea()
            }
            VStack(spacing: 0) {
                // Системный таймер: тикает даже в always-on, когда апп заморожен
                Text(timerInterval: start...end, countsDown: true)
                    .font(.system(size: 54, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                    .foregroundStyle(.orange)
                Text("подход \(model.currentSet + 1)/\(model.totalSets)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if !dimmed {
                    Text("пропустить")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PhaseBackground(color: .orange, dimmed: dimmed))
        .contentShape(Rectangle())
        .onTapGesture { model.skipRest() }
    }

    private func progress(at date: Date) -> Double {
        let total = end.timeIntervalSince(start)
        guard total > 0 else { return 1 }
        return min(1, max(0, date.timeIntervalSince(start) / total))
    }
}

// Прямоугольная рамка со скруглением в форме экрана Ultra
private struct RestFrame: View {
    let progress: Double

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 36, style: .continuous)
    }

    var body: some View {
        ZStack {
            shape
                .stroke(Color.orange.opacity(0.2), lineWidth: 5)
            shape
                .trim(from: 0, to: 1 - progress)
                .stroke(Color.orange, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .animation(.linear(duration: 1), value: progress)
        }
        .padding(3)
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
