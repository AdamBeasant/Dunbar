import Foundation
import SwiftData

enum FamilyGraphV2Migrator {
    static func migrateIfNeeded(context: ModelContext) {
        guard !AppSettings.isFamilyGraphV2MigrationComplete else { return }

        let descriptor = FetchDescriptor<Person>()
        guard let people = try? context.fetch(descriptor) else { return }

        for person in people {
            migrate(person: person, context: context)
        }

        FamilyGraphV2Service.pruneOrphans(context: context)
        try? context.save()
        AppSettings.isFamilyGraphV2MigrationComplete = true
    }

    static func migrate(person: Person, context: ModelContext) {
        guard person.familyNodeV2 == nil else { return }

        let anchor = FamilyGraphV2Service.ensureAnchorNode(for: person, context: context)
        guard let graph = anchor.graph else { return }

        let legacyGraphNodes = person.sortedFamilyPeople
        let legacyGraphEdges = person.sortedFamilyRelationships

        if !legacyGraphNodes.isEmpty || !legacyGraphEdges.isEmpty {
            migrateLegacyGraph(
                person: person,
                anchor: anchor,
                graph: graph,
                legacyNodes: legacyGraphNodes,
                legacyEdges: legacyGraphEdges,
                context: context
            )
            return
        }

        if !person.sortedFamilyMembers.isEmpty {
            migrateLegacyMembers(person: person, anchor: anchor, graph: graph, context: context)
        }
    }

    private static func migrateLegacyGraph(
        person: Person,
        anchor: FamilyNodeV2,
        graph: FamilyGraphV2,
        legacyNodes: [FamilyPerson],
        legacyEdges: [FamilyRelationship],
        context: ModelContext
    ) {
        var nodeByLegacyID: [UUID: FamilyNodeV2] = [:]
        let primaryLegacyID = person.primaryFamilyPerson?.stableID
        var nextNodeOrder = 1

        for node in legacyNodes {
            if node.stableID == primaryLegacyID {
                anchor.age = node.age
                if let role = node.roleHint, !role.isEmpty {
                    anchor.roleHint = role
                }
                nodeByLegacyID[node.stableID] = anchor
                continue
            }

            let newNode = FamilyNodeV2(
                graph: graph,
                name: node.name,
                age: node.age,
                roleHint: node.roleHint,
                sortOrder: node.sortOrder > 0 ? node.sortOrder : nextNodeOrder
            )
            nextNodeOrder += 1
            context.insert(newNode)
            nodeByLegacyID[node.stableID] = newNode
        }

        if primaryLegacyID == nil {
            anchor.roleHint = "Contact"
        }

        var nextEdgeOrder = 1
        for edge in legacyEdges {
            guard let fromLegacyID = edge.fromPerson?.stableID,
                  let toLegacyID = edge.toPerson?.stableID,
                  let from = nodeByLegacyID[fromLegacyID],
                  let to = nodeByLegacyID[toLegacyID],
                  from.stableID != to.stableID else {
                continue
            }

            let migrated = FamilyEdgeV2(
                graph: graph,
                fromNode: from,
                toNode: to,
                type: edge.type,
                note: edge.note,
                sortOrder: edge.sortOrder > 0 ? edge.sortOrder : nextEdgeOrder
            )
            nextEdgeOrder += 1
            context.insert(migrated)
        }
    }

    private static func migrateLegacyMembers(
        person: Person,
        anchor: FamilyNodeV2,
        graph: FamilyGraphV2,
        context: ModelContext
    ) {
        var createdByRole: [String: [FamilyNodeV2]] = [:]
        var nextNodeOrder = 1
        var nextEdgeOrder = 1

        for legacy in person.sortedFamilyMembers {
            let node = FamilyNodeV2(
                graph: graph,
                name: legacy.name,
                age: legacy.age,
                roleHint: legacy.relation,
                sortOrder: legacy.sortOrder > 0 ? legacy.sortOrder : nextNodeOrder
            )
            nextNodeOrder += 1
            context.insert(node)
            createdByRole[FamilyGraphMigrator.normalizedRelation(legacy.relation), default: []].append(node)

            let inferred = FamilyGraphMigrator.inferLegacyRelationship(legacy.relation)
            let target: FamilyNodeV2 = {
                switch inferred.anchor {
                case .contact:
                    return anchor
                case .parent:
                    return createdByRole["parent"]?.first ?? anchor
                case .firstParentOrContact:
                    return createdByRole["parent"]?.first ?? anchor
                }
            }()

            if inferred.type == .relatedTo && node.stableID == target.stableID {
                continue
            }

            let from = inferred.addedIsFrom ? node : target
            let to = inferred.addedIsFrom ? target : node

            let edge = FamilyEdgeV2(
                graph: graph,
                fromNode: from,
                toNode: to,
                type: inferred.type,
                note: "",
                sortOrder: nextEdgeOrder
            )
            nextEdgeOrder += 1
            context.insert(edge)
        }
    }
}
