//
//  BackgroundAnalysisScheduler.swift
//  Ilumionate
//
//  Connects the durable analysis queue to iOS BackgroundTasks. Continued
//  processing keeps user-started analysis running when the app is no longer
//  frontmost; processing tasks provide deferred recovery after suspension.
//

import Foundation
import os

enum BackgroundAnalysisSystemTaskKind {
    case deferredProcessing
    case continuedProcessing
}

enum BackgroundAnalysisSchedulingSource {
    case explicitUserAction
    case foregroundRestoration

    var presentsContinuedProcessingUI: Bool {
        switch self {
        case .explicitUserAction: true
        case .foregroundRestoration: false
        }
    }
}

/// Serializes completion across the normal and expiration paths. BackgroundTasks
/// only expects a task to be completed once, but expiration races the operation's
/// normal unwind.
@MainActor
final class BackgroundAnalysisTaskFinisher {
    private let kind: BackgroundAnalysisSystemTaskKind
    private let completeSystemTask: (Bool) -> Void
    private(set) var isFinished = false

    init(
        kind: BackgroundAnalysisSystemTaskKind,
        completeSystemTask: @escaping (Bool) -> Void
    ) {
        self.kind = kind
        self.completeSystemTask = completeSystemTask
    }

    @discardableResult
    func finish(workSucceeded: Bool) -> Bool {
        guard isFinished == false else { return false }
        isFinished = true
        completeSystemTask(systemSuccess(workSucceeded: workSucceeded))
        return true
    }

    private func systemSuccess(workSucceeded: Bool) -> Bool {
        switch kind {
        case .deferredProcessing:
            // BGProcessingTask can use failure to inform future scheduling.
            return workSucceeded
        case .continuedProcessing:
            // A continued task is a one-shot system presentation; false asks
            // iOS to preserve a visible failure, not to retry the analysis.
            // Durable checkpoints and deferred processing own recovery instead.
            return true
        }
    }
}

#if os(iOS)
import BackgroundTasks
import UIKit

@MainActor
final class BackgroundAnalysisScheduler {
    static let shared = BackgroundAnalysisScheduler()

    static let identifierRoot = "\(Bundle.main.bundleIdentifier ?? "com.byronquine.lumenSync").analysis"
    static let processingIdentifier = "\(identifierRoot).processing"
    static let continuedIdentifierPrefix = "\(identifierRoot).continued."
    static let continuedIdentifierPattern = "\(continuedIdentifierPrefix)*"
    #if !targetEnvironment(macCatalyst)
    @available(iOS 26.0, *)
    static var continuedSubmissionStrategy: BGContinuedProcessingTaskRequest.SubmissionStrategy { .fail }
    #endif

    private var hasActiveContinuedRequest = false
    private var continuedRequestIdentifier: String?
    private var didAttemptProcessingRegistration = false
    private var isProcessingHandlerRegistered = false

    private init() {}

    func register() {
        guard !didAttemptProcessingRegistration else { return }
        didAttemptProcessingRegistration = true

        isProcessingHandlerRegistered = BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.processingIdentifier,
            using: .main
        ) { [weak self] task in
            guard let processingTask = task as? BGProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            self?.handle(processingTask)
        }

