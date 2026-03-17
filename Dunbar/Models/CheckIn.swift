import Foundation
import SwiftData

@Model
final class CheckIn {
    var person: Person?
    var contactedAt: Date
    var note: String
    var kindRaw: String
    
    var kind: CheckInType {
        get { CheckInType(rawValue: kindRaw) ?? .message }
        set { kindRaw = newValue.rawValue }
    }
    
    init(
        person: Person,
        kind: CheckInType = .message,
        contactedAt: Date = .now,
        note: String = ""
    ) {
        self.person = person
        self.contactedAt = contactedAt
        self.note = note
        self.kindRaw = kind.rawValue
    }
}
