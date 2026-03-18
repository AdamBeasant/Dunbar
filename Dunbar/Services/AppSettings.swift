import Foundation

extension Notification.Name {
    static let walkthroughSwitchDetailTab = Notification.Name("walkthroughSwitchDetailTab")
    static let replayWalkthrough = Notification.Name("replayWalkthrough")
}

enum AppSettings {
    static let appearanceModeKey = "settings.appearance.mode"
    static let reminderDefaultHourKey = "settings.reminder.defaultHour"
    static let reminderDefaultMinuteKey = "settings.reminder.defaultMinute"
    static let quietHoursEnabledKey = "settings.quiet.enabled"
    static let quietStartHourKey = "settings.quiet.startHour"
    static let quietStartMinuteKey = "settings.quiet.startMinute"
    static let quietEndHourKey = "settings.quiet.endHour"
    static let quietEndMinuteKey = "settings.quiet.endMinute"
    static let weeklyGoalKey = "settings.weekly.goal"
    static let rebalanceDeferralsKey = "settings.rebalance.deferrals"
    static let rebalanceHistoryKey = "settings.rebalance.history"

    // Premium controls
    static let notificationSoundEnabledKey = "settings.notifications.soundEnabled"
    static let notificationBadgeEnabledKey = "settings.notifications.badgeEnabled"
    static let snoozePreset1DaysKey = "settings.notifications.snoozePreset1Days"
    static let snoozePreset2DaysKey = "settings.notifications.snoozePreset2Days"
    static let snoozePreset3DaysKey = "settings.notifications.snoozePreset3Days"
    static let ringMotionIntensityKey = "settings.motion.ringIntensity"
    static let hapticsEnabledKey = "settings.haptics.enabled"
    static let faceIDEnabledKey = "settings.privacy.faceIDEnabled"

    // Suggestion / widget persistence
    static let smartCadenceDismissalsKey = "settings.smartCadence.dismissals"
    static let widgetSnapshotKey = "settings.widget.snapshot"
    static let ringHealthLastBandKey = "settings.ringHealth.lastBand"
    static let familyGraphV2MigrationCompleteKey = "settings.familyGraphV2.migrationComplete"
    static let hasCompletedOnboardingKey = "settings.onboarding.completed"
    static let userNameKey = "settings.onboarding.userName"
    static let hasCompletedWalkthroughKey = "settings.walkthrough.completed"

    static var defaultReminderHour: Int {
        get { integer(forKey: reminderDefaultHourKey, defaultValue: 10) }
        set { UserDefaults.standard.set(min(max(newValue, 0), 23), forKey: reminderDefaultHourKey) }
    }

    static var defaultReminderMinute: Int {
        get { integer(forKey: reminderDefaultMinuteKey, defaultValue: 0) }
        set { UserDefaults.standard.set(min(max(newValue, 0), 59), forKey: reminderDefaultMinuteKey) }
    }

