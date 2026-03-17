import SwiftUI
import UIKit

// MARK: - PlantView

/// Renders a plant of the given type in the given health state.
/// The plant visually changes: thriving plants are full and vibrant,
/// wilting plants droop and yellow, withering plants brown and shrink.
struct PlantView: View {
    let plantType: PlantType
    let healthState: HealthState
    var size: CGFloat = 48
    var isAnimated: Bool = true
    
    /// Thriving plants gently sway
    @State private var swaying = false
    
    var body: some View {
        Group {
            switch plantType {
            case .succulent: SucculentStateImage(state: healthState)
            case .fern: FernPlant(state: healthState)
            case .flower: FlowerPlant(state: healthState)
            case .tree: TreePlant(state: healthState)
            case .cactus: CactusPlant(state: healthState)
            }
        }
        .frame(width: size, height: size)
        .rotationEffect(
            isAnimated && healthState == .thriving && swaying
                ? .degrees(2) : .degrees(0)
        )
        .animation(
            isAnimated && healthState == .thriving
                ? .easeInOut(duration: 3).repeatForever(autoreverses: true)
                : .none,
            value: swaying
        )
        .onAppear {
            if isAnimated && healthState == .thriving {
                swaying = true
            }
        }
        .onChange(of: healthState) { _, newState in
            swaying = isAnimated && (newState == .thriving)
        }
    }
}

// MARK: - Pot (shared across all plants)

struct PotShape: View {
    var body: some View {
        Canvas { context, canvasSize in
            let w = canvasSize.width
            let h = canvasSize.height
            
            // Pot body
            let potPath = Path { p in
                p.move(to: CGPoint(x: w * 0.33, y: h * 0.67))
                p.addLine(to: CGPoint(x: w * 0.37, y: h * 0.9))
                p.addQuadCurve(
                    to: CGPoint(x: w * 0.63, y: h * 0.9),
                    control: CGPoint(x: w * 0.5, y: h * 0.95)
                )
                p.addLine(to: CGPoint(x: w * 0.67, y: h * 0.67))
                p.closeSubpath()
            }
            context.fill(potPath, with: .color(DunbarTheme.pot))
            
            // Pot rim
            let rimPath = Path { p in
                p.addRoundedRect(
                    in: CGRect(
                        x: w * 0.3, y: h * 0.64,
                        width: w * 0.4, height: h * 0.07
                    ),
                    cornerSize: CGSize(width: 3, height: 3)
                )
            }
            context.fill(rimPath, with: .color(DunbarTheme.pot.opacity(0.8)))
        }
    }
}

// MARK: - Individual Plants

/// Uses image assets for succulent states, with vector fallback if assets are missing.
/// Expected asset names:
/// - `succulent_dying`    -> withering
/// - `succulent_healthy`  -> wilting
/// - `succulent_blooming` -> thriving
struct SucculentStateImage: View {
    let state: HealthState

    private var assetName: String {
        switch state {
        case .withering: return "succulent_dying"
        case .wilting: return "succulent_healthy"
        case .thriving: return "succulent_blooming"
        }
    }

    var body: some View {
        if let uiImage = UIImage(named: assetName) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFit()
        } else {
            SucculentPlant(state: state)
        }
    }
}

struct SucculentPlant: View {
    let state: HealthState
    
    private var leafColor: Color {
        switch state {
        case .thriving: return DunbarTheme.green
        case .wilting: return Color(hex: "B8A44D")
        case .withering: return Color(hex: "B07A6A")
        }
    }
    
    private var leafScale: CGFloat {
        switch state {
        case .thriving: return 1.0
        case .wilting: return 0.85
        case .withering: return 0.65
        }
    }
    
