import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(AppLockManager.self) private var appLockManager
    @Environment(PremiumManager.self) private var premiumManager

    @State private var selectedTab: AppTab = .rings
    @State private var navigationPath = NavigationPath()
    @State private var showingAddSheet = false
    @State private var showingSettingsSheet = false
    @State private var showingPaywall = false
    @State private var showSplash = true
    @State private var showOnboarding = !AppSettings.hasCompletedOnboarding
    @State private var showWalkthrough = AppSettings.hasCompletedOnboarding && !AppSettings.hasCompletedWalkthrough
    @Query(filter: #Predicate<Person> { person in
        person.isArchived == false
    }) private var people: [Person]

    enum AppTab: Hashable {
        case rings, nudges, history, add
    }


    private var overdueCount: Int {
        people.filter { $0.healthState == .withering }.count
    }

    var body: some View {
        ZStack {
            tabShell

            if appLockManager.isLocked {
                lockOverlay
            }

            if showWalkthrough {
                WalkthroughOverlayView(
                    selectedTab: $selectedTab,
                    navigationPath: $navigationPath,
                    onComplete: { openAdd in
                        withAnimation(.easeOut(duration: 0.4)) {
                            showWalkthrough = false
                        }
                        if openAdd {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                showingAddSheet = true
                            }
                        }
                    }
                )
                .zIndex(40)
            }

            if showOnboarding {
                OnboardingView {
                    withAnimation(.easeOut(duration: 0.4)) {
                        showOnboarding = false
                    }
                    // Trigger walkthrough after onboarding dismisses
                    if !AppSettings.hasCompletedWalkthrough {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                            showWalkthrough = true
                        }
                    }
                }
                .zIndex(50)
            }

            if showSplash {
                SplashView {
                    showSplash = false
                }
                .zIndex(100)
            }
        }
        .onOpenURL { url in
            guard url.scheme?.lowercased() == "dunbar" else { return }
            if url.host?.lowercased() == "inbox" {
                selectedTab = .nudges
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .replayWalkthrough)) { _ in
            // Dismiss settings sheet first, then start walkthrough
            showingSettingsSheet = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                navigationPath = NavigationPath()
                selectedTab = .rings
                showWalkthrough = true
            }
        }
    }

    private var tabShell: some View {
        TabView(selection: tabSelection) {
            NavigationStack(path: $navigationPath) {
                GardenView(
                    navigationPath: $navigationPath,
                    onSettingsTap: { showingSettingsSheet = true }
                )
            }
            .tabItem {
                VStack {
                    Image(systemName: selectedTab == .rings ? "smallcircle.filled.circle.fill" : "smallcircle.circle")
                        .environment(\.symbolVariants, .none)
                    Text("Circles")
                }
            }
            .tag(AppTab.rings)

            NavigationStack {
                NudgeListView(onSettingsTap: { showingSettingsSheet = true })
            }
            .tabItem {
                VStack {
                    Image(systemName: selectedTab == .nudges ? "bell.fill" : "bell")
                        .environment(\.symbolVariants, .none)
                    Text("Nudges")
                }
            }
            .badge(overdueCount)
            .tag(AppTab.nudges)

            NavigationStack {
                HistoryView(onSettingsTap: { showingSettingsSheet = true })
            }
            .tabItem {
                VStack {
                    Image(systemName: selectedTab == .history ? "chart.bar.fill" : "chart.bar")
                        .environment(\.symbolVariants, .none)
                    Text("Rhythm")
                }
            }
            .tag(AppTab.history)

            Color.clear
                .tabItem {
                    VStack {
                        Image(systemName: selectedTab == .add ? "person.fill.badge.plus" : "person.badge.plus")
                            .environment(\.symbolVariants, .none)
                        Text("Add")
                    }
                }
                .tag(AppTab.add)
        }
        .tint(DunbarTheme.ringColor(for: .core))
        .preferredColorScheme(nil)
        .sheet(isPresented: $showingAddSheet) {
            AddPersonView()
        }
        .sheet(isPresented: $showingPaywall) {
            PaywallView()
        }
        .sheet(isPresented: $showingSettingsSheet) {
            NavigationStack {
                SettingsView(showsCloseButton: true)
            }
            .presentationDragIndicator(.visible)
        }
    }

    private var lockOverlay: some View {
        ZStack {
            DunbarTheme.background
                .ignoresSafeArea()

            VStack(spacing: 14) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(DunbarTheme.ringColor(for: .core))

                Text("Locked")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(DunbarTheme.textPrimary)

                Text(appLockManager.availabilityText)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(DunbarTheme.textSecondary)

                Button {
                    Task {
                        await appLockManager.unlockIfNeeded(force: true)
                    }
                } label: {
                    if appLockManager.isUnlocking {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    } else {
                        Text("Unlock")
                            .frame(maxWidth: .infinity)
                    }
                }
                .dunbarPrimaryButton()
                .frame(maxWidth: 220)
            }
            .padding(24)
            .background(DunbarTheme.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(DunbarTheme.border, lineWidth: 1)
            )
            .padding(28)
        }
        .transition(.opacity)
        .zIndex(999)
    }

    /// Intercept the .add tab — open the sheet (or paywall) and snap back to the previous tab
    private var tabSelection: Binding<AppTab> {
        Binding(
            get: { selectedTab },
            set: { newTab in
                if newTab == .add {
                    if !premiumManager.isPremium && people.count >= Premium.freeTierPersonLimit {
                        showingPaywall = true
                    } else {
                        showingAddSheet = true
                    }
                } else {
                    selectedTab = newTab
                }
            }
        )
    }

}

#Preview {
    ContentView()
        .modelContainer(for: [Person.self, CheckIn.self, CareerRole.self, FamilyMember.self, FamilyPerson.self, FamilyRelationship.self, FamilyGraphV2.self, FamilyNodeV2.self, FamilyEdgeV2.self], inMemory: true)
        .environment(NudgeScheduler())
        .environment(AppLockManager())
        .environment(HapticFeedbackService())
        .environment(PremiumManager())
}
