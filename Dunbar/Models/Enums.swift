import Foundation

// MARK: - Cadence

enum Cadence: String, Codable, CaseIterable, Identifiable {
    case daily
    case everyOtherDay
    case weekly
    case fortnightly
    case monthly
    case quarterly
    
    var id: String { rawValue }
    
    var label: String {
        switch self {
        case .daily: return "Daily"
        case .everyOtherDay: return "Every other day"
        case .weekly: return "Weekly"
        case .fortnightly: return "Every 2 weeks"
        case .monthly: return "Monthly"
        case .quarterly: return "Quarterly"
        }
    }
    
    var shortLabel: String {
        switch self {
        case .daily: return "Daily"
        case .everyOtherDay: return "Every other day"
        case .weekly: return "Weekly"
        case .fortnightly: return "2 weeks"
        case .monthly: return "Monthly"
        case .quarterly: return "Quarterly"
        }
    }
    
    /// Number of days for this cadence
    var days: Int {
        switch self {
        case .daily: return 1
        case .everyOtherDay: return 2
        case .weekly: return 7
        case .fortnightly: return 14
        case .monthly: return 30
        case .quarterly: return 90
        }
    }
}

// MARK: - Dunbar Ring

enum DunbarRing: String, Codable, CaseIterable, Identifiable {
    case core
    case close
    case active
    case meaningful
    
    var id: String { rawValue }
    
    var label: String {
        switch self {
        case .core: return "Core"
        case .close: return "Close"
        case .active: return "Active"
        case .meaningful: return "Meaningful"
        }
    }
    
    var shortLabel: String {
        switch self {
        case .core: return "Core 5"
        case .close: return "Close 15"
        case .active: return "Active 50"
        case .meaningful: return "150 Circle"
        }
    }
    
    var capacity: Int {
        switch self {
        case .core: return 5
        case .close: return 15
        case .active: return 50
        case .meaningful: return 150
        }
    }
    
    var subtitle: String {
        switch self {
        case .core: return "Closest people"
        case .close: return "Close circle"
        case .active: return "Steady relationships"
        case .meaningful: return "Maintain connection"
        }
    }
    
    var defaultCadence: Cadence {
        switch self {
        case .core: return .everyOtherDay
        case .close: return .weekly
        case .active: return .fortnightly
        case .meaningful: return .monthly
        }
    }
    
    /// One ring closer to your inner circle.
    var tighterRing: DunbarRing? {
        switch self {
        case .core: return nil
        case .close: return .core
        case .active: return .close
        case .meaningful: return .active
        }
    }
    
    /// One ring further from your inner circle.
    var looserRing: DunbarRing? {
        switch self {
        case .core: return .close
        case .close: return .active
        case .active: return .meaningful
        case .meaningful: return nil
        }
    }
}

// MARK: - Plant Type

enum PlantType: String, Codable, CaseIterable, Identifiable {
    case succulent
    case fern
    case flower
    case tree
    case cactus
    
    var id: String { rawValue }
    
    var label: String {
        switch self {
        case .succulent: return "Succulent"
        case .fern: return "Fern"
        case .flower: return "Flower"
        case .tree: return "Tree"
        case .cactus: return "Cactus"
        }
    }
}

// MARK: - Health State

enum HealthState: String, Codable {
    case thriving
    case wilting
    case withering
    
    var label: String {
        switch self {
        case .thriving: return "On track"
        case .wilting: return "Due soon"
        case .withering: return "Overdue"
        }
    }
    
    var sortOrder: Int {
        switch self {
        case .withering: return 0  // Show first
        case .wilting: return 1
        case .thriving: return 2   // Show last
        }
    }
}

// MARK: - Check-in Type

enum CheckInType: String, Codable, CaseIterable, Identifiable {
    case message
    case call
    case inPerson

    var id: String { rawValue }

    var label: String {
        switch self {
        case .message: return "Text"
        case .call: return "Call"
        case .inPerson: return "In person"
        }
    }
    
    var symbolName: String {
        switch self {
        case .message: return "message.fill"
        case .call: return "phone.fill"
        case .inPerson: return "person.fill"
        }
    }
}

// MARK: - App Appearance

enum AppAppearance: String, Codable, CaseIterable, Identifiable {
    case system
    case light
    case dark
    
    var id: String { rawValue }
    
    var label: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
}

// MARK: - Motion

enum RingMotionIntensity: String, Codable, CaseIterable, Identifiable {
    case off
    case low
    case normal

    var id: String { rawValue }

    var label: String {
        switch self {
        case .off: return "Off"
        case .low: return "Low"
        case .normal: return "Normal"
        }
    }
}
