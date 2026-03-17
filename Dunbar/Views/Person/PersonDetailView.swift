import SwiftUI
import SwiftData
import PhotosUI

private enum PersonDetailTab: String, CaseIterable, Identifiable {
    case overview
    case context
    case history
    
    var id: String { rawValue }
    
    var title: String {
        switch self {
        case .overview: return "Overview"
        case .context: return "Context"
        case .history: return "History"
        }
    }
}

struct PersonDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(NudgeScheduler.self) private var nudgeScheduler
    @Environment(HapticFeedbackService.self) private var haptics
    
    @Bindable var person: Person
    
    @Query private var allCheckIns: [CheckIn]
    @Query(filter: #Predicate<Person> { !$0.isArchived }) private var allPeople: [Person]
    
    @State private var showingEditSheet = false
    @State private var showingDeleteAlert = false
    @State private var justMarked = false
    @State private var showingCheckInNotePrompt = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var selectedTab: PersonDetailTab = .overview
    @State private var isEditingContext = false
    @State private var showingFullFamilyTree = false
    @State private var showingAddRoleSheet = false
    @State private var showingAddFamilyConnectionSheet = false
    @State private var showingEditRoleSheet = false
    @State private var showingEditFamilyNodeSheet = false
    @State private var selectedLinkedContact: Person?
    @State private var editingRole: CareerRole?
    @State private var editingFamilyNode: FamilyNodeV2?
    @State private var previewTreeOffset: CGSize = .zero
    @GestureState private var previewTreeGestureOffset: CGSize = .zero
    
    private var checkIns: [CheckIn] {
        person.checkIns.sorted { $0.contactedAt > $1.contactedAt }
    }
    
    private var activeCadenceRecommendation: SmartCadenceRecommendation? {
        let key = person.stableID.uuidString
        guard !AppSettings.isSmartCadenceDismissed(personKey: key) else {
            return nil
        }
        return CadenceRecommendationService.recommendation(for: person, checkIns: allCheckIns)
    }
    
    private var currentRole: CareerRole? {
        person.currentCareerRole
    }
    
    private var familyMembers: [FamilyMember] {
        person.sortedFamilyMembers
    }

    private var familyComponent: FamilyComponent? {
        FamilyGraphV2Service.component(for: person)
    }
    
    private var hasLegacyFamilyData: Bool {
        !familyMembers.isEmpty
    }
    
    private var hasGraphFamilyData: Bool {
        guard let familyComponent else { return false }
        return familyComponent.nodes.contains { $0.stableID != familyComponent.anchor.stableID }
    }
    
    private var familySummaryRows: [(name: String, relation: String)] {
        if let familyComponent {
            return familyComponent.nodes
                .filter { $0.stableID != familyComponent.anchor.stableID }
                .map {
                    (
                        name: $0.displayName,
                        relation: $0.roleHint ?? "Family"
                    )
                }
        }
        
        return familyMembers.map { ($0.name, $0.relation) }
    }
    
    private var familyConnectionTargets: [FamilyConnectionTarget] {
        guard let familyComponent else {
            return []
        }

        return familyComponent.nodes.map {
            FamilyConnectionTarget(
                id: $0.stableID,
                name: $0.displayName,
                isPrimaryContact: $0.stableID == familyComponent.anchor.stableID
            )
        }
    }
    
    private var familyPartnerTargetMap: [UUID: [FamilyConnectionTarget]] {
        guard let familyComponent else { return [:] }
        let allTargets = familyConnectionTargets
        let targetByID = Dictionary(uniqueKeysWithValues: allTargets.map { ($0.id, $0) })
        var map: [UUID: [FamilyConnectionTarget]] = [:]
        
        for target in allTargets {
            let partnerIDs = FamilyGraphV2Service.partnerCandidates(
                for: target.id,
                in: familyComponent
            ).map(\.stableID)
            let partners = partnerIDs.compactMap { targetByID[$0] }
            if !partners.isEmpty {
                map[target.id] = partners
            }
        }
        
        return map
    }

    private var familyRelationshipRows: [FamilyRelationshipRow] {
        guard let familyComponent else { return [] }
        return familyComponent.edges.compactMap { edge in
            guard let fromName = edge.fromNode?.displayName,
                  let toName = edge.toNode?.displayName else {
                return nil
            }
            let relationshipText = edge.type.label.lowercased()
            return FamilyRelationshipRow(
                edge: edge,
                summary: "\(fromName) \(relationshipText) \(toName)"
            )
        }
    }

    private var linkableContacts: [Person] {
        let alreadyLinkedIDs = Set(
            (familyComponent?.nodes.compactMap { $0.linkedContact?.persistentModelID }) ?? []
        )
        return allPeople.filter { candidate in
            candidate.persistentModelID != person.persistentModelID &&
            !alreadyLinkedIDs.contains(candidate.persistentModelID)
        }
        .sorted(by: Person.urgencyComparator)
    }

    private var editableFamilyNodes: [FamilyNodeV2] {
        guard let familyComponent else { return [] }
        return familyComponent.nodes.filter {
            $0.stableID != familyComponent.anchor.stableID && $0.linkedContact == nil
        }
    }

    private var avatarInitials: String {
        if person.initials.isEmpty {
            return Person.makeInitials(from: person.name)
        }
        return person.initials
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                profileHeader
                statsRow.padding(.bottom, 14)
                doneButton.padding(.bottom, 18)
                tabSelector.padding(.bottom, 16)
                tabContent
                secondaryActions
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .background(DunbarTheme.background)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Edit") { showingEditSheet = true }
                    Button(person.isPinned ? "Unpin" : "Pin") {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            person.isPinned.toggle()
                        }
                    }
                    Button("Delete", role: .destructive) { showingDeleteAlert = true }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(DunbarTheme.ringColor(for: .core))
                }
                .buttonStyle(.plain)
            }
        }
        .sheet(isPresented: $showingEditSheet) {
            EditPersonView(person: person)
        }
        .sheet(isPresented: $showingCheckInNotePrompt) {
            CheckInNoteSheet(personName: person.name) { note, kind in
                markAsDone(note: note, kind: kind)
            }
        }
        .sheet(isPresented: $showingAddRoleSheet) {
            AddCareerRoleSheet { title, company, startYear, endYear, isCurrent in
                addCareerRole(
                    title: title,
                    company: company,
                    startYear: startYear,
                    endYear: endYear,
                    isCurrent: isCurrent
                )
            }
        }
        .sheet(isPresented: $showingAddFamilyConnectionSheet) {
            AddFamilyConnectionSheet(
                targets: familyConnectionTargets,
                defaultTargetID: familyComponent?.anchor.stableID,
                partnerTargetsByID: familyPartnerTargetMap,
                existingContactOptions: linkableContacts
            ) { name, age, targetID, relationKind, roleHint, coParentTargetID, existingContact in
                addFamilyConnection(
                    name: name,
                    age: age,
                    targetID: targetID,
                    relationKind: relationKind,
                    roleHint: roleHint,
                    coParentTargetID: coParentTargetID,
                    existingContact: existingContact
                )
            }
        }
        .sheet(isPresented: $showingEditRoleSheet) {
            if let role = editingRole {
                AddCareerRoleSheet(
                    initialTitle: role.title,
                    initialCompany: role.company,
                    initialStartYear: role.startYear,
                    initialEndYear: role.endYear,
                    initialIsCurrent: role.isCurrent,
                    saveLabel: "Update"
                ) { title, company, startYear, endYear, isCurrent in
                    updateCareerRole(
                        role,
                        title: title,
                        company: company,
                        startYear: startYear,
                        endYear: endYear,
                        isCurrent: isCurrent
                    )
                }
            }
        }
        .sheet(isPresented: $showingEditFamilyNodeSheet) {
            if let node = editingFamilyNode {
                AddFamilyMemberSheet(
                    initialName: node.name,
                    initialRelation: node.roleHint ?? "",
                    initialAge: node.age,
                    saveLabel: "Update"
                ) { name, relation, age in
                    updateFamilyNode(node, name: name, relation: relation, age: age)
                }
            }
        }
        .sheet(item: $selectedLinkedContact) { linkedPerson in
            NavigationStack {
                PersonDetailView(person: linkedPerson)
            }
        }
        .fullScreenCover(isPresented: $showingFullFamilyTree) {
            FamilyTreeFullScreenView(
                person: person
            )
        }
        .alert("Remove \(person.name)?", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Remove", role: .destructive) { deletePerson() }
        } message: {
            Text("This will remove \(person.name) from your contacts.")
        }
        .onChange(of: selectedPhoto) { _, newItem in
            Task {
                if let data = try? await newItem?.loadTransferable(type: Data.self) {
                    guard data.count <= 10_000_000 else { return }
                    if let uiImage = UIImage(data: data) {
                        let maxDimension: CGFloat = 800
                        let scaled: UIImage
                        if max(uiImage.size.width, uiImage.size.height) > maxDimension {
                            let scale = maxDimension / max(uiImage.size.width, uiImage.size.height)
                            let newSize = CGSize(width: uiImage.size.width * scale, height: uiImage.size.height * scale)
                            let renderer = UIGraphicsImageRenderer(size: newSize)
                            scaled = renderer.image { _ in uiImage.draw(in: CGRect(origin: .zero, size: newSize)) }
                        } else {
                            scaled = uiImage
                        }
                        person.photoData = scaled.jpegData(compressionQuality: 0.7) ?? data
                    } else {
                        person.photoData = data
                    }
                }
            }
        }
        .onAppear {
            ensureFamilyGraphReady()
        }
    }
    
    // MARK: - Header
    
    private var profileHeader: some View {
        VStack(spacing: 8) {
            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                if let photoData = person.photoData,
                   let uiImage = UIImage(data: photoData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 92, height: 92)
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .strokeBorder(DunbarTheme.color(for: person.healthState), lineWidth: 3)
                        )
                        .overlay(alignment: .bottomTrailing) {
                            Image(systemName: "camera.circle.fill")
                                .font(.system(size: 22))
                                .foregroundStyle(DunbarTheme.ringColor(for: .core))
                                .background(Circle().fill(.white).padding(2))
                        }
                } else {
                    ZStack(alignment: .bottomTrailing) {
                        Circle()
                            .fill(DunbarTheme.surface)
                            .frame(width: 92, height: 92)
                            .overlay {
                                Text(avatarInitials)
                                    .font(.system(size: 31, weight: .semibold))
                                    .foregroundStyle(DunbarTheme.ringColor(for: person.ring))
                            }
                            .overlay(
                                Circle()
                                    .strokeBorder(
                                        DunbarTheme.ringColor(for: person.ring),
                                        lineWidth: 3
                                    )
                            )
                        
                        Image(systemName: "camera.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(DunbarTheme.ringColor(for: .core))
                            .background(Circle().fill(.white).padding(2))
                            .offset(x: 4, y: 4)
                    }
                }
            }
            .buttonStyle(.plain)
            
            Text(person.name)
                .font(.system(size: 31, weight: .semibold, design: .rounded))
                .foregroundStyle(DunbarTheme.textPrimary)
            
            if let role = currentRole {
                Text("\(role.title) · \(role.company)")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(DunbarTheme.textSecondary)
            }
            
            StatusBadge(state: person.healthState)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 14)
        .padding(.bottom, 20)
    }
    
    private var statsRow: some View {
        HStack(spacing: 10) {
            StatCard(
                value: lastCatchUpValue,
                label: "Last catch-up"
            )
            StatCard(
                value: person.cadence.shortLabel,
                label: "Cadence"
            )
            StatCard(
                value: person.ring.shortLabel,
                label: "Circle"
            )
        }
    }
    
    private var lastCatchUpValue: String {
        if person.checkIns.isEmpty {
            return "Not yet"
        }
        return person.daysSinceContact == 0 ? "Today" : "\(person.daysSinceContact)d"
    }
    
    private var tabSelector: some View {
        HStack(spacing: 0) {
            ForEach(PersonDetailTab.allCases) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedTab = tab
                    }
                } label: {
                    VStack(spacing: 8) {
                        Text(tab.title)
                            .font(.system(size: 13, weight: selectedTab == tab ? .semibold : .medium))
                            .foregroundStyle(selectedTab == tab ? DunbarTheme.ringColor(for: .core) : DunbarTheme.textSecondary)
                        
                        Capsule()
                            .fill(selectedTab == tab ? DunbarTheme.ringColor(for: .core) : .clear)
                            .frame(height: 2)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 4)
    }
    
    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .overview:
            overviewTab
        case .context:
            contextTab
        case .history:
            historyTab
        }
    }
    
    private var overviewTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !person.notes.isEmpty {
                noteCard
            }
            
            if let recommendation = activeCadenceRecommendation {
                cadenceRecommendationCard(recommendation)
            }
            
            HStack(spacing: 10) {
                roleSummaryCard
                familySummaryCard
            }
            
            recentCatchupsCard
        }
        .transition(.opacity)
    }
    
    private var contextTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Spacer()
                
                Button(isEditingContext ? "Done editing" : "Quick edit") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isEditingContext.toggle()
                    }
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DunbarTheme.ringColor(for: .core))
            }
            
            careerSection
            familySection
        }
        .transition(.opacity)
    }
    
    private var historyTab: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ALL CATCH-UPS")
                .font(DunbarTheme.eyebrowFont)
                .tracking(0.8)
                .foregroundStyle(DunbarTheme.textTertiary)
            
            if checkIns.isEmpty {
                Text("No check-ins yet")
                    .font(.system(size: 14))
                    .foregroundStyle(DunbarTheme.textSecondary)
                    .dunbarCard()
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(checkIns.prefix(30).enumerated()), id: \.offset) { index, checkIn in
                        checkInRow(checkIn, index: index, showDivider: index < min(checkIns.count - 1, 29))
                    }
                }
                .dunbarCard()
            }
        }
        .transition(.opacity)
    }
    
    private var noteCard: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("NOTE TO SELF")
                .font(DunbarTheme.eyebrowFont)
                .tracking(0.8)
                .foregroundStyle(DunbarTheme.textTertiary)
            
            Text("\"\(person.notes)\"")
                .font(.system(size: 15).italic())
                .foregroundStyle(DunbarTheme.ringColor(for: .core))
                .lineSpacing(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dunbarCard()
    }
    
    private func cadenceRecommendationCard(_ recommendation: SmartCadenceRecommendation) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                Text("SMART CADENCE")
                    .font(DunbarTheme.eyebrowFont)
                    .tracking(0.8)
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
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(DunbarTheme.textPrimary)
            
            Text(recommendation.detail)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(DunbarTheme.textSecondary)
            
            HStack(spacing: 8) {
                Button("Apply suggestion") {
                    applyCadenceRecommendation(recommendation)
                }
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(DunbarTheme.ringColor(for: .core), in: Capsule())
                
                Button("Dismiss 14d") {
                    dismissCadenceRecommendation()
                }
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(DunbarTheme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dunbarCard()
    }
    
    private var roleSummaryCard: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label("Work", systemImage: "briefcase.fill")
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(DunbarTheme.textSecondary)
            
            if let role = currentRole {
                Text(role.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DunbarTheme.textPrimary)
                    .lineLimit(2)
                
                Text(role.company)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(DunbarTheme.ringColor(for: .core))
                    .lineLimit(1)
            } else {
                Text("No role added")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(DunbarTheme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
        .dunbarCard()
    }
    
    private var familySummaryCard: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label("Family", systemImage: "person.2.fill")
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(DunbarTheme.textSecondary)

            if familySummaryRows.isEmpty {
                Text("No family added")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(DunbarTheme.textSecondary)
            } else {
                ForEach(Array(familySummaryRows.prefix(3).enumerated()), id: \.offset) { _, row in
                    HStack(spacing: 4) {
                        Text(row.name)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(DunbarTheme.textPrimary)
                            .lineLimit(1)
                        Text("· \(row.relation)")
                            .font(.system(size: 11))
                            .foregroundStyle(DunbarTheme.textSecondary)
                            .lineLimit(1)
                    }
                }

                if familySummaryRows.count > 3 {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedTab = .context
                        }
                    } label: {
                        Text("View family tree (\(familySummaryRows.count))")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(DunbarTheme.ringColor(for: .core))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
        .dunbarCard()
    }

    private var recentCatchupsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("RECENT CATCH-UPS")
                .font(DunbarTheme.eyebrowFont)
                .tracking(0.8)
                .foregroundStyle(DunbarTheme.textTertiary)
            
            if checkIns.isEmpty {
                Text("No recent check-ins")
                    .font(.system(size: 14))
                    .foregroundStyle(DunbarTheme.textSecondary)
            } else {
                ForEach(Array(checkIns.prefix(3).enumerated()), id: \.offset) { index, checkIn in
                    checkInRow(checkIn, index: index, showDivider: index < min(checkIns.count - 1, 2))
                }
            }
        }
        .dunbarCard()
    }
    
    private var careerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Career", systemImage: "briefcase.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DunbarTheme.textSecondary)
                
                Spacer()
            }
            
            if person.sortedCareerRoles.isEmpty {
                Text("No career history added yet.")
                    .font(.system(size: 13))
                    .foregroundStyle(DunbarTheme.textSecondary)
                    .padding(.vertical, 6)
            } else {
                ForEach(Array(person.sortedCareerRoles.enumerated()), id: \.offset) { index, role in
                    HStack(alignment: .top, spacing: 10) {
                        VStack(spacing: 4) {
                            Circle()
                                .fill(role.isCurrent ? DunbarTheme.ringColor(for: .core) : DunbarTheme.textTertiary.opacity(0.35))
                                .frame(width: 8, height: 8)
                                .shadow(color: role.isCurrent ? DunbarTheme.ringColor(for: .core).opacity(0.35) : .clear, radius: 8)
                            
                            if index < person.sortedCareerRoles.count - 1 {
                                Rectangle()
                                    .fill(DunbarTheme.border)
                                    .frame(width: 1)
                                    .frame(maxHeight: .infinity)
                            }
                        }
                        .padding(.top, 5)
                        
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(role.title)
                                    .font(.system(size: 14, weight: role.isCurrent ? .semibold : .medium))
                                    .foregroundStyle(DunbarTheme.textPrimary)
                                
                                if role.isCurrent {
                                    Text("NOW")
                                        .font(.system(size: 9, weight: .bold))
                                        .tracking(0.6)
                                        .foregroundStyle(DunbarTheme.green)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(DunbarTheme.green.opacity(0.12))
                                        .clipShape(Capsule())
                                }
                            }
                            
                            HStack(spacing: 6) {
                                Text(role.company)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(DunbarTheme.ringColor(for: .core).opacity(0.9))
                                
                                Text(role.yearRangeLabel)
                                    .font(.system(size: 11))
                                    .foregroundStyle(DunbarTheme.textTertiary)
                            }
                        }
                        
                        Spacer()
                        
                        if isEditingContext {
                            VStack(spacing: 6) {
                                Button {
                                    moveCareerRole(role, by: -1)
                                } label: {
                                    Image(systemName: "arrow.up")
                                }
                                .disabled(index == 0)
                                
                                Button {
                                    moveCareerRole(role, by: 1)
                                } label: {
                                    Image(systemName: "arrow.down")
                                }
                                .disabled(index == person.sortedCareerRoles.count - 1)
                                
                                Button {
                                    editingRole = role
                                    showingEditRoleSheet = true
                                } label: {
                                    Image(systemName: "pencil")
                                }
                                
                                Button(role: .destructive) {
                                    removeCareerRole(role)
                                } label: {
                                    Image(systemName: "trash")
                                }
                            }
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(DunbarTheme.textSecondary)
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button {
                            editingRole = role
                            showingEditRoleSheet = true
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        .tint(DunbarTheme.ringColor(for: .core))
                        
                        Button(role: .destructive) {
                            removeCareerRole(role)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            
            Button {
                showingAddRoleSheet = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                    Text("Add role")
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(DunbarTheme.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(
                            style: StrokeStyle(lineWidth: 1, dash: [5, 4])
                        )
                        .foregroundStyle(DunbarTheme.border)
                )
            }
            .buttonStyle(.plain)
        }
        .dunbarCard()
    }
    
    private var familySection: some View {
        let treeData = FamilyTreeData(person: person)
        
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Family", systemImage: "person.2.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DunbarTheme.textSecondary)
                
                Spacer()
                
                if treeData.hasAnyMembers {
                    Text("Tap to expand")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(DunbarTheme.ringColor(for: .core))
                }
            }
            
            if !treeData.hasAnyMembers {
                Text("No family members added yet.")
                    .font(.system(size: 13))
                    .foregroundStyle(DunbarTheme.textSecondary)
                    .padding(.vertical, 8)
            } else {
                GeometryReader { geo in
                    let viewportWidth = max(geo.size.width, 260)
                    let previewCanvasWidth = max(viewportWidth * 2.1, 680)
                    
                    FamilyTreeDiagram(
                        personName: person.name,
                        data: treeData,
                        compact: true,
                        forcedCanvasWidth: previewCanvasWidth,
                        forcedCanvasHeight: 220
                    )
                    .frame(width: previewCanvasWidth, height: 220, alignment: .center)
                    .frame(width: viewportWidth, height: 220, alignment: .center)
                    .offset(
                        x: previewTreeOffset.width + previewTreeGestureOffset.width,
                        y: previewTreeOffset.height + previewTreeGestureOffset.height
                    )
                    .clipped()
                }
                .frame(height: 220)
                .contentShape(Rectangle())
                .simultaneousGesture(
                    DragGesture(minimumDistance: 2)
                        .updating($previewTreeGestureOffset) { value, state, _ in
                            state = value.translation
                        }
                        .onEnded { value in
                            previewTreeOffset.width += value.translation.width
                            previewTreeOffset.height += value.translation.height
                        }
                )
                .onTapGesture {
                    showingFullFamilyTree = true
                }
                
                HStack(spacing: 8) {
                    Button("Open full tree") {
                        showingFullFamilyTree = true
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DunbarTheme.ringColor(for: .core))
                    .buttonStyle(.plain)
                    
                    Button("Reset view") {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            previewTreeOffset = .zero
                        }
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DunbarTheme.textSecondary)
                    .buttonStyle(.plain)
                    
                    Text("Drag to move preview. In full tree, tap Contact nodes.")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(DunbarTheme.textTertiary)
                }
            }
            
            if !familyRelationshipRows.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Connections")
                        .font(DunbarTheme.eyebrowFont)
                        .tracking(0.7)
                        .foregroundStyle(DunbarTheme.textTertiary)
                    
                    ForEach(Array(familyRelationshipRows.prefix(isEditingContext ? familyRelationshipRows.count : 5))) { row in
                        HStack(alignment: .top, spacing: 8) {
                            Circle()
                                .fill(DunbarTheme.textTertiary.opacity(0.5))
                                .frame(width: 4, height: 4)
                                .padding(.top, 6)
                            
                            Text(row.summary)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(DunbarTheme.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            
                            if isEditingContext {
                                Button(role: .destructive) {
                                    removeFamilyRelationship(row.edge)
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.system(size: 11, weight: .semibold))
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(DunbarTheme.textSecondary)
                            }
                        }
                    }
                    
                    if !isEditingContext && familyRelationshipRows.count > 5 {
                        Text("+\(familyRelationshipRows.count - 5) more links")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(DunbarTheme.textTertiary)
                    }
                }
                .padding(.top, 4)
            }

            if !editableFamilyNodes.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Members")
                        .font(DunbarTheme.eyebrowFont)
                        .tracking(0.7)
                        .foregroundStyle(DunbarTheme.textTertiary)

                    ForEach(Array(editableFamilyNodes.enumerated()), id: \.offset) { _, node in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(DunbarTheme.textTertiary.opacity(0.5))
                                .frame(width: 4, height: 4)

                            Text(node.displayName)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(DunbarTheme.textPrimary)

                            let relation = node.roleHint?.trimmingCharacters(in: .whitespacesAndNewlines)
                            if let relation, !relation.isEmpty {
                                Text("· \(relation)")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(DunbarTheme.textSecondary)
                            }

                            if let age = node.age {
                                Text("· \(age)")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(DunbarTheme.textTertiary)
                            }

                            Spacer()

                            if isEditingContext {
                                Button {
                                    editingFamilyNode = node
                                    showingEditFamilyNodeSheet = true
                                } label: {
                                    Image(systemName: "pencil")
                                        .font(.system(size: 11, weight: .semibold))
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(DunbarTheme.textSecondary)

                                Button(role: .destructive) {
                                    removeFamilyNode(node)
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.system(size: 11, weight: .semibold))
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(DunbarTheme.textSecondary)
                            } else {
                                Menu {
                                    Button {
                                        editingFamilyNode = node
                                        showingEditFamilyNodeSheet = true
                                    } label: {
                                        Label("Edit", systemImage: "pencil")
                                    }

                                    Button(role: .destructive) {
                                        removeFamilyNode(node)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                } label: {
                                    Image(systemName: "ellipsis.circle")
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(DunbarTheme.textSecondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                        .contextMenu {
                            Button {
                                editingFamilyNode = node
                                showingEditFamilyNodeSheet = true
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }

                            Button(role: .destructive) {
                                removeFamilyNode(node)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button {
                                editingFamilyNode = node
                                showingEditFamilyNodeSheet = true
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            .tint(DunbarTheme.ringColor(for: .core))

                            Button(role: .destructive) {
                                removeFamilyNode(node)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
                .padding(.top, 4)
            }
            
            Button {
                ensureFamilyGraphReady()
                showingAddFamilyConnectionSheet = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                    Text("Add family connection")
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(DunbarTheme.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(
                            style: StrokeStyle(lineWidth: 1, dash: [5, 4])
                        )
                        .foregroundStyle(DunbarTheme.border)
                )
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
        }
        .dunbarCard()
    }
    
    private func checkInRow(_ checkIn: CheckIn, index: Int, showDivider: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 10) {
                VStack(spacing: 4) {
                    Circle()
                        .fill(DunbarTheme.green.opacity(1.0 - Double(index) * 0.15))
                        .frame(width: 8, height: 8)
                    
                    if showDivider {
                        Rectangle()
                            .fill(DunbarTheme.border)
                            .frame(width: 1, height: 18)
                    }
                }
                .padding(.top, 5)
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(checkIn.contactedAt.formatted(.dateTime.day().month(.abbreviated)))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(DunbarTheme.textPrimary)
                        
                        Label(checkIn.kind.label, systemImage: checkIn.kind.symbolName)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(DunbarTheme.ringColor(for: person.ring))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(DunbarTheme.ringColor(for: person.ring).opacity(0.13))
                            .clipShape(Capsule())
                    }
                    
                    if !checkIn.note.isEmpty {
                        Text(checkIn.note)
                            .font(.system(size: 12))
                            .foregroundStyle(DunbarTheme.textSecondary)
                    }
                }
                
                Spacer(minLength: 0)
            }
            .padding(.vertical, 6)
            
            if showDivider {
                Divider()
                    .foregroundStyle(DunbarTheme.border)
            }
        }
    }
    
    private var doneButton: some View {
        Button {
            showingCheckInNotePrompt = true
        } label: {
            Text(justMarked ? "Checked in!" : "I've reached out")
                .font(DunbarTheme.buttonFont)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    LinearGradient(
                        colors: justMarked
                            ? [DunbarTheme.green.opacity(0.85), DunbarTheme.green.opacity(0.6)]
                            : [DunbarTheme.ringColor(for: .core), DunbarTheme.ringColor(for: .close)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(.white.opacity(0.2), lineWidth: 0.8)
                )
                .shadow(color: DunbarTheme.ringColor(for: .core).opacity(0.3), radius: 14, y: 8)
        }
        .disabled(justMarked)
    }
    
    private var secondaryActions: some View {
        HStack(spacing: 16) {
            Button("Edit") { showingEditSheet = true }
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(DunbarTheme.ringColor(for: .core))
            
            Text("\u{00B7}")
                .foregroundStyle(DunbarTheme.textTertiary)
            
            Button("Remove") { showingDeleteAlert = true }
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(DunbarTheme.textSecondary)
        }
        .padding(.top, 14)
    }
    
    // MARK: - Actions
    
    private func markAsDone(note: String, kind: CheckInType) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
            person.markAsContacted(note: note, kind: kind, context: modelContext)
            justMarked = true
        }
        
        Task {
            await nudgeScheduler.schedule(for: person)
            WidgetSnapshotStore.write(WidgetSnapshotStore.buildSnapshot(people: allPeople))
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation { justMarked = false }
        }
    }
    
    private func applyCadenceRecommendation(_ recommendation: SmartCadenceRecommendation) {
        withAnimation(.easeInOut(duration: 0.2)) {
            person.cadence = recommendation.recommendedCadence
        }
        AppSettings.clearSmartCadenceDismissal(personKey: person.stableID.uuidString)
        haptics.success()
        
        Task {
            await nudgeScheduler.schedule(for: person)
            WidgetSnapshotStore.write(WidgetSnapshotStore.buildSnapshot(people: allPeople))
        }
    }
    
    private func dismissCadenceRecommendation() {
        let until = Calendar.current.date(byAdding: .day, value: 14, to: .now) ?? .now
        AppSettings.dismissSmartCadence(personKey: person.stableID.uuidString, until: until)
        haptics.impactLight()
    }

    private func addCareerRole(
        title: String,
        company: String,
        startYear: Int,
        endYear: Int?,
        isCurrent: Bool
    ) {
        if isCurrent {
            for role in person.careerRoles {
                role.isCurrent = false
            }
        }
        
        let role = CareerRole(
            person: person,
            title: title,
            company: company,
            startYear: startYear,
            endYear: isCurrent ? nil : endYear,
            isCurrent: isCurrent,
            sortOrder: nextCareerSortOrder()
        )
        modelContext.insert(role)
        do { try modelContext.save() } catch { print("[Dunbar] Save failed: \(error)") }
    }
    
    private func ensureFamilyGraphReady() {
        FamilyGraphV2Migrator.migrate(person: person, context: modelContext)
        _ = FamilyGraphV2Service.ensureAnchorNode(for: person, context: modelContext)
        do { try modelContext.save() } catch { print("[Dunbar] Save failed: \(error)") }
    }
    
    private func addFamilyConnection(
        name: String,
        age: Int?,
        targetID: UUID,
        relationKind: FamilyConnectionKind,
        roleHint: String?,
        coParentTargetID: UUID?,
        existingContact: Person?
    ) {
        ensureFamilyGraphReady()

        let cleanedRole = roleHint?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedRole = (cleanedRole?.isEmpty == false)
            ? cleanedRole
            : relationKind.defaultRoleHint

        let relationshipType: FamilyRelationshipType
        let newNodeIsFrom: Bool
        switch relationKind {
        case .parentOfTarget:
            relationshipType = .parentOf
            newNodeIsFrom = true
        case .childOfTarget:
            relationshipType = .parentOf
            newNodeIsFrom = false
        case .partnerOfTarget:
            relationshipType = .partnerOf
            newNodeIsFrom = true
        case .siblingOfTarget:
            relationshipType = .siblingOf
            newNodeIsFrom = true
        case .guardianOfTarget:
            relationshipType = .guardianOf
            newNodeIsFrom = true
        case .formerPartnerOfTarget:
            relationshipType = .formerPartnerOf
            newNodeIsFrom = true
        case .relatedToTarget:
            relationshipType = .relatedTo
            newNodeIsFrom = true
        }

        if let existingContact {
            FamilyGraphV2Service.linkExistingContact(
                for: person,
                existingContact: existingContact,
                targetNodeID: targetID,
                relationshipType: relationshipType,
                contactNodeIsFrom: newNodeIsFrom,
                coParentNodeID: coParentTargetID,
                context: modelContext
            )
        } else {
            _ = FamilyGraphV2Service.addRelative(
                for: person,
                name: name,
                age: age,
                roleHint: resolvedRole,
                targetNodeID: targetID,
                relationshipType: relationshipType,
                newNodeIsFrom: newNodeIsFrom,
                coParentNodeID: coParentTargetID,
                context: modelContext
            )
        }
        
        do { try modelContext.save() } catch { print("[Dunbar] Save failed: \(error)") }
    }
    
    private func updateCareerRole(
        _ role: CareerRole,
        title: String,
        company: String,
        startYear: Int,
        endYear: Int?,
        isCurrent: Bool
    ) {
        if isCurrent {
            for existing in person.careerRoles where existing.persistentModelID != role.persistentModelID {
                existing.isCurrent = false
            }
        }
        
        role.title = title
        role.company = company
        role.startYear = startYear
        role.endYear = isCurrent ? nil : endYear
        role.isCurrent = isCurrent
        do { try modelContext.save() } catch { print("[Dunbar] Save failed: \(error)") }
    }

    private func updateFamilyNode(
        _ node: FamilyNodeV2,
        name: String,
        relation: String,
        age: Int?
    ) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        node.name = trimmedName
        let trimmedRelation = relation.trimmingCharacters(in: .whitespacesAndNewlines)
        node.roleHint = trimmedRelation.isEmpty ? nil : trimmedRelation
        node.age = age
        do { try modelContext.save() } catch { print("[Dunbar] Save failed: \(error)") }
    }
    
    private func removeCareerRole(_ role: CareerRole) {
        modelContext.delete(role)
        do { try modelContext.save() } catch { print("[Dunbar] Save failed: \(error)") }
    }
    
    private func removeFamilyRelationship(_ edge: FamilyEdgeV2) {
        FamilyGraphV2Service.removeEdge(
            edgeID: edge.persistentModelID,
            for: person,
            context: modelContext
        )
        do { try modelContext.save() } catch { print("[Dunbar] Save failed: \(error)") }
    }

    private func removeFamilyNode(_ node: FamilyNodeV2) {
        guard let familyComponent else { return }
        guard node.stableID != familyComponent.anchor.stableID else { return }

        for edge in familyComponent.edges where
            edge.fromNode?.stableID == node.stableID || edge.toNode?.stableID == node.stableID {
            modelContext.delete(edge)
        }

        modelContext.delete(node)
        FamilyGraphV2Service.pruneOrphans(context: modelContext)
        do { try modelContext.save() } catch { print("[Dunbar] Save failed: \(error)") }
    }
    
    private func moveCareerRole(_ role: CareerRole, by offset: Int) {
        ensureCareerSortOrders()
        let ordered = person.sortedCareerRoles
        guard let currentIndex = ordered.firstIndex(where: { $0.persistentModelID == role.persistentModelID }) else {
            return
        }
        let targetIndex = currentIndex + offset
        guard ordered.indices.contains(targetIndex) else { return }
        
        let currentRole = ordered[currentIndex]
        let targetRole = ordered[targetIndex]
        let oldOrder = currentRole.sortOrder
        currentRole.sortOrder = targetRole.sortOrder
        targetRole.sortOrder = oldOrder
        do { try modelContext.save() } catch { print("[Dunbar] Save failed: \(error)") }
    }
    
    private func ensureCareerSortOrders() {
        var hasChanges = false
        for (index, role) in person.sortedCareerRoles.enumerated() where role.sortOrder == 0 {
            role.sortOrder = index + 1
            hasChanges = true
        }
        if hasChanges {
            do { try modelContext.save() } catch { print("[Dunbar] Save failed: \(error)") }
        }
    }
    
    private func nextCareerSortOrder() -> Int {
        let existing = person.careerRoles.map(\.sortOrder).filter { $0 > 0 }
        return (existing.max() ?? person.careerRoles.count) + 1
    }
    
    private func deletePerson() {
        nudgeScheduler.cancel(for: person)
        if let linkedNode = person.familyNodeV2 {
            linkedNode.linkedContact = nil
        }
        FamilyGraphV2Service.pruneOrphans(context: modelContext)
        modelContext.delete(person)
        do { try modelContext.save() } catch { print("[Dunbar] Save failed: \(error)") }
        WidgetSnapshotStore.write(WidgetSnapshotStore.buildSnapshot(people: allPeople))
    }
}

private enum FamilyRelationGroup {
    case grandparent
    case parent
    case parentPartner
    case sibling
    case partner
    case child
    case other
}

private struct FamilyTreeDisplayMember: Identifiable {
    let id: UUID
    let name: String
    let relation: String
    let age: Int?
    let linkedContact: Person?
}

private struct FamilyTreeData {
    let contactID: UUID?
    let partnerIDsOrdered: [UUID]
    let childParentMap: [UUID: [UUID]]
    let inLawParents: [FamilyTreeDisplayMember]
    let inLawParentIDsByPartner: [UUID: [UUID]]
    let grandparents: [FamilyTreeDisplayMember]
    let parents: [FamilyTreeDisplayMember]
    let parentPartners: [FamilyTreeDisplayMember]
    let parentPartnerGroups: [[FamilyTreeDisplayMember]]
    let siblings: [FamilyTreeDisplayMember]
    let siblingPartnerGroups: [[FamilyTreeDisplayMember]]
    let partners: [FamilyTreeDisplayMember]
    let children: [FamilyTreeDisplayMember]
    let others: [FamilyTreeDisplayMember]
    
    var hasAnyMembers: Bool {
        !(grandparents.isEmpty &&
          parents.isEmpty &&
          inLawParents.isEmpty &&
          parentPartners.isEmpty &&
          siblings.isEmpty &&
          siblingPartnerGroups.flatMap { $0 }.isEmpty &&
          partners.isEmpty &&
          children.isEmpty &&
          others.isEmpty)
    }
    
    init(person: Person) {
        guard let component = FamilyGraphV2Service.component(for: person) else {
            self = FamilyTreeData(members: person.sortedFamilyMembers)
            return
        }

        let contactNode = component.anchor
        let nonContactNodes = component.nodes.filter { $0.stableID != contactNode.stableID }
        let contactID = contactNode.stableID
        let orderedNodeIDs = nonContactNodes.map(\.stableID)

        var parentToChildren: [UUID: Set<UUID>] = [:]
        var childToParents: [UUID: Set<UUID>] = [:]
        var partnerAdjacency: [UUID: Set<UUID>] = [:]
        var siblingAdjacency: [UUID: Set<UUID>] = [:]

        for edge in component.edges {
            guard let fromID = edge.fromNode?.stableID,
                  let toID = edge.toNode?.stableID else {
                continue
            }

            switch edge.type {
            case .parentOf, .guardianOf:
                parentToChildren[fromID, default: []].insert(toID)
                childToParents[toID, default: []].insert(fromID)
            case .partnerOf, .formerPartnerOf:
                partnerAdjacency[fromID, default: []].insert(toID)
                partnerAdjacency[toID, default: []].insert(fromID)
            case .siblingOf:
                siblingAdjacency[fromID, default: []].insert(toID)
                siblingAdjacency[toID, default: []].insert(fromID)
            case .relatedTo:
                break
            }
        }

        let parentIDs = childToParents[contactID] ?? []
        let parentOrderedIDs = Self.orderedIDs(from: parentIDs, orderedNodeIDs: orderedNodeIDs)
        let partnerIDs = partnerAdjacency[contactID] ?? []
        let partnerOrderedIDs = Self.orderedIDs(from: partnerIDs, orderedNodeIDs: orderedNodeIDs)

        var inLawParentIDsByPartner: [UUID: [UUID]] = [:]
        var inLawParentOrderedIDs: [UUID] = []
        for partnerID in partnerOrderedIDs {
            let inLawIDs = (childToParents[partnerID] ?? [])
                .subtracting([contactID])
                .subtracting(partnerIDs)
                .subtracting(parentIDs)
            let ordered = Self.orderedIDs(from: inLawIDs, orderedNodeIDs: orderedNodeIDs)
            guard !ordered.isEmpty else { continue }
            inLawParentIDsByPartner[partnerID] = ordered
            for inLawID in ordered where !inLawParentOrderedIDs.contains(inLawID) {
                inLawParentOrderedIDs.append(inLawID)
            }
        }
        let inLawParentIDs = Set(inLawParentOrderedIDs)

        var childIDs = parentToChildren[contactID] ?? []
        for partnerID in partnerIDs {
            childIDs.formUnion(parentToChildren[partnerID] ?? [])
        }
        let childOrderedIDs = Self.orderedIDs(from: childIDs, orderedNodeIDs: orderedNodeIDs)

        var childParentMap: [UUID: [UUID]] = [:]
        let childParentOrder = [contactID] + partnerOrderedIDs
        for childID in childOrderedIDs {
            let availableParents = (childToParents[childID] ?? [])
                .filter { parentID in
                    parentID == contactID || partnerIDs.contains(parentID)
                }
            let orderedParents = childParentOrder.filter { availableParents.contains($0) }
            if !orderedParents.isEmpty {
                childParentMap[childID] = orderedParents
            }
        }

        var siblingIDs = siblingAdjacency[contactID] ?? []
        for parentID in parentIDs {
            for childID in parentToChildren[parentID] ?? [] where childID != contactID {
                siblingIDs.insert(childID)
            }
        }
        let siblingOrderedIDs = Self.orderedIDs(from: siblingIDs, orderedNodeIDs: orderedNodeIDs)

        var grandparentIDs: Set<UUID> = []
        for parentID in parentIDs {
            grandparentIDs.formUnion(childToParents[parentID] ?? [])
        }

        var parentPartnerIDs: Set<UUID> = []
        var parentPartnerIDsByParent: [UUID: Set<UUID>] = [:]
        for parentID in parentOrderedIDs {
            for partnerID in partnerAdjacency[parentID] ?? [] {
                if partnerID != contactID && !parentIDs.contains(partnerID) {
                    parentPartnerIDs.insert(partnerID)
                    parentPartnerIDsByParent[parentID, default: []].insert(partnerID)
                }
            }
        }

        var siblingPartnerIDsBySibling: [UUID: Set<UUID>] = [:]
        var siblingPartnerIDs: Set<UUID> = []
        for siblingID in siblingOrderedIDs {
            let linkedPartners = (partnerAdjacency[siblingID] ?? []).subtracting([contactID])
            if !linkedPartners.isEmpty {
                siblingPartnerIDsBySibling[siblingID] = linkedPartners
                siblingPartnerIDs.formUnion(linkedPartners)
            }
        }

        let usedIDs = grandparentIDs
            .union(parentIDs)
            .union(inLawParentIDs)
            .union(parentPartnerIDs)
            .union(siblingIDs)
            .union(siblingPartnerIDs)
            .union(partnerIDs)
            .union(childIDs)
            .union([contactID])

        let otherIDs = Set(nonContactNodes.map(\.stableID)).subtracting(usedIDs)

        self.contactID = contactID
        self.partnerIDsOrdered = partnerOrderedIDs
        self.childParentMap = childParentMap
        self.inLawParentIDsByPartner = inLawParentIDsByPartner

        self.grandparents = Self.displayMembers(
            ids: grandparentIDs,
            fallbackRelation: "Grandparent",
            orderedNodes: nonContactNodes
        )
        self.inLawParents = Self.displayMembers(
            orderedIDs: inLawParentOrderedIDs,
            fallbackRelation: "Parent",
            orderedNodes: nonContactNodes
        )
        self.parents = Self.displayMembers(
            ids: parentIDs,
            fallbackRelation: "Parent",
            orderedNodes: nonContactNodes
        )
        self.parentPartners = Self.displayMembers(
            ids: parentPartnerIDs,
            fallbackRelation: "Parent partner",
            orderedNodes: nonContactNodes
        )
        self.parentPartnerGroups = parentOrderedIDs.map { parentID in
            Self.displayMembers(
                ids: parentPartnerIDsByParent[parentID] ?? [],
                fallbackRelation: "Parent partner",
                orderedNodes: nonContactNodes
            )
        }
        self.siblings = Self.displayMembers(
            orderedIDs: siblingOrderedIDs,
            fallbackRelation: "Sibling",
            orderedNodes: nonContactNodes
        )
        self.siblingPartnerGroups = siblingOrderedIDs.map { siblingID in
            Self.displayMembers(
                ids: siblingPartnerIDsBySibling[siblingID] ?? [],
                fallbackRelation: "Partner",
                orderedNodes: nonContactNodes
            )
        }
        self.partners = Self.displayMembers(
            orderedIDs: partnerOrderedIDs,
            fallbackRelation: "Partner",
            orderedNodes: nonContactNodes
        )
        self.children = Self.displayMembers(
            orderedIDs: childOrderedIDs,
            fallbackRelation: "Child",
            orderedNodes: nonContactNodes
        )
        self.others = Self.displayMembers(
            ids: otherIDs,
            fallbackRelation: "Family",
            orderedNodes: nonContactNodes
        )
    }
    
    init(members: [FamilyMember]) {
        var grandparents: [FamilyTreeDisplayMember] = []
        var parents: [FamilyTreeDisplayMember] = []
        var parentPartners: [FamilyTreeDisplayMember] = []
        var siblings: [FamilyTreeDisplayMember] = []
        var partners: [FamilyTreeDisplayMember] = []
        var children: [FamilyTreeDisplayMember] = []
        var others: [FamilyTreeDisplayMember] = []
        
        for member in members {
            let displayMember = FamilyTreeDisplayMember(
                id: UUID(),
                name: member.name,
                relation: member.relation,
                age: member.age,
                linkedContact: nil
            )
            switch Self.group(for: member.relation) {
            case .grandparent:
                grandparents.append(displayMember)
            case .parent:
                parents.append(displayMember)
            case .parentPartner:
                parentPartners.append(displayMember)
            case .sibling:
                siblings.append(displayMember)
            case .partner:
                partners.append(displayMember)
            case .child:
                children.append(displayMember)
            case .other:
                others.append(displayMember)
            }
        }
        
        self.contactID = nil
        self.partnerIDsOrdered = []
        self.childParentMap = [:]
        self.inLawParents = []
        self.inLawParentIDsByPartner = [:]
        self.grandparents = grandparents
        self.parents = parents
        self.parentPartners = parentPartners
        if parents.isEmpty {
            self.parentPartnerGroups = parentPartners.isEmpty ? [] : [parentPartners]
        } else {
            var grouped = Array(repeating: [FamilyTreeDisplayMember](), count: parents.count)
            for (index, partner) in parentPartners.enumerated() {
                grouped[index % parents.count].append(partner)
            }
            self.parentPartnerGroups = grouped
        }
        self.siblings = siblings
        self.siblingPartnerGroups = Array(repeating: [], count: siblings.count)
        self.partners = partners
        self.children = children
        self.others = others
    }
    
    private static func orderedIDs(from ids: Set<UUID>, orderedNodeIDs: [UUID]) -> [UUID] {
        orderedNodeIDs.filter { ids.contains($0) }
    }
    
    private static func displayMembers(
        ids: Set<UUID>,
        fallbackRelation: String,
        orderedNodes: [FamilyNodeV2]
    ) -> [FamilyTreeDisplayMember] {
        let orderedIDs = Self.orderedIDs(from: ids, orderedNodeIDs: orderedNodes.map(\.stableID))
        return displayMembers(orderedIDs: orderedIDs, fallbackRelation: fallbackRelation, orderedNodes: orderedNodes)
    }
    
    private static func displayMembers(
        orderedIDs: [UUID],
        fallbackRelation: String,
        orderedNodes: [FamilyNodeV2]
    ) -> [FamilyTreeDisplayMember] {
        orderedIDs.compactMap { id in
            guard let node = orderedNodes.first(where: { $0.stableID == id }) else { return nil }
            let relationText = node.roleHint?.trimmingCharacters(in: .whitespacesAndNewlines)
            return FamilyTreeDisplayMember(
                id: node.stableID,
                name: node.displayName,
                relation: (relationText?.isEmpty == false ? relationText! : fallbackRelation),
                age: node.age,
                linkedContact: node.linkedContact
            )
        }
    }
    
    private static func group(for relation: String) -> FamilyRelationGroup {
        let normalized = relation
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        
        if [
            "grandmother", "grandfather", "grandparent",
            "grandma", "grandpa", "nan", "nana", "granny", "grandad", "granddad"
        ].contains(normalized) {
            return .grandparent
        }
        
        if [
            "mother", "father", "mum", "mom", "dad", "parent",
            "stepmother", "stepfather", "stepmom", "stepdad"
        ].contains(normalized) {
            return .parent
        }
        
        if normalized.contains("step parent")
            || normalized.contains("step-parent")
            || (normalized.contains("step") && normalized.contains("parent")) {
            return .parentPartner
        }
        
        if normalized.contains("parent partner")
            || normalized.contains("parent's partner")
            || normalized.contains("parents partner")
            || normalized.contains("parents' partner") {
            return .parentPartner
        }
        
        if normalized.contains("partner")
            && (
                normalized.contains("mum")
                || normalized.contains("mom")
                || normalized.contains("dad")
                || normalized.contains("mother")
                || normalized.contains("father")
                || normalized.contains("parent")
            ) {
            return .parentPartner
        }
        
        if (
            normalized.contains("boyfriend")
            || normalized.contains("girlfriend")
            || normalized.contains("wife")
            || normalized.contains("husband")
            || normalized.contains("spouse")
        ) && (
            normalized.contains("mum")
            || normalized.contains("mom")
            || normalized.contains("dad")
            || normalized.contains("mother")
            || normalized.contains("father")
            || normalized.contains("parent")
        ) {
            return .parentPartner
        }
        
        if [
            "brother", "sister", "sibling", "stepbrother", "stepsister"
        ].contains(normalized) {
            return .sibling
        }
        
        if [
            "partner", "wife", "husband", "girlfriend", "boyfriend",
            "spouse", "fiance", "fiancée"
        ].contains(normalized) {
            return .partner
        }
        
        if ["son", "daughter", "child", "kid", "children"].contains(normalized) {
            return .child
        }
        
        return .other
    }
}

private struct FamilyTreeDiagram: View {
    let personName: String
    let data: FamilyTreeData
    let compact: Bool
    var onContactTap: ((Person) -> Void)? = nil
    var forcedCanvasWidth: CGFloat? = nil
    var forcedCanvasHeight: CGFloat? = nil
    
    private var canvasWidth: CGFloat {
        forcedCanvasWidth ?? (compact ? 700 : 1200)
    }
    
    private var canvasHeight: CGFloat {
        forcedCanvasHeight ?? (compact ? 360 : 780)
    }
    
    private var nodeWidth: CGFloat {
        if compact {
            return min(max(canvasWidth * 0.22, 88), 102)
        }
        return 148
    }
    
    private var nodeHeight: CGFloat {
        if compact {
            return min(max(canvasHeight * 0.2, 46), 54)
        }
        return 72
    }
    
    private var horizontalSpacing: CGFloat {
        if compact {
            return min(max(canvasWidth * 0.22, nodeWidth + 14), nodeWidth + 32)
        }
        return 166
    }
    
    private var firstName: String {
        personName.split(separator: " ").first.map(String.init) ?? personName
    }
    
    var body: some View {
        let previewOthers: [FamilyTreeDisplayMember] = compact ? [] : data.others
        let compactRowStep = max(nodeHeight + 10, 58)
        let mainY: CGFloat = compact ? (canvasHeight * 0.56) : 320
        let parentsY: CGFloat = compact ? (mainY - compactRowStep) : 206
        let grandparentsY: CGFloat = compact ? (parentsY - compactRowStep) : 94
        let childrenY: CGFloat = compact ? (mainY + compactRowStep) : 450
        let othersY: CGFloat = compact ? (childrenY + compactRowStep) : 596
        let connectorGap: CGFloat = compact ? 6 : 12
        
        let grandparentCenters = centers(
            count: data.grandparents.count,
            y: grandparentsY
        )
        let parentCenters = centers(
            count: data.parents.count,
            y: parentsY
        )
        let selfCenter = CGPoint(x: canvasWidth / 2, y: mainY)
        let parentPartnerCenters = partnerCentersForParents(
            groups: data.parentPartnerGroups,
            y: parentsY,
            parentCenters: parentCenters,
            selfCenterX: selfCenter.x
        )
        let siblingCenters = siblingCenters(
            count: data.siblings.count,
            y: mainY,
            around: selfCenter.x
        )
        let siblingPartnerCenters = siblingPartnerCenters(
            groups: data.siblingPartnerGroups,
            siblingCenters: siblingCenters,
            selfCenterX: selfCenter.x
        )
        
        let partnerCenters: [CGPoint] = {
            guard !data.partners.isEmpty else { return [] }
            let availableRightSpan = max(canvasWidth - nodeWidth / 2 - selfCenter.x, 0)
            let firstShift = min(nodeWidth + (compact ? 26 : 18), availableRightSpan)
            
            if data.partners.count == 1 {
                return [CGPoint(x: selfCenter.x + firstShift, y: mainY)]
            }
            
            let remaining = max(availableRightSpan - firstShift, 0)
            let step = remaining / CGFloat(max(data.partners.count - 1, 1))
            return data.partners.enumerated().map { index, _ in
                CGPoint(x: selfCenter.x + firstShift + CGFloat(index) * step, y: mainY)
            }
        }()
        let partnerCenterByID = Dictionary(uniqueKeysWithValues: zip(data.partnerIDsOrdered, partnerCenters))
        
        let childBranchAnchorX: CGFloat = {
            if let primaryPartner = partnerCenters.first {
                return (selfCenter.x + primaryPartner.x) / 2
            }
            return selfCenter.x
        }()
        let childrenCenters = centers(
            count: data.children.count,
            y: childrenY,
            around: childBranchAnchorX
        )
        let inLawParentCentersByPartner: [UUID: [CGPoint]] = {
            var map: [UUID: [CGPoint]] = [:]
            let firstOffset = nodeWidth + (compact ? 14 : 22)
            let chainSpacing = nodeWidth + (compact ? 10 : 14)

            for partnerID in data.partnerIDsOrdered {
                guard let partnerCenter = partnerCenterByID[partnerID] else { continue }
                let inLawIDs = data.inLawParentIDsByPartner[partnerID] ?? []
                guard !inLawIDs.isEmpty else { continue }

                // Place in-law parents on the side farther from the primary contact.
                let direction: CGFloat = partnerCenter.x >= selfCenter.x ? 1 : -1
                map[partnerID] = inLawIDs.enumerated().map { index, _ in
                    CGPoint(
                        x: partnerCenter.x + direction * (firstOffset + CGFloat(index) * chainSpacing),
                        y: parentsY
                    )
                }
            }

            return map
        }()
        let parentCenterByID: [UUID: CGPoint] = {
            var map = partnerCenterByID
            if let contactID = data.contactID {
                map[contactID] = selfCenter
            }
            return map
        }()
        let inLawParentCenterByID: [UUID: CGPoint] = {
            var map: [UUID: CGPoint] = [:]
            for partnerID in data.partnerIDsOrdered {
                let inLawIDs = data.inLawParentIDsByPartner[partnerID] ?? []
                let centers = inLawParentCentersByPartner[partnerID] ?? []
                for (index, inLawID) in inLawIDs.enumerated() where index < centers.count {
                    map[inLawID] = centers[index]
                }
            }
            return map
        }()
        let otherCenters = centers(
            count: previewOthers.count,
            y: othersY
        )
        
        let parentBranchTargets = siblingCenters + [selfCenter]
        ZStack {
            Path { path in
                connectRows(
                    path: &path,
                    upperCenters: grandparentCenters,
                    lowerCenters: parentCenters,
                    nodeHeight: nodeHeight,
                    connectorGap: connectorGap
                )
                
                connectRows(
                    path: &path,
                    upperCenters: parentCenters,
                    lowerCenters: parentBranchTargets,
                    nodeHeight: nodeHeight,
                    connectorGap: connectorGap
                )
                
                for parentIndex in parentPartnerCenters.indices {
                    let parentPoint: CGPoint
                    if !parentCenters.isEmpty {
                        parentPoint = parentCenters[min(parentIndex, parentCenters.count - 1)]
                    } else {
                        parentPoint = CGPoint(x: selfCenter.x, y: parentsY)
                    }
                    for partnerPoint in parentPartnerCenters[parentIndex] {
                        let movingRight = partnerPoint.x > parentPoint.x
                        let startX = parentPoint.x + (movingRight ? nodeWidth / 2 : -nodeWidth / 2)
                        let endX = partnerPoint.x + (movingRight ? -nodeWidth / 2 : nodeWidth / 2)
                        path.move(to: CGPoint(x: startX, y: parentPoint.y))
                        path.addLine(to: CGPoint(x: endX, y: partnerPoint.y))
                    }
                }
                
                for siblingIndex in siblingPartnerCenters.indices {
                    guard siblingIndex < siblingCenters.count else { continue }
                    let siblingPoint = siblingCenters[siblingIndex]
                    for partnerPoint in siblingPartnerCenters[siblingIndex] {
                        let movingRight = partnerPoint.x > siblingPoint.x
                        let startX = siblingPoint.x + (movingRight ? nodeWidth / 2 : -nodeWidth / 2)
                        let endX = partnerPoint.x + (movingRight ? -nodeWidth / 2 : nodeWidth / 2)
                        path.move(to: CGPoint(x: startX, y: siblingPoint.y))
                        path.addLine(to: CGPoint(x: endX, y: partnerPoint.y))
                    }
                }

                for partnerID in data.partnerIDsOrdered {
                    guard let partnerCenter = partnerCenterByID[partnerID] else { continue }
                    let centersForPartner = inLawParentCentersByPartner[partnerID] ?? []
                    connectRows(
                        path: &path,
                        upperCenters: centersForPartner,
                        lowerCenters: [partnerCenter],
                        nodeHeight: nodeHeight,
                        connectorGap: connectorGap
                    )
                }
                
                if let primaryPartner = partnerCenters.first {
                    path.move(to: CGPoint(x: selfCenter.x + nodeWidth / 2, y: selfCenter.y))
                    path.addLine(to: CGPoint(x: primaryPartner.x - nodeWidth / 2, y: primaryPartner.y))
                }
                
                if !childrenCenters.isEmpty {
                    for (index, childMember) in data.children.enumerated() where index < childrenCenters.count {
                        let childCenter = childrenCenters[index]
                        let childJoinY = childCenter.y - nodeHeight / 2 - connectorGap
                        let parentIDs = data.childParentMap[childMember.id] ?? []
                        let parentCenters = parentIDs.compactMap { parentCenterByID[$0] }

                        if !parentCenters.isEmpty {
                            let parentJoinY = parentCenters[0].y + nodeHeight / 2 + connectorGap
                            for parentCenter in parentCenters {
                                path.move(to: CGPoint(x: parentCenter.x, y: parentCenter.y + nodeHeight / 2))
                                path.addLine(to: CGPoint(x: parentCenter.x, y: parentJoinY))
                            }
                            if parentCenters.count > 1 {
                                path.move(to: CGPoint(x: parentCenters.map(\.x).min() ?? parentCenters[0].x, y: parentJoinY))
                                path.addLine(to: CGPoint(x: parentCenters.map(\.x).max() ?? parentCenters[0].x, y: parentJoinY))
                            }

                            let branchX = parentCenters.map(\.x).reduce(0, +) / CGFloat(parentCenters.count)
                            path.move(to: CGPoint(x: branchX, y: parentJoinY))
                            path.addLine(to: CGPoint(x: branchX, y: childJoinY))
                            path.move(to: CGPoint(x: min(branchX, childCenter.x), y: childJoinY))
                            path.addLine(to: CGPoint(x: max(branchX, childCenter.x), y: childJoinY))
                            path.move(to: CGPoint(x: childCenter.x, y: childJoinY))
                            path.addLine(to: CGPoint(x: childCenter.x, y: childCenter.y - nodeHeight / 2))
                        } else {
                            let branchX = childBranchAnchorX
                            let fallbackTopY = selfCenter.y + nodeHeight / 2 + connectorGap
                            path.move(to: CGPoint(x: branchX, y: selfCenter.y + nodeHeight / 2))
                            path.addLine(to: CGPoint(x: branchX, y: fallbackTopY))
                            path.addLine(to: CGPoint(x: branchX, y: childJoinY))
                            path.move(to: CGPoint(x: min(branchX, childCenter.x), y: childJoinY))
                            path.addLine(to: CGPoint(x: max(branchX, childCenter.x), y: childJoinY))
                            path.move(to: CGPoint(x: childCenter.x, y: childJoinY))
                            path.addLine(to: CGPoint(x: childCenter.x, y: childCenter.y - nodeHeight / 2))
                        }
                    }
                }
            }
            .stroke(DunbarTheme.border, lineWidth: compact ? 1 : 1.4)
            
            ForEach(Array(data.grandparents.enumerated()), id: \.offset) { index, member in
                FamilyTreeMemberNode(
                    member: member,
                    compact: compact,
                    width: nodeWidth,
                    height: nodeHeight,
                    onContactTap: onContactTap
                )
                    .position(grandparentCenters[index])
            }
            
            ForEach(Array(data.parents.enumerated()), id: \.offset) { index, member in
                FamilyTreeMemberNode(
                    member: member,
                    compact: compact,
                    width: nodeWidth,
                    height: nodeHeight,
                    onContactTap: onContactTap
                )
                    .position(parentCenters[index])
            }

            ForEach(data.inLawParents) { member in
                if let center = inLawParentCenterByID[member.id] {
                    FamilyTreeMemberNode(
                        member: member,
                        compact: compact,
                        width: nodeWidth,
                        height: nodeHeight,
                        onContactTap: onContactTap
                    )
                        .position(center)
                }
            }
            
            ForEach(Array(data.parentPartnerGroups.enumerated()), id: \.offset) { parentIndex, partners in
                ForEach(Array(partners.enumerated()), id: \.offset) { partnerIndex, member in
                    if parentIndex < parentPartnerCenters.count,
                       partnerIndex < parentPartnerCenters[parentIndex].count {
                        FamilyTreeMemberNode(
                            member: member,
                            compact: compact,
                            width: nodeWidth,
                            height: nodeHeight,
                            onContactTap: onContactTap
                        )
                        .position(parentPartnerCenters[parentIndex][partnerIndex])
                    }
                }
            }
            
            ForEach(Array(data.siblings.enumerated()), id: \.offset) { index, member in
                FamilyTreeMemberNode(
                    member: member,
                    compact: compact,
                    width: nodeWidth,
                    height: nodeHeight,
                    onContactTap: onContactTap
                )
                    .position(siblingCenters[index])
            }
            
            ForEach(Array(data.siblingPartnerGroups.enumerated()), id: \.offset) { siblingIndex, partners in
                ForEach(Array(partners.enumerated()), id: \.offset) { partnerIndex, member in
                    if siblingIndex < siblingPartnerCenters.count,
                       partnerIndex < siblingPartnerCenters[siblingIndex].count {
                        FamilyTreeMemberNode(
                            member: member,
                            compact: compact,
                            width: nodeWidth,
                            height: nodeHeight,
                            onContactTap: onContactTap
                        )
                        .position(siblingPartnerCenters[siblingIndex][partnerIndex])
                    }
                }
            }
            
            FamilyTreeSelfNode(
                name: firstName,
                compact: compact,
                width: compact ? nodeWidth + 4 : 152,
                height: compact ? nodeHeight : 74
            )
                .position(selfCenter)
            
            ForEach(Array(data.partners.enumerated()), id: \.offset) { index, member in
                FamilyTreeMemberNode(
                    member: member,
                    compact: compact,
                    width: nodeWidth,
                    height: nodeHeight,
                    onContactTap: onContactTap
                )
                    .position(partnerCenters[index])
            }
            
            ForEach(Array(data.children.enumerated()), id: \.offset) { index, member in
                FamilyTreeMemberNode(
                    member: member,
                    compact: compact,
                    width: nodeWidth,
                    height: nodeHeight,
                    onContactTap: onContactTap
                )
                    .position(childrenCenters[index])
            }
            
            ForEach(Array(previewOthers.enumerated()), id: \.offset) { index, member in
                FamilyTreeMemberNode(
                    member: member,
                    compact: compact,
                    width: nodeWidth,
                    height: nodeHeight,
                    onContactTap: onContactTap
                )
                    .position(otherCenters[index])
            }
            
            if !previewOthers.isEmpty {
                Text("Other family")
                    .font(.system(size: compact ? 9 : 11, weight: .medium))
                    .foregroundStyle(DunbarTheme.textTertiary)
                    .position(x: canvasWidth / 2, y: othersY - nodeHeight / 2 - (compact ? 14 : 20))
            }
        }
        .frame(width: canvasWidth, height: canvasHeight)
    }
    
    private func centers(count: Int, y: CGFloat) -> [CGPoint] {
        guard count > 0 else { return [] }
        
        if compact {
            let totalWidth = CGFloat(count - 1) * horizontalSpacing
            let startX = (canvasWidth - totalWidth) / 2
            return (0..<count).map { index in
                CGPoint(x: startX + CGFloat(index) * horizontalSpacing, y: y)
            }
        }
        
        let spacing: CGFloat
        if count > 1 {
            let maxFittingSpacing = (canvasWidth - nodeWidth) / CGFloat(count - 1)
            spacing = min(horizontalSpacing, max(maxFittingSpacing, 0))
        } else {
            spacing = 0
        }
        let totalWidth = CGFloat(count - 1) * spacing
        let startX = (canvasWidth - totalWidth) / 2
        return (0..<count).map { index in
            CGPoint(x: startX + CGFloat(index) * spacing, y: y)
        }
    }
    
    private func centers(count: Int, y: CGFloat, around anchorX: CGFloat) -> [CGPoint] {
        guard count > 0 else { return [] }
        let totalWidth = CGFloat(count - 1) * horizontalSpacing
        let startX = anchorX - totalWidth / 2
        return (0..<count).map { index in
            CGPoint(x: startX + CGFloat(index) * horizontalSpacing, y: y)
        }
    }
    
    private func partnerCentersForParents(
        groups: [[FamilyTreeDisplayMember]],
        y: CGFloat,
        parentCenters: [CGPoint],
        selfCenterX: CGFloat
    ) -> [[CGPoint]] {
        guard !groups.isEmpty else { return [] }
        
        let partnerGap = nodeWidth + (compact ? 14 : 22)
        let chainSpacing = nodeWidth + (compact ? 10 : 14)
        
        return groups.enumerated().map { parentIndex, partners in
            guard !partners.isEmpty else { return [] }
            let parentCenter = parentCenters.isEmpty
                ? CGPoint(x: canvasWidth / 2, y: y)
                : parentCenters[min(parentIndex, parentCenters.count - 1)]
            
            let direction: CGFloat
            if parentCenters.count <= 1 {
                direction = 1
            } else {
                direction = parentCenter.x <= selfCenterX ? -1 : 1
            }
            
            return partners.enumerated().map { partnerIndex, _ in
                CGPoint(
                    x: parentCenter.x + direction * (partnerGap + CGFloat(partnerIndex) * chainSpacing),
                    y: y
                )
            }
        }
    }
    
    private func siblingCenters(count: Int, y: CGFloat, around centerX: CGFloat) -> [CGPoint] {
        guard count > 0 else { return [] }

        // Reserve center for the main contact. Siblings are distributed left/right:
        // count 1 => [-1], count 2 => [-1, +1], count 3 => [-2, -1, +1], etc.
        var laneOffsets: [Int] = []
        var depth = 1
        while laneOffsets.count < count {
            laneOffsets.append(-depth)
            if laneOffsets.count < count {
                laneOffsets.append(depth)
            }
            depth += 1
        }
        laneOffsets.sort()
        
        if compact {
            return laneOffsets.map { lane in
                CGPoint(
                    x: centerX + CGFloat(lane) * horizontalSpacing,
                    y: y
                )
            }
        }
        
        let maxLane = CGFloat(laneOffsets.map(\.magnitude).max() ?? 1)
        let halfSpan = max((canvasWidth - nodeWidth) / 2, 0)
        let fittingSpacing = maxLane > 0 ? halfSpan / maxLane : horizontalSpacing
        let spacing = min(horizontalSpacing, fittingSpacing)
        
        return laneOffsets.map { lane in
            CGPoint(
                x: centerX + CGFloat(lane) * spacing,
                y: y
            )
        }
    }
    
    private func siblingPartnerCenters(
        groups: [[FamilyTreeDisplayMember]],
        siblingCenters: [CGPoint],
        selfCenterX: CGFloat
    ) -> [[CGPoint]] {
        guard !groups.isEmpty else { return [] }
        
        let firstOffset = nodeWidth + (compact ? 16 : 26)
        let chainSpacing = nodeWidth + (compact ? 10 : 14)
        
        return groups.enumerated().map { index, group in
            guard !group.isEmpty, index < siblingCenters.count else { return [] }
            let siblingCenter = siblingCenters[index]
            let direction: CGFloat = siblingCenter.x <= selfCenterX ? -1 : 1
            return group.enumerated().map { partnerIndex, _ in
                CGPoint(
                    x: siblingCenter.x + direction * (firstOffset + CGFloat(partnerIndex) * chainSpacing),
                    y: siblingCenter.y
                )
            }
        }
    }
    
    private func connectRows(
        path: inout Path,
        upperCenters: [CGPoint],
        lowerCenters: [CGPoint],
        nodeHeight: CGFloat,
        connectorGap: CGFloat
    ) {
        guard !upperCenters.isEmpty, !lowerCenters.isEmpty else { return }
        
        let upperStemY = (upperCenters[0].y + nodeHeight / 2) + connectorGap
        let lowerStemY = (lowerCenters[0].y - nodeHeight / 2) - connectorGap
        let trunkX = upperCenters.map(\.x).reduce(0, +) / CGFloat(upperCenters.count)
        
        for point in upperCenters {
            path.move(to: CGPoint(x: point.x, y: point.y + nodeHeight / 2))
            path.addLine(to: CGPoint(x: point.x, y: upperStemY))
        }
        
        if upperCenters.count > 1 {
            path.move(to: CGPoint(x: upperCenters.map(\.x).min() ?? trunkX, y: upperStemY))
            path.addLine(to: CGPoint(x: upperCenters.map(\.x).max() ?? trunkX, y: upperStemY))
        }
        
        path.move(to: CGPoint(x: trunkX, y: upperStemY))
        path.addLine(to: CGPoint(x: trunkX, y: lowerStemY))
        
        if lowerCenters.count > 1 {
            path.move(to: CGPoint(x: lowerCenters.map(\.x).min() ?? trunkX, y: lowerStemY))
            path.addLine(to: CGPoint(x: lowerCenters.map(\.x).max() ?? trunkX, y: lowerStemY))
        } else if let onlyLower = lowerCenters.first, abs(onlyLower.x - trunkX) > 0.5 {
            // For 2->1 relationships (e.g. two parents to one partner/child),
            // bridge the trunk over to the single lower node before dropping down.
            path.move(to: CGPoint(x: trunkX, y: lowerStemY))
            path.addLine(to: CGPoint(x: onlyLower.x, y: lowerStemY))
        }
        
        for point in lowerCenters {
            path.move(to: CGPoint(x: point.x, y: lowerStemY))
            path.addLine(to: CGPoint(x: point.x, y: point.y - nodeHeight / 2))
        }
    }
}

private struct FamilyTreeSelfNode: View {
    let name: String
    let compact: Bool
    let width: CGFloat
    let height: CGFloat
    
    var body: some View {
        VStack(spacing: compact ? 2 : 4) {
            Text(name)
                .font(.system(size: compact ? 12 : 15, weight: .semibold))
                .foregroundStyle(DunbarTheme.textPrimary)
                .lineLimit(1)
            
            Text("Contact")
                .font(.system(size: compact ? 9 : 11, weight: .semibold))
                .foregroundStyle(DunbarTheme.ringColor(for: .core))
        }
        .frame(width: width, height: height)
        .background(DunbarTheme.ringColor(for: .core).opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: compact ? 12 : 14))
        .overlay(
            RoundedRectangle(cornerRadius: compact ? 12 : 14)
                .strokeBorder(DunbarTheme.ringColor(for: .core).opacity(0.35), lineWidth: 1)
        )
    }
}

