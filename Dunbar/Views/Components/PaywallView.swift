import SwiftUI
import StoreKit

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(PremiumManager.self) private var premiumManager

    private let ringRadii: [CGFloat] = [28, 46, 64, 82]

    var body: some View {
        VStack(spacing: 0) {
            // Close button
            HStack {
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(DunbarTheme.textTertiary)
                }
                .accessibilityLabel("Close")
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)

            Spacer()

            // Rings graphic
            ZStack {
                ForEach(Array(DunbarRing.allCases.enumerated()), id: \.element.rawValue) { index, ring in
                    Circle()
                        .stroke(DunbarTheme.ringColor(for: ring).opacity(0.6), lineWidth: 1.5)
                        .frame(width: ringRadii[index] * 2, height: ringRadii[index] * 2)
                }

                Circle()
                    .fill(DunbarTheme.ringColor(for: .core).opacity(0.15))
                    .frame(width: 24, height: 24)
                    .overlay(
                        Circle()
                            .strokeBorder(DunbarTheme.ringColor(for: .core).opacity(0.4), lineWidth: 1)
                    )
            }
            .accessibilityHidden(true)
            .padding(.bottom, 28)

            // Headline
            Text("Unlock your full circle")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(DunbarTheme.textPrimary)
                .padding(.bottom, 6)

            Text("Go beyond your inner 5")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(DunbarTheme.textSecondary)
                .padding(.bottom, 28)

            // Feature list
            VStack(alignment: .leading, spacing: 14) {
                featureRow(icon: "person.3.fill", text: "Track up to 150 relationships")
                featureRow(icon: "arrow.triangle.2.circlepath", text: "Smart rebalancing suggestions")
                featureRow(icon: "bell.fill", text: "Nudges across all circles")
                featureRow(icon: "heart.fill", text: "Support independent development")
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 32)

            Spacer()

            // Purchase button
            Button {
                Task { await premiumManager.purchase() }
            } label: {
                if premiumManager.isLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                        .frame(maxWidth: .infinity)
                } else {
                    Text(purchaseButtonText)
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .frame(maxWidth: .infinity)
                }
            }
            .dunbarPrimaryButton()
            .disabled(premiumManager.isLoading || premiumManager.product == nil)
            .padding(.horizontal, 24)

            // Error message
            if let error = premiumManager.purchaseError {
                Text(error)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(DunbarTheme.red)
                    .padding(.top, 8)
            }

            // Restore purchases
            Button {
                Task { await premiumManager.restorePurchases() }
            } label: {
                Text("Restore Purchases")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(DunbarTheme.textSecondary)
            }
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .background(DunbarTheme.background)
        .onChange(of: premiumManager.isPremium) { _, isPremium in
            if isPremium { dismiss() }
        }
    }

    private var purchaseButtonText: String {
        if let product = premiumManager.product {
            return "Unlock Premium — \(product.displayPrice)"
        }
        return "Unlock Premium"
    }

    private func featureRow(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(DunbarTheme.ringColor(for: .core))
                .frame(width: 24)

            Text(text)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(DunbarTheme.textPrimary)
        }
        .accessibilityElement(children: .combine)
    }
}
