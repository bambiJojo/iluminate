import Foundation
import Testing
@testable import Ilumionate

@Suite("Console concern regressions")
struct ConsoleConcernRegressionTests {
    @Test("Hypnosis metadata repairs duplicate phase identities")
    func hypnosisMetadataRepairsDuplicatePhaseIDs() throws {
        let duplicateID = UUID()
        let phases = [
            PhaseSegment(
                id: duplicateID,
                phase: .induction,
                startTime: 0,
                endTime: 30,
                characteristics: "Induction",
                tranceDepthEstimate: 0.3
            ),
            PhaseSegment(
                id: duplicateID,
                phase: .deepening,
                startTime: 30,
                endTime: 60,
                characteristics: "Deepening",
                tranceDepthEstimate: 0.6
            )
        ]
        let metadata = HypnosisMetadata(
            phases: phases,
            inductionStyle: nil,
            estimatedTranceDeph: .medium,
            suggestionDensity: nil,
            languagePatterns: [],
            detectedTechniques: []
        )

        #expect(metadata.phases.map(\.id).count == Set(metadata.phases.map(\.id)).count)
        #expect(metadata.phases.first?.id == duplicateID)

        let legacyPayload = LegacyHypnosisMetadataPayload(
            phases: phases,
            inductionStyle: nil,
            estimatedTranceDeph: .medium,
            suggestionDensity: nil,
            languagePatterns: [],
            detectedTechniques: []
        )
        let decoded = try JSONDecoder().decode(
            HypnosisMetadata.self,
            from: JSONEncoder().encode(legacyPayload)
        )
        #expect(decoded.phases.map(\.id).count == Set(decoded.phases.map(\.id)).count)
    }

    @Test("Foreground analysis does not request a long UIKit background task")
    func foregroundAnalysisAvoidsBackgroundAssertion() {
        #expect(BackgroundTaskPolicy.shouldRegisterForLongAnalysis() == false)
    }

    @Test("Sustained elevated memory requests cleanup only once")
    func sustainedElevatedMemoryDoesNotThrashCleanup() {
        var policy = MemoryCleanupPolicy()

        #expect(policy.action(for: .warning) == .moderate)
        for _ in 0..<20 {
            #expect(policy.action(for: .warning) == nil)
        }
    }

    @Test("Memory cleanup rearms after pressure returns to normal")
    func cleanupRearmsAfterRecovery() {
        var policy = MemoryCleanupPolicy()

        #expect(policy.action(for: .warning) == .moderate)
        #expect(policy.action(for: .normal) == nil)
        #expect(policy.action(for: .warning) == .moderate)
    }

    @Test("Critical pressure escalates an existing warning")
    func criticalPressureEscalates() {
        var policy = MemoryCleanupPolicy()

        #expect(policy.action(for: .warning) == .moderate)
        #expect(policy.action(for: .critical) == .aggressive)
        #expect(policy.action(for: .critical) == nil)
    }
}

private struct LegacyHypnosisMetadataPayload: Encodable {
    let phases: [PhaseSegment]
    let inductionStyle: HypnosisMetadata.InductionStyle?
    let estimatedTranceDeph: HypnosisMetadata.TranceDeph
    let suggestionDensity: Double?
    let languagePatterns: [String]
    let detectedTechniques: [HypnoticTechnique]
}
