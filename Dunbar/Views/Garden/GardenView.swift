import SwiftUI
import SwiftData

struct GardenView: View {
    @Environment(NudgeScheduler.self) private var nudgeScheduler
    @Environment(HapticFeedbackService.self) private var hapticFeedback
    @Binding var navigationPath: NavigationPath
    let onSettingsTap: () -> Void

    @Query(
        filter: #Predicate<Person> { !$0.isArchived },
        sort: [SortDescriptor(\Person.lastContactedAt, order: .forward)]
    ) private var people: [Person]

    @Query(sort: [SortDescriptor(\CheckIn.contactedAt, order: .reverse)])
    private var allCheckIns: [CheckIn]

    @State private var selectedFilter: RingFilter = .all
    @State private var searchText = ""
    @State private var deferredSuggestionIDs: Set<String> = []
    @State private var showingRebalanceSheet = false
    @State private var pullRevealProgress: CGFloat = 0
    @State private var pullBaseline: CGFloat?
    @State private var searchBarVisible = false
    @AppStorage(AppSettings.ringMotionIntensityKey) private var ringMotionIntensityRaw = RingMotionIntensity.low.rawValue
    @FocusState private var searchFocused: Bool

    private var sortedPeople: [Person] {
        people.sorted(by: Person.urgencyComparator)
    }

    private var visiblePeople: [Person] {
        let byFilter: [Person]
        if let ring = selectedFilter.ring {
            byFilter = sortedPeople.filter { $0.ring == ring }
        } else {
            byFilter = sortedPeople
        }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return byFilter }

