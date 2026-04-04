//
//  SafeAuraBackground.swift
//  Ilumionate
//
//  Memory-safe version of AuraBackground for crash comparison
//

import SwiftUI

/// Safe version of AuraBackground with reduced memory footprint
struct SafeAuraBackground: View {
    var body: some View {
        ZStack {
            // Base void color - same as original
            Color.black
                .ignoresSafeArea()

            // SAFE VERSION: Simplified gradient with fewer colors and smaller radius
            RadialGradient(
                colors: [
                    Color.purple.opacity(0.15),
                    Color.blue.opacity(0.1),
                    Color.clear
                ],
                center: .center,
                startRadius: 50,
                endRadius: 300  // ← REDUCED from 800 to 300
            )
            .ignoresSafeArea()
            // NO ANIMATION - remove the expensive 60-second animation

            // SAFE VERSION: Single floating blob instead of 4
            Circle()
                .fill(Color.purple.opacity(0.2))
                .frame(width: 200, height: 200)
                .blur(radius: 50)  // ← REDUCED blur from 90 to 50
                .position(x: 150, y: 200)
            // NO ANIMATION - static positioning

            // Simple vignette - same as original but smaller
            RadialGradient(
                colors: [
                    .clear,
                    Color.black.opacity(0.4)
                ],
                center: .center,
                startRadius: 100,
                endRadius: 400  // ← REDUCED from 600 to 400
            )
            .ignoresSafeArea()
        }
        .onAppear {
            print("🟢 SafeAuraBackground appeared successfully")
            OrbCrashLogger.shared.logOrbRendering("SafeAuraBackground", details: "Safe version rendered")
        }
    }
}

/// Ultra-minimal orb for testing
struct MinimalOrbBackground: View {
    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            RadialGradient(
                colors: [Color.purple.opacity(0.3), .clear],
                center: .center,
                startRadius: 20,
                endRadius: 100
            )
            .ignoresSafeArea()
        }
        .onAppear {
            print("🟢 MinimalOrbBackground appeared successfully")
        }
    }
}

/// Test the exact problematic components one by one
struct MemoryLeakTest: View {
    @State private var testStage = 0
    @State private var memoryAtStart: Double = 0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack {
                Text("Memory Leak Test")
                    .foregroundStyle(.white)
                    .font(.title)

                Text("Stage: \(testStage)")
                    .foregroundStyle(.green)

                Button("Next Stage") {
                    testStage += 1
                }
                .foregroundStyle(.white)
                .padding()
                .background(Color.blue)
                .cornerRadius(8)

                // Progressive component testing
                Group {
                    if testStage >= 1 {
                        // Stage 1: Large radius gradient (SUSPECT)
                        RadialGradient(
                            colors: [Color.purple.opacity(0.1), .clear],
                            center: .center,
                            startRadius: 50,
                            endRadius: 800  // ← This might be the problem
                        )
                        .frame(width: 100, height: 100)  // Constrain size
                    }

                    if testStage >= 2 {
                        // Stage 2: Multiple color gradient (SUSPECT)
                        RadialGradient(
                            colors: [
                                Color.purple.opacity(0.22),
                                Color.blue.opacity(0.16),
                                Color.indigo.opacity(0.2),
                                Color.purple.opacity(0.15),
                                Color.purple.opacity(0.12),
                                Color.black
                            ],
                            center: .center,
                            startRadius: 50,
                            endRadius: 200  // Smaller radius
                        )
                        .frame(width: 100, height: 100)
                    }

                    if testStage >= 3 {
                        // Stage 3: Large blur radius (SUSPECT)
                        Circle()
                            .fill(Color.purple.opacity(0.3))
                            .frame(width: 300, height: 300)
                            .blur(radius: 90)  // ← This might be the problem
                    }

                    if testStage >= 4 {
                        // Stage 4: Long animation (SUSPECT)
                        Rectangle()
                            .fill(Color.blue.opacity(0.1))
                            .frame(width: 100, height: 100)
                            .hueRotation(.degrees(testStage % 2 == 0 ? 0 : 180))
                            .animation(
                                .easeInOut(duration: 60)  // ← Very long animation
                                .repeatForever(autoreverses: true),
                                value: testStage
                            )
                    }
                }
            }
        }
        .onAppear {
            memoryAtStart = getCurrentMemoryUsage()
            print("🔍 MemoryLeakTest started with \(memoryAtStart)MB")
        }
        .onChange(of: testStage) { _, newStage in
            let currentMemory = getCurrentMemoryUsage()
            let memoryIncrease = currentMemory - memoryAtStart
            print("📊 Stage \(newStage): Memory = \(currentMemory)MB (+\(memoryIncrease)MB)")

            if memoryIncrease > 50 {
                print("🚨 MEMORY LEAK DETECTED: +\(memoryIncrease)MB at stage \(newStage)")
                OrbCrashLogger.shared.logPotentialCrash("Memory leak at stage \(newStage)", context: "MemoryLeakTest +\(memoryIncrease)MB")
            }
        }
    }

    private func getCurrentMemoryUsage() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4

        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }

        if result == KERN_SUCCESS {
            return Double(info.resident_size) / 1024.0 / 1024.0
        } else {
            return 0.0
        }
    }
}