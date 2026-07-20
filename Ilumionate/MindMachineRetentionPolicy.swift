import Foundation

nonisolated enum MindMachineRetentionPolicy {
    static let meaningfulOpenEndedDuration: TimeInterval = 5 * 60

    static func isMeaningful(
        elapsed: TimeInterval,
        duration: TimeInterval
    ) -> Bool {
        if duration > 0 {
            return elapsed / duration >= 0.75
        }
        return elapsed >= meaningfulOpenEndedDuration
    }
}
