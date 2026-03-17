import SwiftUI
import SwiftData

struct HistoryView: View {
    @Query(filter: #Predicate<Person> { !$0.isArchived })
    private var people: [Person]
    @Query(sort: [SortDescriptor(\CheckIn.contactedAt, order: .reverse)])
    private var allCheckIns: [CheckIn]
    @State private var selectedSection: TopSection = .rhythm
    let onSettingsTap: () -> Void

    private var weeklyCounts: [Int] {
        let calendar = Calendar.current
        let now = Date.now
        guard let currentWeek = calendar.dateInterval(of: .weekOfYear, for: now) else {
            return Array(repeating: 0, count: 12)
        }

        return (0..<12).map { offset in
            let shift = 11 - offset
            guard let weekStart = calendar.date(byAdding: .day, value: -(shift * 7), to: currentWeek.start),
                  let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart)
            else {
                return 0
            }

            return allCheckIns.filter {
                $0.contactedAt >= weekStart && $0.contactedAt < weekEnd
            }.count
        }
    }

    private var maxWeeklyCount: Int {
        max(weeklyCounts.max() ?? 0, 1)
    }

    private var ringHealthSnapshot: RingHealthScoreSnapshot {
        RingHealthScoreService.snapshot(people: people)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                sectionPicker
                sectionContent
            }
            .padding(.horizontal, 20)
            .padding(.top, -36)
            .padding(.bottom, 28)
        }
        .background(DunbarTheme.background)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: onSettingsTap) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(DunbarTheme.ringColor(for: .core))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Settings")
            }
        }
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Rhythm")
                .font(DunbarTheme.titleFont)
                .foregroundStyle(DunbarTheme.textPrimary)

            Text(selectedSection.subtitle)
                .font(DunbarTheme.subtitleFont)
                .foregroundStyle(DunbarTheme.textSecondary)
        }
    }

    private var sectionPicker: some View {
        Picker("Rhythm section", selection: $selectedSection) {
            ForEach(TopSection.allCases) { section in
                Text(section.title)
                    .tag(section)
            }
        }
        .pickerStyle(.segmented)
    }

    @ViewBuilder
    private var sectionContent: some View {
        switch selectedSection {
        case .rhythm:
            if allCheckIns.isEmpty {
                emptyState
            } else {
                rhythmCard
                timelineCard
            }
        case .ringHealth:
            if people.isEmpty {
                ringHealthEmptyState
            } else {
                ringHealthCard
                ringHealthStatusCard
            }
        }
    }

    private var rhythmCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("WEEKLY MOMENTUM")
                .font(DunbarTheme.eyebrowFont)
                .tracking(1)
                .foregroundStyle(DunbarTheme.textTertiary)

            HStack(alignment: .bottom, spacing: 6) {
                ForEach(Array(weeklyCounts.enumerated()), id: \.offset) { index, count in
                    let height = max((CGFloat(count) / CGFloat(maxWeeklyCount)) * 68, 4)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(index == weeklyCounts.count - 1
                              ? DunbarTheme.ringColor(for: .core)
                              : DunbarTheme.textSecondary.opacity(0.15 + (Double(count) / Double(maxWeeklyCount)) * 0.35))
                        .frame(maxWidth: .infinity)
                        .frame(height: height)
                }
            }
            .frame(height: 72)

            HStack {
                Text("12w ago")
                Spacer()
                Text("This week")
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(DunbarTheme.textTertiary)
        }
        .dunbarCard()
    }

    private var timelineCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("RECENT CHECK-INS")
                .font(DunbarTheme.eyebrowFont)
                .tracking(1)
                .foregroundStyle(DunbarTheme.textTertiary)

            ForEach(Array(allCheckIns.prefix(40).enumerated()), id: \.element.id) { index, checkIn in
                HStack(spacing: 12) {
                    Circle()
                        .fill(color(for: checkIn.person?.healthState ?? .thriving).opacity(0.9))
                        .frame(width: 8, height: 8)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(checkIn.person?.name ?? "Unknown")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(DunbarTheme.textPrimary)

                        Text(checkIn.contactedAt.formatted(.dateTime.day().month(.abbreviated).hour().minute()))
                            .font(.system(size: 12))
                            .foregroundStyle(DunbarTheme.textSecondary)
                    }

                    Spacer()

                    Label(checkIn.kind.label, systemImage: checkIn.kind.symbolName)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(DunbarTheme.ringColor(for: checkIn.person?.ring ?? .close))
                }

                if !checkIn.note.isEmpty {
                    Text("\"\(checkIn.note)\"")
                        .font(.system(size: 12).italic())
                        .foregroundStyle(DunbarTheme.textSecondary)
                        .padding(.leading, 20)
                }

                if index < min(allCheckIns.count - 1, 39) {
                    Divider()
                        .foregroundStyle(DunbarTheme.border)
                }
            }
        }
        .dunbarCard()
    }
    
    private var ringHealthCard: some View {
        let snapshot = ringHealthSnapshot

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Circle Health")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(DunbarTheme.textSecondary)
                Spacer()
                Text("\(snapshot.totalScore)")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(DunbarTheme.ringColor(for: .core))
                Text("/100")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(DunbarTheme.textTertiary)
            }

            ForEach(DunbarRing.allCases) { ring in
                let value = snapshot.perRingScores[ring] ?? 100
                VStack(spacing: 5) {
                    HStack {
                        Text(ring.label)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(DunbarTheme.textSecondary)
                        Spacer()
                        Text("\(value)")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(DunbarTheme.textTertiary)
                    }
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(DunbarTheme.border.opacity(0.6))
                            Capsule()
                                .fill(DunbarTheme.ringColor(for: ring).opacity(0.86))
                                .frame(width: proxy.size.width * CGFloat(value) / 100)
                        }
                    }
                    .frame(height: 6)
                }
            }
        }
        .dunbarCard()
    }

    private var ringHealthStatusCard: some View {
        let snapshot = ringHealthSnapshot

        return VStack(alignment: .leading, spacing: 12) {
            Text("CONTACT STATES")
                .font(DunbarTheme.eyebrowFont)
                .tracking(1)
                .foregroundStyle(DunbarTheme.textTertiary)

            HStack(spacing: 10) {
                statusChip(
                    title: "Thriving",
                    count: snapshot.thrivingCount,
                    color: DunbarTheme.green.opacity(0.82)
                )
                statusChip(
                    title: "Due soon",
                    count: snapshot.dueSoonCount,
                    color: DunbarTheme.amber.opacity(0.88)
                )
                statusChip(
                    title: "Overdue",
                    count: snapshot.overdueCount,
                    color: DunbarTheme.red.opacity(0.9)
                )
            }
        }
        .dunbarCard()
    }

    private func statusChip(title: String, count: Int, color: Color) -> some View {
        VStack(spacing: 6) {
            Text("\(count)")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(color)
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(DunbarTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(DunbarTheme.surfaceMuted, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "chart.bar.fill")
                .font(.system(size: 32))
                .foregroundStyle(DunbarTheme.ringColor(for: .core).opacity(0.75))

            Text("No history yet")
                .font(.system(size: 19, weight: .semibold, design: .rounded))
                .foregroundStyle(DunbarTheme.textPrimary)
                .multilineTextAlignment(.center)

            Text("Your rhythm chart appears as you check in.")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(DunbarTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }

    private var ringHealthEmptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "heart.text.square.fill")
                .font(.system(size: 32))
                .foregroundStyle(DunbarTheme.ringColor(for: .core).opacity(0.75))

            Text("No circles yet")
                .font(.system(size: 19, weight: .semibold, design: .rounded))
                .foregroundStyle(DunbarTheme.textPrimary)
                .multilineTextAlignment(.center)

            Text("Add contacts to start tracking circle health.")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(DunbarTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }

    private func color(for state: HealthState) -> Color {
        DunbarTheme.color(for: state)
    }

    private enum TopSection: String, CaseIterable, Identifiable {
        case rhythm
        case ringHealth

        var id: String { rawValue }

        var title: String {
            switch self {
            case .rhythm:
                return "Rhythm"
            case .ringHealth:
                return "Circle Health"
            }
        }

        var subtitle: String {
            switch self {
            case .rhythm:
                return "Catch-ups per week, last 12 weeks"
            case .ringHealth:
                return "Health score and coverage by circle"
            }
        }
    }
}

extension HistoryView {
    init(onSettingsTap: @escaping () -> Void = {}) {
        self.onSettingsTap = onSettingsTap
    }
}

#Preview {
    HistoryView()
        .modelContainer(for: [Person.self, CheckIn.self, CareerRole.self, FamilyMember.self, FamilyPerson.self, FamilyRelationship.self, FamilyGraphV2.self, FamilyNodeV2.self, FamilyEdgeV2.self], inMemory: true)
}
