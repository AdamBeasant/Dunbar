import Foundation
import SwiftData

enum CadenceRecommendationReason: String, Codable {
    case sustainedEarlyReplies
    case repeatedMisses

    var title: String {
        switch self {
        case .sustainedEarlyReplies:
            return "You consistently check in early"
        case .repeatedMisses:
            return "You often go overdue at this cadence"
        }
    }
}

enum RecommendationConfidence: String, Codable {
    case low
    case medium
    case high

    var label: String { rawValue.capitalized }
}

struct SmartCadenceRecommendation: Identifiable {
    let person: Person
    let currentCadence: Cadence
    let recommendedCadence: Cadence
    let confidence: RecommendationConfidence
    let reason: CadenceRecommendationReason
    let detail: String

    var id: String {
        "\(person.persistentModelID)-\(recommendedCadence.rawValue)-\(reason.rawValue)"
    }
}

enum CadenceRecommendationService {
    static func recommendation(for person: Person, checkIns: [CheckIn], now: Date = .now) -> SmartCadenceRecommendation? {
        let personCheckIns = checkIns
            .filter { $0.person?.persistentModelID == person.persistentModelID }
            .sorted { $0.contactedAt < $1.contactedAt }

        guard personCheckIns.count >= 3 else { return nil }

        let cutoff = Calendar.current.date(byAdding: .day, value: -56, to: now) ?? now
        let recent = personCheckIns.filter { $0.contactedAt >= cutoff }
        guard recent.count >= 3 else { return nil }

        let intervals = consecutiveIntervalsDays(from: recent)
        guard !intervals.isEmpty else { return nil }

        let averageInterval = intervals.reduce(0, +) / Double(intervals.count)
        let cadenceDays = Double(max(person.cadence.days, 1))
        let overdueCount = recent.filter {
            let days = Calendar.current.dateComponents([.day], from: $0.contactedAt, to: now).day ?? 0
            return days > person.cadence.days
        }.count
        let overdueRatio = Double(overdueCount) / Double(recent.count)

        if averageInterval <= cadenceDays * 0.65,
           let tighter = tighterCadence(than: person.cadence) {
            let confidence: RecommendationConfidence
            if averageInterval <= cadenceDays * 0.5 { confidence = .high }
            else if averageInterval <= cadenceDays * 0.6 { confidence = .medium }
            else { confidence = .low }

            return SmartCadenceRecommendation(
                person: person,
                currentCadence: person.cadence,
                recommendedCadence: tighter,
                confidence: confidence,
                reason: .sustainedEarlyReplies,
                detail: "Average interval is \(Int(round(averageInterval)))d vs current \(person.cadence.days)d cadence."
            )
        }

        if (overdueRatio >= 0.5 || averageInterval >= cadenceDays * 1.25),
           let looser = looserCadence(than: person.cadence) {
            let confidence: RecommendationConfidence
            if overdueRatio >= 0.75 { confidence = .high }
            else if overdueRatio >= 0.6 { confidence = .medium }
            else { confidence = .low }

            return SmartCadenceRecommendation(
                person: person,
                currentCadence: person.cadence,
                recommendedCadence: looser,
                confidence: confidence,
                reason: .repeatedMisses,
                detail: "\(Int(overdueRatio * 100))% of recent check-ins reached overdue state first."
            )
        }

        return nil
    }

    private static func consecutiveIntervalsDays(from checkIns: [CheckIn]) -> [Double] {
        guard checkIns.count > 1 else { return [] }

        var intervals: [Double] = []
        for index in 1..<checkIns.count {
            let previous = checkIns[index - 1].contactedAt
            let current = checkIns[index].contactedAt
            let days = max(current.timeIntervalSince(previous) / 86_400, 0)
            intervals.append(days)
        }
        return intervals
    }

    private static func tighterCadence(than cadence: Cadence) -> Cadence? {
        guard let index = Cadence.allCases.firstIndex(of: cadence), index > 0 else {
            return nil
        }
        return Cadence.allCases[index - 1]
    }

    private static func looserCadence(than cadence: Cadence) -> Cadence? {
        guard let index = Cadence.allCases.firstIndex(of: cadence), index < Cadence.allCases.count - 1 else {
            return nil
        }
        return Cadence.allCases[index + 1]
    }
}
