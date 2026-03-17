import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(AppLockManager.self) private var appLockManager

    @State private var selectedTab: AppTab = .rings
    @State private var navigationPath = NavigationPath()
    @State private var showingAddSheet = false
    @State private var showingSettingsSheet = false
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
        }
        .onOpenURL { url in
            guard url.scheme?.lowercased() == "dunbar" else { return }
            if url.host?.lowercased() == "inbox" {
                selectedTab = .nudges
            }
        }
    }

    private var tabShell: some View {
        TabView(selection: tabSelection) {
            Tab("Circles", systemImage: "smallcircle.circle", value: AppTab.rings) {
                NavigationStack(path: $navigationPath) {
                    GardenView(
                        navigationPath: $navigationPath,
                        onSettingsTap: { showingSettingsSheet = true }
                    )
                }
            }

            Tab("Nudges", systemImage: "bell", value: AppTab.nudges) {
                NavigationStack {
                    NudgeListView(onSettingsTap: { showingSettingsSheet = true })
                }
            }
            .badge(overdueCount)

            Tab("Rhythm", systemImage: "chart.bar", value: AppTab.history) {
                NavigationStack {
                    HistoryView(onSettingsTap: { showingSettingsSheet = true })
                }
            }

            Tab("Add", systemImage: "person.badge.plus", value: AppTab.add) {
                Color.clear
            }
        }
        .tint(DunbarTheme.ringColor(for: .core))
        .toolbarBackground(.clear, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .preferredColorScheme(nil)
        .sheet(isPresented: $showingAddSheet) {
            AddPersonView()
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

    /// Intercept the .add tab — open the sheet and snap back to the previous tab
    private var tabSelection: Binding<AppTab> {
        Binding(
            get: { selectedTab },
            set: { newTab in
                if newTab == .add {
                    showingAddSheet = true
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
}