    var body: some View {
        ZStack {
            PotShape()
            
            // Leaves cluster
            Canvas { context, size in
                let w = size.width
                let h = size.height
                let cx = w * 0.5
                let cy = h * 0.42
                let s = leafScale
                
                // Outer leaves
                let leafPositions: [(CGFloat, CGFloat, CGFloat)] = [
                    (cx, cy, 0),
                    (cx - w * 0.12 * s, cy + h * 0.02, -20),
                    (cx + w * 0.12 * s, cy + h * 0.02, 20),
                ]
                
                for (x, y, rotation) in leafPositions {
                    let rect = CGRect(
                        x: x - w * 0.14 * s,
                        y: y - h * 0.14 * s,
                        width: w * 0.28 * s,
                        height: h * 0.28 * s
                    )
                    let leafPath = Path(ellipseIn: rect)
                    
                    var transform = CGAffineTransform.identity
                    transform = transform.translatedBy(x: x, y: y)
                    transform = transform.rotated(by: CGFloat(rotation) * .pi / 180)
                    transform = transform.translatedBy(x: -x, y: -y)
                    
                    context.fill(
                        leafPath.applying(transform),
                        with: .color(leafColor)
                    )
                }
                
                // Inner highlight
                if state == .thriving {
                    let highlightRect = CGRect(
                        x: cx - w * 0.08,
                        y: cy - h * 0.1,
                        width: w * 0.16,
                        height: h * 0.16
                    )
                    context.fill(
                        Path(ellipseIn: highlightRect),
                        with: .color(leafColor.opacity(0.4))
                    )
                }
            }
        }
    }
}

struct FernPlant: View {
    let state: HealthState
    
    private var leafColor: Color {
        switch state {
        case .thriving: return DunbarTheme.green
        case .wilting: return Color(hex: "B8A44D")
        case .withering: return Color(hex: "B07A6A")
        }
    }
    
    private var droopAngle: Double {
        switch state {
        case .thriving: return -40
        case .wilting: return -15
        case .withering: return 20
        }
    }
    
    var body: some View {
        ZStack {
            PotShape()
            
            Canvas { context, size in
                let w = size.width
                let h = size.height
                let cx = w * 0.5
                
                // Main stem
                var stemPath = Path()
                stemPath.move(to: CGPoint(x: cx, y: h * 0.65))
                stemPath.addLine(to: CGPoint(x: cx, y: h * 0.3))
                context.stroke(stemPath, with: .color(leafColor.opacity(0.8)), lineWidth: 2.5)
                
                // Fronds
                let frondPairs: [(CGFloat, Bool)] = [
                    (h * 0.35, true),
                    (h * 0.45, true),
                    (h * 0.55, true),
                ]
                
                for (yPos, _) in frondPairs {
                    // Left frond
                    var leftPath = Path()
                    leftPath.move(to: CGPoint(x: cx, y: yPos))
                    leftPath.addQuadCurve(
                        to: CGPoint(x: cx - w * 0.3, y: yPos + CGFloat(droopAngle < 0 ? droopAngle * 0.3 : droopAngle * 0.5)),
                        control: CGPoint(x: cx - w * 0.15, y: yPos - h * 0.05)
                    )
                    context.stroke(leftPath, with: .color(leafColor), lineWidth: 2)
                    
                    // Right frond
                    var rightPath = Path()
                    rightPath.move(to: CGPoint(x: cx, y: yPos))
                    rightPath.addQuadCurve(
                        to: CGPoint(x: cx + w * 0.3, y: yPos + CGFloat(droopAngle < 0 ? droopAngle * 0.3 : droopAngle * 0.5)),
                        control: CGPoint(x: cx + w * 0.15, y: yPos - h * 0.05)
                    )
                    context.stroke(rightPath, with: .color(leafColor), lineWidth: 2)
                }
            }
        }
    }
}

struct FlowerPlant: View {
    let state: HealthState
    
    private var petalColor: Color {
        switch state {
        case .thriving: return Color(hex: "E88BA5")
        case .wilting: return Color(hex: "D4A870")
        case .withering: return Color(hex: "B07A6A")
        }
    }
    
    private var stemColor: Color {
        switch state {
        case .thriving: return DunbarTheme.green
        case .wilting: return Color(hex: "B8A44D")
        case .withering: return Color(hex: "8B6B5E")
        }
    }
    
