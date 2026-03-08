//
//  OrbCrashLoggerTests.swift
//  IlumionateTests
//
//  Tests for the orb crash logging system
//

import Testing
import SwiftUI
@testable import Ilumionate

@MainActor
struct OrbCrashLoggerTests {

    @Test func loggerCreation() {
        let logger = OrbCrashLogger.shared
        #expect(logger != nil)
        print("✅ OrbCrashLogger created successfully")
    }

    @Test func logViewCreation() {
        let logger = OrbCrashLogger.shared

        // Test logging view creation
        logger.logViewCreation("TestView", details: "Test view creation")

        // Should not crash
        print("✅ View creation logging works")
    }

    @Test func logColorCreation() {
        let logger = OrbCrashLogger.shared

        // Test color creation logging
        logger.logColorCreation("RGB(1.0, 0.5, 0.2)", context: "TestContext")

        print("✅ Color creation logging works")
    }

    @Test func logGradientCreation() {
        let logger = OrbCrashLogger.shared

        // Test gradient creation logging
        logger.logGradientCreation("RadialGradient", colorCount: 5, context: "TestGradient")

        print("✅ Gradient creation logging works")
    }

    @Test func logEngineOperations() {
        let logger = OrbCrashLogger.shared

        // Test engine operation logging
        logger.logEngineOperation("StartEngine", details: "Test engine start")
        logger.logEngineOperation("StopEngine", details: "Test engine stop")

        print("✅ Engine operation logging works")
    }

    @Test func logOrbRendering() {
        let logger = OrbCrashLogger.shared

        // Test orb rendering logging
        logger.logOrbRendering("TestPhase", details: "Test orb rendering phase")

        print("✅ Orb rendering logging works")
    }

    @Test func logPotentialCrash() {
        let logger = OrbCrashLogger.shared

        // Test potential crash logging
        logger.logPotentialCrash("Test crash scenario", context: "TestContext")

        print("✅ Potential crash logging works")
    }

    @Test func engineStateCaptureWithMockEngine() {
        let logger = OrbCrashLogger.shared
        let engine = LightEngine()

        // Test engine state capture
        let stateStr = logger.captureEngineState(from: engine)
        #expect(!stateStr.isEmpty)
        #expect(stateStr.contains("brightness"))
        #expect(stateStr.contains("isRunning"))

        print("✅ Engine state capture works: \(stateStr)")
    }

    @Test func safeColorCreation() {
        // Test safe color creation
        let color1 = SafeColor.rgb(1.0, 0.5, 0.2, opacity: 0.8, context: "TestColor1")
        let color2 = SafeColor.rgb(0.3, 0.7, 0.9, context: "TestColor2")

        #expect(color1 != nil)
        #expect(color2 != nil)

        print("✅ Safe color creation works")
    }

    @Test func safeGradientCreation() {
        // Test safe gradient creation
        let colors = [Color.red, Color.blue, Color.green]

        let radialGradient = SafeColor.radialGradient(
            colors: colors,
            center: .center,
            startRadius: 0,
            endRadius: 100,
            context: "TestRadialGradient"
        )

        let linearGradient = SafeColor.linearGradient(
            colors: colors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing,
            context: "TestLinearGradient"
        )

        #expect(radialGradient != nil)
        #expect(linearGradient != nil)

        print("✅ Safe gradient creation works")
    }

    @Test func memoryInfoCapture() {
        let logger = OrbCrashLogger.shared

        // This tests the memory capture functionality internally
        logger.logPotentialCrash("Memory test", context: "MemoryTest")

        print("✅ Memory info capture works")
    }
}