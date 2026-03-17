import UIKit
import Observation

@Observable
@MainActor
final class HapticFeedbackService {
    func impactLight() {
        guard AppSettings.hapticsEnabled else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    func impactMedium() {
        guard AppSettings.hapticsEnabled else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    func success() {
        guard AppSettings.hapticsEnabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}