private struct FamilyTreeMemberNode: View {
    let member: FamilyTreeDisplayMember
    let compact: Bool
    let width: CGFloat
    let height: CGFloat
    var onContactTap: ((Person) -> Void)? = nil
    
    var body: some View {
        let cornerRadius = compact ? 12.0 : 14.0

        return VStack(spacing: compact ? 2 : 4) {
            HStack(spacing: 4) {
                Text(marker)
                    .font(.system(size: compact ? 8 : 10, weight: .semibold))
                    .foregroundStyle(markerColor)
                
                Text(member.name)
                    .font(.system(size: compact ? 11 : 13, weight: .semibold))
                    .foregroundStyle(DunbarTheme.textPrimary)
                    .lineLimit(1)
            }
            
            Text(relationLine)
                .font(.system(size: compact ? 9 : 11, weight: .medium))
                .foregroundStyle(DunbarTheme.textSecondary)
                .lineLimit(1)

            if member.linkedContact != nil {
                Text("Contact")
                    .font(.system(size: compact ? 8 : 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(DunbarTheme.ringColor(for: .core))
            }
        }
        .frame(width: width, height: height)
        .background(member.linkedContact == nil ? DunbarTheme.surface : DunbarTheme.ringColor(for: .core).opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius)
                .strokeBorder(
                    member.linkedContact == nil ? DunbarTheme.border : DunbarTheme.ringColor(for: .core).opacity(0.35),
                    lineWidth: 1
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius))
        .onTapGesture {
            guard let linkedContact = member.linkedContact else { return }
            onContactTap?(linkedContact)
        }
    }
    
    private var marker: String {
        let relation = member.relation.lowercased()
        if ["partner", "wife", "husband", "girlfriend", "boyfriend", "spouse"].contains(relation) {
            return "♥"
        }
        if ["son", "daughter", "child", "kid", "children"].contains(relation) {
            return "◆"
        }
        return "●"
    }
    
    private var markerColor: Color {
        let relation = member.relation.lowercased()
        if ["partner", "wife", "husband", "girlfriend", "boyfriend", "spouse"].contains(relation) {
            return DunbarTheme.ringColor(for: .core)
        }
        if ["son", "daughter", "child", "kid", "children"].contains(relation) {
            return DunbarTheme.green
        }
        return DunbarTheme.textSecondary
    }
    
    private var relationLine: String {
        if let age = member.age {
            return "\(member.relation) · \(age)"
        }
        return member.relation
    }
}

private struct FamilyTreeFullScreenView: View {
    @Environment(\.dismiss) private var dismiss
    