    static var quietHoursEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: quietHoursEnabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: quietHoursEnabledKey) }
    }

    static var quietStartHour: Int {
        get { integer(forKey: quietStartHourKey, defaultValue: 22) }
        set { UserDefaults.standard.set(min(max(newValue, 0), 23), forKey: quietStartHourKey) }
    }

    static var quietStartMinute: Int {
        get { integer(forKey: quietStartMinuteKey, defaultValue: 0) }
        set { UserDefaults.standard.set(min(max(newValue, 0), 59), forKey: quietStartMinuteKey) }
    }

    static var quietEndHour: Int {
        get { integer(forKey: quietEndHourKey, defaultValue: 8) }
        set { UserDefaults.standard.set(min(max(newValue, 0), 23), forKey: quietEndHourKey) }
    }

    static var quietEndMinute: Int {
        get { integer(forKey: quietEndMinuteKey, defaultValue: 0) }
        set { UserDefaults.standard.set(min(max(newValue, 0), 59), forKey: quietEndMinuteKey) }
    }

    static var weeklyGoal: Int {
        get { integer(forKey: weeklyGoalKey, defaultValue: 3) }
        set { UserDefaults.standard.set(min(max(newValue, 1), 20), forKey: weeklyGoalKey) }
    }

    static var notificationSoundEnabled: Bool {
        get { bool(forKey: notificationSoundEnabledKey, defaultValue: true) }
        set { UserDefaults.standard.set(newValue, forKey: notificationSoundEnabledKey) }
    }

    static var notificationBadgeEnabled: Bool {
        get { bool(forKey: notificationBadgeEnabledKey, defaultValue: true) }
        set { UserDefaults.standard.set(newValue, forKey: notificationBadgeEnabledKey) }
    }

    static var snoozePreset1Days: Int {
        get { integer(forKey: snoozePreset1DaysKey, defaultValue: 1) }
        set { UserDefaults.standard.set(min(max(newValue, 1), 30), forKey: snoozePreset1DaysKey) }
    }

    static var snoozePreset2Days: Int {
        get { integer(forKey: snoozePreset2DaysKey, defaultValue: 3) }
        set { UserDefaults.standard.set(min(max(newValue, 1), 30), forKey: snoozePreset2DaysKey) }
    }

    static var snoozePreset3Days: Int {
        get { integer(forKey: snoozePreset3DaysKey, defaultValue: 7) }
        set { UserDefaults.standard.set(min(max(newValue, 1), 30), forKey: snoozePreset3DaysKey) }
    }

    static var ringMotionIntensityRaw: String {
        get { string(forKey: ringMotionIntensityKey, defaultValue: RingMotionIntensity.low.rawValue) }
        set { UserDefaults.standard.set(newValue, forKey: ringMotionIntensityKey) }
    }

    static var hapticsEnabled: Bool {
        get { bool(forKey: hapticsEnabledKey, defaultValue: true) }
        set { UserDefaults.standard.set(newValue, forKey: hapticsEnabledKey) }
    }

    static var faceIDEnabled: Bool {
        get { bool(forKey: faceIDEnabledKey, defaultValue: false) }
        set { UserDefaults.standard.set(newValue, forKey: faceIDEnabledKey) }
    }

    static var widgetSnapshotData: Data? {
        get { UserDefaults.standard.data(forKey: widgetSnapshotKey) }
        set { UserDefaults.standard.set(newValue, forKey: widgetSnapshotKey) }
    }

    static var lastRingHealthBand: Int {
        get { integer(forKey: ringHealthLastBandKey, defaultValue: -1) }
        set { UserDefaults.standard.set(newValue, forKey: ringHealthLastBandKey) }
    }

    static var isFamilyGraphV2MigrationComplete: Bool {
        get { bool(forKey: familyGraphV2MigrationCompleteKey, defaultValue: false) }
        set { UserDefaults.standard.set(newValue, forKey: familyGraphV2MigrationCompleteKey) }
    }

    static var hasCompletedOnboarding: Bool {
        get { bool(forKey: hasCompletedOnboardingKey, defaultValue: false) }
        set { UserDefaults.standard.set(newValue, forKey: hasCompletedOnboardingKey) }
    }

    static var userName: String? {
        get { UserDefaults.standard.string(forKey: userNameKey) }
        set { UserDefaults.standard.set(newValue, forKey: userNameKey) }
    }

    static var hasCompletedWalkthrough: Bool {
        get { bool(forKey: hasCompletedWalkthroughKey, defaultValue: false) }
        set { UserDefaults.standard.set(newValue, forKey: hasCompletedWalkthroughKey) }
    }

    static var snoozePresets: [Int] {
        [snoozePreset1Days, snoozePreset2Days, snoozePreset3Days]
            .map { min(max($0, 1), 30) }
    }

    static func deferredRebalanceSuggestionIDs(now: Date = .now) -> Set<String> {
        let active = rebalanceDeferrals(now: now)
        return Set(active.keys)
    }

    static func deferRebalanceSuggestion(id: String, until: Date) {
        var map = rebalanceDeferrals(now: .distantPast)
        map[id] = until
        persistRebalanceDeferrals(map)
    }

    static func clearRebalanceSuggestionDeferral(id: String) {
        var map = rebalanceDeferrals(now: .distantPast)
        map.removeValue(forKey: id)
        persistRebalanceDeferrals(map)
    }

    static func appendRebalanceHistory(_ entry: DunbarRebalanceHistoryEntry) {
        var entries = rebalanceHistoryEntries()
        entries.insert(entry, at: 0)
        if entries.count > 200 {
            entries = Array(entries.prefix(200))
        }
        persistRebalanceHistory(entries)
    }

    static func rebalanceHistoryEntries() -> [DunbarRebalanceHistoryEntry] {
        guard let data = UserDefaults.standard.data(forKey: rebalanceHistoryKey) else {
            return []
        }
        let decoded = try? JSONDecoder().decode([DunbarRebalanceHistoryEntry].self, from: data)
        return decoded ?? []
    }

    static func dismissSmartCadence(personKey: String, until: Date) {
        var raw = UserDefaults.standard.dictionary(forKey: smartCadenceDismissalsKey) as? [String: Double] ?? [:]
        raw[personKey] = until.timeIntervalSince1970
        UserDefaults.standard.set(raw, forKey: smartCadenceDismissalsKey)
    }

    static func isSmartCadenceDismissed(personKey: String, now: Date = .now) -> Bool {
        clearExpiredSmartCadenceDismissals(now: now)
        let raw = UserDefaults.standard.dictionary(forKey: smartCadenceDismissalsKey) as? [String: Double] ?? [:]
        guard let expiry = raw[personKey] else { return false }
        return expiry > now.timeIntervalSince1970
    }

    static func clearSmartCadenceDismissal(personKey: String) {
        var raw = UserDefaults.standard.dictionary(forKey: smartCadenceDismissalsKey) as? [String: Double] ?? [:]
        raw.removeValue(forKey: personKey)
        UserDefaults.standard.set(raw, forKey: smartCadenceDismissalsKey)
    }

    static func clearExpiredSmartCadenceDismissals(now: Date = .now) {
        let nowInterval = now.timeIntervalSince1970
        let raw = UserDefaults.standard.dictionary(forKey: smartCadenceDismissalsKey) as? [String: Double] ?? [:]
        let active = raw.filter { $0.value > nowInterval }
        if active.count != raw.count {
            UserDefaults.standard.set(active, forKey: smartCadenceDismissalsKey)
        }
    }

    private static func rebalanceDeferrals(now: Date) -> [String: Date] {
        let raw = UserDefaults.standard.dictionary(forKey: rebalanceDeferralsKey) as? [String: Double] ?? [:]
        let nowInterval = now.timeIntervalSince1970
        let activeRaw = raw.filter { $0.value > nowInterval }
        let active = activeRaw.mapValues { Date(timeIntervalSince1970: $0) }

        if activeRaw.count != raw.count {
            persistRawRebalanceDeferrals(activeRaw)
        }

        return active
    }

    private static func persistRebalanceDeferrals(_ map: [String: Date]) {
        let raw = map.mapValues(\.timeIntervalSince1970)
        persistRawRebalanceDeferrals(raw)
    }

    private static func persistRawRebalanceDeferrals(_ map: [String: Double]) {
        UserDefaults.standard.set(map, forKey: rebalanceDeferralsKey)
    }

    private static func persistRebalanceHistory(_ entries: [DunbarRebalanceHistoryEntry]) {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(entries) {
            UserDefaults.standard.set(data, forKey: rebalanceHistoryKey)
        }
    }

    private static func integer(forKey key: String, defaultValue: Int) -> Int {
        guard UserDefaults.standard.object(forKey: key) != nil else {
            return defaultValue
        }
        return UserDefaults.standard.integer(forKey: key)
    }

    private static func bool(forKey key: String, defaultValue: Bool) -> Bool {
        guard UserDefaults.standard.object(forKey: key) != nil else {
            return defaultValue
        }
        return UserDefaults.standard.bool(forKey: key)
    }

    private static func string(forKey key: String, defaultValue: String) -> String {
        guard let value = UserDefaults.standard.string(forKey: key) else {
            return defaultValue
        }
        return value
    }
}
