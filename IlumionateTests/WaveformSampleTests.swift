import Testing
import Foundation
@testable import Ilumionate

struct WaveformSampleTests {
    @Test("Sine starts at mid, peaks at quarter")
    func sine() {
        #expect(abs(WaveformSample.value(.sine, phase: 0.0) - 0.5) < 0.001)
        #expect(abs(WaveformSample.value(.sine, phase: 0.25) - 1.0) < 0.001)
        #expect(abs(WaveformSample.value(.sine, phase: 0.75) - 0.0) < 0.001)
    }

    @Test("Square is high in first half, low in second")
    func square() {
        #expect(WaveformSample.value(.square, phase: 0.1) == 1.0)
        #expect(WaveformSample.value(.square, phase: 0.6) == 0.0)
    }

    @Test("Triangle peaks at the midpoint")
    func triangle() {
        #expect(abs(WaveformSample.value(.triangle, phase: 0.0) - 0.0) < 0.001)
        #expect(abs(WaveformSample.value(.triangle, phase: 0.5) - 1.0) < 0.001)
        #expect(abs(WaveformSample.value(.triangle, phase: 1.0) - 0.0) < 0.001)
    }

    @Test("Sawtooth ramps linearly 0→1")
    func sawtooth() {
        #expect(abs(WaveformSample.value(.sawtooth, phase: 0.0) - 0.0) < 0.001)
        #expect(abs(WaveformSample.value(.sawtooth, phase: 0.5) - 0.5) < 0.001)
    }

    @Test("Pulse is a brief spike near the start")
    func pulse() {
        #expect(WaveformSample.value(.pulse, phase: 0.02) == 1.0)
        #expect(WaveformSample.value(.pulse, phase: 0.5) == 0.0)
    }

    @Test("All samples stay within 0...1 across the cycle")
    func bounded() {
        for pattern in MindMachineModel.LightPattern.allCases {
            for i in 0...20 {
                let v = WaveformSample.value(pattern, phase: Double(i) / 20.0)
                #expect(v >= 0.0 && v <= 1.0)
            }
        }
    }
}