        let lowered = query.lowercased()
        return byFilter.filter {
            $0.name.lowercased().contains(lowered) ||
            $0.notes.lowercased().contains(lowered)
        }
    }

    private var overduePeopleCount: Int {
        people.filter { $0.healthState == .withering }.count
    }
    
    private var ringHealthSnapshot: RingHealthScoreSnapshot {
        RingHealthScoreService.snapshot(people: people)
    }

    private var rebalanceSuggestions: [DunbarRebalanceSuggestion] {
        DunbarRebalanceAdvisor.suggestions(
            people: people,
            checkIns: allCheckIns
        )
        .filter { !deferredSuggestionIDs.contains($0.id) }
    }
    
    private var shouldShowFloatingSearch: Bool {
        searchBarVisible || searchFocused || !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                header
                ringsCard

                if !rebalanceSuggestions.isEmpty || !deferredSuggestionIDs.isEmpty {
                    rebalanceSummaryCard
                }

                peopleSection
            }
            .padding(.horizontal, 20)
            .padding(.top, -36)
            .padding(.bottom, 28)
            .background(alignment: .top) {
                GeometryReader { proxy in
                    Color.clear
                        .preference(
                            key: PullToSearchOffsetKey.self,
                            value: proxy.frame(in: .named("garden-scroll")).minY
                        )
                }
                .frame(height: 0)
            }
        }
        .coordinateSpace(name: "garden-scroll")
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
        .navigationDestination(for: Person.self) { person in
            PersonDetailView(person: person)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if shouldShowFloatingSearch {
                floatingSearchBar
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .sheet(isPresented: $showingRebalanceSheet, onDismiss: {
            reloadDeferredSuggestionIDs()
        }) {
            NavigationStack {
                RebalanceView()
            }
        }
        .refreshable {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                searchBarVisible = true
            }
        }
        .onPreferenceChange(PullToSearchOffsetKey.self) { offset in
            if pullBaseline == nil {
                pullBaseline = offset
            }
            
            let baseline = pullBaseline ?? offset
            let pullDistance = max(offset - baseline, 0)
            pullRevealProgress = min(pullDistance / 74, 1)
            
            guard !searchFocused && searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return
            }
            
            if pullDistance > 20, !searchBarVisible {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                    searchBarVisible = true
                }
            } else if pullDistance < 6, searchBarVisible {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                    searchBarVisible = false
                }
            }
        }
        .onChange(of: searchFocused) { _, isFocused in
            if isFocused {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                    searchBarVisible = true
                }
            } else if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && pullRevealProgress < 0.3 {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                    searchBarVisible = false
                }
            }
        }
        .onAppear {
            reloadDeferredSuggestionIDs()
            syncRingHealthMilestoneHaptic()
        }
        .onChange(of: ringHealthSnapshot.totalScore) { _, _ in
            syncRingHealthMilestoneHaptic()
        }
    }
    
    private var floatingSearchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(DunbarTheme.textSecondary)
            
            TextField("Search people", text: $searchText)
                .focused($searchFocused)
                .textInputAutocapitalization(.words)
                .disableAutocorrection(true)
                .font(.system(size: 17, weight: .medium, design: .rounded))
                .foregroundStyle(DunbarTheme.textPrimary)
                .submitLabel(.search)
            
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(DunbarTheme.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(
            Capsule()
                .strokeBorder(.white.opacity(0.42), lineWidth: 0.9)
        )
        .shadow(color: .black.opacity(0.16), radius: 12, y: 6)
        .onTapGesture {
            searchFocused = true
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Dunbar")
                .font(DunbarTheme.titleFont)
                .foregroundStyle(DunbarTheme.textPrimary)

            Text(headerSubtitle)
                .font(DunbarTheme.subtitleFont)
                .foregroundStyle(overduePeopleCount > 0 ? DunbarTheme.red.opacity(0.9) : DunbarTheme.green.opacity(0.92))
            
            Button {
                showingRebalanceSheet = true
            } label: {
                Label("Rebalance", systemImage: "arrow.triangle.2.circlepath")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(DunbarTheme.surfaceMuted)
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .strokeBorder(DunbarTheme.borderStrong, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityHint("Shows suggestions for moving contacts between circles")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var ringsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            RingMapView(
                people: sortedPeople,
                selectedRing: selectedFilter.ring,
                motionIntensity: RingMotionIntensity(rawValue: ringMotionIntensityRaw) ?? .low,
                onSelectRing: { ring in
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedFilter = RingFilter.from(ring: ring)
                    }
                },
                onPersonTap: { person in
                    navigationPath.append(person)
                }
            )

            ringFilterRow

            Text("Tap a circle to focus, or tap a dot to open contact")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(DunbarTheme.textTertiary.opacity(0.9))
                .frame(maxWidth: .infinity, alignment: .center)
                .multilineTextAlignment(.center)
        }
    }
    
    private var ringFilterRow: some View {
        ViewThatFits(in: .horizontal) {
            ringFilterChips
                .frame(maxWidth: .infinity, alignment: .center)
            
            ScrollView(.horizontal, showsIndicators: false) {
                ringFilterChips
                    .padding(.horizontal, 2)
            }
        }
    }
    
    private var ringFilterChips: some View {
        HStack(spacing: 8) {
            ringFilterChip(filter: .all, badge: nil)
            
            ForEach(DunbarRing.allCases) { ring in
                ringFilterChip(
                    filter: RingFilter.from(ring: ring),
                    badge: overdueCount(for: ring)
                )
            }
        }
    }

    private func ringFilterChip(filter: RingFilter, badge: Int?) -> some View {
        let isSelected = selectedFilter == filter
        let tint: Color = filter.ring.map { DunbarTheme.ringColor(for: $0) } ?? DunbarTheme.ringColor(for: .core)
        let filterCount: Int = {
            if let ring = filter.ring {
                return people.filter { $0.ring == ring }.count
            }
            return people.count
        }()

        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedFilter = isSelected && filter != .all ? .all : filter
            }
        } label: {
            HStack(spacing: 6) {
                Text(filter.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isSelected ? tint : DunbarTheme.textSecondary)

                if let badge, badge > 0 {
                    Text("\(badge)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(DunbarTheme.red)
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isSelected ? tint.opacity(0.16) : DunbarTheme.surface)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(
                        isSelected ? tint.opacity(0.36) : DunbarTheme.border.opacity(0.8),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(filter.title) filter, \(filterCount) contacts")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var peopleSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(selectedFilter.title) \u{00B7} \(visiblePeople.count)")
                    .font(DunbarTheme.eyebrowFont)
                    .tracking(1)
                    .foregroundStyle(DunbarTheme.textSecondary.opacity(0.86))

                Spacer()

                Text("By urgency")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(DunbarTheme.textTertiary)
            }

            if visiblePeople.isEmpty {
                emptyState
            } else {
                VStack(spacing: 8) {
                    ForEach(visiblePeople) { person in
                        PersonCard(person: person, onTap: {
                            navigationPath.append(person)
                        })
                    }
                }
            }
        }
    }

    private var rebalanceSummaryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Rebalance")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DunbarTheme.textSecondary)

                Spacer()

                Button("Open") {
                    showingRebalanceSheet = true
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DunbarTheme.ringColor(for: .core))
            }

            if rebalanceSuggestions.isEmpty {
                Text(deferredSuggestionIDs.isEmpty
                     ? "No circle shifts suggested this week."
                     : "No active shifts right now. \(deferredSuggestionIDs.count) deferred.")
                    .font(.system(size: 13))
                    .foregroundStyle(DunbarTheme.textSecondary)
            } else {
                ForEach(Array(rebalanceSuggestions.prefix(2).enumerated()), id: \.element.id) { index, suggestion in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(suggestion.person.name)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(DunbarTheme.textPrimary)

                            Spacer()

                            Text("\(suggestion.person.ring.label) \u{2192} \(suggestion.targetRing.label)")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(DunbarTheme.textSecondary)
                        }

                        Text(suggestion.reason)
                            .font(.system(size: 12))
                            .foregroundStyle(DunbarTheme.textSecondary)

                        HStack(spacing: 8) {
                            Button(suggestion.actionLabel) {
                                apply(suggestion)
                            }
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(DunbarTheme.background)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(DunbarTheme.ringColor(for: .core))
                            .clipShape(Capsule())

                            Button("Later") {
                                deferSuggestion(suggestion)
                            }
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(DunbarTheme.textSecondary)
                        }
                    }

                    if index == 0 && rebalanceSuggestions.count > 1 {
                        Divider()
                            .foregroundStyle(DunbarTheme.border)
                    }
                }
            }
        }
        .dunbarCard()
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Text("No contacts in this circle")
                .font(.system(size: 19, weight: .semibold, design: .rounded))
                .foregroundStyle(DunbarTheme.textPrimary)
                .multilineTextAlignment(.center)

            Text("Try another circle or add a contact.")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(DunbarTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 8)
        .padding(.vertical, 30)
        .dunbarCard()
    }

    private var headerSubtitle: String {
        if overduePeopleCount > 0 {
            return "\(overduePeopleCount) \(overduePeopleCount == 1 ? "person" : "people") waiting to hear from you"
        }
        return "All circles looking healthy"
    }

    private func overdueCount(for ring: DunbarRing) -> Int {
        people.filter { $0.ring == ring && $0.healthState == .withering }.count
    }

    private func apply(_ suggestion: DunbarRebalanceSuggestion) {
        withAnimation(.easeInOut(duration: 0.18)) {
            let entry = DunbarRebalanceAdvisor.apply(suggestion)
            AppSettings.appendRebalanceHistory(entry)
            AppSettings.clearRebalanceSuggestionDeferral(id: suggestion.id)
            deferredSuggestionIDs.remove(suggestion.id)
        }

        Task {
            await nudgeScheduler.schedule(for: suggestion.person)
        }
    }

    private func deferSuggestion(_ suggestion: DunbarRebalanceSuggestion) {
        let deferredUntil = Calendar.current.date(byAdding: .day, value: 7, to: .now) ?? .now
        AppSettings.deferRebalanceSuggestion(id: suggestion.id, until: deferredUntil)
        deferredSuggestionIDs.insert(suggestion.id)

        let history = DunbarRebalanceHistoryEntry(
            personName: suggestion.person.name,
            fromRingRaw: suggestion.person.ring.rawValue,
            toRingRaw: suggestion.targetRing.rawValue,
            directionRaw: suggestion.direction.label,
            outcomeRaw: DunbarRebalanceHistoryOutcome.deferred.rawValue,
            reason: suggestion.reason,
            recordedAt: .now,
            deferredUntilAt: deferredUntil
        )
        AppSettings.appendRebalanceHistory(history)
    }

    private func reloadDeferredSuggestionIDs() {
        deferredSuggestionIDs = AppSettings.deferredRebalanceSuggestionIDs()
    }
    
    private func syncRingHealthMilestoneHaptic() {
        let band = RingHealthScoreService.band(for: ringHealthSnapshot.totalScore)
        let previousBand = AppSettings.lastRingHealthBand
        
        if previousBand >= 0, band > previousBand {
            hapticFeedback.success()
        }
        
        AppSettings.lastRingHealthBand = band
    }
}

