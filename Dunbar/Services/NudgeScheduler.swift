import Foundation
import SwiftData
import UserNotifications
import Observation

@Observable
final class NudgeScheduler {
    
    private let center = UNUserNotificationCenter.current()
    
    // MARK: - Permissions
    
    /// Request notification permission once. Subsequent calls are no-ops.
    func requestPermissionIfNeeded() async {
        let settings = await center.notificationSettings()
        
        guard settings.authorizationStatus == .notDetermined else {
            return // Already granted or denied — don't re-prompt
        }
        
        _ = await requestPermission()
    }
    
    func requestPermission() async -> Bool {
        do {
            let granted = try await center.requestAuthorization(
                options: [.alert, .sound, .badge]
            )
            return granted
        } catch {
            print("Notification permission error: \(error)")
            return false
        }
    }
    
    // MARK: - Scheduling
    
    func snooze(_ person: Person, byDays days: Int) async {
        guard days > 0 else { return }
        person.snoozedUntilAt = Calendar.current.date(byAdding: .day, value: days, to: .now)
        await schedule(for: person)
    }
    
    /// Schedule a nudge for a single person based on their cadence and last contact.
    func schedule(for person: Person) async {
        // Remove any existing notifications for this person
        let identifier = notificationID(for: person)
        center.removePendingNotificationRequests(withIdentifiers: [identifier])

        if let snoozedUntilAt = person.snoozedUntilAt, snoozedUntilAt > .now {
            await scheduleOneOff(
                for: person,
                at: snoozedUntilAt,
                message: "Snoozed reminder: check in with \(person.name)."
            )
            return
        }

        if person.cadence == .daily {
            let content = UNMutableNotificationContent()
            content.title = "Dunbar"
            content.body = "Time to check in with \(person.name)."
            content.sound = AppSettings.notificationSoundEnabled ? .default : nil
            if AppSettings.notificationBadgeEnabled {
                content.badge = 1
            }
            content.categoryIdentifier = "CATCH_UP"
            content.userInfo = ["personName": person.name]
            
            var components = DateComponents()
            let reminderTime = Self.adjustedReminderTime(
                hour: person.reminderHour,
                minute: person.reminderMinute
            )
            components.hour = reminderTime.hour
            components.minute = reminderTime.minute
            
            let trigger = UNCalendarNotificationTrigger(
                dateMatching: components,
                repeats: true
            )
            let request = UNNotificationRequest(
                identifier: identifier,
                content: content,
                trigger: trigger
            )
            do {
                try await center.add(request)
            } catch {
                print("[NudgeScheduler] Failed to add notification: \(error)")
            }
            return
        }
        
        // Calculate when the nudge should fire
        guard let fireDate = nudgeDate(for: person) else { return }
        
        // Don't schedule if the fire date is in the past
        // (person is already overdue — fire immediately instead)
        let content = UNMutableNotificationContent()
        content.title = "Dunbar"
        content.body = nudgeCopy(for: person)
        content.sound = AppSettings.notificationSoundEnabled ? .default : nil
        if AppSettings.notificationBadgeEnabled {
            content.badge = 1
        }
        content.categoryIdentifier = "CATCH_UP"
        content.userInfo = ["personName": person.name]
        
        await scheduleOneOff(for: person, at: fireDate, message: content.body)
    }
    
    /// Reschedule nudges for all people. Call on app launch and after any changes.
    /// Removes all pending requests first, then schedules new ones.
    func rescheduleAll(people: [Person]) async {
        // Build all requests first, then swap atomically to minimize the gap
        // where no notifications are pending.
        let activePeople = people.filter { !$0.isArchived }
        center.removeAllPendingNotificationRequests()
        for person in activePeople {
            await schedule(for: person)
        }
    }
    
    /// Remove scheduled nudge for a person (e.g. when they're deleted).
    func cancel(for person: Person) {
        center.removePendingNotificationRequests(
            withIdentifiers: [notificationID(for: person)]
        )
    }
    
