import SwiftUI
import UIKit

enum DunbarTheme {
    
    // MARK: - Colours
    
    /// Primary accent and status tones
    static let green = Color(hex: "059669")
    static let amber = Color(hex: "D97706")
    static let lime = Color(hex: "F59E0B")
    static let red = Color(hex: "DC2626")
    
    /// App canvas
    static let background = Color(lightHex: "F4F7FB", darkHex: "0E1116")
    
    /// Card / surface background
    static let surface = Color(lightHex: "FFFFFF", darkHex: "141923")
    static let surfaceElevated = Color(lightHex: "F8FAFD", darkHex: "1A2130")
    static let surfaceMuted = Color(lightHex: "EEF3FA", darkHex: "101723")
    
    /// Primary text
    static let textPrimary = Color(lightHex: "111827", darkHex: "E8EEF8")
    
    /// Secondary text
    static let textSecondary = Color(lightHex: "4B5563", darkHex: "A7B4C8")
    
    /// Tertiary / muted text
    static let textTertiary = Color(lightHex: "6B7280", darkHex: "7C8AA0")
    
    /// Subtle dividers and borders
    static let border = Color(lightHex: "A3B2C7", darkHex: "C5D2E8").opacity(0.22)
    static let borderStrong = Color(lightHex: "90A4BF", darkHex: "D1DCF0").opacity(0.36)
    
    /// Legacy accent token kept for compatibility with older assets.
    static let pot = Color(lightHex: "0D9488", darkHex: "22D3EE").opacity(0.75)
    
    // MARK: - State Colours
    
    static func color(for state: HealthState) -> Color {
        switch state {
        case .thriving: return green
        case .wilting: return amber
        case .withering: return red
        }
    }
    
    static func backgroundColor(for state: HealthState) -> Color {
        switch state {
        case .thriving: return green.opacity(0.18)
        case .wilting: return amber.opacity(0.16)
        case .withering: return red.opacity(0.16)
        }
    }
    
    static func ringColor(for ring: DunbarRing) -> Color {
        switch ring {
        case .core: return Color(hex: "0EA5E9")
        case .close: return Color(hex: "06B6D4")
        case .active: return Color(hex: "14B8A6")
        case .meaningful: return Color(hex: "22C55E")
        }
    }
    
    static func ringHighlightColor(for ring: DunbarRing) -> Color {
        switch ring {
        case .core: return Color(hex: "38BDF8")
        case .close: return Color(hex: "22D3EE")
        case .active: return Color(hex: "2DD4BF")
        case .meaningful: return Color(hex: "4ADE80")
        }
    }
    
    static func ringShadowColor(for ring: DunbarRing) -> Color {
        switch ring {
        case .core: return Color(hex: "0C4A6E")
        case .close: return Color(hex: "155E75")
        case .active: return Color(hex: "115E59")
        case .meaningful: return Color(hex: "14532D")
        }
    }
    
    // MARK: - Typography
    
    static let titleFont = Font.system(size: 36, weight: .bold, design: .rounded)
    static let sectionTitleFont = Font.system(size: 30, weight: .bold, design: .rounded)
    static let subtitleFont = Font.system(size: 14, weight: .medium, design: .rounded)
    static let bodyFont = Font.system(size: 15, weight: .regular, design: .rounded)
    static let buttonFont = Font.system(size: 16, weight: .semibold, design: .rounded)
    static let eyebrowFont = Font.system(size: 11, weight: .semibold, design: .rounded)
    
    // MARK: - Card Style
    
    static let cardRadius: CGFloat = 22
    static let cardPadding: CGFloat = 16
    
    static let cardShadow: some ShapeStyle = Color.black.opacity(0.28)
    static let cardShadowColor = Color(
        lightHex: "000000",
        darkHex: "000000",
        lightAlpha: 0.08,
        darkAlpha: 0.28
    )

    static let cardInnerHighlight = Color(
        lightHex: "FFFFFF",
        darkHex: "FFFFFF",
        lightAlpha: 0.65,
        darkAlpha: 0.04
    )
}

// MARK: - Color Extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        
        let r, g, b: UInt64
        switch hex.count {
        case 6:
            (r, g, b) = ((int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default:
            (r, g, b) = (0, 0, 0)
        }
        
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: 1
        )
    }
    
    init(lightHex: String, darkHex: String) {
        self.init(
            UIColor { trait in
                if trait.userInterfaceStyle == .dark {
                    return UIColor(hex: darkHex)
                }
                return UIColor(hex: lightHex)
            }
        )
    }
    
    init(lightHex: String, darkHex: String, lightAlpha: CGFloat, darkAlpha: CGFloat) {
        self.init(
            UIColor { trait in
                if trait.userInterfaceStyle == .dark {
                    return UIColor(hex: darkHex).withAlphaComponent(darkAlpha)
                }
                return UIColor(hex: lightHex).withAlphaComponent(lightAlpha)
            }
        )
    }
}

extension UIColor {
    convenience init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        
        let r, g, b: UInt64
        switch hex.count {
        case 6:
            (r, g, b) = ((int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default:
            (r, g, b) = (0, 0, 0)
        }
        
        self.init(
            red: CGFloat(r) / 255,
            green: CGFloat(g) / 255,
            blue: CGFloat(b) / 255,
            alpha: 1
        )
    }
}

// MARK: - View Modifiers

struct DunbarCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(DunbarTheme.cardPadding)
            .background(
                RoundedRectangle(cornerRadius: DunbarTheme.cardRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [DunbarTheme.surface, DunbarTheme.surfaceElevated],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: DunbarTheme.cardRadius, style: .continuous)
                    .strokeBorder(DunbarTheme.border, lineWidth: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DunbarTheme.cardRadius, style: .continuous)
                    .strokeBorder(DunbarTheme.cardInnerHighlight, lineWidth: 0.8)
            )
            .shadow(color: DunbarTheme.cardShadowColor, radius: 22, y: 10)
    }
}

struct DunbarPrimaryButtonModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(DunbarTheme.buttonFont)
            .foregroundStyle(Color.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                DunbarTheme.ringColor(for: .core),
                                DunbarTheme.ringColor(for: .close)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(.white.opacity(0.2), lineWidth: 0.8)
            )
            .shadow(color: DunbarTheme.ringColor(for: .core).opacity(0.28), radius: 10, y: 6)
    }
}

struct DunbarSecondaryButtonModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(DunbarTheme.buttonFont)
            .foregroundStyle(DunbarTheme.textPrimary)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(DunbarTheme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(DunbarTheme.border, lineWidth: 1)
            )
    }
}

struct DunbarIconButtonModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.system(size: 14, weight: .bold, design: .rounded))
            .foregroundStyle(DunbarTheme.ringColor(for: .core))
            .frame(width: 34, height: 34)
            .background(
                Circle()
                    .fill(DunbarTheme.surface)
            )
            .overlay(
                Circle()
                    .strokeBorder(DunbarTheme.border, lineWidth: 1)
            )
            .shadow(color: DunbarTheme.cardShadowColor, radius: 8, y: 4)
    }
}

extension View {
    func dunbarCard() -> some View {
        modifier(DunbarCardModifier())
    }

    func dunbarPrimaryButton() -> some View {
        modifier(DunbarPrimaryButtonModifier())
    }

    func dunbarSecondaryButton() -> some View {
        modifier(DunbarSecondaryButtonModifier())
    }

    func dunbarIconButton() -> some View {
        modifier(DunbarIconButtonModifier())
    }
}
