import SwiftUI

struct SetupView: View {
    @AppStorage("totalSets") private var totalSets = 4
    @AppStorage("restSeconds") private var restSeconds = 120
    @State private var notificationsDenied = false
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case sets, rest
    }

    let onStart: (Int, TimeInterval) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                adjustRow(
                    title: "Подходы",
                    display: "\(totalSets)",
                    field: .sets,
                    value: Binding(
                        get: { Double(totalSets) },
                        set: { totalSets = Int($0.rounded()) }
                    ),
                    range: 1...10,
                    step: 1
                )

                adjustRow(
                    title: "Отдых",
                    display: Self.timeString(restSeconds),
                    field: .rest,
                    value: Binding(
                        get: { Double(restSeconds) },
                        set: { restSeconds = Int($0.rounded()) }
                    ),
                    range: 30...300,
                    step: 15
                )

                Button {
                    onStart(totalSets, TimeInterval(restSeconds))
                } label: {
                    Text("СТАРТ")
                        .font(.headline)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)

                if notificationsDenied {
                    Text("Уведомления запрещены — при опущенной руке вибрации не будет. Включи их для Rest в настройках часов.")
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.top, 4)
        }
        .navigationTitle("Rest")
        .onAppear { focusedField = .sets }
        .task {
            notificationsDenied = await NotificationManager.shared.authorizationDenied()
        }
    }

    // Строка «минус — значение — плюс». Фокус (зелёная рамка) назначает
    // Digital Crown на это значение; тап по строке переносит фокус.
    @ViewBuilder
    private func adjustRow(
        title: String,
        display: String,
        field: Field,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double
    ) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.footnote)
                .foregroundStyle(.secondary)
            HStack {
                roundButton("minus") {
                    value.wrappedValue = max(range.lowerBound, value.wrappedValue - step)
                    focusedField = field
                }
                Spacer()
                Text(display)
                    .font(.title2.weight(.semibold))
                    .monospacedDigit()
                Spacer()
                roundButton("plus") {
                    value.wrappedValue = min(range.upperBound, value.wrappedValue + step)
                    focusedField = field
                }
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.08)))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(focusedField == field ? Color.green : .clear, lineWidth: 1.5)
        )
        .contentShape(Rectangle())
        .onTapGesture { focusedField = field }
        .focusable(true)
        .focused($focusedField, equals: field)
        .digitalCrownRotation(
            value,
            from: range.lowerBound,
            through: range.upperBound,
            by: step,
            sensitivity: .low,
            isContinuous: false,
            isHapticFeedbackEnabled: true
        )
    }

    private func roundButton(_ systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.headline)
                .frame(width: 34, height: 34)
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