private struct PullToSearchOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private enum RingFilter: String, CaseIterable, Identifiable {
    case all
    case core
    case close
    case active
    case meaningful

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .core: return "Inner"
        case .close: return "Close"
        case .active: return "Wider"
        case .meaningful: return "Outer"
        }
    }

    var ring: DunbarRing? {
        switch self {
        case .all: return nil
        case .core: return .core
        case .close: return .close
        case .active: return .active
        case .meaningful: return .meaningful
        }
    }

    static func from(ring: DunbarRing?) -> RingFilter {
        switch ring {
        case .none: return .all
        case .some(.core): return .core
        case .some(.close): return .close
        case .some(.active): return .active
        case .some(.meaningful): return .meaningful
        }
    }
}

private struct RingMapView: View {
    let people: [Person]
    let selectedRing: DunbarRing?
    let motionIntensity: RingMotionIntensity
    let onSelectRing: (DunbarRing?) -> Void
    let onPersonTap: (Person) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let size: CGFloat = 308
    private let radii: [CGFloat] = [52, 86, 120, 154]

    var body: some View {
        let center = size / 2

        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { timeline in
            let elapsed = timeline.date.timeIntervalSinceReferenceDate

            ZStack {
                // Layer 1: ring strokes
                ForEach(Array(DunbarRing.allCases.enumerated()), id: \.element.rawValue) { index, ring in
                    let ringRotation = rotationAngle(for: index, elapsed: elapsed)
                    Button {
                        onSelectRing(selectedRing == ring ? nil : ring)
                    } label: {
                        Circle()
                            .stroke(
                                strokeColor(for: ring),
                                style: StrokeStyle(lineWidth: selectedRing == ring ? 2 : 1)
                            )
                            .frame(width: radii[index] * 2, height: radii[index] * 2)
                    }
                    .buttonStyle(.plain)
                    .rotationEffect(.degrees(ringRotation))
                }

                // Layer 2: dots/chips above ring lines
                ForEach(Array(DunbarRing.allCases.enumerated()), id: \.element.rawValue) { index, ring in
                    let ringRotation = rotationAngle(for: index, elapsed: elapsed)
                    let ringPeople = people.filter { $0.ring == ring }
                    ZStack {
                        ForEach(Array(ringPeople.enumerated()), id: \.offset) { personIndex, person in
                            RingMapDot(person: person, ringRotationDegrees: ringRotation) {
                                onPersonTap(person)
                            }
                            .position(point(for: personIndex, total: ringPeople.count, radius: radii[index], center: center))
                        }
                    }
                    .frame(width: size, height: size)
                    .rotationEffect(.degrees(ringRotation))
                }

                Circle()
                    .fill(DunbarTheme.ringColor(for: .core).opacity(0.1))
                    .frame(width: 42, height: 42)
                    .overlay(
                        Circle()
                            .strokeBorder(DunbarTheme.ringColor(for: .core).opacity(0.35), lineWidth: 1)
                    )

                Text("\(people.count)")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(DunbarTheme.ringColor(for: .core))
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Circle map showing \(people.count) contacts")
        .frame(maxWidth: .infinity)
        .padding(.top, 2)
        .padding(.bottom, 2)
    }

    private func point(for index: Int, total: Int, radius: CGFloat, center: CGFloat) -> CGPoint {
        let count = max(total, 1)
        let angle = (Double(index) / Double(count)) * (.pi * 2) - (.pi / 2)
        let x = center + CGFloat(Darwin.cos(angle)) * radius
        let y = center + CGFloat(Darwin.sin(angle)) * radius

        return CGPoint(
            x: x,
            y: y
        )
    }

    private func strokeColor(for ring: DunbarRing) -> Color {
        if let selectedRing {
            return selectedRing == ring
                ? DunbarTheme.ringColor(for: ring).opacity(0.92)
                : DunbarTheme.border.opacity(0.4)
        }

        return DunbarTheme.ringColor(for: ring).opacity(0.22)
    }
    
    private func rotationAngle(for index: Int, elapsed: TimeInterval) -> Double {
        guard motionIntensity != .off else { return 0 }
        
        let rotationDuration: TimeInterval = {
            switch motionIntensity {
            case .off: return 1
            case .low: return 260
            case .normal: return 160
            }
        }()
        
        let direction = index.isMultiple(of: 2) ? 1.0 : -1.0
        let normalizedProgress = (elapsed.truncatingRemainder(dividingBy: rotationDuration)) / rotationDuration
        return normalizedProgress * 360 * direction
    }
}

private struct RingMapDot: View {
    let person: Person
    let ringRotationDegrees: Double
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false
    @State private var showingName = false

    private var statusColor: Color {
        DunbarTheme.color(for: person.healthState)
    }
    
    private var tooltipOffset: CGSize {
        let distance: CGFloat = 30
        let radians = ringRotationDegrees * .pi / 180
        return CGSize(
            width: -CGFloat(Darwin.sin(radians)) * distance,
            height: -CGFloat(Darwin.cos(radians)) * distance
        )
    }

    var body: some View {
        ZStack {
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.94))
                    .frame(width: person.healthState == .withering ? 13 : 10, height: person.healthState == .withering ? 13 : 10)

                if person.healthState == .withering {
                    Circle()
                        .stroke(statusColor.opacity(0.55), lineWidth: 1)
                        .frame(width: 17, height: 17)
                        .scaleEffect(pulse ? 1.35 : 1.0)
                        .opacity(pulse ? 0 : 1)
                        .animation(reduceMotion ? .none : .easeOut(duration: 1.8).repeatForever(autoreverses: false), value: pulse)
                }
            }
            
            if showingName {
                Text(person.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DunbarTheme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(minWidth: 72)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(DunbarTheme.surface)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(DunbarTheme.border, lineWidth: 1)
                    )
                    .offset(tooltipOffset)
                    .rotationEffect(.degrees(-ringRotationDegrees))
                    .transition(.opacity.combined(with: .scale(scale: 0.94)))
                    .zIndex(200)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(person.name), \(person.ring.label) circle, \(person.healthState.label)")
        .accessibilityHint("Double tap to view contact. Long press to show name.")
        .zIndex(showingName ? 100 : 1)
        .contentShape(Rectangle())
        .onTapGesture {
            action()
        }
        .onLongPressGesture(
            minimumDuration: 0.28,
            maximumDistance: 22,
            pressing: { pressing in
                withAnimation(.easeOut(duration: 0.16)) {
                    showingName = pressing
                }
            },
            perform: {}
        )
        .onAppear {
            if person.healthState == .withering && !reduceMotion {
                pulse = true
            }
        }
    }
}

#Preview {
    NavigationStack {
        GardenView(
            navigationPath: .constant(NavigationPath()),
            onSettingsTap: {}
        )
    }
    .modelContainer(for: [Person.self, CheckIn.self, CareerRole.self, FamilyMember.self, FamilyPerson.self, FamilyRelationship.self, FamilyGraphV2.self, FamilyNodeV2.self, FamilyEdgeV2.self], inMemory: true)
    .environment(NudgeScheduler())
    .environment(HapticFeedbackService())
}
