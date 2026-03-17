import Foundation
import SwiftData

enum FamilyGraphMigrator {
    static func migrateIfNeeded(context: ModelContext) {
        let descriptor = FetchDescriptor<Person>()
        guard let people = try? context.fetch(descriptor) else { return }
        
        var didChange = false
        for person in people {
            if migrate(person: person, context: context) {
                didChange = true
            }
        }
        
        if didChange {
            try? context.save()
        }
    }
    
    @discardableResult
    static func migrate(person: Person, context: ModelContext) -> Bool {
        let hasLegacy = !person.familyMembers.isEmpty
        let hasGraph = !person.familyPeople.isEmpty || !person.familyRelationships.isEmpty
        guard hasLegacy, !hasGraph else {
            ensurePrimaryNode(for: person, context: context)
            return false
        }
        
        let primary = ensurePrimaryNode(for: person, context: context)
        var createdNodesByRole: [String: [FamilyPerson]] = [:]
        var changed = false
        
        for (index, legacy) in person.sortedFamilyMembers.enumerated() {
            let node = FamilyPerson(
                owner: person,
                name: legacy.name,
                age: legacy.age,
                roleHint: legacy.relation,
                isPrimaryContact: false,
                sortOrder: index + 1
            )
            context.insert(node)
            createdNodesByRole[normalizedRelation(legacy.relation), default: []].append(node)
            changed = true
            
            let inferred = inferLegacyRelationship(legacy.relation)
            let target: FamilyPerson = {
                switch inferred.anchor {
                case .contact:
                    return primary
                case .parent:
                    return createdNodesByRole["parent"]?.first ?? primary
                case .firstParentOrContact:
                    return createdNodesByRole["parent"]?.first ?? primary
                }
            }()
            
            if let relationship = makeRelationship(
                owner: person,
                added: node,
                target: target,
                inferred: inferred,
                sortOrder: index + 1
            ) {
                context.insert(relationship)
            }
        }
        
        return changed
    }
    
    @discardableResult
    static func ensurePrimaryNode(for person: Person, context: ModelContext) -> FamilyPerson {
        if let existing = person.primaryFamilyPerson {
            return existing
        }
        
        let node = FamilyPerson(
            owner: person,
            name: person.name,
            age: nil,
            roleHint: "Contact",
            isPrimaryContact: true,
            sortOrder: 0
        )
        context.insert(node)
        return node
    }
    
    static func normalizedRelation(_ relation: String) -> String {
        relation
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
    
    struct LegacyInference {
        enum Anchor {
            case contact
            case parent
            case firstParentOrContact
        }
        
        let type: FamilyRelationshipType
        let anchor: Anchor
        let addedIsFrom: Bool
    }
    
    static func inferLegacyRelationship(_ relation: String) -> LegacyInference {
        let normalized = normalizedRelation(relation)
        
        if [
            "mother", "father", "mum", "mom", "dad", "parent",
            "stepmother", "stepfather", "stepmom", "stepdad"
        ].contains(normalized) || normalized.contains("step parent") || normalized.contains("step-parent") {
            return .init(type: .parentOf, anchor: .contact, addedIsFrom: true)
        }
        
        if [
            "grandmother", "grandfather", "grandparent",
            "grandma", "grandpa", "nan", "nana", "granny", "grandad", "granddad"
        ].contains(normalized) {
            return .init(type: .parentOf, anchor: .firstParentOrContact, addedIsFrom: true)
        }
        
        if [
            "brother", "sister", "sibling", "stepbrother", "stepsister"
        ].contains(normalized) {
            return .init(type: .siblingOf, anchor: .contact, addedIsFrom: true)
        }
        
        if [
            "partner", "wife", "husband", "girlfriend", "boyfriend", "spouse", "fiance", "fiancée"
        ].contains(normalized) {
            return .init(type: .partnerOf, anchor: .contact, addedIsFrom: true)
        }
        
        if normalized.contains("parent partner")
            || normalized.contains("parent's partner")
            || normalized.contains("parents partner")
            || normalized.contains("parents' partner")
            || (normalized.contains("partner") && normalized.contains("parent")) {
            return .init(type: .partnerOf, anchor: .firstParentOrContact, addedIsFrom: true)
        }
        
        if ["son", "daughter", "child", "kid", "children"].contains(normalized) {
            return .init(type: .parentOf, anchor: .contact, addedIsFrom: false)
        }
        
        return .init(type: .relatedTo, anchor: .contact, addedIsFrom: true)
    }
    
    static func makeRelationship(
        owner: Person,
        added: FamilyPerson,
        target: FamilyPerson,
        inferred: LegacyInference,
        sortOrder: Int
    ) -> FamilyRelationship? {
        if inferred.type == .relatedTo && added.stableID == target.stableID {
            return nil
        }
        
        let from = inferred.addedIsFrom ? added : target
        let to = inferred.addedIsFrom ? target : added
        return FamilyRelationship(
            owner: owner,
            fromPerson: from,
            toPerson: to,
            type: inferred.type,
            note: "",
            sortOrder: sortOrder
        )
    }
}
