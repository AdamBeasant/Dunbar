import Foundation
import SwiftData

struct FamilyComponent {
    let graph: FamilyGraphV2
    let anchor: FamilyNodeV2
    let nodes: [FamilyNodeV2]
    let edges: [FamilyEdgeV2]

    var nodeIDs: Set<UUID> {
        Set(nodes.map(\.stableID))
    }
}

enum FamilyGraphV2Service {
    @discardableResult
    static func ensureAnchorNode(for person: Person, context: ModelContext) -> FamilyNodeV2 {
        if let existing = person.familyNodeV2 {
            if existing.linkedContact == nil {
                existing.linkedContact = person
            }
            if existing.graph == nil {
                let graph = FamilyGraphV2()
                context.insert(graph)
                existing.graph = graph
            }
            if existing.name != person.name {
                existing.name = person.name
            }
            return existing
        }

        let graph = FamilyGraphV2()
        context.insert(graph)

        let anchor = FamilyNodeV2(
            graph: graph,
            name: person.name,
            age: nil,
            roleHint: "Contact",
            sortOrder: 0,
            linkedContact: person
        )
        context.insert(anchor)
        person.familyNodeV2 = anchor
        return anchor
    }

    static func component(for person: Person) -> FamilyComponent? {
        guard let anchor = person.familyNodeV2,
              let graph = anchor.graph
        else {
            return nil
        }

        let allNodes = graph.nodes
        let allEdges = graph.edges
        let reachableIDs = reachableNodeIDs(from: anchor, nodes: allNodes, edges: allEdges)

        let nodes = allNodes
            .filter { reachableIDs.contains($0.stableID) }
            .sorted { lhs, rhs in
                let lhsContact = lhs.linkedContact != nil
                let rhsContact = rhs.linkedContact != nil
                if lhsContact != rhsContact {
                    return lhsContact && !rhsContact
                }
                if lhs.sortOrder != rhs.sortOrder {
                    return lhs.sortOrder < rhs.sortOrder
                }
                return lhs.createdAt < rhs.createdAt
            }
        let edges = allEdges
            .filter { edge in
                guard let fromID = edge.fromNode?.stableID,
                      let toID = edge.toNode?.stableID else {
                    return false
                }
                return reachableIDs.contains(fromID) && reachableIDs.contains(toID)
            }
            .sorted { lhs, rhs in
                if lhs.sortOrder != rhs.sortOrder {
                    return lhs.sortOrder < rhs.sortOrder
                }
                return lhs.createdAt < rhs.createdAt
            }

        return FamilyComponent(
            graph: graph,
            anchor: anchor,
            nodes: nodes,
            edges: edges
        )
    }

    @discardableResult
    static func addRelative(
        for person: Person,
        name: String,
        age: Int?,
        roleHint: String?,
        targetNodeID: UUID,
        relationshipType: FamilyRelationshipType,
        newNodeIsFrom: Bool,
        coParentNodeID: UUID?,
        context: ModelContext
    ) -> FamilyNodeV2? {
        let anchor = ensureAnchorNode(for: person, context: context)
        guard let component = component(for: person),
              let targetNode = component.nodes.first(where: { $0.stableID == targetNodeID }),
              let graph = anchor.graph
        else {
            return nil
        }

        let nextNodeOrder = nextNodeSortOrder(in: graph)
        let node = FamilyNodeV2(
            graph: graph,
            name: name,
            age: age,
            roleHint: roleHint,
            sortOrder: nextNodeOrder,
            linkedContact: nil
        )
        context.insert(node)

        _ = insertEdgeIfNeeded(
            graph: graph,
            from: newNodeIsFrom ? node : targetNode,
            to: newNodeIsFrom ? targetNode : node,
            type: relationshipType,
            note: "",
            context: context
        )

        if relationshipType == .parentOf,
           newNodeIsFrom == false,
           let coParentNodeID,
           coParentNodeID != targetNode.stableID,
           let coParentNode = component.nodes.first(where: { $0.stableID == coParentNodeID }) {
            _ = insertEdgeIfNeeded(
                graph: graph,
                from: coParentNode,
                to: node,
                type: .parentOf,
                note: "",
                context: context
            )
        }

        return node
    }

