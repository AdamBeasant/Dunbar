import StoreKit
import Observation

@Observable
@MainActor
final class PremiumManager {
    var isPremium = false
    var product: Product?
    var isLoading = false
    var purchaseError: String?

    private var transactionListener: Task<Void, Never>?

    init() {
        transactionListener = listenForTransactions()
        Task {
            await checkEntitlement()
            await loadProduct()
        }
    }

    deinit {
        MainActor.assumeIsolated {
            transactionListener?.cancel()
        }
    }

    // MARK: - Load Product

    func loadProduct() async {
        do {
            let products = try await Product.products(for: [Premium.productID])
            product = products.first
        } catch {
            print("[Dunbar] Failed to load products: \(error)")
        }
    }

    // MARK: - Purchase

    func purchase() async {
        guard let product else {
            purchaseError = "Product not available"
            return
        }

        isLoading = true
        purchaseError = nil

        do {
            let result = try await product.purchase()

            switch result {
            case .success(let verification):
                let transaction = try Self.checkVerified(verification)
                isPremium = true
                await transaction.finish()

            case .userCancelled:
                break

            case .pending:
                purchaseError = "Purchase is pending approval"

            @unknown default:
                break
            }
        } catch {
            purchaseError = "Purchase failed: \(error.localizedDescription)"
            print("[Dunbar] Purchase error: \(error)")
        }

        isLoading = false
    }

    // MARK: - Restore Purchases

    func restorePurchases() async {
        isLoading = true
        purchaseError = nil

        var foundPremium = false
        for await result in Transaction.currentEntitlements {
            if let transaction = try? Self.checkVerified(result),
               transaction.productID == Premium.productID {
                foundPremium = true
            }
        }

        isPremium = foundPremium
        isLoading = false

        if !foundPremium {
            purchaseError = "No purchases to restore"
        }
    }

    // MARK: - Check Entitlement

    func checkEntitlement() async {
        if let result = await Transaction.currentEntitlement(for: Premium.productID) {
            if let _ = try? Self.checkVerified(result) {
                isPremium = true
                return
            }
        }
        isPremium = false
    }

    // MARK: - Transaction Listener

    private func listenForTransactions() -> Task<Void, Never> {
        Task.detached { [weak self] in
            for await result in Transaction.updates {
                if let transaction = try? PremiumManager.checkVerified(result),
                   transaction.productID == Premium.productID {
                    await MainActor.run {
                        self?.isPremium = true
                    }
                    await transaction.finish()
                }
            }
        }
    }

    // MARK: - Verification

    nonisolated private static func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, let error):
            throw error
        case .verified(let value):
            return value
        }
    }
}