    var body: some View {
        ZStack {
            PotShape()
            
            Canvas { context, size in
                let w = size.width
                let h = size.height
                let cx = w * 0.5
                
                // Stem (droops when withering)
                let stemEndX: CGFloat = state == .withering ? cx + w * 0.1 : cx
                let stemEndY: CGFloat = state == .withering ? h * 0.35 : h * 0.2
                
                var stemPath = Path()
                stemPath.move(to: CGPoint(x: cx, y: h * 0.65))
                stemPath.addQuadCurve(
                    to: CGPoint(x: stemEndX, y: stemEndY),
                    control: CGPoint(x: cx, y: h * 0.45)
                )
                context.stroke(stemPath, with: .color(stemColor), lineWidth: 2.5)
                
                // Flower head
                if state != .withering {
                    let petalCount = 6
                    let flowerCX = stemEndX
                    let flowerCY = stemEndY
                    let petalRadius: CGFloat = state == .wilting ? w * 0.06 : w * 0.08
                    let spread: CGFloat = state == .wilting ? w * 0.08 : w * 0.1
                    
                    for i in 0..<petalCount {
                        let angle = (CGFloat(i) / CGFloat(petalCount)) * .pi * 2
                        let px = flowerCX + cos(angle) * spread
                        let py = flowerCY + sin(angle) * spread
                        let rect = CGRect(
                            x: px - petalRadius,
                            y: py - petalRadius * 1.3,
                            width: petalRadius * 2,
                            height: petalRadius * 2.6
                        )
                        
                        var transform = CGAffineTransform.identity
                        transform = transform.translatedBy(x: px, y: py)
                        transform = transform.rotated(by: angle)
                        transform = transform.translatedBy(x: -px, y: -py)
                        
                        context.fill(
                            Path(ellipseIn: rect).applying(transform),
                            with: .color(petalColor)
                        )
                    }
                    
                    // Center
                    let centerRect = CGRect(
                        x: flowerCX - w * 0.05,
                        y: flowerCY - w * 0.05,
                        width: w * 0.1,
                        height: w * 0.1
                    )
                    context.fill(Path(ellipseIn: centerRect), with: .color(Color(hex: "F7D76D")))
                } else {
                    // Drooping petals for withering
                    let flowerCX = stemEndX
                    let flowerCY = stemEndY
                    
                    let petal1 = CGRect(x: flowerCX - w * 0.05, y: flowerCY, width: w * 0.08, height: w * 0.12)
                    context.fill(Path(ellipseIn: petal1), with: .color(petalColor.opacity(0.7)))
                    
                    let centerRect = CGRect(x: flowerCX - w * 0.04, y: flowerCY - w * 0.04, width: w * 0.08, height: w * 0.08)
                    context.fill(Path(ellipseIn: centerRect), with: .color(Color(hex: "A89070")))
                }
                
                // Leaves on stem (thriving only)
                if state == .thriving {
                    var leafPath = Path()
                    leafPath.move(to: CGPoint(x: cx - w * 0.02, y: h * 0.5))
                    leafPath.addQuadCurve(
                        to: CGPoint(x: cx - w * 0.15, y: h * 0.48),
                        control: CGPoint(x: cx - w * 0.1, y: h * 0.44)
                    )
                    leafPath.addQuadCurve(
                        to: CGPoint(x: cx - w * 0.02, y: h * 0.5),
                        control: CGPoint(x: cx - w * 0.1, y: h * 0.53)
                    )
                    context.fill(leafPath, with: .color(stemColor))
                }
            }
        }
    }
}

struct TreePlant: View {
    let state: HealthState
    
    private var canopyColor: Color {
        switch state {
        case .thriving: return DunbarTheme.green
        case .wilting: return Color(hex: "B8A44D")
        case .withering: return Color(hex: "B07A6A")
        }
    }
    
    private var canopyScale: CGFloat {
        switch state {
        case .thriving: return 1.0
        case .wilting: return 0.8
        case .withering: return 0.55
        }
    }
    
    var body: some View {
        ZStack {
            // Trunk (no pot — trees grow from ground)
            Canvas { context, size in
                let w = size.width
                let h = size.height
                let cx = w * 0.5
                
                // Trunk
                let trunkRect = CGRect(
                    x: cx - w * 0.06,
                    y: h * 0.45,
                    width: w * 0.12,
                    height: h * 0.45
                )
                context.fill(
                    Path(roundedRect: trunkRect, cornerRadius: 3),
                    with: .color(Color(hex: "8B7355"))
                )
                
                // Canopy
                let canopyCY = h * 0.32
                let rx = w * 0.3 * canopyScale
                let ry = h * 0.24 * canopyScale
                
                let canopyRect = CGRect(
                    x: cx - rx, y: canopyCY - ry,
                    width: rx * 2, height: ry * 2
                )
                context.fill(Path(ellipseIn: canopyRect), with: .color(canopyColor))
                
                // Canopy highlight
                let highlightRect = CGRect(
                    x: cx - rx * 0.7, y: canopyCY - ry * 0.8,
                    width: rx * 1.4, height: ry * 1.2
                )
                context.fill(
                    Path(ellipseIn: highlightRect),
                    with: .color(canopyColor.opacity(0.3))
                )
                
                // Fallen leaves when withering
                if state == .withering {
                    for (x, y, r) in [(w * 0.3, h * 0.82, 2.0), (w * 0.65, h * 0.85, 1.5), (w * 0.25, h * 0.88, 1.2)] as [(CGFloat, CGFloat, CGFloat)] {
                        let leafRect = CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)
                        context.fill(Path(ellipseIn: leafRect), with: .color(canopyColor.opacity(0.4)))
                    }
                }
            }
        }
    }
}

