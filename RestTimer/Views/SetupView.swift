import SwiftUI
import WatchKit

struct SetupView: View {
    @AppStorage("totalSets") private var totalSets = 4
    @AppStorage("restSeconds") private var restSeconds = 120

    // Локальные Double для Digital Crown: биндинг напрямую в @AppStorage
    // через get/set создаёт обратную связь, и накопление поворота ломается.
    // Отдых крутим ШАГАМИ по 15 сек (2...20), а не секундами — иначе колесо
    // приходится крутить слишком долго
    @State private var setsValue = 4.0
    @State private var restSteps = 8.0
    @State private var notificationsDenied = false
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case sets, rest
    }

    let onStart: (Int, TimeInterval) -> Void

    var body: some View {
        VStack(spacing: 13) {
            // Два круглых циферблата (1e): зелёная обводка = фокус Crown,
            // тап переносит фокус. Кнопок −/+ нет — только колесо
            HStack(spacing: 12) {
                dial(
                    title: "ПОДХОДЫ",
                    display: "\(totalSets)",
                    fontSize: 32,
                    field: .sets,
                    value: $setsValue,
                    range: 1...10
                )
                dial(
                    title: "ОТДЫХ",
                    display: Self.timeString(restSeconds),
                    fontSize: 25,
                    field: .rest,
                    value: $restSteps,
                    range: 2...20
                )
            }

            Button {
                WKInterfaceDevice.current().play(.click)
                onStart(totalSets, TimeInterval(restSeconds))
            } label: {
                Text("СТАРТ")
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .tracking(0.6)
                    .foregroundStyle(.black)
                    .frame(width: Theme.screenWidth * 0.77, height: 42)
                    .background(Capsule().fill(.white))
            }
            .buttonStyle(.plain)

            if notificationsDenied {
                Text("Уведомления запрещены — при опущенной руке вибрации не будет. Включи их для Rest в настройках часов.")
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            }
        }
        // Группа чуть ниже середины полного экрана: сверху воздух под
        // системные часы, СТАРТ ближе к низу
        .offset(y: 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bgSetup)
        .ignoresSafeArea()
        .onAppear {
            setsValue = Double(totalSets)
            restSteps = Double(restSeconds / 15)
            focusedField = .sets
        }
        .onChange(of: setsValue) { _, newValue in
            totalSets = Int(newValue.rounded())
        }
        .onChange(of: restSteps) { _, newValue in
            restSeconds = Int(newValue.rounded()) * 15
        }
        .task {
            notificationsDenied = await NotificationManager.shared.authorizationDenied()
        }
    }

    // Круглый циферблат: значение внутри кольца-обводки, подпись под ним.
    // Фокус (зелёная обводка) назначает Digital Crown на это значение,
    // тап по циферблату переносит фокус. Один щелчок колеса = один шаг
    @ViewBuilder
    private func dial(
        title: String,
        display: String,
        fontSize: CGFloat,
        field: Field,
        value: Binding<Double>,
        range: ClosedRange<Double>
    ) -> some View {
        let isFocused = focusedField == field

        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .strokeBorder(isFocused ? Theme.work : Theme.dialInactive, lineWidth: 2.5)
                Text(display)
                    .font(.system(size: fontSize, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.easeOut(duration: 0.12), value: display)
            }
            .frame(width: Theme.setupDialSide, height: Theme.setupDialSide)
            Text(title)
                .font(.system(size: 10, weight: .heavy, design: .rounded))
                .tracking(1.4)
                .foregroundStyle(.white.opacity(0.45))
        }
        .animation(.snappy(duration: 0.2), value: isFocused)
        .contentShape(Rectangle())
        .onTapGesture { focusedField = field }
        .focusable(true)
        .focused($focusedField, equals: field)
        .digitalCrownRotation(
            value,
            from: range.lowerBound,
            through: range.upperBound,
            by: 1,
            sensitivity: .medium,
            isContinuous: false,
            isHapticFeedbackEnabled: true
        )
    }

    static func timeString(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

#Preview {
    SetupView { _, _ in }
}
