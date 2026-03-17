import SwiftUI

struct PersonCard: View {
    let person: Person
    var onTap: (() -> Void)?
    var onDone: (() -> Void)?
    
    @State private var justMarked = false
    
    private var cadenceDays: Int {
        max(person.cadence.days, 1)
    }
    
    private var progress: CGFloat {
        CGFloat(min(Double(person.daysSinceContact) / Double(cadenceDays), 1.3))
    }
    
    private var statusColor: Color {
        DunbarTheme.color(for: person.healthState)
    }
    
    var body: some View {
        HStack(spacing: 10) {
            cardContent
                .contentShape(RoundedRectangle(cornerRadius: DunbarTheme.cardRadius))
                .onTapGesture {
                    onTap?()
                }
            
            if person.healthState != .thriving, let onDone {
                Button {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                        justMarked = true
                    }
                    onDone()
                } label: {
                    Image(systemName: "checkmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(justMarked ? DunbarTheme.green : statusColor.opacity(0.92))
                        .frame(width: 42, height: 42)
                        .background(statusColor.opacity(0.12))
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .strokeBorder(statusColor.opacity(0.35), lineWidth: 1.5)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    private var cardContent: some View {
        HStack(spacing: 12) {
            PersonAvatar(person: person, size: 44)
            
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline) {
                    Text(person.name)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(DunbarTheme.textPrimary)
                    
                    Spacer(minLength: 6)
                    
                    Text(daysAgoText)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(statusColor)
                }
                
                if let role = person.currentCareerRole {
                    Text("\(role.title) · \(role.company)")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(DunbarTheme.textTertiary.opacity(0.95))
                        .lineLimit(1)
                }
                
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(DunbarTheme.border.opacity(0.6))
                            .frame(height: 4)
                        Capsule()
                            .fill(statusColor.opacity(0.88))
                            .frame(width: max(proxy.size.width * min(progress, 1), 8), height: 4)
                    }
                }
                .frame(height: 4)
                
                HStack(alignment: .firstTextBaseline) {
                    Text(person.cadence.label)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(DunbarTheme.textSecondary)
                    
                    Spacer(minLength: 8)
                    
                    if !person.notes.isEmpty {
                        Text(person.notes)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(DunbarTheme.ringColor(for: person.ring).opacity(0.85))
                            .lineLimit(1)
                    }
                }
            }
        }
        .dunbarCard()
    }
    
    private var daysAgoText: String {
        if person.checkIns.isEmpty {
            return "Not yet"
        }
        
        switch person.daysSinceContact {
        case 0: return "Today"
        case 1: return "Yesterday"
        case 2...6: return "\(person.daysSinceContact)d ago"
        case 7...29: return "\(person.daysSinceContact / 7)w ago"
        default: return "\(person.daysSinceContact / 30)mo ago"
        }
    }
}
