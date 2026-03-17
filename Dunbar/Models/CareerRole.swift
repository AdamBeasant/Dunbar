import Foundation
import SwiftData

@Model
final class CareerRole {
    var person: Person?
    var title: String
    var company: String
    var startYear: Int
    var endYear: Int?
    var isCurrent: Bool
    var sortOrder: Int
    var createdAt: Date
    
    init(
        person: Person? = nil,
        title: String,
        company: String,
        startYear: Int,
        endYear: Int? = nil,
        isCurrent: Bool = false,
        sortOrder: Int = 0
    ) {
        self.person = person
        self.title = title
        self.company = company
        self.startYear = startYear
        self.endYear = endYear
        self.isCurrent = isCurrent
        self.sortOrder = sortOrder
        self.createdAt = .now
    }
    
    var yearRangeLabel: String {
        if isCurrent {
            return "\(startYear)–Present"
        }
        if let endYear {
            return "\(startYear)–\(endYear)"
        }
        return "\(startYear)"
    }
}
