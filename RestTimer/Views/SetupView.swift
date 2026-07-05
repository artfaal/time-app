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
        ScrollView {
            VStack(spacing: 6) {
                valueCard(
                    title: "ПОДХОДЫ",
                    display: "\(totalSets)",
                    field: .sets,
                    value: $setsValue,
                    range: 1...10
                )

                valueCard(
                    title: "ОТДЫХ",
                    display: Self.timeString(restSeconds),
                    field: .rest,
                    value: $restSteps,
                    range: 2...20
                )

                Button {
                    WKInterfaceDevice.current().play(.click)
                    onStart(totalSets, TimeInterval(restSeconds))
                } label: {
                    Text("СТАРТ")
                        .font(.system(.headline, design: .rounded).weight(.black))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            Capsule().fill(
                                LinearGradient(
                                    colors: [.green, Color(red: 0.35, green: 0.9, blue: 0.55)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                        )
                }
                .buttonStyle(.plain)

                // Пресеты: тап — применить и сразу стартовать
                HStack(spacing: 4) {
                    presetChip(sets: 4, seconds: 120)
                    presetChip(sets: 4, seconds: 90)
                    presetChip(sets: 5, seconds: 120)
                }

                if notificationsDenied {
                    Text("Уведомления запрещены — при опущенной руке вибрации не будет. Включи их для Rest в настройках часов.")
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .scrollIndicators(.hidden)
        .contentMargins(.horizontal, 2, for: .scrollContent)
        .contentMargins(.vertical, 2, for: .scrollContent)
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

    // Карточка значения: подпись, крупное число, «минус/плюс».
    // Фокус (подсветка) назначает Digital Crown на это значение,
    // тап по карточке переносит фокус. Один щелчок колеса = один шаг.
    @ViewBuilder
    private func valueCard(
        title: String,
        display: String,
        field: Field,
        value: Binding<Double>,
        range: ClosedRange<Double>
    ) -> some View {
        let isFocused = focusedField == field

        VStack(spacing: 0) {
            Text(title)
                .font(.system(.caption2, design: .rounded).weight(.semibold))
                .tracking(1.2)
                .foregroundStyle(isFocused ? Color.green : .secondary)
            HStack {
                roundButton("minus") {
                    value.wrappedValue = max(range.lowerBound, value.wrappedValue - 1)
                    focusedField = field
                }
                Spacer()
                Text(display)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.easeOut(duration: 0.12), value: display)
                Spacer()
                roundButton("plus") {
                    value.wrappedValue = min(range.upperBound, value.wrappedValue + 1)
                    focusedField = field
                }
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(isFocused ? 0.12 : 0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(isFocused ? Color.green.opacity(0.7) : .clear, lineWidth: 1.5)
        )
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

    private func presetChip(sets: Int, seconds: Int) -> some View {
        Button {
            WKInterfaceDevice.current().play(.click)
            totalSets = sets
            restSeconds = seconds
            setsValue = Double(sets)
            restSteps = Double(seconds / 15)
            onStart(sets, TimeInterval(seconds))
        } label: {
            Text("\(sets)×\(Self.timeString(seconds))")
                .font(.system(.caption2, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(Capsule().fill(Color.white.opacity(0.10)))
        }
        .buttonStyle(.plain)
    }

    private func roundButton(_ systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.subheadline.weight(.semibold))
                .frame(width: 30, height: 30)
                .background(Circle().fill(.white.opacity(0.12)))
        }
        .buttonStyle(.plain)
    }

    static func timeString(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

#Preview {
    SetupView { _, _ in }
}