    let person: Person
    
    @State private var dragOffset: CGSize = .zero
    @State private var zoomScale: CGFloat = 1.0
    @State private var selectedLinkedContact: Person?
    @GestureState private var gestureOffset: CGSize = .zero
    @GestureState private var pinchScale: CGFloat = 1.0
    
    private let minZoom: CGFloat = 0.6
    private let maxZoom: CGFloat = 2.3
    
    private var effectiveScale: CGFloat {
        max(min(zoomScale * pinchScale, maxZoom), minZoom)
    }
    
    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                ZStack {
                    DunbarTheme.background
                        .ignoresSafeArea()
                    
                    FamilyTreeDiagram(
                        personName: person.name,
                        data: FamilyTreeData(person: person),
                        compact: false,
                        onContactTap: { linkedContact in
                            selectedLinkedContact = linkedContact
                        }
                    )
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)
                    .scaleEffect(effectiveScale)
                    .offset(
                        x: dragOffset.width + gestureOffset.width,
                        y: dragOffset.height + gestureOffset.height
                    )
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 2)
                        .updating($gestureOffset) { value, state, _ in
                            state = value.translation
                        }
                        .onEnded { value in
                            dragOffset.width += value.translation.width
                            dragOffset.height += value.translation.height
                        }
                )
                .simultaneousGesture(
                    MagnificationGesture()
                        .updating($pinchScale) { value, state, _ in
                            state = value
                        }
                        .onEnded { value in
                            zoomScale = max(min(zoomScale * value, maxZoom), minZoom)
                        }
                )
                .overlay(alignment: .bottom) {
                    Text("Drag to explore. Pinch to zoom.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(DunbarTheme.textSecondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(DunbarTheme.surfaceElevated.opacity(0.9))
                        .clipShape(Capsule())
                        .padding(.bottom, 16)
                }
                .onAppear {
                    dragOffset = .zero
                    zoomScale = 1.0
                }
            }
            .navigationTitle("Family tree")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Reset") {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            dragOffset = .zero
                            zoomScale = 1.0
                        }
                    }
                    .font(.system(size: 14, weight: .semibold))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.system(size: 15, weight: .semibold))
                }
            }
            .sheet(item: $selectedLinkedContact) { linkedPerson in
                NavigationStack {
                    PersonDetailView(person: linkedPerson)
                }
            }
        }
    }
}

