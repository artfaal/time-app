import SwiftUI

struct SetupView: View {
    @AppStorage("totalSets") private var totalSets = 4
    @AppStorage("restSeconds") private var restSeconds = 120

    let onStart: (Int, TimeInterval) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                VStack(spacing: 4) {
                    Text("Подходы")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Stepper(value: $totalSets, in: 1...10) {
                        Text("\(totalSets)")
                            .font(.title2.weight(.semibold))
                    }
                }

                VStack(spacing: 4) {
                    Text("Отдых")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Stepper(value: $restSeconds, in: 30...300, step: 15) {
                        Text(Self.timeString(restSeconds))
                            .font(.title2.weight(.semibold))
                            .monospacedDigit()
                    }
                }

                Button {
                    onStart(totalSets, TimeInterval(restSeconds))
                } label: {
                    Text("СТАРТ")
                        .font(.headline)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            }
            .padding(.top, 4)
        }
        .navigationTitle("Rest")
    }

    static func timeString(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

#Preview {
    SetupView { _, _ in }
}
