import SwiftUI
import SwiftData
import PhotosUI
import StoreKit

struct AddPersonView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.requestReview) private var requestReview
    @Environment(NudgeScheduler.self) private var nudgeScheduler
    
    @Query(filter: #Predicate<Person> { !$0.isArchived })
    private var people: [Person]
    
    @State private var name = ""
    @State private var ring: DunbarRing? = nil
    @State private var cadence: Cadence = .monthly
    @State private var notes = ""
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var reminderTime: Date = .now
    @State private var roleTitle = ""
    @State private var roleCompany = ""
    @State private var familyName = ""
    @State private var familyRoleHint = ""
    @State private var familyAge = ""
    @State private var selectedFamilyInputMode: DraftFamilyInputMode = .newRelative
    @State private var selectedFamilyExistingContactKey: String = ""
    @State private var selectedFamilyTargetID: UUID?
    @State private var selectedFamilyRelationKind: DraftFamilyConnectionKind = .partnerOfTarget
    @State private var alsoLinkFamilyCoParent = true
    @State private var selectedFamilyCoParentID: UUID?
    @State private var familyDrafts: [DraftFamilyConnectionDraft] = []
    @State private var draftContactID = UUID()
    
    @FocusState private var nameFieldFocused: Bool
    
    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && ring != nil
    }

    private var draftInitials: String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return "?" }
        return Person.makeInitials(from: trimmed)
    }
    
    private var draftContactName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Contact" : trimmed
    }
    
    private var familyDraftTargets: [FamilyDraftTargetOption] {
        var targets = [FamilyDraftTargetOption(id: draftContactID, name: draftContactName, isContact: true)]
        targets.append(contentsOf: familyDrafts.map {
            FamilyDraftTargetOption(id: $0.id, name: $0.name, isContact: $0.existingContact != nil)
        })
        return targets
    }

    private var existingFamilyContactOptions: [Person] {
        let alreadyLinked = Set(familyDrafts.compactMap { $0.existingContact?.persistentModelID })
        return people
            .filter { !alreadyLinked.contains($0.persistentModelID) }
            .sorted(by: Person.urgencyComparator)
    }

    private var existingFamilyContactKeyValues: [(key: String, person: Person)] {
        existingFamilyContactOptions.map { (String(describing: $0.persistentModelID), $0) }
    }

    private var selectedExistingFamilyContact: Person? {
        existingFamilyContactKeyValues.first(where: { $0.key == selectedFamilyExistingContactKey })?.person
    }
    
    private var availableDraftCoParents: [FamilyDraftTargetOption] {
        guard let targetID = selectedFamilyTargetID ?? familyDraftTargets.first?.id else { return [] }
        return familyDraftTargets.filter { $0.id != targetID }
    }
    
    private var shouldShowDraftCoParentOptions: Bool {
        selectedFamilyRelationKind == .childOfTarget && !availableDraftCoParents.isEmpty
    }

    private var isFamilyDraftInputValid: Bool {
        guard (selectedFamilyTargetID ?? familyDraftTargets.first?.id) != nil else {
            return false
        }

        switch selectedFamilyInputMode {
        case .newRelative:
            return !familyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .existingContact:
            return selectedExistingFamilyContact != nil
        }
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Title
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Add contact")
                            .font(DunbarTheme.titleFont)
                            .foregroundStyle(DunbarTheme.textPrimary)
                        
                        Text("Create a reminder to stay in touch")
                            .font(DunbarTheme.subtitleFont)
                            .foregroundStyle(DunbarTheme.textSecondary)
                    }
                    .padding(.bottom, 28)
                    
                    // Photo picker
                    photoSection
                    
                    // Name field
                    fieldSection("NAME") {
                        TextField("e.g. Sarah, Dad, Chris W", text: $name)
                            .font(.system(size: 16))
                            .foregroundStyle(DunbarTheme.textPrimary)
                            .padding(14)
                            .background(DunbarTheme.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .strokeBorder(
                                        nameFieldFocused ? DunbarTheme.green : Color.clear,
                                        lineWidth: 1.5
                                    )
                            )
                            .focused($nameFieldFocused)
                    }

                    // Ring picker
                    fieldSection("RELATIONSHIP CIRCLE") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(DunbarRing.allCases) { option in
                                    RingChip(
                                        ring: option,
                                        isSelected: ring == option
                                    ) {
                                        withAnimation(.easeInOut(duration: 0.15)) {
                                            ring = option
                                            cadence = option.defaultCadence
                                        }
                                    }
                                }
                            }
                        }
                        
                        if let ring {
                            Text("Recommended cadence: \(ring.defaultCadence.label)")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(DunbarTheme.textSecondary)
                                .padding(.top, 2)
                        } else {
                            Text("Select a circle to set recommended cadence.")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(DunbarTheme.textTertiary)
                                .padding(.top, 2)
                        }
                        
                        Text(ringCapacityText)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(ringIsAtCapacity ? DunbarTheme.textSecondary : DunbarTheme.textTertiary)
                    }
                    
                    // Cadence picker
                    fieldSection("HOW OFTEN?") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(Cadence.allCases) { option in
                                    CadenceChip(
                                        label: option.shortLabel,
                                        isSelected: cadence == option
                                    ) {
                                        withAnimation(.easeInOut(duration: 0.15)) {
                                            cadence = option
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                        .padding(.horizontal, -20)
                    }
                    
                    fieldSection("REMINDER TIME") {
                        DatePicker(
                            "Reminder time",
                            selection: $reminderTime,
                            displayedComponents: .hourAndMinute
                        )
                        .datePickerStyle(.compact)
                        .labelsHidden()
                        
                        Text(nextReminderPreviewText)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(DunbarTheme.textSecondary)
                            .padding(.top, 2)
                    }

                    // Notes
                    fieldSection("NOTES", subtitle: "(optional)") {
                        TextField("e.g. Ask about the new job", text: $notes, axis: .vertical)
                            .font(.system(size: 15))
                            .foregroundStyle(DunbarTheme.textPrimary)
                            .lineLimit(2...4)
                            .padding(14)
                            .background(DunbarTheme.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    
                    fieldSection("CURRENT ROLE", subtitle: "(optional)") {
                        VStack(spacing: 8) {
                            TextField("Role title", text: $roleTitle)
                                .font(.system(size: 15))
                                .foregroundStyle(DunbarTheme.textPrimary)
                                .padding(12)
                                .background(DunbarTheme.surface)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            
                            TextField("Company", text: $roleCompany)
                                .font(.system(size: 15))
                                .foregroundStyle(DunbarTheme.textPrimary)
                                .padding(12)
                                .background(DunbarTheme.surface)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        
                        Text("This appears as the subtle subtitle on contact cards.")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(DunbarTheme.textTertiary)
                    }
                    
                    fieldSection("FAMILY TREE", subtitle: "(optional)") {
                        VStack(spacing: 8) {
                            Picker("Add type", selection: $selectedFamilyInputMode) {
                                ForEach(DraftFamilyInputMode.allCases) { mode in
                                    Text(mode.title).tag(mode)
                                }
                            }
                            .pickerStyle(.segmented)

                            if selectedFamilyInputMode == .newRelative {
                                TextField("Name", text: $familyName)
                                    .font(.system(size: 15))
                                    .foregroundStyle(DunbarTheme.textPrimary)
                                    .padding(12)
                                    .background(DunbarTheme.surface)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                
                                TextField("Age (optional)", text: $familyAge)
                                    .font(.system(size: 15))
                                    .foregroundStyle(DunbarTheme.textPrimary)
                                    .keyboardType(.numberPad)
                                    .padding(12)
                                    .background(DunbarTheme.surface)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            } else if existingFamilyContactOptions.isEmpty {
                                Text("No available contacts to link")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(DunbarTheme.textSecondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 6)
                            } else {
                                Picker("Contact", selection: $selectedFamilyExistingContactKey) {
                                    ForEach(existingFamilyContactKeyValues, id: \.key) { item in
                                        Text(item.person.name).tag(item.key)
                                    }
                                }
                                .pickerStyle(.menu)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            
                            Picker("Relationship", selection: $selectedFamilyRelationKind) {
                                ForEach(DraftFamilyConnectionKind.allCases) { relation in
                                    Text(relation.label).tag(relation)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            
                            Picker("To", selection: Binding(
                                get: { selectedFamilyTargetID ?? familyDraftTargets.first?.id },
                                set: { selectedFamilyTargetID = $0 }
                            )) {
                                ForEach(familyDraftTargets) { target in
                                    Text(target.isContact ? "\(target.name) (Contact)" : target.name)
                                        .tag(Optional(target.id))
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            
                            TextField("Display role (optional)", text: $familyRoleHint)
                                .font(.system(size: 15))
                                .foregroundStyle(DunbarTheme.textPrimary)
                                .padding(12)
                                .background(DunbarTheme.surface)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            
                            if shouldShowDraftCoParentOptions {
                                Toggle("Also link to partner", isOn: $alsoLinkFamilyCoParent)
                                    .font(.system(size: 13, weight: .medium))
                                    .tint(DunbarTheme.ringColor(for: .core))
                                
                                if alsoLinkFamilyCoParent {
                                    Picker("Partner", selection: Binding(
                                        get: { selectedFamilyCoParentID ?? availableDraftCoParents.first?.id },
                                        set: { selectedFamilyCoParentID = $0 }
                                    )) {
                                        ForEach(availableDraftCoParents) { target in
                                            Text(target.isContact ? "\(target.name) (Contact)" : target.name)
                                                .tag(Optional(target.id))
                                        }
                                    }
                                    .pickerStyle(.menu)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                            
                            Button(action: addFamilyDraft) {
                                HStack(spacing: 6) {
                                    Image(systemName: "plus")
                                    Text("Add family connection")
                                }
                                .font(.system(size: 12, weight: .semibold))
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
                            .disabled(!isFamilyDraftInputValid)
                            
                            if !familyDrafts.isEmpty {
                                VStack(alignment: .leading, spacing: 6) {
                                    ForEach(familyDrafts) { draft in
                                        HStack(spacing: 8) {
                                            Text(familyDraftSummary(draft))
                                                .font(.system(size: 12, weight: .medium))
                                                .foregroundStyle(DunbarTheme.textPrimary)
                                            
                                            Spacer()
                                            
                                            Button(role: .destructive) {
                                                removeFamilyDraft(id: draft.id)
                                            } label: {
                                                Image(systemName: "trash")
                                                    .font(.system(size: 12, weight: .semibold))
                                            }
                                            .buttonStyle(.plain)
                                            .foregroundStyle(DunbarTheme.textSecondary)
                                        }
                                        .padding(.vertical, 4)
                                    }
                                }
                                .padding(10)
                                .background(DunbarTheme.surface)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                        }
                    }
                    
                    // Preview card
                    if isValid {
                        previewCard
                            .transition(.opacity.combined(with: .scale(scale: 0.95)))
                            .padding(.bottom, 20)
                    }
                }
                .padding(.horizontal, 20)
            }
            .background(DunbarTheme.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(DunbarTheme.red)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { createContact() }
                        .foregroundStyle(isValid ? DunbarTheme.green : DunbarTheme.textTertiary)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .disabled(!isValid)
                }
            }
            .onAppear {
                nameFieldFocused = true
                reminderTime = Calendar.current.date(
                    bySettingHour: AppSettings.defaultReminderHour,
                    minute: AppSettings.defaultReminderMinute,
                    second: 0,
                    of: .now
                ) ?? .now
                selectedFamilyTargetID = selectedFamilyTargetID ?? draftContactID
                selectedFamilyCoParentID = selectedFamilyCoParentID ?? availableDraftCoParents.first?.id
                if selectedFamilyExistingContactKey.isEmpty {
                    selectedFamilyExistingContactKey = existingFamilyContactKeyValues.first?.key ?? ""
                }
            }
            .onChange(of: selectedFamilyTargetID) { _, _ in
                selectedFamilyCoParentID = availableDraftCoParents.first?.id
            }
            .onChange(of: selectedFamilyRelationKind) { _, newValue in
                if newValue != .childOfTarget {
                    alsoLinkFamilyCoParent = false
                    selectedFamilyCoParentID = nil
                } else {
                    alsoLinkFamilyCoParent = true
                    selectedFamilyCoParentID = availableDraftCoParents.first?.id
                }
            }
            .onChange(of: selectedFamilyInputMode) { _, newMode in
                if newMode == .existingContact, selectedFamilyExistingContactKey.isEmpty {
                    selectedFamilyExistingContactKey = existingFamilyContactKeyValues.first?.key ?? ""
                }
            }
            .onChange(of: familyDrafts.count) { _, _ in
                if existingFamilyContactKeyValues.contains(where: { $0.key == selectedFamilyExistingContactKey }) == false {
                    selectedFamilyExistingContactKey = existingFamilyContactKeyValues.first?.key ?? ""
                }
            }
        }
    }
    
    // MARK: - Photo Section
    
    private var photoSection: some View {
        VStack(spacing: 8) {
            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                if let photoData, let uiImage = UIImage(data: photoData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 80, height: 80)
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .strokeBorder(DunbarTheme.green, lineWidth: 2.5)
                        )
                } else {
                    ZStack {
                        Circle()
                            .fill(DunbarTheme.surface)
                            .frame(width: 80, height: 80)

                        Text(draftInitials)
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(DunbarTheme.ringColor(for: ring ?? .core))
                    }
                    .overlay(
                        Circle()
                            .strokeBorder(DunbarTheme.ringColor(for: ring ?? .core).opacity(0.9), lineWidth: 2.5)
                    )
                }
            }
            
            Text(photoData == nil ? "Add photo" : "Change photo")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(DunbarTheme.green)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 24)
        .onChange(of: selectedPhoto) { _, newItem in
            Task {
                if let data = try? await newItem?.loadTransferable(type: Data.self) {
                    // Reject files larger than 10 MB to prevent memory issues
                    guard data.count <= 10_000_000 else { return }
                    // Compress to JPEG and downscale to keep storage small
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
                        photoData = scaled.jpegData(compressionQuality: 0.7) ?? data
                    } else {
                        photoData = data
                    }
                }
            }
        }
    }
    
    // MARK: - Subviews
    
    private func fieldSection(
        _ title: String,
        subtitle: String? = nil,
        @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DunbarTheme.textTertiary)
                    .tracking(0.8)
                
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(DunbarTheme.textTertiary)
                }
            }
            
            content()
        }
        .padding(.bottom, 20)
    }
    
    private var previewCard: some View {
        VStack(spacing: 4) {
            if let photoData, let uiImage = UIImage(data: photoData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 64, height: 64)
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .strokeBorder(DunbarTheme.green, lineWidth: 2)
                    )
            } else {
                Circle()
                    .fill(DunbarTheme.surface)
                    .frame(width: 64, height: 64)
                    .overlay {
                        Text(draftInitials)
                            .font(.system(size: 23, weight: .semibold))
                            .foregroundStyle(DunbarTheme.ringColor(for: ring ?? .core))
                    }
                    .overlay(
                        Circle()
                            .strokeBorder(DunbarTheme.ringColor(for: ring ?? .core).opacity(0.9), lineWidth: 2)
                    )
            }
            
            Text(name.trimmingCharacters(in: .whitespaces))
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(DunbarTheme.textPrimary)
            
            Text(cadence.label)
                .font(.system(size: 13))
                .foregroundStyle(DunbarTheme.green)
            
            Text((ring ?? .core).shortLabel)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DunbarTheme.ringColor(for: ring ?? .core))

        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(DunbarTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(DunbarTheme.border, lineWidth: 1)
        )
    }
    
    // MARK: - Actions
    
    private func createContact() {
        guard isValid, let selectedRing = ring else { return }
        
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        
        let person = Person(
            name: trimmedName,
            ring: selectedRing,
            cadence: cadence,
            plantType: .succulent,
            notes: notes.trimmingCharacters(in: .whitespaces),
            photoData: photoData,
            reminderHour: reminderComponents.hour ?? AppSettings.defaultReminderHour,
            reminderMinute: reminderComponents.minute ?? AppSettings.defaultReminderMinute
        )
        modelContext.insert(person)
        
        let trimmedRoleTitle = roleTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedRoleCompany = roleCompany.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedRoleTitle.isEmpty, !trimmedRoleCompany.isEmpty {
            let role = CareerRole(
                person: person,
                title: trimmedRoleTitle,
                company: trimmedRoleCompany,
                startYear: Calendar.current.component(.year, from: .now),
                endYear: nil,
                isCurrent: true,
                sortOrder: 1
            )
            modelContext.insert(role)
        }
        
        var drafts = familyDrafts
        if let pendingDraft = pendingFamilyDraftFromInputs() {
            drafts.append(pendingDraft)
        }
        
        buildFamilyGraph(for: person, drafts: drafts)
        
        Task {
            await nudgeScheduler.schedule(for: person)
            WidgetSnapshotStore.write(WidgetSnapshotStore.buildSnapshot(people: people + [person]))
        }

        // Request App Store review after adding the 3rd real contact
        let realContactCount = people.filter { !$0.isDummyData }.count + 1 // +1 for the one just added
        if realContactCount >= 3 && !AppSettings.hasRequestedReview {
            AppSettings.hasRequestedReview = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                requestReview()
            }
        }

        dismiss()
    }
    
    private func addFamilyDraft() {
        guard let draft = pendingFamilyDraftFromInputs() else { return }
        familyDrafts.append(draft)
        resetFamilyDraftInputs()
    }
    
    private func removeFamilyDraft(id: UUID) {
        familyDrafts.removeAll { $0.id == id }
    }
    
    private func pendingFamilyDraftFromInputs() -> DraftFamilyConnectionDraft? {
        guard let targetID = selectedFamilyTargetID ?? familyDraftTargets.first?.id else {
            return nil
        }
        
        let trimmedRole = familyRoleHint.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedRole = trimmedRole.isEmpty ? selectedFamilyRelationKind.defaultRoleHint : trimmedRole
        let trimmedName = familyName.trimmingCharacters(in: .whitespacesAndNewlines)
        let parsedAge = selectedFamilyInputMode == .newRelative
            ? Int(familyAge.trimmingCharacters(in: .whitespacesAndNewlines))
            : nil
        let coParentID = (alsoLinkFamilyCoParent && selectedFamilyRelationKind == .childOfTarget)
            ? (selectedFamilyCoParentID ?? availableDraftCoParents.first?.id)
            : nil

        let resolvedName: String
        let linkedContact: Person?
        switch selectedFamilyInputMode {
        case .newRelative:
            guard !trimmedName.isEmpty else { return nil }
            resolvedName = trimmedName
            linkedContact = nil
        case .existingContact:
            guard let selectedExistingFamilyContact else { return nil }
            resolvedName = selectedExistingFamilyContact.name
            linkedContact = selectedExistingFamilyContact
        }
        
        return DraftFamilyConnectionDraft(
            name: resolvedName,
            age: parsedAge,
            roleHint: resolvedRole,
            targetID: targetID,
            relationKind: selectedFamilyRelationKind,
            coParentTargetID: coParentID,
            existingContact: linkedContact
        )
    }
    
    private func resetFamilyDraftInputs() {
        if selectedFamilyInputMode == .newRelative {
            familyName = ""
        }
        familyRoleHint = ""
        familyAge = ""
        selectedFamilyRelationKind = .partnerOfTarget
        selectedFamilyTargetID = draftContactID
        alsoLinkFamilyCoParent = false
        selectedFamilyCoParentID = nil
        if selectedFamilyInputMode == .existingContact {
            selectedFamilyExistingContactKey = existingFamilyContactKeyValues.first?.key ?? ""
        }
    }
    
    private func familyDraftSummary(_ draft: DraftFamilyConnectionDraft) -> String {
        let targetName = familyDraftTargets.first(where: { $0.id == draft.targetID })?.name ?? "Contact"
        var summary = "\(draft.name) · \(draft.relationKind.label.lowercased()) \(targetName)"
        if let coParentID = draft.coParentTargetID,
           let coParentName = familyDraftTargets.first(where: { $0.id == coParentID })?.name,
           draft.relationKind == .childOfTarget {
            summary += " + \(coParentName)"
        }
        return summary
    }
    
    private var reminderComponents: DateComponents {
        Calendar.current.dateComponents([.hour, .minute], from: reminderTime)
    }
    
    private var draftReminderHour: Int {
        reminderComponents.hour ?? AppSettings.defaultReminderHour
    }
    
    private var draftReminderMinute: Int {
        reminderComponents.minute ?? AppSettings.defaultReminderMinute
    }
    
    private var nextReminderDatePreview: Date? {
        NudgeScheduler.nextReminderDate(
            cadence: cadence,
            lastContactedAt: .now,
            hasPriorContact: false,
            reminderHour: draftReminderHour,
            reminderMinute: draftReminderMinute
        )
    }
    
    private var nextReminderPreviewText: String {
        guard let nextReminderDatePreview else {
            return "Next reminder date unavailable"
        }
        
        let day = nextReminderDatePreview.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        let time = nextReminderDatePreview.formatted(date: .omitted, time: .shortened)
        
        if cadence == .daily {
            return "Starts \(day) at \(time), then repeats daily."
        }
        return "First reminder: \(day) at \(time)."
    }
    
    private var ringCount: Int {
        guard let ring else { return 0 }
        return people.filter { $0.ring == ring }.count
    }

    private func buildFamilyGraph(for person: Person, drafts: [DraftFamilyConnectionDraft]) {
        guard !drafts.isEmpty else { return }

        let anchor = FamilyGraphV2Service.ensureAnchorNode(for: person, context: modelContext)
        var nodeStableIDByDraftID: [UUID: UUID] = [draftContactID: anchor.stableID]

        for draft in drafts {
            guard let targetNodeID = nodeStableIDByDraftID[draft.targetID] else { continue }
            let coParentNodeID = draft.coParentTargetID.flatMap { nodeStableIDByDraftID[$0] }
            let (relationshipType, newNodeIsFrom) = relationshipSpec(for: draft.relationKind)

            if let existingContact = draft.existingContact {
                let existingAnchor = FamilyGraphV2Service.ensureAnchorNode(for: existingContact, context: modelContext)
                nodeStableIDByDraftID[draft.id] = existingAnchor.stableID

                FamilyGraphV2Service.linkExistingContact(
                    for: person,
                    existingContact: existingContact,
                    targetNodeID: targetNodeID,
                    relationshipType: relationshipType,
                    contactNodeIsFrom: newNodeIsFrom,
                    coParentNodeID: coParentNodeID,
                    context: modelContext
                )
            } else {
                let addedNode = FamilyGraphV2Service.addRelative(
                    for: person,
                    name: draft.name,
                    age: draft.age,
                    roleHint: draft.roleHint,
                    targetNodeID: targetNodeID,
                    relationshipType: relationshipType,
                    newNodeIsFrom: newNodeIsFrom,
                    coParentNodeID: coParentNodeID,
                    context: modelContext
                )
                if let addedNode {
                    nodeStableIDByDraftID[draft.id] = addedNode.stableID
                }
            }
        }

        do { try modelContext.save() } catch { print("[Dunbar] Save failed: \(error)") }
    }

    private func relationshipSpec(for kind: DraftFamilyConnectionKind) -> (type: FamilyRelationshipType, newNodeIsFrom: Bool) {
        switch kind {
        case .parentOfTarget:
            return (.parentOf, true)
        case .childOfTarget:
            return (.parentOf, false)
        case .partnerOfTarget:
            return (.partnerOf, true)
        case .siblingOfTarget:
            return (.siblingOf, true)
        case .guardianOfTarget:
            return (.guardianOf, true)
        case .formerPartnerOfTarget:
            return (.formerPartnerOf, true)
        case .relatedToTarget:
            return (.relatedTo, true)
        }
    }
    
    private var ringIsAtCapacity: Bool {
        guard let ring else { return false }
        return ringCount >= ring.capacity
    }
    
    private var ringCapacityText: String {
        guard let ring else {
            return "Pick a circle to view capacity."
        }
        if ringIsAtCapacity {
            return "Currently \(ringCount)/\(ring.capacity). Circle is full, consider rebalancing."
        }
        return "Currently \(ringCount)/\(ring.capacity) in this circle."
    }
}