    static func nextReminderDate(
        cadence: Cadence,
        lastContactedAt: Date,
        hasPriorContact: Bool = true,
        reminderHour: Int,
        reminderMinute: Int,
        snoozedUntilAt: Date? = nil,
        ring: DunbarRing = .meaningful,
        now: Date = .now
    ) -> Date? {
        let calendar = Calendar.current
        
        if let snoozedUntilAt, snoozedUntilAt > now {
            return snoozedUntilAt
        }
        
        let reminderTime = adjustedReminderTime(hour: reminderHour, minute: reminderMinute)
        
        if cadence == .daily {
            guard let todayAtReminder = calendar.date(
                bySettingHour: reminderTime.hour,
                minute: reminderTime.minute,
                second: 0,
                of: now
            ) else { return nil }
            
            if todayAtReminder > now {
                return todayAtReminder
            }
            return calendar.date(byAdding: .day, value: 1, to: todayAtReminder)
        }
        
        if !hasPriorContact {
            guard let todayAtReminder = calendar.date(
                bySettingHour: reminderTime.hour,
                minute: reminderTime.minute,
                second: 0,
                of: now
            ) else { return nil }
            
            if todayAtReminder > now {
                return todayAtReminder
            }
            return calendar.date(byAdding: .day, value: 1, to: todayAtReminder)
        }
        
        let daysSinceContact = max(
            calendar.dateComponents([.day], from: lastContactedAt, to: now).day ?? 0,
            0
        )
        let effectiveDays = PlantHealthCalculator.effectiveCadenceDays(cadence: cadence, ring: ring)
        let daysUntilDue = effectiveDays - daysSinceContact
        
        let dueDate: Date
        if daysUntilDue <= 0 {
            dueDate = now
        } else {
            guard let date = calendar.date(byAdding: .day, value: daysUntilDue, to: now) else {
                return nil
            }
            dueDate = date
        }
        
        return calendar.date(
            bySettingHour: reminderTime.hour,
            minute: reminderTime.minute,
            second: 0,
            of: dueDate
        )
    }
    
    static func projectedReminderDates(
        cadence: Cadence,
        lastContactedAt: Date,
        hasPriorContact: Bool,
        reminderHour: Int,
        reminderMinute: Int,
        snoozedUntilAt: Date? = nil,
        ring: DunbarRing = .meaningful,
        count: Int = 3,
        now: Date = .now
    ) -> [Date] {
        guard count > 0 else { return [] }
        
        var projections: [Date] = []
        var referenceNow = now
        var referenceLastContact = lastContactedAt
        var priorContact = hasPriorContact
        
        for _ in 0..<count {
            guard let next = nextReminderDate(
                cadence: cadence,
                lastContactedAt: referenceLastContact,
                hasPriorContact: priorContact,
                reminderHour: reminderHour,
                reminderMinute: reminderMinute,
                snoozedUntilAt: snoozedUntilAt,
                ring: ring,
                now: referenceNow
            ) else {
                break
            }
            projections.append(next)
            
            referenceNow = next.addingTimeInterval(60)
            if !priorContact {
                priorContact = true
                referenceLastContact = next
            } else if let advanced = Calendar.current.date(byAdding: .day, value: cadence.days, to: referenceLastContact) {
                referenceLastContact = advanced
            } else {
                referenceLastContact = next
            }
        }
        
        return projections
    }
    
    // MARK: - Private Helpers
    
    private func notificationID(for person: Person) -> String {
        "dunbar-nudge-\(person.persistentModelID)"
    }
    
