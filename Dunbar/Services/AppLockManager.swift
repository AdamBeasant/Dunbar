import Foundation
import LocalAuthentication
import Observation

@Observable
@MainActor
final class AppLockManager {
    var isLocked: Bool = false
    var isUnlocking: Bool = false
    var biometricAvailable: Bool = false
    var availabilityText: String = "Face ID unavailable"
    private var suppressAutoUnlockUntilBackground: Bool = false

    var isLockEnabled: Bool {
        AppSettings.faceIDEnabled
    }

    init() {
        biometricAvailable = refreshBiometricAvailability()
        if !isLockEnabled {
            isLocked = false
        }
    }

    @discardableResult
    func refreshBiometricAvailability() -> Bool {
        let context = LAContext()
        var error: NSError?
        let canEvaluate = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        biometricAvailable = canEvaluate

        if canEvaluate {
            switch context.biometryType {
            case .faceID:
                availabilityText = "Face ID available"
            case .touchID:
                availabilityText = "Touch ID available"
            default:
                availabilityText = "Biometrics available"
            }
        } else {
            availabilityText = "Face ID unavailable"
        }

        return canEvaluate
    }

    func lockIfNeeded() {
        guard isLockEnabled else {
            isLocked = false
            return
        }
        isLocked = true
        suppressAutoUnlockUntilBackground = false
    }

    func unlockIfNeeded(force: Bool = false) async {
        guard force || isLockEnabled else {
            isLocked = false
            return
        }
        guard !isUnlocking else { return }
        guard force || isLocked else { return }
        guard force || !suppressAutoUnlockUntilBackground else { return }

        let context = LAContext()
        var policyError: NSError?
        let canAuthenticate = context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &policyError)
        biometricAvailable = refreshBiometricAvailability()

        guard canAuthenticate else {
            isLocked = true
            availabilityText = "Authentication unavailable on this device"
            return
        }

        isUnlocking = true
        defer { isUnlocking = false }

        context.localizedCancelTitle = "Cancel"

        do {
            let reason = "Unlock Dunbar"
            let success = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
            isLocked = !success
            if success {
                suppressAutoUnlockUntilBackground = false
            }
        } catch {
            isLocked = true
            if let laError = error as? LAError {
                switch laError.code {
                case .userCancel, .appCancel, .systemCancel, .notInteractive:
                    suppressAutoUnlockUntilBackground = true
                    availabilityText = "Unlock canceled"
                default:
                    break
                }
            }
        }
    }
}