    static func linkExistingContact(
        for person: Person,
        existingContact: Person,
        targetNodeID: UUID,
        relationshipType: FamilyRelationshipType,
        contactNodeIsFrom: Bool,
        coParentNodeID: UUID?,
        context: ModelContext
    ) {
        guard person.persistentModelID != existingContact.persistentModelID else {
            return
        }

        let sourceAnchor = ensureAnchorNode(for: person, context: context)
        let linkedAnchor = ensureAnchorNode(for: existingContact, context: context)

        guard let sourceGraph = sourceAnchor.graph else { return }
        let targetGraph = linkedAnchor.graph
        if let targetGraph, targetGraph.persistentModelID != sourceGraph.persistentModelID {
            mergeGraphs(into: sourceGraph, from: targetGraph, context: context)
        }

        guard let component = component(for: person),
              let targetNode = component.nodes.first(where: { $0.stableID == targetNodeID }),
              let contactNode = existingContact.familyNodeV2,
              contactNode.stableID != targetNode.stableID
        else {
            return
        }

        _ = insertEdgeIfNeeded(
            graph: sourceGraph,
            from: contactNodeIsFrom ? contactNode : targetNode,
            to: contactNodeIsFrom ? targetNode : contactNode,
            type: relationshipType,
            note: "",
            context: context
        )

        if relationshipType == .parentOf,
           contactNodeIsFrom == false,
           let coParentNodeID,
           coParentNodeID != targetNode.stableID,
           let coParentNode = component.nodes.first(where: { $0.stableID == coParentNodeID }) {
            _ = insertEdgeIfNeeded(
                graph: sourceGraph,
                from: coParentNode,
                to: contactNode,
                type: .parentOf,
                note: "",
                context: context
            )
        }
    }

    static func removeEdge(
        edgeID: PersistentIdentifier,
        for person: Person,
        context: ModelContext
    ) {
        guard let component = component(for: person),
              let edge = component.edges.first(where: { $0.persistentModelID == edgeID })
        else {
            return
        }

        context.delete(edge)
        pruneOrphans(context: context)
    }

    static func partnerCandidates(for nodeID: UUID, in component: FamilyComponent) -> [FamilyNodeV2] {
        var ids: Set<UUID> = []
        for edge in component.edges where edge.type == .partnerOf || edge.type == .formerPartnerOf {
            guard let fromID = edge.fromNode?.stableID,
                  let toID = edge.toNode?.stableID else {
                continue
            }
            if fromID == nodeID {
                ids.insert(toID)
            } else if toID == nodeID {
                ids.insert(fromID)
            }
        }
        return component.nodes
            .filter { ids.contains($0.stableID) }
            .sorted { lhs, rhs in
                let lhsContact = lhs.linkedContact != nil
                let rhsContact = rhs.linkedContact != nil
                if lhsContact != rhsContact {
                    return lhsContact && !rhsContact
                }
                if lhs.sortOrder != rhs.sortOrder {
                    return lhs.sortOrder < rhs.sortOrder
                }
                return lhs.createdAt < rhs.createdAt
            }
    }

    static func openContact(for node: FamilyNodeV2) -> Person? {
        node.linkedContact
    }

    static func pruneOrphans(context: ModelContext) {
        let descriptor = FetchDescriptor<FamilyGraphV2>()
        guard let graphs = try? context.fetch(descriptor) else { return }

        for graph in graphs {
            let nodes = graph.nodes
            let edges = graph.edges

            guard !nodes.isEmpty else {
                context.delete(graph)
                continue
            }

            let components = connectedComponents(nodes: nodes, edges: edges)
            for componentIDs in components {
                let componentNodes = nodes.filter { componentIDs.contains($0.stableID) }
                let hasContact = componentNodes.contains { $0.linkedContact != nil }
                guard !hasContact else { continue }

                for edge in edges {
                    guard let fromID = edge.fromNode?.stableID,
                          let toID = edge.toNode?.stableID else {
                        continue
                    }
                    if componentIDs.contains(fromID) || componentIDs.contains(toID) {
                        context.delete(edge)
                    }
                }

                for node in componentNodes {
                    node.linkedContact = nil
                    context.delete(node)
                }
            }

            if graph.nodes.isEmpty {
                context.delete(graph)
            }
        }
    }

