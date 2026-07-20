import Testing
@testable import Ilumionate

struct AnalysisStageFeedbackTests {
    @Test
    func exposesStableStepNames() {
        #expect(AnalysisStageFeedback.stageSummary(.transcribing) == "Transcribing · step 1 of 4")
        #expect(AnalysisStageFeedback.stageSummary(.generatingSession) == "Building Light Sync · step 3 of 4")
    }

    @Test
    func estimatesRemainingTimeOnlyAfterUsefulProgress() {
        #expect(AnalysisStageFeedback.estimatedRemainingText(progress: 0.01, elapsed: 60) == nil)
        #expect(AnalysisStageFeedback.estimatedRemainingText(progress: 0.5, elapsed: 120) == "About 2 minutes remaining")
    }
}
