import Foundation
import SwiftData

enum PlantHealthCalculator {
    
    /// Returns the health state based on cadence and days since last contact.
    /// - thriving: within 70% of the cadence window
    /// - wilting: between 70% and 100% of the cadence window
    /// - withering: past the cadence window
    static func state(cadence: Cadence, daysSinceContact: Int) -> HealthState {
        state(cadence: cadence, daysSinceContact: daysSinceContact, ring: .meaningful)
    }
    
    static func state(cadence: Cadence, daysSinceContact: Int, ring: DunbarRing) -> HealthState {
        let threshold = effectiveCadenceDays(cadence: cadence, ring: ring)
        
        if daysSinceContact > threshold {
            return .withering
        } else if daysSinceContact > Int(Double(threshold) * 0.7) {
            return .wilting
        } else {
            return .thriving
        }
    }
    
    /// Returns a 0.0 → 1.0+ progress value through the cadence cycle.
    /// 0.0 = just contacted, 1.0 = exactly at cadence boundary, >1.0 = overdue.
    static func progress(cadence: Cadence, daysSinceContact: Int) -> Double {
        progress(cadence: cadence, daysSinceContact: daysSinceContact, ring: .meaningful)
    }
    
    static func progress(cadence: Cadence, daysSinceContact: Int, ring: DunbarRing) -> Double {
        let effectiveDays = effectiveCadenceDays(cadence: cadence, ring: ring)
        guard effectiveDays > 0 else { return 0 }
        return Double(daysSinceContact) / Double(effectiveDays)
    }
    
    /// Days remaining until overdue. Negative values mean overdue.
    static func daysRemaining(cadence: Cadence, daysSinceContact: Int) -> Int {
        daysRemaining(cadence: cadence, daysSinceContact: daysSinceContact, ring: .meaningful)
    }
    
    static func daysRemaining(cadence: Cadence, daysSinceContact: Int, ring: DunbarRing) -> Int {
        effectiveCadenceDays(cadence: cadence, ring: ring) - daysSinceContact
    }
    
    /// Human-readable status string for display
    static func statusText(cadence: Cadence, daysSinceContact: Int) -> String {
        statusText(cadence: cadence, daysSinceContact: daysSinceContact, ring: .meaningful)
    }
    
    static func statusText(cadence: Cadence, daysSinceContact: Int, ring: DunbarRing) -> String {
        let remaining = daysRemaining(
            cadence: cadence,
            daysSinceContact: daysSinceContact,
            ring: ring
        )
        
        if daysSinceContact == 0 {
            return "Just now"
        } else if remaining < 0 {
            return "\(abs(remaining))d overdue"
        } else if remaining <= 3 {
            return "Due in \(remaining)d"
        } else {
            return "\(daysSinceContact)d ago"
        }
    }
    
    private static func effectiveCadenceDays(cadence: Cadence, ring: DunbarRing) -> Int {
        let multiplier: Double
        
        switch ring {
        case .core:
            multiplier = 0.8
        case .close:
            multiplier = 0.9
        case .active:
            multiplier = 1.0
        case .meaningful:
            multiplier = 1.1
        }
        
        return max(1, Int(round(Double(cadence.days) * multiplier)))
    }
}

enum DunbarRingShiftDirection {
    case promote
    case demote
    
    var label: String {
        switch self {
        case .promote: return "Promote"
        case .demote: return "Demote"
        }
    }
}

struct DunbarRebalanceSuggestion: Identifiable {
    let person: Person
    let direction: DunbarRingShiftDirection
    let targetRing: DunbarRing
    let reason: String
    let priority: Int
    
    var id: String {
        "\(person.persistentModelID)-\(targetRing.rawValue)-\(direction.label)"
    }
    
    var actionLabel: String {
        switch direction {
        case .promote: return "Promote to \(targetRing.label)"
        case .demote: return "Move to \(targetRing.label)"
        }
    }
}

enum DunbarRebalanceHistoryOutcome: String, Codable {
    case applied
    case deferred
}

struct DunbarRebalanceHistoryEntry: Codable, Identifiable {
    var id: UUID = UUID()
    var personName: String
    var fromRingRaw: String
    var toRingRaw: String
    var directionRaw: String
    var outcomeRaw: String
    var reason: String
    var recordedAt: Date
    var deferredUntilAt: Date?
    
