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
            // simultaneousGesture, а не onLongPressGesture: экраны обёрнуты
            // в кнопки на весь экран (Double Tap), и кнопка съедает
            // обычный внешний long-press
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.8)
                    .onEnded { _ in
                        WKInterfaceDevice.current().play(.click)
                        showExitDialog = true
                    }
            )
            .confirmationDialog("Закончить упражнение?", isPresented: $showExitDialog) {
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
                    .transition(.opacity)
            case .resting(let start, let end):
                RestingView(model: model, start: start, end: end)
                    .transition(.opacity)
            case .finished:
                FinishedView(totalSets: model.totalSets, onExit: endSession)
                    .transition(.opacity)
            }
        }
        // Кросс-фейд фаз ~0.4 с (спека 1e): фон и кольцо перетекают
        .animation(.easeOut(duration: 0.4), value: model.phase)
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
            ZStack {
                // Кольцо-прогресс тренировки: заполнено currentSet/totalSets
                // (эталон: 2/5 → 40%). Рисуем сами — в AOD гасим
                if !dimmed {
                    PhaseRing(
                        progress: Double(model.currentSet) / Double(model.totalSets),
                        color: Theme.work,
                        lineWidth: Theme.workRingWidth
                    )
                    .frame(width: Theme.workRingSide, height: Theme.workRingSide)
                }
                VStack(spacing: 2) {
                    Text("ПОДХОД")
                        .font(.system(size: 10, weight: .heavy, design: .rounded))
                        .tracking(2.0)
                        .foregroundStyle(.white.opacity(0.4))
                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        Text("\(model.currentSet)")
                            .font(.system(size: 68, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                        Text("/\(model.totalSets)")
                            .font(.system(size: 40, weight: .black, design: .rounded))
                            .foregroundStyle(Theme.work.opacity(0.6))
                    }
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.easeOut(duration: 0.2), value: model.currentSet)
                }
                if !dimmed {
                    VStack {
                        Spacer()
                        Text("двойной тап — готово")
                            .font(.system(size: 10, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white.opacity(0.42))
                            .padding(.bottom, 10)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .handGestureShortcut(.primaryAction)
        .background(
            RadialPhaseBackground(inner: Theme.bgWorkInner, outer: Theme.bgWorkOuter, dimmed: dimmed)
        )
        // Эталон центрует кольцо на ПОЛНОМ экране, не в safe area
        .ignoresSafeArea()
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
    // Двойная защита от случайного задевания: мёртвая зона ~1.5 щелчка
    // до первой дельты + пауза 0.8 сек перед применением.
    // @State живёт в пределах одного отдыха (view пересоздаётся на фазу)
    @State private var crownSteps = 0.0
    @State private var crownAnchor = 0.0
    @State private var pendingSteps = 0
    @State private var applyTask: Task<Void, Never>?
    // Прорисовка кольца от 0 до текущего remaining при входе в отдых
    @State private var ringAppeared = false

    var body: some View {
        // Кнопка на весь экран: тап и системный Double Tap — скип отдыха
        Button {
            model.skipRest()
        } label: {
            ZStack {
                // Кольцо «сгорает» синхронно с таймером. Рисуем сами
                // (TimelineView), поэтому в AOD гасим — остаются системные цифры
                if !dimmed {
                    TimelineView(.animation(minimumInterval: 0.1)) { context in
                        PhaseRing(
                            progress: ringAppeared ? progress(at: context.date) : 0,
                            color: Theme.rest,
                            lineWidth: Theme.restRingWidth,
                            glow: true
                        )
                        // Последние 10 сек кольцо пульсирует (предупреждение)
                        .opacity(warningPulse(at: context.date))
                    }
                    .frame(width: Theme.restRingSide, height: Theme.restRingSide)
                }
                VStack(spacing: 2) {
                    if !dimmed {
                        Text("ОТДЫХ")
                            .font(.system(size: 10, weight: .heavy, design: .rounded))
                            .tracking(2.2)
                            .foregroundStyle(Theme.rest)
                    }
                    // Системный таймер: тикает даже в always-on, когда апп заморожен
                    Text(timerInterval: start...end, countsDown: true)
                        .font(.system(size: 60, weight: .black, design: .rounded))
                        .tracking(-1.2)
                        .monospacedDigit()
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                        .foregroundStyle(.white)
                }
                // Номера подходов и превью дельты не сдвигают системный таймер.
                .overlay {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                        Text("\(model.currentSet)")
                        Image(systemName: "arrow.right")
                            .font(.system(size: 10, weight: .bold))
                        Text("\(model.currentSet + 1) из \(model.totalSets)")
                            .foregroundStyle(dimmed ? .white.opacity(0.7) : Theme.rest)
                    }
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.65))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Подход \(model.currentSet) завершён. Далее подход \(model.currentSet + 1) из \(model.totalSets)")
                    .offset(y: 52)

                    if pendingSteps != 0 {
                        Text(pendingLabel)
                            .font(.system(size: 17, weight: .heavy, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(Theme.rest.opacity(0.85))
                            .offset(y: 76)
                            .transition(.opacity)
                    }
                }
                .animation(.spring(duration: 0.3), value: pendingSteps != 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .handGestureShortcut(.primaryAction)
        .background(
            RadialPhaseBackground(inner: Theme.bgRestInner, outer: Theme.bgRestOuter, dimmed: dimmed)
        )
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeOut(duration: 0.4)) { ringAppeared = true }
        }
        .focusable(true)
        .digitalCrownRotation(
            $crownSteps,
            from: -40,
            through: 40,
            by: 1,
            sensitivity: .low,
            isContinuous: false,
            isHapticFeedbackEnabled: true
        )
        .onChange(of: crownSteps) { _, newValue in
            let raw = newValue - crownAnchor
            // Мёртвая зона: пока не накрутил ~1.5 щелчка от точки покоя,
            // дельта не появляется вовсе
            if pendingSteps == 0, abs(raw) < 1.5 { return }
            let effective = raw > 0 ? max(0, raw - 1.5) : min(0, raw + 1.5)
            let steps = Int(effective.rounded())
            guard steps != pendingSteps else { return }
            pendingSteps = steps
            applyTask?.cancel()
            guard steps != 0 else { return }
            // Применяем через паузу после последнего щелчка
            applyTask = Task {
                try? await Task.sleep(for: .milliseconds(800))
                guard !Task.isCancelled, pendingSteps != 0 else { return }
                model.adjustRest(by: TimeInterval(pendingSteps * 15))
                crownAnchor = crownSteps
                pendingSteps = 0
            }
        }
    }

    private var pendingLabel: String {
        let seconds = abs(pendingSteps) * 15
        let sign = pendingSteps > 0 ? "+" : "−"
        return sign + SetupView.timeString(seconds)
    }

    // Кольцо отдыха убывает: remaining/total → 0
    private func progress(at date: Date) -> Double {
        let total = end.timeIntervalSince(start)
        guard total > 0 else { return 0 }
        return min(1, max(0, end.timeIntervalSince(date) / total))
    }

    // Пульс 0.55↔1 (~1.6 с) в последние 10 сек отдыха
    private func warningPulse(at date: Date) -> Double {
        let remaining = end.timeIntervalSince(date)
        guard remaining > 0, remaining <= 10 else { return 1 }
        let t = date.timeIntervalSinceReferenceDate
        return 0.775 + 0.225 * cos(t * 2 * .pi / 1.6)
    }
}

private struct FinishedView: View {
    let totalSets: Int
    let onExit: () -> Void

    @State private var pulsing = false

    var body: some View {
        // Кнопка на весь экран: тап и Double Tap завершают
        Button(action: onExit) {
            ZStack {
                PhaseRing(progress: 1, color: Theme.work, lineWidth: Theme.workRingWidth, glow: true)
                    .frame(width: Theme.workRingSide, height: Theme.workRingSide)
                VStack(spacing: 7) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(Theme.work)
                    Text(setsLabel)
                        .font(.system(size: 16, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                }
                // Idle-пульс галочки: 1→1.09→1, цикл ~2 с
                .scaleEffect(pulsing ? 1.09 : 1.0)
                .animation(.easeInOut(duration: 1).repeatForever(autoreverses: true), value: pulsing)
                .onAppear { pulsing = true }
                // Разовый салют при завершении всех подходов
                ConfettiView()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .handGestureShortcut(.primaryAction)
        .background(
            RadialPhaseBackground(inner: Theme.bgWorkInner, outer: Theme.bgWorkOuter, dimmed: false)
        )
        .ignoresSafeArea()
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

// Разовый салют на экране финиша: конфетти сыпется сверху и затухает.
// Самонарисованное и анимированное → в AOD гасим (конвенция проекта).
private struct ConfettiView: View {
    @Environment(\.isLuminanceReduced) private var dimmed
    // Частицы готовы к ПЕРВОМУ кадру (fall=false, все вверху). Иначе, если
    // заполнять их одновременно с fall=true, ForEach вставит капсулы сразу
    // в конечном состоянии и падение не заанимируется
    @State private var pieces = ConfettiPiece.make()
    @State private var fall = false

    var body: some View {
        if !dimmed {
            GeometryReader { geo in
                ZStack {
                    ForEach(pieces) { piece in
                        Capsule()
                            .fill(piece.color)
                            .frame(width: piece.size, height: piece.size * 1.9)
                            .rotationEffect(.degrees(fall ? piece.spin : 0))
                            .position(
                                x: geo.size.width / 2 + piece.x,
                                y: fall ? geo.size.height + 40 : -40
                            )
                            .opacity(fall ? 0 : 1)
                            .animation(.easeIn(duration: piece.duration).delay(piece.delay), value: fall)
                    }
                }
                .onAppear { fall = true }
            }
            .allowsHitTesting(false)
            .ignoresSafeArea()
        }
    }
}

private struct ConfettiPiece: Identifiable {
    let id = UUID()
    let x: CGFloat          // отклонение от центра по горизонтали, pt
    let spin: Double        // итоговый угол вращения
    let duration: Double    // время падения
    let delay: Double       // разброс старта, чтобы сыпалось не разом
    let color: Color
    let size: CGFloat

    static func make() -> [ConfettiPiece] {
        let palette: [Color] = [Theme.work, Theme.rest, .white]
        return (0..<26).map { _ in
            ConfettiPiece(
                x: .random(in: -110...110),
                spin: .random(in: 180...720) * (Bool.random() ? 1 : -1),
                duration: .random(in: 1.1...1.9),
                delay: .random(in: 0...0.5),
                color: palette.randomElement()!,
                size: .random(in: 5...8)
            )
        }
    }
}
