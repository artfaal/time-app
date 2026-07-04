import SwiftUI

struct SessionView: View {
    let model: WorkoutModel
    let onExit: () -> Void

    @Environment(\.scenePhase) private var scenePhase
    @State private var showExitDialog = false

    private let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        content
            .onReceive(timer) { _ in model.tick() }
            .onChange(of: scenePhase) { _, newPhase in
                // После сна догоняем состояние по фактическому времени
                if newPhase == .active { model.tick() }
            }
            .onLongPressGesture(minimumDuration: 0.8) {
                showExitDialog = true
            }
            .confirmationDialog("Закончить тренировку?", isPresented: $showExitDialog) {
                Button("Закончить", role: .destructive) {
                    model.abort()
                    onExit()
                }
                Button("Продолжить", role: .cancel) {}
            }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .working:
            WorkingView(model: model)
        case .resting(let start, let end):
            RestingView(model: model, start: start, end: end)
        case .finished:
            FinishedView(totalSets: model.totalSets, onExit: onExit)
        }
    }
}

private struct WorkingView: View {
    let model: WorkoutModel

    var body: some View {
        VStack(spacing: 10) {
            Text("ПОДХОД \(model.currentSet)/\(model.totalSets)")
                .font(.title3.weight(.bold))
            Text("💪")
                .font(.system(size: 44))
            Text("тап — начать отдых")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { model.finishSet() }
    }
}

private struct RestingView: View {
    let model: WorkoutModel
    let start: Date
    let end: Date

    var body: some View {
        VStack(spacing: 6) {
            Text("дальше подход \(model.currentSet + 1)/\(model.totalSets)")
                .font(.footnote)
                .foregroundStyle(.secondary)

            // Системный таймер: тикает даже в always-on, когда апп заморожен
            Text(timerInterval: start...end, countsDown: true)
                .font(.system(size: 52, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.orange)

            ProgressView(timerInterval: start...end, countsDown: true) {
                EmptyView()
            } currentValueLabel: {
                EmptyView()
            }
            .tint(.orange)
            .padding(.horizontal)

            Text("тап — пропустить")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { model.skipRest() }
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
            Text("\(totalSets) подходов")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button("Завершить", action: onExit)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
