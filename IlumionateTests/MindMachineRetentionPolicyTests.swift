import Foundation
import Testing
@testable import Ilumionate

struct MindMachineRetentionPolicyTests {
    @Test(arguments: [0.74, 0.75, 1.0])
    func finiteSessionsUseMeaningfulCompletionThreshold(_ fraction: Double) {
        #expect(
            MindMachineRetentionPolicy.isMeaningful(elapsed: 600 * fraction, duration: 600)
                == (fraction >= 0.75)
        )
    }

    @Test
    func openEndedSessionsBecomeMeaningfulAtFiveMinutes() {
        #expect(MindMachineRetentionPolicy.isMeaningful(elapsed: 299, duration: 0) == false)
        #expect(MindMachineRetentionPolicy.isMeaningful(elapsed: 300, duration: 0))
    }
}