    var fromRing: DunbarRing {
        DunbarRing(rawValue: fromRingRaw) ?? .meaningful
    }
    
    var toRing: DunbarRing {
        DunbarRing(rawValue: toRingRaw) ?? .meaningful
    }
    
    var direction: DunbarRingShiftDirection {
        directionRaw == DunbarRingShiftDirection.promote.label ? .promote : .demote
    }
    
    var outcome: DunbarRebalanceHistoryOutcome {
        DunbarRebalanceHistoryOutcome(rawValue: outcomeRaw) ?? .applied
    }
}

enum DunbarRebalanceAdvisor {
    static func suggestions(
        people: [Person],
        checkIns: [CheckIn],
        now: Date = .now
    ) -> [DunbarRebalanceSuggestion] {
        let recentCutoff = Calendar.current.date(byAdding: .day, value: -45, to: now) ?? now
        
        var result: [DunbarRebalanceSuggestion] = []
        
        for person in people where !person.isArchived {
            let personCheckIns = checkIns.filter { $0.person === person }
            let recentCount = personCheckIns.filter { $0.contactedAt >= recentCutoff }.count
            let daysSince = person.daysSinceContact
            
            if let tighterRing = person.ring.tighterRing {
                let minRecent = promotionRecentThreshold(for: person.ring)
                let maxSilence = max(2, Int(Double(person.cadence.days) * 0.6))
                
                if recentCount >= minRecent && daysSince <= maxSilence {
                    let reason = "Strong recent momentum (\(recentCount) check-ins in 45d)."
                    let priority = (recentCount * 4) + max(0, maxSilence - daysSince)
                    result.append(
                        DunbarRebalanceSuggestion(
                            person: person,
                            direction: .promote,
                            targetRing: tighterRing,
                            reason: reason,
                            priority: priority
                        )
                    )
                    continue
                }
            }
            
            if let looserRing = person.ring.looserRing {
                let demotionSilence = demotionSilenceThreshold(for: person.ring, cadence: person.cadence)
                let shouldDemote = daysSince >= demotionSilence && recentCount == 0
                
                if shouldDemote {
                    let reason = "No recent check-ins and \(daysSince)d since last contact."
                    let priority = (daysSince - demotionSilence) + 20
                    result.append(
                        DunbarRebalanceSuggestion(
                            person: person,
                            direction: .demote,
                            targetRing: looserRing,
                            reason: reason,
                            priority: priority
                        )
                    )
                }
            }
        }
        
        return result
            .sorted { lhs, rhs in
                if lhs.priority != rhs.priority {
                    return lhs.priority > rhs.priority
                }
                return lhs.person.daysSinceContact > rhs.person.daysSinceContact
            }
    }
    
    static func apply(
        _ suggestion: DunbarRebalanceSuggestion,
        at timestamp: Date = .now
    ) -> DunbarRebalanceHistoryEntry {
        let fromRing = suggestion.person.ring
        suggestion.person.ring = suggestion.targetRing
        suggestion.person.cadence = suggestion.targetRing.defaultCadence
        
        return DunbarRebalanceHistoryEntry(
            personName: suggestion.person.name,
            fromRingRaw: fromRing.rawValue,
            toRingRaw: suggestion.targetRing.rawValue,
            directionRaw: suggestion.direction.label,
            outcomeRaw: DunbarRebalanceHistoryOutcome.applied.rawValue,
            reason: suggestion.reason,
            recordedAt: timestamp,
            deferredUntilAt: nil
        )
    }
    
    private static func promotionRecentThreshold(for ring: DunbarRing) -> Int {
        switch ring {
        case .core:
            return .max
        case .close:
            return 6
        case .active:
            return 4
        case .meaningful:
            return 3
        }
    }
    
    private static func demotionSilenceThreshold(for ring: DunbarRing, cadence: Cadence) -> Int {
        switch ring {
        case .core:
            return max(18, cadence.days * 2)
        case .close:
            return max(28, cadence.days * 2)
        case .active:
            return max(45, cadence.days * 2)
        case .meaningful:
            return .max
        }
    }
}
