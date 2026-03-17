# Dunbar

A SwiftUI iOS app for relationship maintenance based on Dunbar's number theory. Helps users track and nurture relationships across concentric circles (Core 5, Close 15, Active 50, Meaningful 150) with contact cadences, nudge notifications, and health visualizations.

## Tech Stack

- **SwiftUI** - All UI
- **SwiftData** - Local persistence (`@Model`, `@Query`, `@Relationship`)
- **UserNotifications** - Scheduled nudge reminders
- **LocalAuthentication** - Face ID / Touch ID app lock
- **WidgetKit** - Today widget (app group: `group.com.handbook.dunbar`)
- **Observation** - `@Observable` services

## Project Structure

```
Dunbar/
├── App/                  # DunbarApp.swift, ContentView.swift (tab bar + deep linking)
├── Models/               # SwiftData models
│   ├── Person.swift      # Core contact model (ring, cadence, photo, check-ins)
│   ├── CheckIn.swift     # Contact event records (message/call/inPerson)
│   ├── CareerRole.swift  # Work history per person
│   ├── FamilyGraphV2.swift, FamilyNodeV2, FamilyEdgeV2  # Family tree graph
│   ├── FamilyMember.swift, FamilyGraph.swift  # Legacy (being migrated)
│   └── Enums.swift       # DunbarRing, Cadence, PlantType, etc.
├── Views/
│   ├── Garden/           # GardenView - concentric ring visualization + person list
│   ├── Nudge/            # NudgeListView - overdue/due contacts with swipe actions
│   ├── History/          # HistoryView - weekly momentum chart + ring health
│   ├── Person/           # PersonDetailView - full profile + family tree editing
│   ├── Add/              # AddPersonView - create contact with photo/ring/cadence/family
│   ├── Rebalance/        # RebalanceView - circle rebalancing suggestions
│   ├── Settings/         # SettingsView - appearance, notifications, quiet hours, Face ID
│   └── Components/       # PersonCard, PersonAvatar, PlantView, CheckInNoteSheet, StatusBadge
├── Services/
│   ├── NudgeScheduler.swift           # Notification scheduling with quiet hours + snooze
│   ├── PlantHealthCalculator.swift    # Health state (thriving/wilting/withering) per cadence
│   ├── RingHealthScoreService.swift   # Weighted health score across all rings
│   ├── CadenceRecommendationService.swift  # Smart cadence adjustment suggestions
│   ├── FamilyGraphV2Service.swift     # Family graph CRUD + connectivity algorithms
│   ├── AppSettings.swift              # UserDefaults wrapper for all settings
│   ├── AppLockManager.swift           # Biometric auth state machine
│   ├── HapticFeedbackService.swift    # Haptic feedback (respects user toggle)
│   ├── WidgetSnapshotStore.swift      # Shared data for Today widget
│   ├── Premium.swift                  # Free tier limit (10 people), StoreKit 2 TODO
│   └── FamilyGraphMigrator.swift      # Legacy → V2 family graph migration
└── Theme/
    └── DunbarTheme.swift  # Colors, typography (.rounded), card/button modifiers
```

## Key Concepts

- **Dunbar Rings**: Core (5) → Close (15) → Active (50) → Meaningful (150). Ring determines health multiplier and priority weight.
- **Cadence**: How often to contact someone (daily → quarterly). Each cadence has a day count used for health calculation.
- **Health States**: thriving (0-70% of cadence elapsed), wilting (70-100%), withering (>100% overdue). Ring multipliers: core 0.8x, meaningful 1.1x.
- **Rebalancing**: Automatic suggestions to promote (3+ check-ins in 45 days) or demote (0 check-ins + overdue) contacts between rings.
- **Family Graph V2**: Directed graph with anchor nodes per person. Supports relationship types (parent, sibling, partner, child, etc.) with bidirectional traversal.

## Conventions

- Services are enums with static methods (stateless calculators) or `@Observable` classes (stateful managers)
- SwiftData models use `@Relationship(deleteRule: .cascade)` for owned children
- Photo data stored with `.externalStorage` attribute, JPEG compressed at 70% quality
- Deep linking via `dunbar://inbox` URL scheme for notification tap → Nudges tab
- Design system: `DunbarTheme` namespace with `.dunbarCard()`, `.dunbarPrimaryButton()`, `.dunbarSecondaryButton()` view modifiers
- Typography uses `.rounded` design throughout
- All haptic feedback goes through `HapticFeedbackService` (respects user preference)
- Widget communicates via app group UserDefaults with 30-min refresh cadence

## SwiftData Schema

Models registered in `DunbarApp`: Person, CheckIn, CareerRole, FamilyMember, FamilyPerson, FamilyRelationship, FamilyGraphV2, FamilyNodeV2, FamilyEdgeV2. Falls back to in-memory store on corruption.

## Build & Run

Open `Dunbar.xcodeproj` in Xcode. No external package dependencies.