    // MARK: - Helpers

    private static func mergeGraphs(
        into sourceGraph: FamilyGraphV2,
        from targetGraph: FamilyGraphV2,
        context: ModelContext
    ) {
        for node in targetGraph.nodes {
            node.graph = sourceGraph
        }
        for edge in targetGraph.edges {
            edge.graph = sourceGraph
        }
        context.delete(targetGraph)
    }

    private static func insertEdgeIfNeeded(
        graph: FamilyGraphV2,
        from: FamilyNodeV2,
        to: FamilyNodeV2,
        type: FamilyRelationshipType,
        note: String,
        context: ModelContext
    ) -> FamilyEdgeV2? {
        guard from.stableID != to.stableID else { return nil }

        let isSymmetric = (type == .partnerOf || type == .formerPartnerOf || type == .siblingOf || type == .relatedTo)
        if graph.edges.contains(where: { edge in
            guard edge.type == type,
                  let existingFrom = edge.fromNode?.stableID,
                  let existingTo = edge.toNode?.stableID else {
                return false
            }
            if isSymmetric {
                return (existingFrom == from.stableID && existingTo == to.stableID) ||
                    (existingFrom == to.stableID && existingTo == from.stableID)
            }
            return existingFrom == from.stableID && existingTo == to.stableID
        }) {
            return nil
        }

        let edge = FamilyEdgeV2(
            graph: graph,
            fromNode: from,
            toNode: to,
            type: type,
            note: note,
            sortOrder: nextEdgeSortOrder(in: graph)
        )
        context.insert(edge)
        return edge
    }

    private static func nextNodeSortOrder(in graph: FamilyGraphV2) -> Int {
        let maxOrder = graph.nodes.map(\.sortOrder).max() ?? 0
        return max(maxOrder + 1, graph.nodes.count + 1)
    }

    private static func nextEdgeSortOrder(in graph: FamilyGraphV2) -> Int {
        let maxOrder = graph.edges.map(\.sortOrder).max() ?? 0
        return max(maxOrder + 1, graph.edges.count + 1)
    }

    private static func reachableNodeIDs(
        from anchor: FamilyNodeV2,
        nodes: [FamilyNodeV2],
        edges: [FamilyEdgeV2]
    ) -> Set<UUID> {
        let validNodeIDs = Set(nodes.map(\.stableID))
        var adjacency: [UUID: Set<UUID>] = [:]
        for edge in edges {
            guard let fromID = edge.fromNode?.stableID,
                  let toID = edge.toNode?.stableID,
                  validNodeIDs.contains(fromID),
                  validNodeIDs.contains(toID) else {
                continue
            }
            adjacency[fromID, default: []].insert(toID)
            adjacency[toID, default: []].insert(fromID)
        }

        var visited: Set<UUID> = []
        var queue: [UUID] = [anchor.stableID]
        while let id = queue.first {
            queue.removeFirst()
            guard !visited.contains(id), validNodeIDs.contains(id) else { continue }
            visited.insert(id)
            for next in adjacency[id] ?? [] where !visited.contains(next) {
                queue.append(next)
            }
        }
        return visited
    }

    private static func connectedComponents(
        nodes: [FamilyNodeV2],
        edges: [FamilyEdgeV2]
    ) -> [Set<UUID>] {
        let ids = Set(nodes.map(\.stableID))
        guard !ids.isEmpty else { return [] }

        var adjacency: [UUID: Set<UUID>] = [:]
        for edge in edges {
            guard let fromID = edge.fromNode?.stableID,
                  let toID = edge.toNode?.stableID,
                  ids.contains(fromID),
                  ids.contains(toID) else {
                continue
            }
            adjacency[fromID, default: []].insert(toID)
            adjacency[toID, default: []].insert(fromID)
        }

        var remaining = ids
        var components: [Set<UUID>] = []

        while let start = remaining.first {
            var component: Set<UUID> = []
            var queue: [UUID] = [start]
            while let id = queue.first {
                queue.removeFirst()
                guard !component.contains(id) else { continue }
                component.insert(id)
                for next in adjacency[id] ?? [] where !component.contains(next) {
                    queue.append(next)
                }
            }
            components.append(component)
            remaining.subtract(component)
        }

        return components
    }
}
