import SwiftUI
import SwiftData

struct RebalanceView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(NudgeScheduler.self) private var nudgeScheduler
    @Environment(PremiumManager.self) private var premiumManager
    
    @Query(
        filter: #Predicate<Person> { !$0.isArchived },
        sort: [SortDescriptor(\Person.lastContactedAt, order: .forward)]
    ) private var people: [Person]
    
    @Query(sort: [SortDescriptor(\CheckIn.contactedAt, order: .reverse)])
    private var allCheckIns: [CheckIn]
    
    @State private var deferredSuggestionIDs: Set<String> = []
    @State private var historyEntries: [DunbarRebalanceHistoryEntry] = []
    
    private var allSuggestions: [DunbarRebalanceSuggestion] {
        DunbarRebalanceAdvisor.suggestions(
            people: people,
            checkIns: allCheckIns
        )
    }
    
    private var activeSuggestions: [DunbarRebalanceSuggestion] {
        allSuggestions.filter { !deferredSuggestionIDs.contains($0.id) }
    }
    
    private var deferredSuggestions: [DunbarRebalanceSuggestion] {
        allSuggestions.filter { deferredSuggestionIDs.contains($0.id) }
    }
    
    @State private var showingPaywall = false

    var body: some View {
        ZStack {
            DunbarTheme.background
                .ignoresSafeArea()

            if premiumManager.isPremium {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        header

                        if !activeSuggestions.isEmpty {
                            activeSuggestionsCard
                        }

                        if !deferredSuggestions.isEmpty {
                            deferredSuggestionsCard
                        }

                        historyCard
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 14)
                    .padding(.bottom, 26)
                }
            } else {
                premiumUpgradePrompt
            }
        }
        .navigationTitle("Rebalance")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }
                    .foregroundStyle(DunbarTheme.ringColor(for: .core))
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
            }
        }
        .sheet(isPresented: $showingPaywall) {
            PaywallView()
        }
        .onAppear(perform: reloadData)
    }

    private var premiumUpgradePrompt: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(DunbarTheme.ringColor(for: .core).opacity(0.6))

            Text("Rebalancing is a premium feature")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(DunbarTheme.textPrimary)
                .multilineTextAlignment(.center)

            Text("Get smart suggestions to promote or move contacts between circles based on your activity.")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(DunbarTheme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button {
                showingPaywall = true
            } label: {
                Text("Unlock Premium")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .dunbarPrimaryButton()
            .padding(.horizontal, 40)

            Spacer()
        }
    }
    
    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Circle rebalancing")
                .font(DunbarTheme.titleFont)
                .foregroundStyle(DunbarTheme.textPrimary)

            Text("Apply suggestions in bulk or review previous circle moves.")
                .font(DunbarTheme.subtitleFont)
                .foregroundStyle(DunbarTheme.textSecondary)
        }
    }
    
    private var activeSuggestionsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Active suggestions")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DunbarTheme.textSecondary)
                
                Spacer()
                
                Button("Apply all (\(activeSuggestions.count))") {
                    applyAllActiveSuggestions()
                }
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(DunbarTheme.ringColor(for: .core))
            }
            
            ForEach(Array(activeSuggestions.enumerated()), id: \.element.id) { index, suggestion in
                suggestionRow(
                    suggestion: suggestion,
                    primaryLabel: suggestion.actionLabel,
                    primaryAction: { applySuggestion(suggestion) },
                    secondaryLabel: "Later",
                    secondaryAction: { deferSuggestion(suggestion) }
                )
                
                if index < activeSuggestions.count - 1 {
                    Divider()
                        .foregroundStyle(DunbarTheme.border)
                }
            }
        }
        .dunbarCard()
    }
    
    private var deferredSuggestionsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Deferred until next week")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(DunbarTheme.textSecondary)
            
            ForEach(Array(deferredSuggestions.enumerated()), id: \.element.id) { index, suggestion in
                suggestionRow(
                    suggestion: suggestion,
                    primaryLabel: "Apply now",
                    primaryAction: { applySuggestion(suggestion) },
                    secondaryLabel: "Undo defer",
                    secondaryAction: { clearDeferral(for: suggestion) }
                )
                
                if index < deferredSuggestions.count - 1 {
                    Divider()
                        .foregroundStyle(DunbarTheme.border)
                }
            }
        }
        .dunbarCard()
    }
    
    private var historyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("History")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(DunbarTheme.textSecondary)
            
            if historyEntries.isEmpty {
                Text("No rebalance activity yet.")
                    .font(.system(size: 13))
                    .foregroundStyle(DunbarTheme.textSecondary)
            } else {
                ForEach(Array(historyEntries.prefix(40).enumerated()), id: \.element.id) { index, entry in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(historyHeadline(for: entry))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(DunbarTheme.textPrimary)
                        
                        Text(historyDetail(for: entry))
                            .font(.system(size: 13))
                            .foregroundStyle(DunbarTheme.textSecondary)
                    }
                    
                    if index < min(historyEntries.count - 1, 39) {
                        Divider()
                            .foregroundStyle(DunbarTheme.border)
                    }
                }
            }
        }
        .dunbarCard()
    }
    
    private func suggestionRow(
        suggestion: DunbarRebalanceSuggestion,
        primaryLabel: String,
        primaryAction: @escaping () -> Void,
        secondaryLabel: String,
        secondaryAction: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(suggestion.person.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(DunbarTheme.textPrimary)
                
                Spacer()
                
                Text("\(suggestion.person.ring.label) → \(suggestion.targetRing.label)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DunbarTheme.textSecondary)
            }
            
            Text(suggestion.reason)
                .font(.system(size: 13))
                .foregroundStyle(DunbarTheme.textSecondary)
            
            HStack(spacing: 8) {
                Button(primaryLabel, action: primaryAction)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [DunbarTheme.ringColor(for: .core), DunbarTheme.ringColor(for: .close)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
                
                Button(secondaryLabel, action: secondaryAction)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(DunbarTheme.textSecondary)
            }
        }
    }
    
    private func applySuggestion(_ suggestion: DunbarRebalanceSuggestion) {
        let entry = DunbarRebalanceAdvisor.apply(suggestion)
        AppSettings.appendRebalanceHistory(entry)
        AppSettings.clearRebalanceSuggestionDeferral(id: suggestion.id)
        reloadData()
        
        Task {
            await nudgeScheduler.schedule(for: suggestion.person)
        }
    }
    
    private func applyAllActiveSuggestions() {
        let snapshot = activeSuggestions
        guard !snapshot.isEmpty else { return }
        
        for suggestion in snapshot {
            let entry = DunbarRebalanceAdvisor.apply(suggestion)
            AppSettings.appendRebalanceHistory(entry)
            AppSettings.clearRebalanceSuggestionDeferral(id: suggestion.id)
        }
        reloadData()
        
        Task {
            for suggestion in snapshot {
                await nudgeScheduler.schedule(for: suggestion.person)
            }
        }
    }
    
    private func deferSuggestion(_ suggestion: DunbarRebalanceSuggestion) {
        let deferredUntil = Calendar.current.date(byAdding: .day, value: 7, to: .now) ?? .now
        AppSettings.deferRebalanceSuggestion(id: suggestion.id, until: deferredUntil)
        
        let entry = DunbarRebalanceHistoryEntry(
            personName: suggestion.person.name,
            fromRingRaw: suggestion.person.ring.rawValue,
            toRingRaw: suggestion.targetRing.rawValue,
            directionRaw: suggestion.direction.label,
            outcomeRaw: DunbarRebalanceHistoryOutcome.deferred.rawValue,
            reason: suggestion.reason,
            recordedAt: .now,
            deferredUntilAt: deferredUntil
        )
        AppSettings.appendRebalanceHistory(entry)
        reloadData()
    }
    
    private func clearDeferral(for suggestion: DunbarRebalanceSuggestion) {
        AppSettings.clearRebalanceSuggestionDeferral(id: suggestion.id)
        reloadData()
    }
    
    private func historyHeadline(for entry: DunbarRebalanceHistoryEntry) -> String {
        switch entry.outcome {
        case .applied:
            if entry.direction == .promote {
                return "\(entry.personName) promoted to \(entry.toRing.label)"
            }
            return "\(entry.personName) moved to \(entry.toRing.label)"
        case .deferred:
            return "\(entry.personName) deferred"
        }
    }
    
    private func historyDetail(for entry: DunbarRebalanceHistoryEntry) -> String {
        let timestamp = entry.recordedAt.formatted(.dateTime.day().month(.abbreviated).hour().minute())
        
        switch entry.outcome {
        case .applied:
            return "\(entry.fromRing.label) → \(entry.toRing.label) · \(timestamp)"
        case .deferred:
            if let deferredUntil = entry.deferredUntilAt {
                let until = deferredUntil.formatted(.dateTime.day().month(.abbreviated))
                return "Until \(until) · \(timestamp)"
            }
            return timestamp
        }
    }
    
    private func reloadData() {
        deferredSuggestionIDs = AppSettings.deferredRebalanceSuggestionIDs()
        historyEntries = AppSettings.rebalanceHistoryEntries().sorted { $0.recordedAt > $1.recordedAt }
    }
}

#Preview {
    NavigationStack {
        RebalanceView()
    }
    .modelContainer(for: [Person.self, CheckIn.self, CareerRole.self, FamilyMember.self, FamilyPerson.self, FamilyRelationship.self, FamilyGraphV2.self, FamilyNodeV2.self, FamilyEdgeV2.self], inMemory: true)
    .environment(NudgeScheduler())
    .environment(PremiumManager())
}