// MARK: - Stat Card

private struct StatCard: View {
    let value: String
    let label: String
    
    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 21, weight: .semibold, design: .rounded))
                .foregroundStyle(DunbarTheme.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 54, alignment: .center)
            
            Text(label)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(DunbarTheme.textTertiary)
        }
        .frame(maxWidth: .infinity, minHeight: 96)
        .dunbarCard()
    }
}

private struct AddCareerRoleSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    @State private var title: String
    @State private var company: String
    @State private var startYear: String
    @State private var endYear: String
    @State private var isCurrent: Bool
    
    let saveLabel: String
    let onSave: (String, String, Int, Int?, Bool) -> Void
    
    init(
        initialTitle: String = "",
        initialCompany: String = "",
        initialStartYear: Int = Calendar.current.component(.year, from: .now),
        initialEndYear: Int? = nil,
        initialIsCurrent: Bool = true,
        saveLabel: String = "Save",
        onSave: @escaping (String, String, Int, Int?, Bool) -> Void
    ) {
        self._title = State(initialValue: initialTitle)
        self._company = State(initialValue: initialCompany)
        self._startYear = State(initialValue: String(initialStartYear))
        self._endYear = State(initialValue: initialEndYear.map(String.init) ?? "")
        self._isCurrent = State(initialValue: initialIsCurrent)
        self.saveLabel = saveLabel
        self.onSave = onSave
    }
    
    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !company.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        Int(startYear) != nil
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Role") {
                    TextField("Role title", text: $title)
                    TextField("Company", text: $company)
                }
                
                Section("Timeline") {
                    TextField("Start year", text: $startYear)
                        .keyboardType(.numberPad)
                    
                    Toggle("Current role", isOn: $isCurrent)
                    
                    if !isCurrent {
                        TextField("End year", text: $endYear)
                            .keyboardType(.numberPad)
                    }
                }
            }
            .navigationTitle("Add role")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saveLabel) {
                        let parsedStart = Int(startYear) ?? Calendar.current.component(.year, from: .now)
                        let parsedEnd = isCurrent ? nil : Int(endYear)
                        onSave(
                            title.trimmingCharacters(in: .whitespacesAndNewlines),
                            company.trimmingCharacters(in: .whitespacesAndNewlines),
                            parsedStart,
                            parsedEnd,
                            isCurrent
                        )
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
        }
    }
}

