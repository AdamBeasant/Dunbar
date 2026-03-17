import SwiftUI

struct EllipsisLiquidIcon: View {
    var body: some View {
        Image(systemName: "ellipsis")
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(DunbarTheme.ringColor(for: .core))
            .frame(width: 36, height: 36)
            .background(.ultraThinMaterial, in: Circle())
            .overlay(
                Circle()
                    .strokeBorder(.white.opacity(0.28), lineWidth: 0.8)
            )
            .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
    }
}