        if !isProcessingHandlerRegistered {
            Log.analysis.error("Deferred background analysis handler could not be registered")
        }
    }

    /// Schedule both the immediate iOS 26 continuation and a deferred recovery
    /// request. The continued request is only legal while the app is foregrounded.
    func schedule(
        for audioFiles: [AudioFile],
        source: BackgroundAnalysisSchedulingSource = .explicitUserAction
    ) {
        scheduleDeferredProcessing()

        #if !targetEnvironment(macCatalyst)
        if #available(iOS 26.0, *) {
            guard source.presentsContinuedProcessingUI else { return }
            guard UIApplication.shared.applicationState == .active else { return }
            guard !hasActiveContinuedRequest else { return }

            let identifier = Self.makeContinuedIdentifier()
            guard registerContinuedHandler(for: identifier) else {
                // Never submit an unregistered request. BackgroundTasks raises an
                // Objective-C exception for this programmer error, so it cannot be
                // recovered from with Swift's do/catch.
                Log.analysis.error("Continued background analysis handler could not be registered")
                return
            }

            let count = max(audioFiles.count, 1)
            let request = BGContinuedProcessingTaskRequest(
                identifier: identifier,
                title: "Analyzing audio",
                subtitle: count == 1 ? "Preparing your light session" : "Processing \(count) audio files"
            )
            request.strategy = Self.continuedSubmissionStrategy

            do {
                try BGTaskScheduler.shared.submit(request)
                hasActiveContinuedRequest = true
                continuedRequestIdentifier = identifier
                Log.analysis.info("Scheduled continued background analysis")
            } catch {
                // Deferred processing remains scheduled when immediate continuation
                // is unavailable because of current system load or user settings.
                Log.analysis.info("Continued background analysis unavailable: \(error.localizedDescription)")
            }
        }
        #endif
    }

    func scheduleDeferredProcessing() {
        guard isProcessingHandlerRegistered else {
            Log.analysis.error("Deferred background analysis skipped because its handler is unavailable")
            return
        }

        let request = BGProcessingTaskRequest(identifier: Self.processingIdentifier)
        request.requiresExternalPower = false
        request.requiresNetworkConnectivity = false

        do {
            try BGTaskScheduler.shared.submit(request)
            Log.analysis.info("Scheduled deferred background analysis")
        } catch {
            Log.analysis.error("Could not schedule deferred background analysis: \(error.localizedDescription)")
        }
    }

    func cancelDeferredProcessing() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.processingIdentifier)
    }

    func analysisFinished() async {
        cancelDeferredProcessing()
        if let continuedRequestIdentifier {
            BGTaskScheduler.shared.cancel(
                taskRequestWithIdentifier: continuedRequestIdentifier
            )
        }
        continuedRequestIdentifier = nil
        hasActiveContinuedRequest = false
        await cancelPendingContinuedRequests()
    }

    func resumeWhenForegrounded() {
        Task { @MainActor in
            // Concrete identifiers are process-local. After a force quit or
            // relaunch, discover and remove requests whose IDs were lost.
            if hasActiveContinuedRequest == false {
                await cancelPendingContinuedRequests()
            }

            let pending = await AnalysisProgressStore.shared.allPending()
            guard !pending.isEmpty else {
                await analysisFinished()
                return
            }
            schedule(
                for: pending.map(\.audioFile),
                source: .foregroundRestoration
            )
            _ = await AnalysisStateManager.shared.resumeInterruptedAnalyses(priority: .utility)
        }
    }

    private func handle(_ task: BGProcessingTask) {
        runAnalysis(for: task, kind: .deferredProcessing)
    }

    #if !targetEnvironment(macCatalyst)
    @available(iOS 26.0, *)
    private func handle(_ task: BGContinuedProcessingTask) {
        hasActiveContinuedRequest = true
        continuedRequestIdentifier = task.identifier
        runAnalysis(
            for: task,
            kind: .continuedProcessing,
            progress: task.progress,
            updateTitle: task.updateTitle
        )
    }
    #endif

    static func makeContinuedIdentifier(id: UUID = UUID()) -> String {
        continuedIdentifierPrefix + id.uuidString
    }

    static func continuedRequestIdentifiers(from identifiers: [String]) -> [String] {
        identifiers.filter { $0.hasPrefix(continuedIdentifierPrefix) }
    }

    private func cancelPendingContinuedRequests() async {
        let identifiers = await withCheckedContinuation { continuation in
            BGTaskScheduler.shared.getPendingTaskRequests { requests in
                continuation.resume(returning: requests.map(\.identifier))
            }
        }
        let continuedIdentifiers = Self.continuedRequestIdentifiers(from: identifiers)

        for identifier in continuedIdentifiers {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)
        }

        if continuedIdentifiers.isEmpty == false {
            Log.analysis.info(
                "Cancelled \(continuedIdentifiers.count) stale continued analysis request(s)"
            )
        }
    }

    /// Continued-processing handlers must be registered for each concrete
    /// identifier. The wildcard belongs only in Info.plist; registering the
    /// wildcard itself is rejected by BackgroundTasks on iOS 26.
    @discardableResult
    @available(iOS 26.0, *)
    func registerContinuedHandler(for identifier: String) -> Bool {
        guard identifier.hasPrefix(Self.continuedIdentifierPrefix),
              !identifier.contains("*") else {
            return false
        }

        #if targetEnvironment(macCatalyst)
        return false
        #else
        return BGTaskScheduler.shared.register(
            forTaskWithIdentifier: identifier,
            using: .main
        ) { [weak self] task in
            guard let continuedTask = task as? BGContinuedProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            self?.handle(continuedTask)
        }
        #endif
    }

    private func runAnalysis(
        for systemTask: BGTask,
        kind: BackgroundAnalysisSystemTaskKind,
        progress: Progress? = nil,
        updateTitle: ((String, String) -> Void)? = nil
    ) {
        let finisher = BackgroundAnalysisTaskFinisher(kind: kind) { success in
            systemTask.setTaskCompleted(success: success)
        }
        let operation = Task { @MainActor [weak self] in
            let initialPendingCount = max(
                await AnalysisProgressStore.shared.allPending().count,
                1
            )
            let reporter = Task { @MainActor in
                guard let progress else { return }
                progress.totalUnitCount = 1_000
                var greatestReportedFraction = 0.0

                while !Task.isCancelled {
                    let remainingCount = await AnalysisProgressStore.shared.allPending().count
                    let currentFraction = AnalysisStateManager.shared.currentAnalysis?.progress ?? 0
                    let completedCount = max(initialPendingCount - remainingCount, 0)
                    let overallFraction = min(
                        (Double(completedCount) + currentFraction) / Double(initialPendingCount),
                        0.999
                    )
                    greatestReportedFraction = max(greatestReportedFraction, overallFraction)
                    progress.completedUnitCount = Int64(greatestReportedFraction * 1_000)

                    if let filename = AnalysisStateManager.shared.currentAnalysis?.audioFile.filename {
                        updateTitle?(
                            "Analyzing audio",
                            filename
                        )
                    }
                    try? await Task.sleep(for: .milliseconds(500))
                }
            }

            let succeeded = await AnalysisStateManager.shared
                .resumeInterruptedAnalyses(priority: .utility)
            reporter.cancel()

            if let progress, succeeded {
                progress.completedUnitCount = progress.totalUnitCount
            }
            guard finisher.finish(workSucceeded: succeeded) else { return }

            if succeeded {
                await self?.analysisFinished()
            } else {
                self?.continuedRequestIdentifier = nil
                self?.hasActiveContinuedRequest = false
                await self?.cancelPendingContinuedRequests()
                self?.scheduleDeferredProcessing()
            }
        }

        systemTask.expirationHandler = { [weak self] in
            operation.cancel()
            Task { @MainActor in
                guard finisher.finish(workSucceeded: false) else { return }
                AnalysisStateManager.shared.expireBackgroundProcessing()
                self?.continuedRequestIdentifier = nil
                self?.hasActiveContinuedRequest = false
                self?.scheduleDeferredProcessing()
            }
        }
    }
}

