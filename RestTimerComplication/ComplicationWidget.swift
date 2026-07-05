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

    // Оранжевый — в тон иконке и кольцу отдыха (дизайн 1e)
    private static let amber = Color(red: 1.0, green: 0.72, blue: 0.35)
    private static let accent = Color(red: 1.0, green: 138 / 255, blue: 26 / 255)   // #FF8A1A
    private static let warmDark = Color(red: 46 / 255, green: 23 / 255, blue: 3 / 255)  // #2e1703

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
                            colors: [Self.amber, Self.accent],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .widgetAccentable()
            }
        }
        .containerBackground(for: .widget) {
            LinearGradient(
                colors: [Self.warmDark.opacity(0.9), Self.warmDark.opacity(0.35)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}