private struct FamilyDraftTargetOption: Identifiable, Hashable {
    let id: UUID
    let name: String
    let isContact: Bool
}

private enum DraftFamilyInputMode: String, CaseIterable, Identifiable {
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

private enum DraftFamilyConnectionKind: String, CaseIterable, Identifiable {
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

private struct DraftFamilyConnectionDraft: Identifiable {
    let id: UUID
    let name: String
    let age: Int?
    let roleHint: String
    let targetID: UUID
    let relationKind: DraftFamilyConnectionKind
    let coParentTargetID: UUID?
    let existingContact: Person?
    
    init(
        id: UUID = UUID(),
        name: String,
        age: Int?,
        roleHint: String,
        targetID: UUID,
        relationKind: DraftFamilyConnectionKind,
        coParentTargetID: UUID? = nil,
        existingContact: Person? = nil
    ) {
        self.id = id
        self.name = name
        self.age = age
        self.roleHint = roleHint
        self.targetID = targetID
        self.relationKind = relationKind
        self.coParentTargetID = coParentTargetID
        self.existingContact = existingContact
    }
}

// MARK: - Cadence Chip

private struct CadenceChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isSelected ? DunbarTheme.green : DunbarTheme.textSecondary)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
                .background(isSelected ? DunbarTheme.backgroundColor(for: .thriving) : DunbarTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(
                            isSelected ? DunbarTheme.green : DunbarTheme.border,
                            lineWidth: isSelected ? 2 : 1
                        )
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Ring Chip

private struct RingChip: View {
    let ring: DunbarRing
    let isSelected: Bool
    let action: () -> Void
    
    private var ringColor: Color {
        DunbarTheme.ringColor(for: ring)
    }
    
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 1) {
                Text(ring.label)
                    .font(.system(size: 13, weight: .semibold))
                Text("\(ring.capacity) people")
                    .font(.system(size: 11, weight: .medium))
                    .opacity(0.82)
            }
            .foregroundStyle(isSelected ? ringColor : DunbarTheme.textSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(isSelected ? ringColor.opacity(0.14) : DunbarTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(
                        isSelected ? ringColor : DunbarTheme.border,
                        lineWidth: isSelected ? 2 : 1
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    AddPersonView()
        .modelContainer(for: [Person.self, CheckIn.self, CareerRole.self, FamilyMember.self, FamilyPerson.self, FamilyRelationship.self, FamilyGraphV2.self, FamilyNodeV2.self, FamilyEdgeV2.self], inMemory: true)
        .environment(NudgeScheduler())
}
