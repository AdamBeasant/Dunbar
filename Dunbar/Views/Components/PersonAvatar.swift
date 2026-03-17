import SwiftUI
import UIKit

/// Shows the person's photo (if set) with a ring accent,
/// or falls back to initials.
struct PersonAvatar: View {
    let person: Person
    var size: CGFloat = 46
    
    private var stateOpacity: Double {
        switch person.healthState {
        case .thriving: return 1.0
        case .wilting: return 0.78
        case .withering: return 0.58
        }
    }

    private var initials: String {
        if person.initials.isEmpty {
            return Person.makeInitials(from: person.name)
        }
        return person.initials
    }
    
    var body: some View {
        if let photoData = person.photoData,
           let uiImage = UIImage(data: photoData) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .strokeBorder(
                            DunbarTheme.ringColor(for: person.ring).opacity(stateOpacity),
                            lineWidth: size > 60 ? 3 : 2
                        )
                )
        } else {
            Circle()
                .fill(DunbarTheme.surface)
                .frame(width: size, height: size)
                .overlay {
                    Text(initials)
                        .font(.system(size: max(11, size * 0.34), weight: .semibold))
                        .foregroundStyle(DunbarTheme.ringColor(for: person.ring))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                .overlay(
                    Circle()
                        .strokeBorder(
                            DunbarTheme.ringColor(for: person.ring).opacity(stateOpacity),
                            lineWidth: size > 60 ? 3 : 2
                        )
                )
        }
    }
}

struct RingStatusView: View {
    let ring: DunbarRing
    let state: HealthState
    var size: CGFloat = 56
    var interactiveMotion: Bool = false
    
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var spinProgress: Double = 0
    
    private var stateOpacity: Double {
        switch state {
        case .thriving: return 1.0
        case .wilting: return 0.78
        case .withering: return 0.58
        }
    }
    
    private var motionEnabled: Bool {
        interactiveMotion && !reduceMotion
    }
    
    private var spinEnabled: Bool {
        motionEnabled && size >= 72
    }
    
    private var useCompactRendering: Bool {
        size <= 56
    }
    
    var body: some View {
        Group {
            if motionEnabled {
                GeometryReader { proxy in
                    let motion = motionMetrics(for: proxy)
                    ringLayers(
                        tiltX: motion.tiltX,
                        tiltY: motion.tiltY,
                        driftX: motion.driftX,
                        driftY: motion.driftY
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(width: size, height: size)
            } else {
                ringLayers(tiltX: 0, tiltY: 0, driftX: 0, driftY: 0)
                    .frame(width: size, height: size)
            }
        }
        .onAppear { startSpinIfNeeded() }
        .onChange(of: motionEnabled) { _, enabled in
            if !enabled {
                spinProgress = 0
            } else {
                startSpinIfNeeded(reset: true)
            }
        }
    }
    
    private func ringLayers(tiltX: Double, tiltY: Double, driftX: CGFloat, driftY: CGFloat) -> some View {
        let baseColor = DunbarTheme.ringColor(for: ring).opacity(stateOpacity)
        let highlightColor = DunbarTheme.ringHighlightColor(for: ring).opacity(stateOpacity)
        let shadowColor = DunbarTheme.ringShadowColor(for: ring).opacity(stateOpacity)
        let spinDegrees = (spinEnabled ? spinProgress : 0) * 360
        
        if useCompactRendering {
            return AnyView(
                compactRingLayers(baseColor: baseColor, highlightColor: highlightColor, shadowColor: shadowColor)
                    .offset(x: driftX * 0.4, y: driftY * 0.4)
            )
        }
        
        return AnyView(
            ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            .white.opacity(0.92),
                            DunbarTheme.backgroundColor(for: state).opacity(0.92)
                        ],
                        center: .topLeading,
                        startRadius: 2,
                        endRadius: size * 0.5
                    )
                )
                .frame(width: size * 0.98, height: size * 0.98)
            
            ForEach(0..<3) { index in
                let scale = 1.0 - (Double(index) * 0.23)
                let lineWidth = max(1.4, size * 0.078 - (CGFloat(index) * 0.92))
                let rotationFactor: Double = {
                    switch index {
                    case 0: return 0.44
                    case 1: return -0.32
                    default: return 0.20
                    }
                }()
                
                Circle()
                    .stroke(
                        AngularGradient(
                            colors: [
                                highlightColor.opacity(0.9 - Double(index) * 0.15),
                                baseColor.opacity(0.88 - Double(index) * 0.14),
                                shadowColor.opacity(0.94 - Double(index) * 0.12),
                                baseColor.opacity(0.9 - Double(index) * 0.14),
                                highlightColor.opacity(0.9 - Double(index) * 0.15)
                            ],
                            center: .center,
                            angle: .degrees(230)
                        ),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(spinDegrees * rotationFactor))
                    .overlay {
                        Circle()
                            .trim(from: 0.07, to: 0.34)
                            .stroke(
                                .white.opacity(0.34 - Double(index) * 0.08),
                                style: StrokeStyle(lineWidth: lineWidth * 0.62, lineCap: .round)
                            )
                            .rotationEffect(.degrees(-26))
                    }
                    .overlay {
                        if state == .withering && index == 0 {
                            Circle()
                                .stroke(
                                    shadowColor.opacity(0.55),
                                    style: StrokeStyle(lineWidth: lineWidth, dash: [4, 3])
                                )
                        }
                    }
                    .shadow(
                        color: shadowColor.opacity(0.30 - Double(index) * 0.08),
                        radius: size * 0.04,
                        x: 0,
                        y: size * 0.015
                    )
                    .shadow(
                        color: .white.opacity(0.22 - Double(index) * 0.06),
                        radius: size * 0.02,
                        x: -size * 0.012,
                        y: -size * 0.012
                    )
                    .frame(width: size * scale, height: size * scale)
            }
            
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            .white.opacity(0.9),
                            baseColor.opacity(0.16)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size * 0.28, height: size * 0.28)
            