private struct FamilyRelationshipRow: Identifiable {
    var id: PersistentIdentifier { edge.persistentModelID }
    let edge: FamilyEdgeV2
    let summary: String
}

private struct FamilyConnectionTarget: Identifiable, Hashable {
    let id: UUID
    let name: String
    let isPrimaryContact: Bool
}

private enum FamilyConnectionKind: String, CaseIterable, Identifiable {
    case parentOfTarget
    case childOfTarget
    case partnerOfTarget
    case siblingOfTarget
    case guardianOfTarget
    case formerPartnerOfTarget
    case relatedToTarget
    
    var id: String { rawValue }
    
    var label: String {
        switch self {
        case .parentOfTarget: return "Parent of"
        case .childOfTarget: return "Child of"
        case .partnerOfTarget: return "Partner of"
        case .siblingOfTarget: return "Sibling of"
        case .guardianOfTarget: return "Guardian of"
        case .formerPartnerOfTarget: return "Former partner of"
        case .relatedToTarget: return "Related to"
        }
    }
    
    var defaultRoleHint: String {
        switch self {
        case .parentOfTarget: return "Parent"
        case .childOfTarget: return "Child"
        case .partnerOfTarget: return "Partner"
        case .siblingOfTarget: return "Sibling"
        case .guardianOfTarget: return "Guardian"
        case .formerPartnerOfTarget: return "Former partner"
        case .relatedToTarget: return "Family"
        }
    }
}

