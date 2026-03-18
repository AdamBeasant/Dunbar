import SwiftUI
import SwiftData
import UserNotifications

@main
struct DunbarApp: App {
    
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Person.self,
            CheckIn.self,
            CareerRole.self,
            FamilyMember.self,
            FamilyPerson.self,
            FamilyRelationship.self,
            FamilyGraphV2.self,
            FamilyNodeV2.self,
            FamilyEdgeV2.self,
        ])
        let storeURL = URL.applicationSupportDirectory.appending(path: "Dunbar.store")
        let diskConfiguration = ModelConfiguration(url: storeURL)
        
        func wipeKnownStoreFiles() {
            let fileManager = FileManager.default
            let appSupportURL = URL.applicationSupportDirectory
            
            try? fileManager.createDirectory(
                at: appSupportURL,
                withIntermediateDirectories: true
            )
            
            // Clean both old and new local store names.
            for baseName in ["default.store", "Dunbar.store"] {
                let baseURL = appSupportURL.appending(path: baseName)
                for suffix in ["", "-wal", "-shm"] {
                    try? fileManager.removeItem(
                        at: URL(fileURLWithPath: baseURL.path() + suffix)
                    )
                }
            }
        }
        
        do {
            return try ModelContainer(
                for: schema,
                configurations: diskConfiguration
            )
        } catch {
            print("ModelContainer failed: \(error). Deleting store and retrying...")
            wipeKnownStoreFiles()
            
            do {
                return try ModelContainer(
                    for: schema,
                    configurations: diskConfiguration
                )
            } catch {
                print("Disk ModelContainer failed again: \(error). Falling back to in-memory store.")
                
                do {
                    return try ModelContainer(
                        for: schema,
                        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
                    )
                } catch {
                    fatalError("Could not create ModelContainer: \(error)")
                }
            }
        }
    }()
    
    @State private var nudgeScheduler = NudgeScheduler()
    @State private var appLockManager = AppLockManager()
    @State private var hapticFeedback = HapticFeedbackService()
    @State private var premiumManager = PremiumManager()
    @Environment(\.scenePhase) private var scenePhase
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(nudgeScheduler)
                .environment(appLockManager)
                .environment(hapticFeedback)
                .environment(premiumManager)
                .task {
                    // Only auto-request notifications if user already completed onboarding
                    // (new users get prompted during the onboarding flow instead)
                    if AppSettings.hasCompletedOnboarding {
                        await nudgeScheduler.requestPermissionIfNeeded()
                    }
                    appLockManager.refreshBiometricAvailability()
                    FamilyGraphMigrator.migrateIfNeeded(context: sharedModelContainer.mainContext)
                    FamilyGraphV2Migrator.migrateIfNeeded(context: sharedModelContainer.mainContext)
                }
        }
        .modelContainer(sharedModelContainer)
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                UNUserNotificationCenter.current().setBadgeCount(0)
                Task {
                    if appLockManager.isLocked {
                        await appLockManager.unlockIfNeeded()
                    }
                    let context = sharedModelContainer.mainContext
                    let descriptor = FetchDescriptor<Person>(
                        predicate: #Predicate { !$0.isArchived && !$0.isDummyData }
                    )
                    if let people = try? context.fetch(descriptor) {
                        await nudgeScheduler.rescheduleAll(people: people)
                        WidgetSnapshotStore.write(
                            WidgetSnapshotStore.buildSnapshot(people: people)
                        )
                    }
                }
            } else if newPhase == .inactive || newPhase == .background {
                appLockManager.lockIfNeeded()
                // Update widget snapshot before backgrounding so it stays fresh
                let context = sharedModelContainer.mainContext
                let descriptor = FetchDescriptor<Person>(
                    predicate: #Predicate { !$0.isArchived && !$0.isDummyData }
                )
                if let people = try? context.fetch(descriptor) {
                    WidgetSnapshotStore.write(
                        WidgetSnapshotStore.buildSnapshot(people: people)
                    )
                }
            }
        }
    }
}
