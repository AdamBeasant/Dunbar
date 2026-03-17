import SwiftUI
import SwiftData

struct NudgeListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(NudgeScheduler.self) private var nudgeScheduler
    @Environment(HapticFeedbackService.self) private var haptics
    let onSettingsTap: () -> Void

    @Query(
        filter: #Predicate<Person> { !$0.isArchived },
        sort: [SortDescriptor(\Person.lastContactedAt, order: .forward)]
    ) private var allPeople: [Person]

    @Query(sort: [SortDescriptor(\CheckIn.contactedAt, order: .reverse)])
    private var allCheckIns: [CheckIn]

    @State private var expandedPersonKeys: Set<String> = []
    @State private var selectedNotePerson: Person?
    @State private var selectedSnoozePerson: Person?

    private var overduePeople: [Person] {
        allPeople
            .filter { $0.healthState == .withering }
            .filter { ($0.snoozedUntilAt ?? .distantPast) <= .now }
            .sorted(by: nudgeComparator)
    }

    private var dueSoonPeople: [Person] {
        allPeople
            .filter { $0.healthState == .wilting }
            .filter { ($0.snoozedUntilAt ?? .distantPast) <= .now }
            .sorted(by: nudgeComparator)
    }

    private var queueRows: [NudgeQueueRow] {
        var rows: [NudgeQueueRow] = []

        if !overduePeople.isEmpty {
            rows.append(.marker(title: "Overdue", color: DunbarTheme.red))
            rows.append(contentsOf: overduePeople.map { .person($0, group: .overdue) })
        }

        if !dueSoonPeople.isEmpty {
            rows.append(.marker(title: "Due soon", color: DunbarTheme.lime))
            rows.append(contentsOf: dueSoonPeople.map { .person($0, group: .dueSoon) })
        }

        return rows
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Nudges")
                    .font(DunbarTheme.titleFont)
                    .foregroundStyle(DunbarTheme.textPrimary)

                Text(overduePeople.isEmpty
                     ? (dueSoonPeople.isEmpty ? "Your relationships are on track" : "Inbox for today and upcoming nudges")
                     : "Inbox for relationships that need attention")
                    .font(DunbarTheme.subtitleFont)
                    .foregroundStyle(DunbarTheme.textSecondary)
            }
            .padding(.horizontal, 20)
            .padding(.top, -36)
            .padding(.bottom, 16)

            if queueRows.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(queueRows) { row in
                        switch row {
                        case .marker(let title, let color):
                            markerRow(title: title, color: color)
                                .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 6, trailing: 20))
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)

                        case .person(let person, _):
                            inboxPersonRow(person)
                                .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 4, trailing: 20))
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button("Done") {
                                        haptics.impactMedium()
                                        selectedNotePerson = person
                                    }
                                    .tint(DunbarTheme.green)
                                }
                                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                    Button("Snooze") {
                                        haptics.impactLight()
                                        selectedSnoozePerson = person
                                    }
                                    .tint(DunbarTheme.ringColor(for: .core))
                                }
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(DunbarTheme.background)
            }
        }
        .background(DunbarTheme.background)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: onSettingsTap) {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(DunbarTheme.ringColor(for: .core))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Settings")
            }
        }
        .toolbarBackground(.hidden, for: .navigationBar)
        .sheet(item: $selectedNotePerson) { person in
            CheckInNoteSheet(personName: person.name) { note, kind in
                markAsDone(person, note: note, kind: kind)
            }
        }
        .confirmationDialog("Snooze reminder", isPresented: Binding(
            get: { selectedSnoozePerson != nil },
            set: { isPresented in
                if !isPresented { selectedSnoozePerson = nil }
            }
        )) {
            if let person = selectedSnoozePerson {
                ForEach(AppSettings.snoozePresets, id: \.self) { days in
                    Button(days == 1 ? "1 day" : "\(days) days") {
                        snooze(person, days: days)
                        selectedSnoozePerson = nil
                    }
                }
            }

            Button("Cancel", role: .cancel) {
                selectedSnoozePerson = nil
            }
        }
        .onAppear {
            AppSettings.clearExpiredSmartCadenceDismissals()
        }
    }

    private func markerRow(title: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)

            Text(title.uppercased())
                .font(DunbarTheme.eyebrowFont)
                .tracking(1)
                .foregroundStyle(DunbarTheme.textTertiary)

            Spacer()
        }
    }

    private func inboxPersonRow(_ person: Person) -> some View {
        let key = personKey(for: person)
        let isExpanded = expandedPersonKeys.contains(key)
        let recommendation = cadenceRecommendation(for: person)

        return VStack(alignment: .leading, spacing: 8) {
            PersonCard(person: person)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        if isExpanded {
                            expandedPersonKeys.remove(key)
                        } else {
                            expandedPersonKeys.insert(key)
                        }
                    }
                    haptics.impactLight()
                }

            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    prepLine(title: "Last note", value: latestNote(for: person) ?? "No note yet")

                    if let role = person.currentCareerRole {
                        prepLine(title: "Work", value: "\(role.title) · \(role.company)")
                    }

                    let family = familySummary(for: person)
                    if !family.isEmpty {
                        prepLine(title: "Family", value: family)
                    }

                    if let recommendation {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Suggested cadence")
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                                    .foregroundStyle(DunbarTheme.textTertiary)

                                Spacer()

                                Text(recommendation.confidence.label)
                                    .font(.system(size: 10, weight: .bold, design: .rounded))
                                    .foregroundStyle(DunbarTheme.ringColor(for: .core))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(DunbarTheme.ringColor(for: .core).opacity(0.12), in: Capsule())
                            }

                            Text("\(recommendation.currentCadence.label) → \(recommendation.recommendedCadence.label)")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(DunbarTheme.textPrimary)

                            Text(recommendation.detail)
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(DunbarTheme.textSecondary)

                            HStack(spacing: 8) {
                                Button("Apply") {
                                    apply(recommendation: recommendation)
                                }
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(DunbarTheme.ringColor(for: .core), in: Capsule())

                                Button("Dismiss") {
                                    dismiss(recommendation: recommendation)
                                }
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(DunbarTheme.textSecondary)
                            }
                        }
                        .padding(.top, 2)
                    }

                    NavigationLink {
                        PersonDetailView(person: person)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "person.text.rectangle")
                            Text("Open profile")
                        }
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(DunbarTheme.ringColor(for: .core))
                    }
                    .buttonStyle(.plain)
                }
                .padding(12)
                .background(DunbarTheme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(DunbarTheme.border, lineWidth: 1)
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func prepLine(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .tracking(0.8)
                .foregroundStyle(DunbarTheme.textTertiary)

            Text(value)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(DunbarTheme.textPrimary)
                .lineLimit(2)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(DunbarTheme.green.opacity(0.5))

            Text("No overdue contacts right now.\nYou're keeping great momentum.")
                .font(.system(size: 16))
                .foregroundStyle(DunbarTheme.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 60)
    }

    private func latestNote(for person: Person) -> String? {
        allCheckIns.first(where: {
            $0.person?.persistentModelID == person.persistentModelID && !$0.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        })?.note
    }

    private func familySummary(for person: Person) -> String {
        if let component = FamilyGraphV2Service.component(for: person) {
            let graphFamily = component.nodes
                .filter { $0.stableID != component.anchor.stableID }
                .prefix(2)
                .map(\.displayName)

            if !graphFamily.isEmpty {
                return graphFamily.joined(separator: " · ")
            }
        }

        return person.sortedFamilyMembers
            .prefix(2)
            .map { $0.name }
            .joined(separator: " · ")
    }

    private func cadenceRecommendation(for person: Person) -> SmartCadenceRecommendation? {
        let key = personKey(for: person)
        guard !AppSettings.isSmartCadenceDismissed(personKey: key) else {
            return nil
        }

        return CadenceRecommendationService.recommendation(for: person, checkIns: allCheckIns)
    }

    private func apply(recommendation: SmartCadenceRecommendation) {
        recommendation.person.cadence = recommendation.recommendedCadence
        AppSettings.clearSmartCadenceDismissal(personKey: personKey(for: recommendation.person))
        haptics.success()

        Task {
            await nudgeScheduler.schedule(for: recommendation.person)
            WidgetSnapshotStore.write(WidgetSnapshotStore.buildSnapshot(people: allPeople))
        }
    }

    private func dismiss(recommendation: SmartCadenceRecommendation) {
        let until = Calendar.current.date(byAdding: .day, value: 14, to: .now) ?? .now
        AppSettings.dismissSmartCadence(personKey: personKey(for: recommendation.person), until: until)
        haptics.impactLight()
    }

    private func markAsDone(_ person: Person, note: String, kind: CheckInType) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
            person.markAsContacted(note: note, kind: kind, context: modelContext)
        }
        haptics.success()

        Task {
            await nudgeScheduler.schedule(for: person)
            WidgetSnapshotStore.write(WidgetSnapshotStore.buildSnapshot(people: allPeople))
        }
    }

    private func snooze(_ person: Person, days: Int) {
        haptics.impactLight()
        Task {
            await nudgeScheduler.snooze(person, byDays: days)
            WidgetSnapshotStore.write(WidgetSnapshotStore.buildSnapshot(people: allPeople))
        }
    }

    private func personKey(for person: Person) -> String {
        person.stableID.uuidString
    }

    private func nudgeComparator(_ a: Person, _ b: Person) -> Bool {
        if a.isPinned != b.isPinned {
            return a.isPinned && !b.isPinned
        }
        return a.daysSinceContact > b.daysSinceContact
    }
}

extension NudgeListView {
    init(onSettingsTap: @escaping () -> Void = {}) {
        self.onSettingsTap = onSettingsTap
    }
}

private enum NudgeQueueGroup {
    case overdue
    case dueSoon
}

private enum NudgeQueueRow: Identifiable {
    case marker(title: String, color: Color)
    case person(Person, group: NudgeQueueGroup)

    var id: String {
        switch self {
        case .marker(let title, _):
            return "marker-\(title)"
        case .person(let person, _):
            return "person-\(person.persistentModelID)"
        }
    }
}

#Preview {
    NavigationStack {
        NudgeListView()
    }
    .modelContainer(for: [Person.self, CheckIn.self, CareerRole.self, FamilyMember.self, FamilyPerson.self, FamilyRelationship.self, FamilyGraphV2.self, FamilyNodeV2.self, FamilyEdgeV2.self], inMemory: true)
    .environment(NudgeScheduler())
    .environment(HapticFeedbackService())
}
