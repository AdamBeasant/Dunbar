import SwiftUI

struct CheckInNoteSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    let personName: String
    let onSave: (String, CheckInType) -> Void
    
    @State private var note: String = ""
    @State private var checkInType: CheckInType = .message
    
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Text("Add a note for \(personName)")
                    .font(.system(size: 22, weight: .semibold, design: .serif))
                    .foregroundStyle(DunbarTheme.textPrimary)
                
                TextField(
                    "What did you talk about?",
                    text: $note,
                    axis: .vertical
                )
                .lineLimit(3...6)
                .font(DunbarTheme.bodyFont)
                .padding(12)
                .background(DunbarTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(DunbarTheme.border, lineWidth: 1)
                )
                
                HStack(spacing: 8) {
                    ForEach(CheckInType.allCases) { type in
                        Button {
                            checkInType = type
                        } label: {
                            Text(type.label)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(checkInType == type ? Color.white : DunbarTheme.textSecondary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(
                                    checkInType == type ? DunbarTheme.ringColor(for: .core) : DunbarTheme.surface
                                )
                                .clipShape(Capsule())
                                .overlay(
                                    Capsule()
                                        .strokeBorder(DunbarTheme.border, lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                
                Spacer()
                
                Button {
                    onSave(
                        note.trimmingCharacters(in: .whitespacesAndNewlines),
                        checkInType
                    )
                    dismiss()
                } label: {
                    Text("Save check-in")
                        .font(DunbarTheme.buttonFont)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            LinearGradient(
                                colors: [DunbarTheme.ringColor(for: .core), DunbarTheme.ringColor(for: .close)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(.white.opacity(0.2), lineWidth: 0.8)
                        )
                }
                
                Button {
                    onSave("", checkInType)
                    dismiss()
                } label: {
                    Text("Skip note")
                        .font(DunbarTheme.buttonFont)
                        .foregroundStyle(DunbarTheme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
            }
            .padding(20)
            .background(DunbarTheme.background)
            .navigationTitle("Check-in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(DunbarTheme.ringColor(for: .core))
                }
            }
        }
    }
}
