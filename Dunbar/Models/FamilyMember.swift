import Foundation
import SwiftData

@Model
final class FamilyMember {
    var person: Person?
    var name: String
    var relation: String
    var age: Int?
    var sortOrder: Int
    var createdAt: Date
    
    init(
        person: Person? = nil,
        name: String,
        relation: String,
        age: Int? = nil,
        sortOrder: Int = 0
    ) {
        self.person = person
        self.name = name
        self.relation = relation
        self.age = age
        self.sortOrder = sortOrder
        self.createdAt = .now
    }
    
    var relationSymbol: String {
        let normalized = relation.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if ["partner", "wife", "husband", "girlfriend", "boyfriend"].contains(normalized) {
            return "heart.fill"
        }
        if ["son", "daughter", "child"].contains(normalized) {
            return "diamond.fill"
        }
        return "circle.fill"
    }
}