private struct AddFamilyConnectionSheet: View {
    private enum InputMode: String, CaseIterable, Identifiable {
        case newRelative
        case existingContact

        var id: String { rawValue }

        var title: String {
            switch self {
            case .newRelative: return "New relative"
            case .existingContact: return "Existing contact"
            }
        }
    }

    @Environment(\.dismiss) private var dismiss
    
    let targets: [FamilyConnectionTarget]
    let defaultTargetID: UUID?
    let partnerTargetsByID: [UUID: [FamilyConnectionTarget]]
    let existingContactOptions: [Person]
    let onSave: (String, Int?, UUID, FamilyConnectionKind, String?, UUID?, Person?) -> Void
    
    @State private var inputMode: InputMode = .newRelative
    @State private var name: String = ""
    @State private var age: String = ""
    @State private var roleHint: String = ""
    @State private var selectedTargetID: UUID?
    @State private var selectedKind: FamilyConnectionKind = .partnerOfTarget
    @State private var alsoLinkToCoParent = true
    @State private var selectedCoParentID: UUID?
    @State private var selectedExistingContactKey: String = ""
    
    private var canSave: Bool {
        switch inputMode {
        case .newRelative:
            return !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                selectedTargetID != nil &&
                !targets.isEmpty
        case .existingContact:
            return !selectedExistingContactKey.isEmpty &&
                selectedTargetID != nil &&
                !targets.isEmpty
        }
    }
    
