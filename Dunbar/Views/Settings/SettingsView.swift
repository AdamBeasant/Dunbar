import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(NudgeScheduler.self) private var nudgeScheduler

    let showsCloseButton: Bool

    @Query(
        filter: #Predicate<Person> { !$0.isArchived },
        sort: [SortDescriptor(\Person.name)]
    ) private var people: [Person]

    @AppStorage(AppSettings.reminderDefaultHourKey) private var defaultReminderHour = 10
    @AppStorage(AppSettings.reminderDefaultMinuteKey) private var defaultReminderMinute = 0
    @AppStorage(AppSettings.quietHoursEnabledKey) private var quietHoursEnabled = false
    @AppStorage(AppSettings.quietStartHourKey) private var quietStartHour = 22
    @AppStorage(AppSettings.quietStartMinuteKey) private var quietStartMinute = 0
    @AppStorage(AppSettings.quietEndHourKey) private var quietEndHour = 8
    @AppStorage(AppSettings.quietEndMinuteKey) private var quietEndMinute = 0
    @AppStorage(AppSettings.weeklyGoalKey) private var weeklyGoal = 3
    @AppStorage(AppSettings.notificationSoundEnabledKey) private var notificationSoundEnabled = true
    @AppStorage(AppSettings.notificationBadgeEnabledKey) private var notificationBadgeEnabled = true
    @AppStorage(AppSettings.snoozePreset1DaysKey) private var snoozePreset1Days = 1
    @AppStorage(AppSettings.snoozePreset2DaysKey) private var snoozePreset2Days = 3
    @AppStorage(AppSettings.snoozePreset3DaysKey) private var snoozePreset3Days = 7

    @State private var simulatorCadence: Cadence = .weekly
    @State private var simulatorNeverContacted = true
    @State private var simulatorDaysSinceContact = 0

    init(showsCloseButton: Bool = false) {
        self.showsCloseButton = showsCloseButton
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                reminderCard
                reminderSimulatorCard
                notificationControlsCard
                quietHoursCard
                weeklyGoalCard
                actionsCard
                footerBranding
            }
            .padding(.horizontal, 20)
            .padding(.top, showsCloseButton ? 18 : 8)
            .padding(.bottom, 28)
        }
        .background(DunbarTheme.background)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(showsCloseButton ? .visible : .hidden, for: .navigationBar)
        .toolbar {
            if showsCloseButton {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(DunbarTheme.ringColor(for: .core))
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                }
            }
        }
        .onChange(of: quietHoursEnabled) { _, _ in rescheduleAll() }
        .onChange(of: quietStartHour) { _, _ in rescheduleAll() }
        .onChange(of: quietStartMinute) { _, _ in rescheduleAll() }
        .onChange(of: quietEndHour) { _, _ in rescheduleAll() }
        .onChange(of: quietEndMinute) { _, _ in rescheduleAll() }
        .onChange(of: notificationSoundEnabled) { _, _ in rescheduleAll() }
        .onChange(of: notificationBadgeEnabled) { _, _ in rescheduleAll() }
        .onAppear {
            simulatorCadence = .weekly
            simulatorNeverContacted = true
            simulatorDaysSinceContact = 0
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Settings")
                .font(DunbarTheme.titleFont)
                .foregroundStyle(DunbarTheme.textPrimary)

            Text("Tune reminders, premium controls, and weekly momentum.")
                .font(DunbarTheme.subtitleFont)
                .foregroundStyle(DunbarTheme.textSecondary)
        }
        .padding(.bottom, 6)
    }

    private var reminderCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("DEFAULT REMINDER TIME")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DunbarTheme.textTertiary)
                .tracking(0.8)

            DatePicker(
                "Time",
                selection: defaultReminderDateBinding,
                displayedComponents: .hourAndMinute
            )
            .datePickerStyle(.compact)
            .labelsHidden()

            Text("Used when creating new contacts.")
                .font(.system(size: 13))
                .foregroundStyle(DunbarTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dunbarCard()
    }

    private var reminderSimulatorCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("REMINDER SIMULATOR")
                .font(DunbarTheme.eyebrowFont)
                .foregroundStyle(DunbarTheme.textTertiary)
                .tracking(0.8)

            Picker("Cadence", selection: $simulatorCadence) {
                ForEach(Cadence.allCases) { cadence in
                    Text(cadence.label).tag(cadence)
                }
            }
            .pickerStyle(.menu)

            Toggle("Never contacted yet", isOn: $simulatorNeverContacted)
                .tint(DunbarTheme.ringColor(for: .core))

            if !simulatorNeverContacted {
                Stepper(value: $simulatorDaysSinceContact, in: 0...365) {
                    Text("Days since last contact: \(simulatorDaysSinceContact)")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(DunbarTheme.textPrimary)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(simulatorPreviewDates.enumerated()), id: \.offset) { index, date in
                    let day = date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
                    let time = date.formatted(date: .omitted, time: .shortened)
                    Text("\(index + 1). \(day) at \(time)")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(DunbarTheme.textSecondary)
                }
            }

            if quietHoursEnabled {
                Text("Quiet hours are active: reminders in quiet window shift to quiet-end time.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(DunbarTheme.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dunbarCard()
    }

    private var notificationControlsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("NOTIFICATION CONTROLS")
                .font(DunbarTheme.eyebrowFont)
                .foregroundStyle(DunbarTheme.textTertiary)
                .tracking(0.8)

            Toggle("Sound", isOn: $notificationSoundEnabled)
                .tint(DunbarTheme.ringColor(for: .core))

            Toggle("Badge", isOn: $notificationBadgeEnabled)
                .tint(DunbarTheme.ringColor(for: .core))

            VStack(alignment: .leading, spacing: 8) {
                Text("SNOOZE PRESETS")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(DunbarTheme.textTertiary)

                presetStepper(title: "Preset 1", value: $snoozePreset1Days)
                presetStepper(title: "Preset 2", value: $snoozePreset2Days)
                presetStepper(title: "Preset 3", value: $snoozePreset3Days)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dunbarCard()
    }

    private func presetStepper(title: String, value: Binding<Int>) -> some View {
        Stepper(value: value, in: 1...30) {
            Text("\(title): \(value.wrappedValue)d")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(DunbarTheme.textPrimary)
        }
    }


    private var quietHoursCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Toggle(isOn: $quietHoursEnabled) {
                Text("Quiet hours")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(DunbarTheme.textPrimary)
            }
            .tint(DunbarTheme.ringColor(for: .core))

            if quietHoursEnabled {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Start")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(DunbarTheme.textTertiary)
                        DatePicker(
                            "Quiet start",
                            selection: quietStartDateBinding,
                            displayedComponents: .hourAndMinute
                        )
                        .labelsHidden()
                        .datePickerStyle(.compact)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("End")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(DunbarTheme.textTertiary)
                        DatePicker(
                            "Quiet end",
                            selection: quietEndDateBinding,
                            displayedComponents: .hourAndMinute
                        )
                        .labelsHidden()
                        .datePickerStyle(.compact)
                    }
                }

                Text("If a reminder lands in this window, it moves to the quiet end time.")
                    .font(.system(size: 13))
                    .foregroundStyle(DunbarTheme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dunbarCard()
    }

    private var weeklyGoalCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("WEEKLY GOAL")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DunbarTheme.textTertiary)
                .tracking(0.8)

            Stepper(value: $weeklyGoal, in: 1...20) {
                Text("\(weeklyGoal) check-ins per week")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(DunbarTheme.textPrimary)
            }
            .tint(DunbarTheme.ringColor(for: .core))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dunbarCard()
    }

    private var actionsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button("Apply default time to all contacts") {
                applyDefaultReminderToAll()
            }
            .frame(maxWidth: .infinity)
            .dunbarPrimaryButton()

            Button("Reschedule all reminders now") {
                rescheduleAll()
            }
            .frame(maxWidth: .infinity)
            .dunbarSecondaryButton()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var footerBranding: some View {
        VStack(spacing: 4) {
            Text("Dunbar")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(DunbarTheme.textSecondary)
            Text("Handbook Digital Limited")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(DunbarTheme.textTertiary)
            Text("v1.0.0")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(DunbarTheme.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 12)
    }

    private var defaultReminderDateBinding: Binding<Date> {
        Binding(
            get: { timeDate(hour: defaultReminderHour, minute: defaultReminderMinute) },
            set: { newValue in
                let components = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                defaultReminderHour = components.hour ?? 10
                defaultReminderMinute = components.minute ?? 0
            }
        )
    }

    private var quietStartDateBinding: Binding<Date> {
        Binding(
            get: { timeDate(hour: quietStartHour, minute: quietStartMinute) },
            set: { newValue in
                let components = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                quietStartHour = components.hour ?? 22
                quietStartMinute = components.minute ?? 0
            }
        )
    }

    private var quietEndDateBinding: Binding<Date> {
        Binding(
            get: { timeDate(hour: quietEndHour, minute: quietEndMinute) },
            set: { newValue in
                let components = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                quietEndHour = components.hour ?? 8
                quietEndMinute = components.minute ?? 0
            }
        )
    }


    private var simulatorPreviewDates: [Date] {
        let lastContact: Date
        if simulatorNeverContacted {
            lastContact = .now
        } else {
            lastContact = Calendar.current.date(byAdding: .day, value: -simulatorDaysSinceContact, to: .now) ?? .now
        }

        return NudgeScheduler.projectedReminderDates(
            cadence: simulatorCadence,
            lastContactedAt: lastContact,
            hasPriorContact: !simulatorNeverContacted,
            reminderHour: defaultReminderHour,
            reminderMinute: defaultReminderMinute,
            count: 3
        )
    }

    private func timeDate(hour: Int, minute: Int) -> Date {
        Calendar.current.date(
            bySettingHour: hour,
            minute: minute,
            second: 0,
            of: .now
        ) ?? .now
    }

    private func applyDefaultReminderToAll() {
        for person in people {
            person.reminderHour = min(max(defaultReminderHour, 0), 23)
            person.reminderMinute = min(max(defaultReminderMinute, 0), 59)
        }
        do { try modelContext.save() } catch { print("[Dunbar] Save failed: \(error)") }
        rescheduleAll()
    }

    private func rescheduleAll() {
        Task {
            await nudgeScheduler.rescheduleAll(people: people)
            WidgetSnapshotStore.write(WidgetSnapshotStore.buildSnapshot(people: people))
        }
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
    .modelContainer(for: [Person.self, CheckIn.self, CareerRole.self, FamilyMember.self, FamilyPerson.self, FamilyRelationship.self, FamilyGraphV2.self, FamilyNodeV2.self, FamilyEdgeV2.self], inMemory: true)
    .environment(NudgeScheduler())
    .environment(AppLockManager())
    .environment(HapticFeedbackService())
}