#else

/// Native macOS keeps analysis in the app process. The durable progress store
/// still restores interrupted work when the app becomes active again.
@MainActor
final class BackgroundAnalysisScheduler {
    static let shared = BackgroundAnalysisScheduler()

    static let identifierRoot = "\(Bundle.main.bundleIdentifier ?? "com.byronquine.lumenSync").analysis"
    static let processingIdentifier = "\(identifierRoot).processing"
    static let continuedIdentifierPrefix = "\(identifierRoot).continued."
    static let continuedIdentifierPattern = "\(continuedIdentifierPrefix)*"

    private init() {}

    func register() {}

    func schedule(
        for audioFiles: [AudioFile],
        source: BackgroundAnalysisSchedulingSource = .explicitUserAction
    ) {
        _ = audioFiles
        _ = source
    }

    func scheduleDeferredProcessing() {}
    func cancelDeferredProcessing() {}
    func analysisFinished() async {}

    func resumeWhenForegrounded() {
        Task { @MainActor in
            let pending = await AnalysisProgressStore.shared.allPending()
            guard !pending.isEmpty else { return }
            _ = await AnalysisStateManager.shared.resumeInterruptedAnalyses(priority: .utility)
        }
    }

    static func makeContinuedIdentifier(id: UUID = UUID()) -> String {
        continuedIdentifierPrefix + id.uuidString
    }

    static func continuedRequestIdentifiers(from identifiers: [String]) -> [String] {
        identifiers.filter { $0.hasPrefix(continuedIdentifierPrefix) }
    }

    @discardableResult
    func registerContinuedHandler(for identifier: String) -> Bool {
        _ = identifier
        return false
    }
}

#endif
