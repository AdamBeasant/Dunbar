import SwiftUI
import UserNotifications

struct OnboardingView: View {
    let onComplete: () -> Void

    @State private var currentPage = 0
    @State private var userName = ""
    @State private var notificationsGranted = false
    @FocusState private var nameFieldFocused: Bool

    // Animation states
    @State private var ringScales: [CGFloat] = [0, 0, 0, 0]
    @State private var ringOpacities: [Double] = [0, 0, 0, 0]
    @State private var contentOpacity: Double = 0
    @State private var pulseScale: CGFloat = 1.0

    private let totalPages = 6
    private let rings = DunbarRing.allCases
    private let ringRadii: [CGFloat] = [44, 74, 104, 134]

    var body: some View {
        ZStack {
            DunbarTheme.background
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Skip button (notifications + personalisation pages)
                HStack {
                    Spacer()
                    if currentPage == 3 || currentPage == 4 {
                        Button(currentPage == 3 ? "Not now" : "Skip") {
                            advance()
                        }
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(DunbarTheme.textSecondary)
                    }
                }
                .frame(height: 24)
                .padding(.horizontal, 24)
                .padding(.top, 16)

                // Page content
                TabView(selection: $currentPage) {
                    emotionPage.tag(0)
                    sciencePage.tag(1)
                    benefitsPage.tag(2)
                    notificationsPage.tag(3)
                    personalisePage.tag(4)
                    launchPage.tag(5)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut(duration: 0.3), value: currentPage)

                // Page dots
                pageIndicator
                    .padding(.bottom, 16)

                // Bottom button
                bottomButton
                    .padding(.horizontal, 24)
                    .padding(.bottom, 40)
            }
        }
        .onAppear {
            animateRingsIn()
        }
    }

    // MARK: - Shared Ring Graphic

    private func concentricRings(animated: Bool) -> some View {
        ZStack {
            ForEach(Array(rings.enumerated()), id: \.element.rawValue) { index, ring in
                Circle()
                    .stroke(
                        DunbarTheme.ringColor(for: ring).opacity(0.45),
                        lineWidth: 1.5
                    )
                    .frame(width: ringRadii[index] * 2, height: ringRadii[index] * 2)
                    .scaleEffect(animated ? ringScales[index] : 1)
                    .opacity(animated ? ringOpacities[index] : 1)
            }

            centerDot(animated: animated)
        }
    }

    private func centerDot(animated: Bool) -> some View {
        ZStack {
            Circle()
                .fill(DunbarTheme.ringColor(for: .core).opacity(0.15))
                .frame(width: 36, height: 36)
                .overlay(
                    Circle()
                        .strokeBorder(DunbarTheme.ringColor(for: .core).opacity(0.4), lineWidth: 1)
                )

            Image(systemName: "heart.fill")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(DunbarTheme.ringColor(for: .core))
        }
        .scaleEffect(animated ? ringScales[0] : 1)
        .opacity(animated ? ringOpacities[0] : 1)
    }

    private var labeledRingsGraphic: some View {
        ZStack {
            labeledRingCircles
            labeledRingLabels
            centerDot(animated: false)
        }
    }

    private var labeledRingCircles: some View {
        ZStack {
            ForEach(Array(rings.enumerated()), id: \.element.rawValue) { index, ring in
                Circle()
                    .stroke(
                        DunbarTheme.ringColor(for: ring).opacity(0.5),
                        lineWidth: 1.5
                    )
                    .frame(width: ringRadii[index] * 2, height: ringRadii[index] * 2)
            }
        }
    }

    private var labeledRingLabels: some View {
        ZStack {
            ForEach(Array(rings.enumerated()), id: \.element.rawValue) { index, ring in
                Text("\(ring.capacity)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(DunbarTheme.ringColor(for: ring))
                    .offset(x: ringRadii[index] + 14)
            }
        }
    }

    // MARK: - Screen 1: Emotional Hook

    private var emotionPage: some View {
        VStack(spacing: 0) {
            Spacer()

            concentricRings(animated: true)
                .padding(.bottom, 48)

            Text("Your relationships are your\nmost valuable asset")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(DunbarTheme.textPrimary)
                .multilineTextAlignment(.center)
                .opacity(contentOpacity)
                .padding(.bottom, 12)

            Text("The people closest to you shape your\nhappiness, health, and sense of belonging.")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(DunbarTheme.textSecondary)
                .multilineTextAlignment(.center)
                .opacity(contentOpacity)

            Spacer()
            Spacer()
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Screen 2: Scientific Evidence

    private var sciencePage: some View {
        VStack(spacing: 0) {
            Spacer()

            labeledRingsGraphic
                .padding(.bottom, 48)

            Text("The science of connection")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(DunbarTheme.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.bottom, 12)

            Text("Anthropologist Robin Dunbar discovered that humans naturally maintain relationships in layers \u{2014} an inner circle of 5, then 15, 50, and 150.")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(DunbarTheme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
                .padding(.bottom, 16)

            // Research badge
            HStack(spacing: 6) {
                Image(systemName: "book.closed.fill")
                    .font(.system(size: 11))
                Text("Based on 30+ years of research")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(DunbarTheme.ringColor(for: .core))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(DunbarTheme.ringColor(for: .core).opacity(0.1))
            )

            Spacer()
            Spacer()
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Screen 3: Benefits

    private var benefitsPage: some View {
        VStack(spacing: 0) {
            Spacer()

            // Feature icon cluster
            ZStack {
                Circle()
                    .fill(DunbarTheme.ringColor(for: .core).opacity(0.08))
                    .frame(width: 140, height: 140)

                Image(systemName: "sparkles")
                    .font(.system(size: 48, weight: .light))
                    .foregroundStyle(DunbarTheme.ringColor(for: .core).opacity(0.7))
            }
            .padding(.bottom, 48)

            Text("Stay close to the people\nwho matter")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(DunbarTheme.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.bottom, 28)

            VStack(alignment: .leading, spacing: 18) {
                benefitRow(
                    icon: "bell.fill",
                    title: "Gentle nudges",
                    detail: "A quiet reminder when it's been too long"
                )
                benefitRow(
                    icon: "leaf.fill",
                    title: "Watch relationships grow",
                    detail: "See your connections bloom or wilt over time"
                )
                benefitRow(
                    icon: "arrow.triangle.2.circlepath",
                    title: "Smart rebalancing",
                    detail: "Suggestions to keep your circles healthy"
                )
            }
            .padding(.horizontal, 8)

            Spacer()
            Spacer()
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Screen 4: Notifications

    private var notificationsPage: some View {
        VStack(spacing: 0) {
            Spacer()

            notificationsBellGraphic
                .padding(.bottom, 44)

            Text("Never lose touch")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(DunbarTheme.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.bottom, 12)

            Text("Get gentle reminders when it's time\nto reach out to someone you care about.")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(DunbarTheme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.bottom, 24)

            notificationFeatureRows

            Spacer()
            Spacer()
        }
        .padding(.horizontal, 24)
        .onAppear {
            // Auto-trigger the permission prompt after a brief pause
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                guard currentPage == 3 else { return }
                requestNotifications()
            }
        }
    }

    private var notificationsBellGraphic: some View {
        ZStack {
            // Outer glow ring
            Circle()
                .fill(DunbarTheme.ringColor(for: .core).opacity(0.06))
                .frame(width: 160, height: 160)

            Circle()
                .fill(DunbarTheme.ringColor(for: .core).opacity(0.10))
                .frame(width: 110, height: 110)

            Circle()
                .fill(DunbarTheme.ringColor(for: .core).opacity(0.15))
                .frame(width: 72, height: 72)

            Image(systemName: "bell.badge.fill")
                .font(.system(size: 32, weight: .medium))
                .foregroundStyle(DunbarTheme.ringColor(for: .core))
        }
    }

    private var notificationFeatureRows: some View {
        VStack(alignment: .leading, spacing: 14) {
            notificationFeature(
                icon: "clock.fill",
                text: "Perfectly timed, never pushy"
            )
            notificationFeature(
                icon: "moon.fill",
                text: "Respects your quiet hours"
            )
            notificationFeature(
                icon: "hand.raised.fill",
                text: "You're always in control"
            )
        }
        .padding(.horizontal, 8)
    }

    private func notificationFeature(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundStyle(DunbarTheme.ringColor(for: .core))
                .frame(width: 24)

            Text(text)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(DunbarTheme.textPrimary)
        }
    }

    // MARK: - Screen 5: Personalisation

    private var personalisePage: some View {
        VStack(spacing: 0) {
            Spacer()

            ZStack {
                Circle()
                    .fill(DunbarTheme.ringColor(for: .core).opacity(0.08))
                    .frame(width: 120, height: 120)

                Image(systemName: "person.crop.circle")
                    .font(.system(size: 48, weight: .light))
                    .foregroundStyle(DunbarTheme.ringColor(for: .core).opacity(0.7))
            }
            .padding(.bottom, 40)

            Text("What should we call you?")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(DunbarTheme.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.bottom, 8)

            Text("We'll use this to personalise your experience.")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(DunbarTheme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.bottom, 32)

            TextField("Your first name", text: $userName)
                .font(.system(size: 17, weight: .medium, design: .rounded))
                .foregroundStyle(DunbarTheme.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.vertical, 14)
                .padding(.horizontal, 20)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(DunbarTheme.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(
                            nameFieldFocused
                                ? DunbarTheme.ringColor(for: .core).opacity(0.5)
                                : DunbarTheme.border,
                            lineWidth: 1
                        )
                )
                .focused($nameFieldFocused)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .padding(.horizontal, 40)

            Spacer()
            Spacer()
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Screen 5: Launch

    private var launchPage: some View {
        VStack(spacing: 0) {
            Spacer()

            concentricRings(animated: false)
                .scaleEffect(pulseScale)
            .onAppear {
                withAnimation(
                    .easeInOut(duration: 2.0)
                    .repeatForever(autoreverses: true)
                ) {
                    pulseScale = 1.06
                }
            }
            .padding(.bottom, 48)

            Text(welcomeHeadline)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(DunbarTheme.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.bottom, 12)

            Text("Start by adding the 5 people closest\nto you \u{2014} your inner circle.")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(DunbarTheme.textSecondary)
                .multilineTextAlignment(.center)

            Spacer()
            Spacer()
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Components

    private var pageIndicator: some View {
        HStack(spacing: 8) {
            ForEach(0..<totalPages, id: \.self) { index in
                Circle()
                    .fill(
                        index == currentPage
                            ? DunbarTheme.ringColor(for: .core)
                            : DunbarTheme.textTertiary.opacity(0.3)
                    )
                    .frame(width: index == currentPage ? 8 : 6, height: index == currentPage ? 8 : 6)
                    .animation(.easeInOut(duration: 0.2), value: currentPage)
            }
        }
    }

    private var bottomButton: some View {
        Button {
            if currentPage == totalPages - 1 {
                completeOnboarding()
            } else if currentPage == 3 {
                requestNotifications()
            } else {
                advance()
            }
        } label: {
            Text(bottomButtonLabel)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .frame(maxWidth: .infinity)
        }
        .dunbarPrimaryButton()
    }

    private var bottomButtonLabel: String {
        if currentPage == totalPages - 1 {
            return "Build your circle"
        } else if currentPage == 3 {
            return notificationsGranted ? "Continue" : "Enable Notifications"
        }
        return "Continue"
    }

    private func benefitRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(DunbarTheme.ringColor(for: .core))
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(DunbarTheme.textPrimary)

                Text(detail)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(DunbarTheme.textSecondary)
            }
        }
    }

    private var welcomeHeadline: String {
        let trimmed = userName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "Welcome"
        }
        return "Welcome, \(trimmed)"
    }

    // MARK: - Actions

    private func advance() {
        nameFieldFocused = false
        withAnimation {
            currentPage = min(currentPage + 1, totalPages - 1)
        }
    }

    private func requestNotifications() {
        Task {
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()

            if settings.authorizationStatus == .notDetermined {
                let granted = (try? await center.requestAuthorization(options: [.alert, .badge, .sound])) ?? false
                await MainActor.run {
                    notificationsGranted = granted
                    advance()
                }
            } else {
                // Already granted or denied — just move on
                await MainActor.run {
                    notificationsGranted = settings.authorizationStatus == .authorized
                    advance()
                }
            }
        }
    }

    private func completeOnboarding() {
        let trimmed = userName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            AppSettings.userName = trimmed
        }
        AppSettings.hasCompletedOnboarding = true
        onComplete()
    }

    private func animateRingsIn() {
        for index in rings.indices {
            let delay = Double(index) * 0.15
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7).delay(delay)) {
                ringScales[index] = 1
                ringOpacities[index] = 1
            }
        }

        withAnimation(.easeOut(duration: 0.5).delay(0.7)) {
            contentOpacity = 1
        }
    }
}

#Preview {
    OnboardingView(onComplete: {})
}
