import Foundation

nonisolated enum AnalysisStageFeedback {
    static func stageSummary(_ stage: AnalysisStage) -> String {
        switch stage {
        case .starting: "Preparing · step 1 of 4"
        case .transcribing: "Transcribing · step 1 of 4"
        case .analyzing: "Understanding content · step 2 of 4"
        case .generatingSession: "Building Light Sync · step 3 of 4"
        case .complete: "Complete"
        case .failed: "Needs attention"
        }
    }

    static func estimatedRemainingText(
        progress: Double,
        elapsed: TimeInterval
    ) -> String? {
        guard progress >= 0.03, progress < 0.99, elapsed >= 5 else { return nil }
        let estimate = min(max(elapsed * (1 - progress) / progress, 15), 3_600)
        let minutes = max(1, Int((estimate / 60).rounded(.up)))
        return minutes == 1 ? "About 1 minute remaining" : "About \(minutes) minutes remaining"
    }
}
