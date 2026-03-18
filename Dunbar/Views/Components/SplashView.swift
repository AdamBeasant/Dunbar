import SwiftUI

struct SplashView: View {
    let onFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var ringScales: [CGFloat] = [0, 0, 0, 0]
    @State private var ringOpacities: [Double] = [0, 0, 0, 0]
    @State private var textOpacity: Double = 0
    @State private var dismissOpacity: Double = 1

    private let rings = DunbarRing.allCases
    private let radii: [CGFloat] = [52, 86, 120, 154]

    var body: some View {
        ZStack {
            DunbarTheme.background
                .ignoresSafeArea()

            ZStack {
                // Concentric rings
                ForEach(Array(rings.enumerated()), id: \.element.rawValue) { index, ring in
                    Circle()
                        .stroke(
                            DunbarTheme.ringColor(for: ring).opacity(0.5),
                            lineWidth: 1.5
                        )
                        .frame(width: radii[index] * 2, height: radii[index] * 2)
                        .scaleEffect(ringScales[index])
                        .opacity(ringOpacities[index])
                }

                // Center dot
                Circle()
                    .fill(DunbarTheme.ringColor(for: .core).opacity(0.15))
                    .frame(width: 42, height: 42)
                    .overlay(
                        Circle()
                            .strokeBorder(DunbarTheme.ringColor(for: .core).opacity(0.4), lineWidth: 1)
                    )
                    .scaleEffect(ringScales[0])
                    .opacity(ringOpacities[0])

                // App name
                VStack(spacing: 4) {
                    Text("Dunbar")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(DunbarTheme.textPrimary)
                }
                .offset(y: radii[3] + 40)
                .opacity(textOpacity)
            }
        }
        .opacity(dismissOpacity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Dunbar. Loading.")
        .onAppear {
            animateIn()
        }
    }

    private func animateIn() {
        if reduceMotion {
            ringScales = rings.map { _ in CGFloat(1) }
            ringOpacities = rings.map { _ in 1.0 }
            textOpacity = 1

            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                dismissOpacity = 0
                onFinished()
            }
            return
        }

        // Stagger ring animations from inner to outer
        for index in rings.indices {
            let delay = Double(index) * 0.15
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7).delay(delay)) {
                ringScales[index] = 1
                ringOpacities[index] = 1
            }
        }

        // Fade in text after rings
        withAnimation(.easeOut(duration: 0.4).delay(0.7)) {
            textOpacity = 1
        }

        // Dismiss after pause
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation(.easeOut(duration: 0.3)) {
                dismissOpacity = 0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                onFinished()
            }
        }
    }
}