    private func scheduleOneOff(for person: Person, at date: Date, message: String) async {
        let identifier = notificationID(for: person)
        
        let content = UNMutableNotificationContent()
        content.title = "Dunbar"
        content.body = message
        content.sound = AppSettings.notificationSoundEnabled ? .default : nil
        if AppSettings.notificationBadgeEnabled {
            content.badge = 1
        }
        content.categoryIdentifier = "CATCH_UP"
        content.userInfo = ["personName": person.name]
        
        if date <= .now {
            let trigger = UNTimeIntervalNotificationTrigger(
                timeInterval: 60,
                repeats: false
            )
            let request = UNNotificationRequest(
                identifier: identifier,
                content: content,
                trigger: trigger
            )
            do {
                try await center.add(request)
            } catch {
                print("[NudgeScheduler] Failed to add notification: \(error)")
            }
            return
        }
        
        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: date
        )
        let trigger = UNCalendarNotificationTrigger(
            dateMatching: components,
            repeats: false
        )
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: trigger
        )
        do {
            try await center.add(request)
        } catch {
            print("[NudgeScheduler] Failed to add notification: \(error)")
        }
    }
    
    /// When should we nudge? At the cadence boundary.
    /// e.g. if cadence is 14 days and last contact was 5 days ago, nudge in 9 days.
    private func nudgeDate(for person: Person) -> Date? {
        Self.nextReminderDate(
            cadence: person.cadence,
            lastContactedAt: person.lastContactedAt,
            hasPriorContact: !person.checkIns.isEmpty,
            reminderHour: person.reminderHour,
            reminderMinute: person.reminderMinute,
            snoozedUntilAt: person.snoozedUntilAt,
            ring: person.ring
        )
    }
    
    private static func adjustedReminderTime(hour: Int, minute: Int) -> (hour: Int, minute: Int) {
        let normalizedHour = min(max(hour, 0), 23)
        let normalizedMinute = min(max(minute, 0), 59)
        
        guard AppSettings.quietHoursEnabled else {
            return (normalizedHour, normalizedMinute)
        }
        
        let candidate = normalizedHour * 60 + normalizedMinute
        let quietStart = AppSettings.quietStartHour * 60 + AppSettings.quietStartMinute
        let quietEnd = AppSettings.quietEndHour * 60 + AppSettings.quietEndMinute
        
        let inQuietHours: Bool
        if quietStart < quietEnd {
            inQuietHours = candidate >= quietStart && candidate < quietEnd
        } else if quietStart > quietEnd {
            inQuietHours = candidate >= quietStart || candidate < quietEnd
        } else {
            // Start == end means no quiet window — disable quiet hours
            inQuietHours = false
        }
        
        guard inQuietHours else {
            return (normalizedHour, normalizedMinute)
        }
        
        return (AppSettings.quietEndHour, AppSettings.quietEndMinute)
    }
    
    /// Generate warm, varied notification copy.
    private func nudgeCopy(for person: Person) -> String {
        let name = person.name
        
        if person.checkIns.isEmpty {
            return "You haven't checked in with \(name) yet. Start with a quick hello."
        }
        
        let days = person.daysSinceContact
        
        let templates: [String] = [
            "It's been \(days) days since you caught up with \(name).",
            "A quick check-in with \(name) would keep this relationship warm.",
            "Been a little while since you reached out to \(name).",
            "\(name) is overdue for a catch-up. Even a quick text counts.",
            "\(name) is in your \(person.ring.label.lowercased()) circle. Time for a touchpoint.",
            "It's been \(formatDuration(days)) since you and \(name) connected.",
        ]
        
        // Deterministic but varied selection based on person name + current day
        let dayOfYear = Calendar.current.ordinality(of: .day, in: .year, for: .now) ?? 0
        let index = (name.hashValue + dayOfYear) % templates.count
        return templates[abs(index) % templates.count]
    }
    
    private func formatDuration(_ days: Int) -> String {
        if days < 7 {
            return "\(days) days"
        } else if days < 30 {
            let weeks = days / 7
            return "\(weeks) \(weeks == 1 ? "week" : "weeks")"
        } else {
            let months = days / 30
            return "\(months) \(months == 1 ? "month" : "months")"
        }
    }
}