    private var selectedTargetName: String {
        guard let targetID = selectedTargetID ?? targets.first?.id,
              let target = targets.first(where: { $0.id == targetID }) else {
            return "contact"
        }
        return target.isPrimaryContact ? "\(target.name) (Contact)" : target.name
    }

    private var existingContactKeyValues: [(key: String, person: Person)] {
        existingContactOptions.map { (String(describing: $0.persistentModelID), $0) }
    }

    private var selectedExistingContact: Person? {
        existingContactKeyValues.first(where: { $0.key == selectedExistingContactKey })?.person
    }

    private var selectedExistingContactName: String {
        selectedExistingContact?.name ?? "contact"
    }
    
    private var availableCoParents: [FamilyConnectionTarget] {
        guard let targetID = selectedTargetID ?? targets.first?.id else { return [] }
        return partnerTargetsByID[targetID] ?? []
    }
    
    private var shouldShowCoParentOptions: Bool {
        selectedKind == .childOfTarget && !availableCoParents.isEmpty
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Add type") {
                    Picker("Add type", selection: $inputMode) {
                        ForEach(InputMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Who") {
                    if inputMode == .newRelative {
                        TextField("Name", text: $name)
                        TextField("Age (optional)", text: $age)
                            .keyboardType(.numberPad)
                    } else if existingContactOptions.isEmpty {
                        Text("No available contacts to link")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(DunbarTheme.textSecondary)
                    } else {
                        Picker("Contact", selection: $selectedExistingContactKey) {
                            ForEach(existingContactKeyValues, id: \.key) { item in
                                Text(item.person.name).tag(item.key)
                            }
                        }
                    }
                }
                
                Section("Connection") {
                    Picker("Relationship", selection: $selectedKind) {
                        ForEach(FamilyConnectionKind.allCases) { kind in
                            Text(kind.label).tag(kind)
                        }
                    }
                    
                    Picker("To", selection: Binding(
                        get: { selectedTargetID ?? targets.first?.id },
                        set: { selectedTargetID = $0 }
                    )) {
                        ForEach(targets) { target in
                            Text(target.isPrimaryContact ? "\(target.name) (Contact)" : target.name)
                                .tag(Optional(target.id))
                        }
                    }
                    
                    if inputMode == .newRelative {
                        TextField("Display role (optional)", text: $roleHint)
                    }
                }
                
                if shouldShowCoParentOptions {
                    Section("Parent links") {
                        Toggle("Also link to partner", isOn: $alsoLinkToCoParent)
                        
                        if alsoLinkToCoParent {
                            Picker("Partner", selection: Binding(
                                get: { selectedCoParentID ?? availableCoParents.first?.id },
                                set: { selectedCoParentID = $0 }
                            )) {
                                ForEach(availableCoParents) { target in
                                    Text(target.isPrimaryContact ? "\(target.name) (Contact)" : target.name)
                                        .tag(Optional(target.id))
                                }
                            }
                        }
                    }
                }
                
                Section("Preview") {
                    Text(
                        previewLine
                    )
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(DunbarTheme.textSecondary)
                }
            }
            .navigationTitle("Add family link")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let targetID = selectedTargetID ?? targets.first?.id else { return }
                        let cleanRole = roleHint.trimmingCharacters(in: .whitespacesAndNewlines)
                        let existingContact = inputMode == .existingContact ? selectedExistingContact : nil
                        onSave(
                            inputMode == .newRelative
                                ? name.trimmingCharacters(in: .whitespacesAndNewlines)
                                : (selectedExistingContact?.name ?? ""),
                            inputMode == .newRelative ? Int(age) : nil,
                            targetID,
                            selectedKind,
                            inputMode == .newRelative ? (cleanRole.isEmpty ? nil : cleanRole) : nil,
                            (alsoLinkToCoParent && selectedKind == .childOfTarget)
                                ? (selectedCoParentID ?? availableCoParents.first?.id)
                                : nil,
                            existingContact
                        )
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
            .onAppear {
                if selectedTargetID == nil {
                    selectedTargetID = defaultTargetID ?? targets.first?.id
                }
                if selectedCoParentID == nil {
                    selectedCoParentID = availableCoParents.first?.id
                }
                if selectedExistingContactKey.isEmpty {
                    selectedExistingContactKey = existingContactKeyValues.first?.key ?? ""
                }
            }
            .onChange(of: selectedTargetID) { _, _ in
                selectedCoParentID = availableCoParents.first?.id
            }
            .onChange(of: selectedKind) { _, newKind in
                if newKind != .childOfTarget {
                    alsoLinkToCoParent = false
                } else if !availableCoParents.isEmpty {
                    alsoLinkToCoParent = true
                }
            }
            .onChange(of: inputMode) { _, newMode in
                if newMode == .existingContact, selectedExistingContactKey.isEmpty {
                    selectedExistingContactKey = existingContactKeyValues.first?.key ?? ""
                }
            }
        }
    }

    private var previewLine: String {
        switch inputMode {
        case .newRelative:
            let displayName = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "This person"
                : name.trimmingCharacters(in: .whitespacesAndNewlines)
            return "\(displayName) will be added as \(selectedKind.label.lowercased()) \(selectedTargetName)."
        case .existingContact:
            return "\(selectedExistingContactName) will be linked as \(selectedKind.label.lowercased()) \(selectedTargetName)."
        }
    }
}

