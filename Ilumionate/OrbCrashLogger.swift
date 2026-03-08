//
//  OrbCrashLogger.swift
//  Ilumionate
//
//  Internal crash diagnostic logging system
//

import Foundation
import SwiftUI
import os.log

/// Comprehensive logging system for tracking orb rendering crashes
@MainActor
final class OrbCrashLogger {
    static let shared = OrbCrashLogger()

    private let logger = Logger(subsystem: "com.ilumionate.crashdiag", category: "orb")
    private var logEntries: [LogEntry] = []
    private var crashDetectionTimer: Timer?

    struct LogEntry {
        let timestamp: Date
        let phase: String
        let component: String
        let details: String
        let engineState: String?
        let memoryInfo: String?
    }

    private init() {
        startCrashDetection()
    }

    // MARK: - Public Logging Methods

    func logViewCreation(_ viewName: String, details: String = "") {
        let engineState = captureEngineState()
        let memoryInfo = captureMemoryInfo()

        let entry = LogEntry(
            timestamp: Date(),
            phase: "VIEW_CREATION",
            component: viewName,
            details: details,
            engineState: engineState,
            memoryInfo: memoryInfo
        )

        addLogEntry(entry)
        logger.info("🏗️ VIEW_CREATION: \(viewName) - \(details)")
    }

    func logViewAppear(_ viewName: String, details: String = "") {
        let engineState = captureEngineState()
        let memoryInfo = captureMemoryInfo()

        let entry = LogEntry(
            timestamp: Date(),
            phase: "VIEW_APPEAR",
            component: viewName,
            details: details,
            engineState: engineState,
            memoryInfo: memoryInfo
        )

        addLogEntry(entry)
        logger.info("👀 VIEW_APPEAR: \(viewName) - \(details)")
    }

    func logColorCreation(_ colorInfo: String, context: String) {
        let entry = LogEntry(
            timestamp: Date(),
            phase: "COLOR_CREATION",
            component: "Color",
            details: "\(colorInfo) in \(context)",
            engineState: nil,
            memoryInfo: captureMemoryInfo()
        )

        addLogEntry(entry)
        logger.debug("🎨 COLOR_CREATION: \(colorInfo) in \(context)")
    }

    func logGradientCreation(_ gradientType: String, colorCount: Int, context: String) {
        let entry = LogEntry(
            timestamp: Date(),
            phase: "GRADIENT_CREATION",
            component: gradientType,
            details: "\(colorCount) colors in \(context)",
            engineState: nil,
            memoryInfo: captureMemoryInfo()
        )

        addLogEntry(entry)
        logger.debug("🌈 GRADIENT_CREATION: \(gradientType) with \(colorCount) colors in \(context)")
    }

    func logEngineOperation(_ operation: String, details: String = "") {
        let engineState = captureEngineState()

        let entry = LogEntry(
            timestamp: Date(),
            phase: "ENGINE_OPERATION",
            component: "LightEngine",
            details: "\(operation) - \(details)",
            engineState: engineState,
            memoryInfo: captureMemoryInfo()
        )

        addLogEntry(entry)
        logger.info("⚡️ ENGINE_OPERATION: \(operation) - \(details)")
    }

    func logOrbRendering(_ phase: String, details: String) {
        let engineState = captureEngineState()
        let memoryInfo = captureMemoryInfo()

        let entry = LogEntry(
            timestamp: Date(),
            phase: "ORB_RENDERING",
            component: phase,
            details: details,
            engineState: engineState,
            memoryInfo: memoryInfo
        )

        addLogEntry(entry)
        logger.critical("🔮 ORB_RENDERING: \(phase) - \(details)")
    }

    func logPotentialCrash(_ reason: String, context: String) {
        let engineState = captureEngineState()
        let memoryInfo = captureMemoryInfo()

        let entry = LogEntry(
            timestamp: Date(),
            phase: "POTENTIAL_CRASH",
            component: context,
            details: reason,
            engineState: engineState,
            memoryInfo: memoryInfo
        )

        addLogEntry(entry)
        logger.fault("💥 POTENTIAL_CRASH: \(reason) in \(context)")

        // Dump recent logs immediately
        dumpRecentLogs()
    }

    // MARK: - State Capture

    private func captureEngineState() -> String {
        // This will be populated when we have access to the engine
        return "brightness: unknown, isRunning: unknown"
    }

    func captureEngineState(from engine: LightEngine) -> String {
        return "brightness: \(String(format: "%.3f", engine.brightness)), left: \(String(format: "%.3f", engine.brightnessLeft)), right: \(String(format: "%.3f", engine.brightnessRight)), isRunning: \(engine.isRunning), frequency: \(String(format: "%.1f", engine.currentFrequency))Hz"
    }

    private func captureMemoryInfo() -> String {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4

        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }

        if result == KERN_SUCCESS {
            let memoryMB = Double(info.resident_size) / 1024.0 / 1024.0
            return String(format: "%.1fMB", memoryMB)
        } else {
            return "unknown"
        }
    }

    // MARK: - Log Management

    private func addLogEntry(_ entry: LogEntry) {
        logEntries.append(entry)

        // Keep only last 100 entries to prevent memory bloat
        if logEntries.count > 100 {
            logEntries.removeFirst(logEntries.count - 100)
        }
    }

    func dumpRecentLogs() {
        let separator = String(repeating: "=", count: 80)
        print("\n" + separator)
        print("🚨 CRASH DIAGNOSTIC LOG DUMP")
        print(separator)

        let recentEntries = Array(logEntries.suffix(20))

        for entry in recentEntries {
            let timeStr = DateFormatter.crashLog.string(from: entry.timestamp)
            print("[\(timeStr)] \(entry.phase):\(entry.component)")
            print("  Details: \(entry.details)")
            if let engineState = entry.engineState {
                print("  Engine: \(engineState)")
            }
            if let memoryInfo = entry.memoryInfo {
                print("  Memory: \(memoryInfo)")
            }
            print("")
        }

        print(separator)
        print("🚨 END CRASH DIAGNOSTIC LOG DUMP")
        print(separator + "\n")
    }

    // MARK: - Crash Detection

    private func startCrashDetection() {
        // Monitor for UI hangs that might indicate a crash
        crashDetectionTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                self.checkForSuspiciousActivity()
            }
        }
    }

    private func checkForSuspiciousActivity() {
        let memoryInfo = captureMemoryInfo()

        // Extract memory value for checking
        if let memoryStr = memoryInfo.components(separatedBy: "MB").first,
           let memoryMB = Double(memoryStr) {

            // Log if memory usage is very high (might indicate leak before crash)
            if memoryMB > 500 {
                logPotentialCrash("High memory usage: \(memoryInfo)", context: "MemoryMonitor")
            }
        }
    }
}

// MARK: - Convenience Extensions

extension DateFormatter {
    static let crashLog: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()
}

// MARK: - SwiftUI Integration

extension View {
    func logViewCreation(_ viewName: String, details: String = "") -> some View {
        OrbCrashLogger.shared.logViewCreation(viewName, details: details)
        return self
    }

    func logViewAppear(_ viewName: String, details: String = "") -> some View {
        self.onAppear {
            OrbCrashLogger.shared.logViewAppear(viewName, details: details)
        }
    }
}