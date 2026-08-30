//
//  GuardrailFeedbackRecorder.swift
//  Ilumionate
//
//  Captures a Feedback Assistant attachment when the on-device model refuses
//  to analyse a file, so a refusal can be reported with the prompt that caused
//  it rather than from memory.
//
//  Apple exposes no way to relax `SystemLanguageModel`'s guardrails — there is
//  no safety-level parameter and no entitlement. A refusal is therefore
//  permanent for that content, which is why `AIGenerationDiagnosis.guardrail`
//  is classified non-transient and never retried. This recorder exists to
//  answer *which* files trip it and *what* was in the prompt, which is the only
//  part still actionable locally.
//

import Foundation
import FoundationModels
import os

nonisolated enum GuardrailFeedbackRecorder {

    /// Kept in private storage, not the Documents root.
    ///
    /// This used to sit in Documents so the attachment could be dragged from
    /// Finder straight into a feedbackassistant.apple.com report. That is a real
    /// cost of moving it, and nothing replaces that path yet — but the
    /// attachment embeds the refused prompt, which carries transcript excerpts,
    /// and `UIFileSharingEnabled` exposes the Documents root to any USB-trusted
    /// host. Retrieving one now needs an in-app share action. See ERRORS.md
    /// ERR-024.
    ///
    /// `static let` is lazy, so the migration runs once on first use.
    static let directory = PrivateStorageMigration.migrateItemIfNeeded(
        from: URL.documentsDirectory
            .appending(path: "Guardrail Feedback", directoryHint: .isDirectory),
        to: AppStoragePaths.guardrailFeedback
    )

    /// Asks the failed session for its attachment and stores it.
    ///
    /// Called on the session that was refused: `logFeedbackAttachment` captures
    /// that session's transcript, so recording against a fresh session would
    /// produce an attachment describing a prompt that never failed.
    @discardableResult
    @available(iOS 26.0, macOS 26.0, *)
    static func record(
        session: LanguageModelSession,
        filename: String,
        explanation: String,
        in directory: URL = GuardrailFeedbackRecorder.directory,
        now: Date = Date()
    ) -> URL? {
        let attachment = session.logFeedbackAttachment(
            sentiment: .negative,
            issues: [
                LanguageModelFeedback.Issue(
                    category: .triggeredGuardrailUnexpectedly,
                    explanation: explanation
                )
            ]
        )
        return write(attachment, filename: filename, in: directory, now: now)
    }

    /// Separated from `record` so the naming and write behaviour can be tested
    /// without standing up a `LanguageModelSession`.
    @discardableResult
    static func write(
        _ attachment: Data,
        filename: String,
        in directory: URL = GuardrailFeedbackRecorder.directory,
        now: Date = Date()
    ) -> URL? {
        let destination = directory.appending(path: attachmentName(for: filename, at: now))
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            try attachment.write(to: destination, options: .atomic)
            Log.analysis.info("🧾 Guardrail feedback written: \(destination.lastPathComponent)")
            return destination
        } catch {
            // Diagnostics must never take down the analysis that produced them.
            Log.analysis.error("Guardrail feedback could not be written: \(error.localizedDescription)")
            return nil
        }
    }

    /// Keeps the audio filename legible in Finder while staying unique per
    /// attempt, so repeated refusals of one file are visible as repeats rather
    /// than overwriting each other.
    static func attachmentName(for filename: String, at date: Date) -> String {
        let stem = filename
            .replacing(#/\.[A-Za-z0-9]{1,5}$/#, with: "")
            .replacing(#/[^A-Za-z0-9 _-]/#, with: "_")
        let stamp = date.formatted(
            .iso8601.year().month().day().timeSeparator(.omitted)
                .dateTimeSeparator(.standard).time(includingFractionalSeconds: false)
        )
        return "\(stem) \(stamp).json"
    }
}
