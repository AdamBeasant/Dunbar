import UIKit
import Observation

@Observable
@MainActor
final class HapticFeedbackService {
    func impactLight() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    func impactMedium() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}
