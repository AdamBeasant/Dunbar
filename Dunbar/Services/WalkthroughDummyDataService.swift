import Foundation
import SwiftData

enum WalkthroughDummyDataService {

    static func insertDummyData(context: ModelContext) {
        // Clean any stale dummy data first
        removeDummyData(context: context)

        let cal = Calendar.current
        let now = Date.now

        // MARK: - Sarah M. (core, thriving, 3 check-ins)
        let sarah = Person(name: "Sarah M.", ring: .core, cadence: .everyOtherDay)
        sarah.isDummyData = true
        sarah.lastContactedAt = cal.date(byAdding: .day, value: -1, to: now)!
        context.insert(sarah)

        let s1 = CheckIn(person: sarah, kind: .message, contactedAt: cal.date(byAdding: .day, value: -1, to: now)!, note: "Caught up about the weekend")
        let s2 = CheckIn(person: sarah, kind: .call, contactedAt: cal.date(byAdding: .day, value: -3, to: now)!, note: "Quick call to check in")
        let s3 = CheckIn(person: sarah, kind: .inPerson, contactedAt: cal.date(byAdding: .day, value: -6, to: now)!, note: "Coffee together")
        context.insert(s1)
        context.insert(s2)
        context.insert(s3)

        // MARK: - James T. (core, withering, 1 check-in + career role)
        let james = Person(name: "James T.", ring: .core, cadence: .weekly)
        james.isDummyData = true
        james.lastContactedAt = cal.date(byAdding: .day, value: -10, to: now)!
        context.insert(james)

        let j1 = CheckIn(person: james, kind: .message, contactedAt: cal.date(byAdding: .day, value: -10, to: now)!, note: "Shared an article")
        context.insert(j1)

        let jRole = CareerRole(person: james, title: "Product Manager", company: "Acme Corp", startYear: 2023, isCurrent: true)
        context.insert(jRole)

        // MARK: - Emily R. (close, wilting, 2 check-ins)
        let emily = Person(name: "Emily R.", ring: .close, cadence: .weekly)
        emily.isDummyData = true
        emily.lastContactedAt = cal.date(byAdding: .day, value: -5, to: now)!
        context.insert(emily)

        let e1 = CheckIn(person: emily, kind: .message, contactedAt: cal.date(byAdding: .day, value: -5, to: now)!, note: "Happy birthday message")
        let e2 = CheckIn(person: emily, kind: .call, contactedAt: cal.date(byAdding: .day, value: -12, to: now)!, note: "Planned a get-together")
        context.insert(e1)
        context.insert(e2)

        // MARK: - David K. (close, thriving, 1 check-in)
        let david = Person(name: "David K.", ring: .close, cadence: .fortnightly)
        david.isDummyData = true
        david.lastContactedAt = cal.date(byAdding: .day, value: -2, to: now)!
        context.insert(david)

        let d1 = CheckIn(person: david, kind: .inPerson, contactedAt: cal.date(byAdding: .day, value: -2, to: now)!, note: "Lunch catch-up")
        context.insert(d1)

        // MARK: - Priya S. (active, withering, 0 check-ins)
        let priya = Person(name: "Priya S.", ring: .active, cadence: .monthly)
        priya.isDummyData = true
        priya.lastContactedAt = cal.date(byAdding: .day, value: -35, to: now)!
        context.insert(priya)

        // MARK: - Chris W. (meaningful, thriving, 1 check-in)
        let chris = Person(name: "Chris W.", ring: .meaningful, cadence: .quarterly)
        chris.isDummyData = true
        chris.lastContactedAt = cal.date(byAdding: .day, value: -15, to: now)!
        context.insert(chris)

        let c1 = CheckIn(person: chris, kind: .message, contactedAt: cal.date(byAdding: .day, value: -15, to: now)!, note: "Congratulated on the new job")
        context.insert(c1)

        try? context.save()
    }

    static func removeDummyData(context: ModelContext) {
        let descriptor = FetchDescriptor<Person>(
            predicate: #Predicate<Person> { $0.isDummyData }
        )
        guard let dummies = try? context.fetch(descriptor) else { return }
        for person in dummies {
            context.delete(person)
        }
        try? context.save()
    }

    static func hasDummyData(context: ModelContext) -> Bool {
        let descriptor = FetchDescriptor<Person>(
            predicate: #Predicate<Person> { $0.isDummyData }
        )
        let count = (try? context.fetchCount(descriptor)) ?? 0
        return count > 0
    }
}
