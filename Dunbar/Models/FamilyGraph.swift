import Foundation
import SwiftData

enum FamilyRelationshipType: String, CaseIterable, Codable, Identifiable {
    case parentOf
    case partnerOf
    case siblingOf
    case guardianOf
    case formerPartnerOf
    case relatedTo
    
    var id: String { rawValue }
    
    var label: String {
        switch self {
        case .parentOf: return "Parent of"
        case .partnerOf: return "Partner of"
        case .siblingOf: return "Sibling of"
        case .guardianOf: return "Guardian of"
        case .formerPartnerOf: return "Former partner of"
        case .relatedTo: return "Related to"
        }
    }
    
    var shortLabel: String {
        switch self {
        case .parentOf: return "Parent"
        case .partnerOf: return "Partner"
        case .siblingOf: return "Sibling"
        case .guardianOf: return "Guardian"
        case .formerPartnerOf: return "Former partner"
        case .relatedTo: return "Related"
        }
    }
}

@Model
final class FamilyPerson {
    var owner: Person?
    var stableID: UUID
    var name: String
    var age: Int?
    var roleHint: String?
    var isPrimaryContact: Bool
    var sortOrder: Int
    var createdAt: Date
    
    @Relationship(deleteRule: .cascade, inverse: \FamilyRelationship.fromPerson)
    var outgoingRelationships: [FamilyRelationship] = []
    
    @Relationship(deleteRule: .cascade, inverse: \FamilyRelationship.toPerson)
    var incomingRelationships: [FamilyRelationship] = []
    
    init(
        owner: Person? = nil,
        name: String,
        age: Int? = nil,
        roleHint: String? = nil,
        isPrimaryContact: Bool = false,
        sortOrder: Int = 0
    ) {
        self.owner = owner
        self.stableID = UUID()
        self.name = name
        self.age = age
        self.roleHint = roleHint
        self.isPrimaryContact = isPrimaryContact
        self.sortOrder = sortOrder
        self.createdAt = .now
    }
}

@Model
final class FamilyRelationship {
    var owner: Person?
    var fromPerson: FamilyPerson?
    var toPerson: FamilyPerson?
    var typeRaw: String
    var note: String
    var sortOrder: Int
    var createdAt: Date
    
    init(
        owner: Person? = nil,
        fromPerson: FamilyPerson? = nil,
        toPerson: FamilyPerson? = nil,
        type: FamilyRelationshipType = .relatedTo,
        note: String = "",
        sortOrder: Int = 0
    ) {
        self.owner = owner
        self.fromPerson = fromPerson
        self.toPerson = toPerson
        self.typeRaw = type.rawValue
        self.note = note
        self.sortOrder = sortOrder
        self.createdAt = .now
    }
    
    var type: FamilyRelationshipType {
        get { FamilyRelationshipType(rawValue: typeRaw) ?? .relatedTo }
        set { typeRaw = newValue.rawValue }
    }
}
