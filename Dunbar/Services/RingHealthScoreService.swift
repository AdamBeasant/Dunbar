import Foundation

struct RingHealthScoreSnapshot {
    let totalScore: Int
    let perRingScores: [DunbarRing: Int]
    let thrivingCount: Int
    let dueSoonCount: Int
    let overdueCount: Int
}

enum RingHealthScoreService {
    private static func ringWeight(for ring: DunbarRing) -> Double {
        switch ring {
        case .core: return 4
        case .close: return 3
        case .active: return 2
        case .meaningful: return 1
        }
    }

    private static func statePoints(for state: HealthState) -> Double {
        switch state {
        case .thriving: return 1.0
        case .wilting: return 0.6
        case .withering: return 0.2
        }
    }

    static func snapshot(people: [Person]) -> RingHealthScoreSnapshot {
        let activePeople = people.filter { !$0.isArchived }

        var weightedNumerator = 0.0
        var weightedDenominator = 0.0

        var perRingScores: [DunbarRing: Int] = [:]

        for ring in DunbarRing.allCases {
            let ringPeople = activePeople.filter { $0.ring == ring }
            guard !ringPeople.isEmpty else {
                perRingScores[ring] = 100
                continue
            }

            let ringPoints = ringPeople.map { statePoints(for: $0.healthState) }
            let ringAverage = ringPoints.reduce(0, +) / Double(ringPeople.count)
            perRingScores[ring] = Int((ringAverage * 100).rounded())

            let weight = ringWeight(for: ring)
            weightedNumerator += ringPoints.reduce(0, +) * weight
            weightedDenominator += Double(ringPeople.count) * weight
        }

        let totalScore: Int
        if weightedDenominator == 0 {
            totalScore = 100
        } else {
            totalScore = Int(((weightedNumerator / weightedDenominator) * 100).rounded())
        }

        return RingHealthScoreSnapshot(
            totalScore: totalScore,
            perRingScores: perRingScores,
            thrivingCount: activePeople.filter { $0.healthState == .thriving }.count,
            dueSoonCount: activePeople.filter { $0.healthState == .wilting }.count,
            overdueCount: activePeople.filter { $0.healthState == .withering }.count
        )
    }

    static func band(for score: Int) -> Int {
        switch score {
        case ..<55: return 0
        case 55..<75: return 1
        case 75..<90: return 2
        default: return 3
        }
    }
}
