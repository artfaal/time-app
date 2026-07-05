import SwiftUI
import WidgetKit

// Статичная компликация-кнопка: тап на циферблате открывает апп
@main
struct RestTimerComplicationBundle: WidgetBundle {
    var body: some Widget {
        LaunchComplication()
    }
}

struct LaunchEntry: TimelineEntry {
    let date: Date
}

struct LaunchProvider: TimelineProvider {
    func placeholder(in context: Context) -> LaunchEntry {
        LaunchEntry(date: .now)
    }

    func getSnapshot(in context: Context, completion: @escaping (LaunchEntry) -> Void) {
        completion(LaunchEntry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LaunchEntry>) -> Void) {
        completion(Timeline(entries: [LaunchEntry(date: .now)], policy: .never))
    }
}

struct LaunchComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "LaunchComplication", provider: LaunchProvider()) { _ in
            LaunchComplicationView()
        }
        .configurationDisplayName("Rest Timer")
        .description("Запуск таймера отдыха")
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryInline])
    }
}

struct LaunchComplicationView: View {
    @Environment(\.widgetFamily) private var family

    // Голубой — в тон иконке аппа, чтобы пиктограмма не была чёрной
    private static let skyBlue = Color(red: 0.45, green: 0.75, blue: 1.0)
    private static let deepBlue = Color(red: 0.15, green: 0.4, blue: 0.95)

    var body: some View {
        Group {
            switch family {
            case .accessoryInline:
                Label("Rest Timer", systemImage: "figure.strengthtraining.traditional")
            default:
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Self.skyBlue, .white],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .widgetAccentable()
            }
        }
        .containerBackground(for: .widget) {
            LinearGradient(
                colors: [Self.deepBlue.opacity(0.55), Self.deepBlue.opacity(0.25)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}