            Circle()
                .fill(highlightColor.opacity(0.9))
                .frame(width: size * 0.11, height: size * 0.11)
                .shadow(color: baseColor.opacity(0.4), radius: size * 0.03, y: size * 0.01)
        }
        .offset(x: driftX, y: driftY)
        .rotation3DEffect(.degrees(tiltX), axis: (x: 1, y: 0, z: 0), perspective: 0.72)
        .rotation3DEffect(.degrees(tiltY), axis: (x: 0, y: 1, z: 0), perspective: 0.72)
        )
    }
    
    private func compactRingLayers(baseColor: Color, highlightColor: Color, shadowColor: Color) -> some View {
        let outerLine = max(1.6, size * 0.10)
        let innerLine = max(1.2, size * 0.075)
        
        return ZStack {
            Circle()
                .fill(.white.opacity(0.92))
                .frame(width: size * 0.98, height: size * 0.98)
            
            Circle()
                .stroke(
                    LinearGradient(
                        colors: [highlightColor, baseColor, shadowColor],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: outerLine
                )
                .frame(width: size * 0.84, height: size * 0.84)
            
            Circle()
                .stroke(baseColor.opacity(0.55), lineWidth: innerLine)
                .frame(width: size * 0.52, height: size * 0.52)
            
            Circle()
                .fill(highlightColor.opacity(0.88))
                .frame(width: size * 0.14, height: size * 0.14)
        }
    }
    
    private func motionMetrics(for proxy: GeometryProxy) -> (tiltX: Double, tiltY: Double, driftX: CGFloat, driftY: CGFloat) {
        let frame = proxy.frame(in: .global)
        let screenBounds = currentScreenBounds
        guard screenBounds.width > 0, screenBounds.height > 0 else {
            return (0, 0, 0, 0)
        }
        
        let normalizedX = (((frame.midX / screenBounds.width) - 0.5) * 2).clamped(to: -1...1)
        let normalizedY = (((frame.midY / screenBounds.height) - 0.5) * 2).clamped(to: -1...1)
        
        return (
            tiltX: -normalizedY * 9,
            tiltY: normalizedX * 11,
            driftX: normalizedX * size * 0.018,
            driftY: normalizedY * size * 0.014
        )
    }
    
    private func startSpinIfNeeded(reset: Bool = false) {
        guard spinEnabled else { return }
        if reset {
            spinProgress = 0
        }
        guard spinProgress == 0 else { return }
        withAnimation(.linear(duration: 26).repeatForever(autoreverses: false)) {
            spinProgress = 1
        }
    }
    
    private var currentScreenBounds: CGRect {
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
        
        if let active = scenes.first(where: { $0.activationState == .foregroundActive }) {
            return active.screen.bounds
        }
        if let first = scenes.first {
            return first.screen.bounds
        }
        
        return CGRect(x: 0, y: 0, width: 390, height: 844)
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