struct CactusPlant: View {
    let state: HealthState
    
    private var bodyColor: Color {
        switch state {
        case .thriving: return DunbarTheme.green
        case .wilting: return Color(hex: "9A9B50")
        case .withering: return Color(hex: "9B8070")
        }
    }
    
    var body: some View {
        ZStack {
            PotShape()
            
            Canvas { context, size in
                let w = size.width
                let h = size.height
                let cx = w * 0.5
                let lean: CGFloat = state == .withering ? w * 0.04 : 0
                
                // Main body
                let bodyRect = CGRect(
                    x: cx - w * 0.08 + lean,
                    y: h * 0.2,
                    width: w * 0.16,
                    height: h * 0.45
                )
                context.fill(
                    Path(roundedRect: bodyRect, cornerRadius: w * 0.08),
                    with: .color(bodyColor)
                )
                
                // Arms
                if state != .withering {
                    // Left arm
                    let leftArmRect = CGRect(
                        x: cx - w * 0.25 + lean,
                        y: h * 0.32,
                        width: w * 0.12,
                        height: h * 0.22
                    )
                    context.fill(
                        Path(roundedRect: leftArmRect, cornerRadius: w * 0.06),
                        with: .color(bodyColor)
                    )
                    // Connector
                    let leftConn = CGRect(
                        x: cx - w * 0.15 + lean,
                        y: h * 0.38,
                        width: w * 0.12,
                        height: h * 0.08
                    )
                    context.fill(Path(roundedRect: leftConn, cornerRadius: 3), with: .color(bodyColor))
                    
                    // Right arm
                    let rightArmRect = CGRect(
                        x: cx + w * 0.13 + lean,
                        y: h * 0.28,
                        width: w * 0.12,
                        height: h * 0.18
                    )
                    context.fill(
                        Path(roundedRect: rightArmRect, cornerRadius: w * 0.06),
                        with: .color(bodyColor)
                    )
                    let rightConn = CGRect(
                        x: cx + w * 0.05 + lean,
                        y: h * 0.34,
                        width: w * 0.12,
                        height: h * 0.08
                    )
                    context.fill(Path(roundedRect: rightConn, cornerRadius: 3), with: .color(bodyColor))
                } else {
                    // Drooping arms for withering
                    let leftArmRect = CGRect(
                        x: cx - w * 0.22 + lean,
                        y: h * 0.4,
                        width: w * 0.1,
                        height: h * 0.16
                    )
                    context.fill(
                        Path(roundedRect: leftArmRect, cornerRadius: w * 0.05),
                        with: .color(bodyColor)
                    )
                }
                
                // Flower on top (thriving only)
                if state == .thriving {
                    let flowerRect = CGRect(
                        x: cx - w * 0.05 + lean,
                        y: h * 0.14,
                        width: w * 0.1,
                        height: w * 0.1
                    )
                    context.fill(Path(ellipseIn: flowerRect), with: .color(Color(hex: "F2AFC2")))
                    
                    let centerRect = CGRect(
                        x: cx - w * 0.025 + lean,
                        y: h * 0.155,
                        width: w * 0.05,
                        height: w * 0.05
                    )
                    context.fill(Path(ellipseIn: centerRect), with: .color(Color(hex: "F7D76D")))
                }
            }
        }
    }
}

// MARK: - Preview

#Preview("All Plants - All States") {
    VStack(spacing: 24) {
        ForEach(PlantType.allCases) { plantType in
            HStack(spacing: 20) {
                ForEach([HealthState.thriving, .wilting, .withering], id: \.self) { state in
                    VStack(spacing: 4) {
                        PlantView(plantType: plantType, healthState: state, size: 64)
                        Text(state.label)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
    .padding()
    .background(DunbarTheme.background)
}
