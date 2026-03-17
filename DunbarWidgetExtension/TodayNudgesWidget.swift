import WidgetKit
import SwiftUI

private struct WidgetNudgeItem: Codable {
    let name: String
    let ringLabel: String
    let statusLabel: String
}

private struct WidgetSnapshot: Codable {
    let generatedAt: Date
    let overdueCount: Int
    let dueSoonCount: Int
    let topItems: [WidgetNudgeItem]
    let ringHealthScore: Int?
}

private enum WidgetStore {
    static let appGroupID = "group.com.handbook.dunbar"
    static let snapshotKey = "settings.widget.snapshot"

    static func readSnapshot() -> WidgetSnapshot? {
        guard let defaults = UserDefaults(suiteName: appGroupID),
              let data = defaults.data(forKey: snapshotKey) else {
            return nil
        }

        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }
}

private struct TodayNudgesEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

private struct TodayNudgesProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayNudgesEntry {
        TodayNudgesEntry(date: .now, snapshot: fallbackSnapshot)
    }

    func getSnapshot(in context: Context, completion: @escaping (TodayNudgesEntry) -> Void) {
        let snapshot = WidgetStore.readSnapshot() ?? fallbackSnapshot
        completion(TodayNudgesEntry(date: .now, snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayNudgesEntry>) -> Void) {
        let snapshot = WidgetStore.readSnapshot() ?? fallbackSnapshot
        let entry = TodayNudgesEntry(date: .now, snapshot: snapshot)
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: .now) ?? .now.addingTimeInterval(1800)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private var fallbackSnapshot: WidgetSnapshot {
        WidgetSnapshot(
            generatedAt: .now,
            overdueCount: 0,
            dueSoonCount: 0,
            topItems: [],
            ringHealthScore: nil
        )
    }
}

private struct TodayNudgesWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TodayNudgesEntry

    var body: some View {
        Group {
            switch family {
            case .systemSmall:
                smallView
            default:
                mediumView
            }
        }
        .widgetURL(URL(string: "dunbar://inbox"))
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private var totalDue: Int {
        entry.snapshot.overdueCount + entry.snapshot.dueSoonCount
    }

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Today nudges")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)

            Text("\(totalDue)")
                .font(.system(size: 34, weight: .bold, design: .rounded))

            if let first = entry.snapshot.topItems.first {
                Text(first.name)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                Text(first.statusLabel)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            } else {
                Text("All caught up")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var mediumView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Today nudges")
                    .font(.system(size: 14, weight: .bold, design: .rounded))

                Spacer()

                Text("\(entry.snapshot.overdueCount) overdue")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            if entry.snapshot.topItems.isEmpty {
                Text("No contacts due right now.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            } else {
                ForEach(Array(entry.snapshot.topItems.enumerated()), id: \.offset) { _, item in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(item.statusLabel.lowercased() == "withering" ? Color.red.opacity(0.8) : Color.mint.opacity(0.8))
                            .frame(width: 6, height: 6)

                        Text(item.name)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .lineLimit(1)

                        Spacer()

                        Text(item.ringLabel)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            HStack {
                if let score = entry.snapshot.ringHealthScore {
                    Text("Health \(score)")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text("Open inbox")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.blue)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct TodayNudgesWidget: Widget {
    let kind: String = "TodayNudgesWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TodayNudgesProvider()) { entry in
            TodayNudgesWidgetView(entry: entry)
        }
        .configurationDisplayName("Today Nudges")
        .description("See who needs a check-in and jump straight into Inbox.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct DunbarWidgetBundle: WidgetBundle {
    var body: some Widget {
        TodayNudgesWidget()
    }
}
