import SwiftUI
import SwiftData

struct WalkthroughOverlayView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var selectedTab: ContentView.AppTab
    @Binding var navigationPath: NavigationPath
    let onComplete: (_ openAddSheet: Bool) -> Void

    @State private var currentStep = 0
    @State private var dummyDataInserted = false
    @State private var sheetVisible = false
    @State private var dummyPerson: Person?

    private var steps: [WalkthroughStep] {
        [
            // Tab-level steps
            WalkthroughStep(
                icon: "circle.grid.cross",
                title: "Your circle map",
                body: "Each ring is a level of closeness — Inner 5, Close 15, Wider 50, Outer 150. The coloured dots are your contacts.",
                tab: .rings,
                detailTab: nil
            ),
            WalkthroughStep(
                icon: "heart.text.square",
                title: "Health at a glance",
                body: "Green means on track, amber means due soon, and red means overdue — based on how often you want to stay in touch.",
                tab: .rings,
                detailTab: nil
            ),
            WalkthroughStep(
                icon: "person.2",
                title: "Your contacts",
                body: "Scroll through everyone sorted by urgency. The most overdue contacts appear first so you know who needs attention.",
                tab: .rings,
                detailTab: nil
            ),
            WalkthroughStep(
                icon: "bell.badge",
                title: "Nudges",
                body: "When a relationship needs attention, it shows up here. Swipe right to mark as done, or left to snooze.",
                tab: .nudges,
                detailTab: nil
            ),
            WalkthroughStep(
                icon: "chart.bar",
                title: "Your rhythm",
                body: "See your check-in momentum over the last 12 weeks. Consistency builds stronger relationships.",
                tab: .history,
                detailTab: nil
            ),
            // Contact detail steps
            WalkthroughStep(
                icon: "person.text.rectangle",
                title: "Contact overview",
                body: "Tap any contact to see their profile. The overview shows notes, cadence suggestions, and recent catch-ups at a glance.",
                tab: .rings,
                detailTab: "overview"
            ),
            WalkthroughStep(
                icon: "briefcase",
                title: "Context & connections",
                body: "The context tab tracks work history and family connections — so you always have something to talk about.",
                tab: .rings,
                detailTab: "context"
            ),
            WalkthroughStep(
                icon: "clock.arrow.circlepath",
                title: "Contact history",
                body: "Every check-in is logged here. See when you last reached out and what you talked about.",
                tab: .rings,
                detailTab: "history"
            ),
        ]
    }

    private var totalSteps: Int { steps.count }
    private var isLastStep: Bool { currentStep >= totalSteps - 1 }

    var body: some View {
        VStack {
            Spacer()

            if sheetVisible {
                sheetCard
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .ignoresSafeArea(.container, edges: .bottom)
        .onAppear {
            if !dummyDataInserted {
                WalkthroughDummyDataService.insertDummyData(context: modelContext)
                dummyDataInserted = true
                // Find a dummy person with career data for the detail steps
                findDummyPerson()
            }
            selectedTab = steps[currentStep].tab
            withAnimation(reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.5, dampingFraction: 0.85)) {
                sheetVisible = true
            }
        }
    }

    // MARK: - Bottom Sheet Card

    private var sheetCard: some View {
        let step = steps[currentStep]

        return VStack(spacing: 16) {
            // Drag handle
            Capsule()
                .fill(Color(.systemGray4))
                .frame(width: 36, height: 5)
                .padding(.top, 10)

            // Icon + title row
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(DunbarTheme.ringColor(for: .core).opacity(0.12))
                        .frame(width: 44, height: 44)

                    Image(systemName: step.icon)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(DunbarTheme.ringColor(for: .core))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(step.title)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(DunbarTheme.textPrimary)

                    Text("\(currentStep + 1) of \(totalSteps)")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(DunbarTheme.textTertiary)
                }

                Spacer()
            }

            // Body
            Text(step.body)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(DunbarTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Step dots
            stepDots
                .padding(.top, 2)

            // Buttons
            HStack(spacing: 12) {
                Button {
                    completeWalkthrough(openAdd: false)
                } label: {
                    Text("Skip")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .frame(maxWidth: .infinity)
                }
                .dunbarSecondaryButton()

                Button {
                    advance()
                } label: {
                    Text(isLastStep ? "Add contact" : "Next")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .frame(maxWidth: .infinity)
                }
                .dunbarPrimaryButton()
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
        .background(
            UnevenRoundedRectangle(
                topLeadingRadius: 24,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: 24
            )
            .fill(DunbarTheme.surface)
            .shadow(color: .black.opacity(0.15), radius: 20, y: -8)
        )
        .accessibilityElement(children: .contain)
    }

    private var stepDots: some View {
        HStack(spacing: 6) {
            ForEach(0..<totalSteps, id: \.self) { i in
                Capsule()
                    .fill(i == currentStep ? DunbarTheme.ringColor(for: .core) : DunbarTheme.border)
                    .frame(width: i == currentStep ? 20 : 8, height: 6)
            }
        }
        .accessibilityHidden(true)
    }

    // MARK: - Actions

    private func advance() {
        if isLastStep {
            completeWalkthrough(openAdd: true)
        } else {
            let nextStep = currentStep + 1
            let step = steps[nextStep]

            withAnimation(reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.4, dampingFraction: 0.85)) {
                currentStep = nextStep
            }

            // Handle tab switching
            if step.tab != selectedTab {
                // Pop back before switching tabs
                if !navigationPath.isEmpty {
                    navigationPath = NavigationPath()
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    selectedTab = step.tab
                }
            }

            // Handle detail page navigation
            if let detailTab = step.detailTab {
                if detailTab == "overview" {
                    // First detail step — push the dummy person
                    if navigationPath.isEmpty, let person = dummyPerson {
                        selectedTab = .rings
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            navigationPath.append(person)
                            // Switch to overview tab after a short delay
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                                NotificationCenter.default.post(name: .walkthroughSwitchDetailTab, object: detailTab)
                            }
                        }
                    }
                } else {
                    // Context or history — just switch the detail tab
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        NotificationCenter.default.post(name: .walkthroughSwitchDetailTab, object: detailTab)
                    }
                }
            } else if steps[currentStep].detailTab != nil && step.detailTab == nil {
                // Leaving detail steps — pop back
                navigationPath = NavigationPath()
            }
        }
    }

    private func completeWalkthrough(openAdd: Bool) {
        // Pop any navigation first
        if !navigationPath.isEmpty {
            navigationPath = NavigationPath()
        }

        withAnimation(reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.35, dampingFraction: 0.9)) {
            sheetVisible = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            WalkthroughDummyDataService.removeDummyData(context: modelContext)
            AppSettings.hasCompletedWalkthrough = true
            selectedTab = .rings
            onComplete(openAdd)
        }
    }

    private func findDummyPerson() {
        let descriptor = FetchDescriptor<Person>(
            predicate: #Predicate<Person> { $0.isDummyData }
        )
        if let people = try? modelContext.fetch(descriptor) {
            // Prefer James T. who has a career role for richer context tab
            dummyPerson = people.first { $0.name == "James T." } ?? people.first
        }
    }
}

// MARK: - Step Model

private struct WalkthroughStep {
    let icon: String
    let title: String
    let body: String
    let tab: ContentView.AppTab
    let detailTab: String? // nil = main tab, "overview"/"context"/"history" = person detail
}
