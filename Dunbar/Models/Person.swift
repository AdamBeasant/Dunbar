import Foundation
import SwiftData

@Model
final class Person {
    var name: String = ""
    var initials: String = ""
    var cadenceRaw: String = "monthly"
    var ringRaw: String = "meaningful"
    var plantTypeRaw: String = "succulent"
    var reminderHour: Int = 10
    var reminderMinute: Int = 0
    var snoozedUntilAt: Date? = nil
    var lastContactedAt: Date = Date.now
    var notes: String = ""
    var createdAt: Date = Date.now
    var isArchived: Bool = false
    var isPinned: Bool = false
    
    /// JPEG photo data (compressed). nil = no photo, show ring glyph only.
    @Attribute(.externalStorage)
    var photoData: Data? = nil
    
    @Relationship(deleteRule: .cascade, inverse: \CheckIn.person)
    var checkIns: [CheckIn] = []
    
    @Relationship(deleteRule: .cascade, inverse: \CareerRole.person)
    var careerRoles: [CareerRole] = []
    
    @Relationship(deleteRule: .cascade, inverse: \FamilyMember.person)
    var familyMembers: [FamilyMember] = []
    
    @Relationship(deleteRule: .cascade, inverse: \FamilyPerson.owner)
    var familyPeople: [FamilyPerson] = []
    
    @Relationship(deleteRule: .cascade, inverse: \FamilyRelationship.owner)
    var familyRelationships: [FamilyRelationship] = []

    var familyNodeV2: FamilyNodeV2?
    
    // MARK: - Computed Properties
    
    var cadence: Cadence {
        get { Cadence(rawValue: cadenceRaw) ?? .monthly }
        set { cadenceRaw = newValue.rawValue }
    }

    var ring: DunbarRing {
        get { DunbarRing(rawValue: ringRaw) ?? .meaningful }
        set { ringRaw = newValue.rawValue }
    }
    
    var plantType: PlantType {
        get { PlantType(rawValue: plantTypeRaw) ?? .succulent }
        set { plantTypeRaw = newValue.rawValue }
    }

    var daysSinceContact: Int {
        Calendar.current.dateComponents([.day], from: lastContactedAt, to: .now).day ?? 0
    }
    
    var healthState: HealthState {
        PlantHealthCalculator.state(
            cadence: cadence,
            daysSinceContact: daysSinceContact,
            ring: ring
        )
    }
    
    var healthProgress: Double {
        PlantHealthCalculator.progress(
            cadence: cadence,
            daysSinceContact: daysSinceContact,
            ring: ring
        )
    }
    
    var isOverdue: Bool { healthState == .withering }
    var isDueSoon: Bool { healthState == .wilting }
    
    var hasPhoto: Bool { photoData != nil }
    
    var sortedCareerRoles: [CareerRole] {
        careerRoles.sorted { lhs, rhs in
            if lhs.isCurrent != rhs.isCurrent {
                return lhs.isCurrent && !rhs.isCurrent
            }
            let lhsHasOrder = lhs.sortOrder > 0
            let rhsHasOrder = rhs.sortOrder > 0
            if lhsHasOrder && rhsHasOrder && lhs.sortOrder != rhs.sortOrder {
                return lhs.sortOrder < rhs.sortOrder
            }
            if lhs.startYear != rhs.startYear {
                return lhs.startYear > rhs.startYear
            }
            return lhs.createdAt > rhs.createdAt
        }
    }
    
    var currentCareerRole: CareerRole? {
        sortedCareerRoles.first(where: { $0.isCurrent }) ?? sortedCareerRoles.first
    }
    
    var sortedFamilyMembers: [FamilyMember] {
        familyMembers.sorted { lhs, rhs in
            let lhsHasOrder = lhs.sortOrder > 0
            let rhsHasOrder = rhs.sortOrder > 0
            if lhsHasOrder && rhsHasOrder && lhs.sortOrder != rhs.sortOrder {
                return lhs.sortOrder < rhs.sortOrder
            }
            return lhs.createdAt < rhs.createdAt
        }
    }
    
    var sortedFamilyPeople: [FamilyPerson] {
        familyPeople.sorted { lhs, rhs in
            if lhs.isPrimaryContact != rhs.isPrimaryContact {
                return lhs.isPrimaryContact && !rhs.isPrimaryContact
            }
            let lhsHasOrder = lhs.sortOrder > 0
            let rhsHasOrder = rhs.sortOrder > 0
            if lhsHasOrder && rhsHasOrder && lhs.sortOrder != rhs.sortOrder {
                return lhs.sortOrder < rhs.sortOrder
            }
            return lhs.createdAt < rhs.createdAt
        }
    }
    
    var sortedFamilyRelationships: [FamilyRelationship] {
        familyRelationships.sorted { lhs, rhs in
            let lhsHasOrder = lhs.sortOrder > 0
            let rhsHasOrder = rhs.sortOrder > 0
            if lhsHasOrder && rhsHasOrder && lhs.sortOrder != rhs.sortOrder {
                return lhs.sortOrder < rhs.sortOrder
            }
            return lhs.createdAt < rhs.createdAt
        }
    }
    
    var primaryFamilyPerson: FamilyPerson? {
        sortedFamilyPeople.first(where: \.isPrimaryContact)
    }
    
    // MARK: - Init
    
    init(
        name: String,
        ring: DunbarRing = .meaningful,
        cadence: Cadence = .monthly,
        plantType: PlantType = .succulent,
        notes: String = "",
        photoData: Data? = nil,
        reminderHour: Int = AppSettings.defaultReminderHour,
        reminderMinute: Int = AppSettings.defaultReminderMinute
    ) {
        self.name = name
        self.initials = Person.makeInitials(from: name)
        self.ringRaw = ring.rawValue
        self.cadenceRaw = cadence.rawValue
        self.plantTypeRaw = plantType.rawValue
        self.reminderHour = reminderHour
        self.reminderMinute = reminderMinute
        self.snoozedUntilAt = nil
        self.lastContactedAt = .now
        self.notes = notes
        self.createdAt = .now
        self.isArchived = false
        self.isPinned = false
        self.photoData = photoData
        self.careerRoles = []
        self.familyMembers = []
        self.familyPeople = []
        self.familyRelationships = []
        self.familyNodeV2 = nil
    }
    
    // MARK: - Actions
    
    func markAsContacted(
        note: String = "",
        kind: CheckInType = .message,
        context: ModelContext
    ) {
        let checkIn = CheckIn(person: self, kind: kind, note: note)
        context.insert(checkIn)
        self.lastContactedAt = .now
        self.snoozedUntilAt = nil
    }
    
    // MARK: - Helpers
    
    static func makeInitials(from name: String) -> String {
        name.trimmingCharacters(in: .whitespaces)
            .split(separator: " ")
            .prefix(2)
            .compactMap { $0.first }
            .map { String($0).uppercased() }
            .joined()
    }
}

extension Person {
    static func urgencyComparator(_ a: Person, _ b: Person) -> Bool {
        if a.isPinned != b.isPinned {
            return a.isPinned && !b.isPinned
        }
        if a.healthState.sortOrder != b.healthState.sortOrder {
            return a.healthState.sortOrder < b.healthState.sortOrder
        }
        return a.daysSinceContact > b.daysSinceContact
    }
}
