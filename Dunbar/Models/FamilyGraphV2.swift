import Foundation
import SwiftData

@Model
final class FamilyGraphV2 {
    var stableID: UUID
    var createdAt: Date

    @Relationship(deleteRule: .cascade, inverse: \FamilyNodeV2.graph)
    var nodes: [FamilyNodeV2] = []

    @Relationship(deleteRule: .cascade, inverse: \FamilyEdgeV2.graph)
    var edges: [FamilyEdgeV2] = []

    init() {
        self.stableID = UUID()
        self.createdAt = .now
    }
}

@Model
final class FamilyNodeV2 {
    var graph: FamilyGraphV2?
    var stableID: UUID
    var name: String
    var age: Int?
    var roleHint: String?
    var sortOrder: Int
    var createdAt: Date

    @Relationship(deleteRule: .nullify, inverse: \Person.familyNodeV2)
    var linkedContact: Person?

    @Relationship(deleteRule: .cascade, inverse: \FamilyEdgeV2.fromNode)
    var outgoingEdges: [FamilyEdgeV2] = []

    @Relationship(deleteRule: .cascade, inverse: \FamilyEdgeV2.toNode)
    var incomingEdges: [FamilyEdgeV2] = []

    init(
        graph: FamilyGraphV2? = nil,
        name: String,
        age: Int? = nil,
        roleHint: String? = nil,
        sortOrder: Int = 0,
        linkedContact: Person? = nil
    ) {
        self.graph = graph
        self.stableID = UUID()
        self.name = name
        self.age = age
        self.roleHint = roleHint
        self.sortOrder = sortOrder
        self.createdAt = .now
        self.linkedContact = linkedContact
    }

    var displayName: String {
        linkedContact?.name ?? name
    }
}

@Model
final class FamilyEdgeV2 {
    var graph: FamilyGraphV2?
    var fromNode: FamilyNodeV2?
    var toNode: FamilyNodeV2?
    var typeRaw: String
    var note: String
    var sortOrder: Int
    var createdAt: Date

    init(
        graph: FamilyGraphV2? = nil,
        fromNode: FamilyNodeV2? = nil,
        toNode: FamilyNodeV2? = nil,
        type: FamilyRelationshipType = .relatedTo,
        note: String = "",
        sortOrder: Int = 0
    ) {
        self.graph = graph
        self.fromNode = fromNode
        self.toNode = toNode
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
