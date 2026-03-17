import Foundation
import WidgetKit

struct WidgetNudgeItem: Codable {
    let name: String
    let ringLabel: String
    let statusLabel: String
}

struct WidgetSnapshot: Codable {
    let generatedAt: Date
    let overdueCount: Int
    let dueSoonCount: Int
    let topItems: [WidgetNudgeItem]
    let ringHealthScore: Int?
}

enum WidgetSnapshotStore {
    static let appGroupID = "group.com.handbook.dunbar"

    static func write(_ snapshot: WidgetSnapshot) {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(snapshot) else { return }

        if let sharedDefaults = UserDefaults(suiteName: appGroupID) {
            sharedDefaults.set(data, forKey: AppSettings.widgetSnapshotKey)
        } else {
            AppSettings.widgetSnapshotData = data
        }

        WidgetCenter.shared.reloadTimelines(ofKind: "TodayNudgesWidget")
    }

    static func read() -> WidgetSnapshot? {
        let data: Data?
        if let sharedDefaults = UserDefaults(suiteName: appGroupID) {
            data = sharedDefaults.data(forKey: AppSettings.widgetSnapshotKey)
        } else {
            data = AppSettings.widgetSnapshotData
        }

        guard let data else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    static func buildSnapshot(people: [Person]) -> WidgetSnapshot {
        let activePeople = people
            .filter { !$0.isArchived }
            .filter { ($0.snoozedUntilAt ?? .distantPast) <= .now }

        let overdue = activePeople.filter { $0.healthState == .withering }
            .sorted(by: Person.urgencyComparator)
        let dueSoon = activePeople.filter { $0.healthState == .wilting }
            .sorted(by: Person.urgencyComparator)

        let top = Array((overdue + dueSoon).prefix(3)).map {
            WidgetNudgeItem(
                name: $0.name,
                ringLabel: $0.ring.shortLabel,
                statusLabel: $0.healthState.label
            )
        }

        let score = RingHealthScoreService.snapshot(people: activePeople).totalScore

        return WidgetSnapshot(
            generatedAt: .now,
            overdueCount: overdue.count,
            dueSoonCount: dueSoon.count,
            topItems: top,
            ringHealthScore: score
        )
    }
}