private struct AddFamilyMemberSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    @State private var name: String
    @State private var relation: String
    @State private var age: String
    
    let saveLabel: String
    let onSave: (String, String, Int?) -> Void
    
    init(
        initialName: String = "",
        initialRelation: String = "",
        initialAge: Int? = nil,
        saveLabel: String = "Save",
        onSave: @escaping (String, String, Int?) -> Void
    ) {
        self._name = State(initialValue: initialName)
        self._relation = State(initialValue: initialRelation)
        self._age = State(initialValue: initialAge.map(String.init) ?? "")
        self.saveLabel = saveLabel
        self.onSave = onSave
    }
    
    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !relation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Family member") {
                    TextField("Name", text: $name)
                    TextField("Relation", text: $relation)
                    TextField("Age (optional)", text: $age)
                        .keyboardType(.numberPad)
                }
            }
            .navigationTitle("Add family")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saveLabel) {
                        onSave(
                            name.trimmingCharacters(in: .whitespacesAndNewlines),
                            relation.trimmingCharacters(in: .whitespacesAndNewlines),
                            Int(age)
                        )
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
        }
    }
}

// MARK: - Edit Person

struct EditPersonView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(NudgeScheduler.self) private var nudgeScheduler
    @Bindable var person: Person
    
    @Query(filter: #Predicate<Person> { !$0.isArchived })
    private var people: [Person]
    
    @State private var name: String = ""
    @State private var ring: DunbarRing = .meaningful
    @State private var cadence: Cadence = .monthly
    @State private var notes: String = ""
    @State private var reminderTime: Date = .now
    @State private var hasLoaded = false
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                }
                Section("Relationship circle") {
                    Picker("Circle", selection: $ring) {
                        ForEach(DunbarRing.allCases) { r in
                            Text("\(r.label) (\(r.capacity))").tag(r)
                        }
                    }
                    .pickerStyle(.menu)
                    
                    Text("Recommended cadence: \(ring.defaultCadence.label)")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(DunbarTheme.textSecondary)
                    
                    Text(ringCapacityText)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(selectedRingAtCapacity ? DunbarTheme.textSecondary : DunbarTheme.textTertiary)
                }
                Section("Cadence") {
                    Picker("How often", selection: $cadence) {
                        ForEach(Cadence.allCases) { c in
                            Text(c.label).tag(c)
                        }
                    }
                    .pickerStyle(.menu)
                }
                Section("Reminder") {
                    DatePicker(
                        "Time",
                        selection: $reminderTime,
                        displayedComponents: .hourAndMinute
                    )
                    .datePickerStyle(.compact)
                    
                    Text(nextReminderPreviewText)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(DunbarTheme.textSecondary)
                }
                Section("Notes") {
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(2...6)
                }
            }
            .navigationTitle("Edit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        person.name = name.trimmingCharacters(in: .whitespaces)
                        person.initials = Person.makeInitials(from: name)
                        person.ring = ring
                        person.cadence = cadence
                        person.notes = notes.trimmingCharacters(in: .whitespaces)
                        let components = Calendar.current.dateComponents([.hour, .minute], from: reminderTime)
                        person.reminderHour = components.hour ?? person.reminderHour
                        person.reminderMinute = components.minute ?? person.reminderMinute
                        Task {
                            await nudgeScheduler.schedule(for: person)
                            WidgetSnapshotStore.write(WidgetSnapshotStore.buildSnapshot(people: people))
                        }
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                name = person.name
                ring = person.ring
                cadence = person.cadence
                notes = person.notes
                reminderTime = Calendar.current.date(
                    bySettingHour: person.reminderHour,
                    minute: person.reminderMinute,
                    second: 0,
                    of: .now
                ) ?? .now
                hasLoaded = true
            }
            .onChange(of: ring) { _, newRing in
                guard hasLoaded else { return }
                cadence = newRing.defaultCadence
            }
        }
    }
    
    private var reminderComponents: DateComponents {
        Calendar.current.dateComponents([.hour, .minute], from: reminderTime)
    }
    
    private var previewReminderHour: Int {
        reminderComponents.hour ?? person.reminderHour
    }
    
    private var previewReminderMinute: Int {
        reminderComponents.minute ?? person.reminderMinute
    }
    
    private var nextReminderPreviewText: String {
        guard let nextReminderDate = NudgeScheduler.nextReminderDate(
            cadence: cadence,
            lastContactedAt: person.lastContactedAt,
            hasPriorContact: !person.checkIns.isEmpty,
            reminderHour: previewReminderHour,
            reminderMinute: previewReminderMinute,
            snoozedUntilAt: person.snoozedUntilAt
        ) else {
            return "Next reminder date unavailable"
        }
        
        let day = nextReminderDate.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        let time = nextReminderDate.formatted(date: .omitted, time: .shortened)
        
        if cadence == .daily {
            return "Starts \(day) at \(time), then repeats daily."
        }
        if person.checkIns.isEmpty {
            return "First reminder: \(day) at \(time)."
        }
        return "Next reminder: \(day) at \(time)."
    }
    
    private var selectedRingCountAfterMove: Int {
        let selectedCount = people.filter { $0.ring == ring }.count
        if ring == person.ring {
            return selectedCount
        }
        return selectedCount + 1
    }
    
    private var selectedRingAtCapacity: Bool {
        selectedRingCountAfterMove >= ring.capacity
    }
    
    private var ringCapacityText: String {
        if selectedRingAtCapacity {
            return "This circle would be \(selectedRingCountAfterMove)/\(ring.capacity). Consider rebalancing."
        }
        return "This circle would be \(selectedRingCountAfterMove)/\(ring.capacity)."
    }
}
