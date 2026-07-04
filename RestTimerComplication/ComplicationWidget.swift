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

    var body: some View {
        Group {
            switch family {
            case .accessoryInline:
                Label("Rest Timer", systemImage: "timer")
            default:
                Image(systemName: "timer")
                    .font(.title2)
                    .widgetAccentable()
            }
        }
        .containerBackground(for: .widget) { Color.clear }
    }
}
