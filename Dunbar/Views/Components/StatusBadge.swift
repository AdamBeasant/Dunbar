import SwiftUI

struct StatusBadge: View {
    let state: HealthState
    
    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(DunbarTheme.color(for: state))
                .frame(width: 7, height: 7)
            
            Text(state.label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DunbarTheme.color(for: state))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 5)
        .background(DunbarTheme.backgroundColor(for: state))
        .clipShape(Capsule())
    }
}

#Preview {
    VStack(spacing: 12) {
        StatusBadge(state: .thriving)
        StatusBadge(state: .wilting)
        StatusBadge(state: .withering)
    }
}
