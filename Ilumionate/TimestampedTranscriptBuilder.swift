//
//  TimestampedTranscriptBuilder.swift
//  Ilumionate
//

import Foundation

/// Converts community transcript timestamp markers into analyzer-ready segments.
///
/// Supported line prefixes include `1:23`, `[1:23]`, `01:02:03`, and ranges
/// such as `[0:00-1:20]`. Untimed transcripts remain useful as one full-duration
/// segment.
nonisolated struct TimestampedTranscriptBuilder: Sendable {
    func makeResult(
        transcript: String,
        duration: TimeInterval,
        confidence: Double = 0.92
    ) -> AudioTranscriptionResult? {
        let lines = transcript.components(separatedBy: .newlines)
        var timedChunks: [(timestamp: TimeInterval, text: String)] = []
        var pendingText: [String] = []
        var currentTimestamp: TimeInterval?

        func appendPendingText() {
            let text = sanitizedLines(pendingText)
            guard !text.isEmpty else {
                pendingText.removeAll(keepingCapacity: true)
                return
            }

            // Text before the first marker is still part of the official
            // transcript. Treat it as the opening segment instead of dropping
            // it when the first timestamp appears later in the file.
            timedChunks.append((currentTimestamp ?? 0, text))
            pendingText.removeAll(keepingCapacity: true)
        }

        for line in lines {
            guard let marker = timestampPrefix(in: line) else {
                pendingText.append(line)
                continue
            }

            if let currentTimestamp, marker.timestamp + 0.5 < currentTimestamp {
                // A backward timestamp is usually ordinary prose or a malformed
                // caption. Keep it as text instead of corrupting the timeline.
                pendingText.append(line)
                continue
            }

            appendPendingText()
            currentTimestamp = marker.timestamp
            if !marker.remainder.isEmpty {
                pendingText.append(marker.remainder)
            }
        }
        appendPendingText()

        let sanitizedTranscript = AudioTranscriptionResult.sanitizedTranscriptText(
            timedChunks.isEmpty
                ? transcript
                : timedChunks.map(\.text).joined(separator: " ")
        )
        guard !sanitizedTranscript.isEmpty else { return nil }

        let resolvedDuration = max(duration, 1)
        let segments: [AudioTranscriptionSegment]
        if timedChunks.count >= 2 {
            segments = timedChunks.enumerated().compactMap { index, chunk in
                let start = min(max(chunk.timestamp, 0), resolvedDuration)
                let nextStart = index + 1 < timedChunks.count
                    ? timedChunks[index + 1].timestamp
                    : resolvedDuration
                let end = min(max(nextStart, start + 0.25), resolvedDuration)
                guard end > start else { return nil }

                return AudioTranscriptionSegment(
                    text: chunk.text,
                    timestamp: start,
                    duration: end - start,
                    confidence: confidence
                )
            }
        } else {
            segments = [
                AudioTranscriptionSegment(
                    text: sanitizedTranscript,
                    timestamp: 0,
                    duration: resolvedDuration,
                    confidence: confidence
                )
            ]
        }

        return AudioTranscriptionResult(
            fullText: sanitizedTranscript,
            segments: segments,
            duration: duration,
            detectedLanguage: "en"
        )
    }

    private func timestampPrefix(
        in line: String
    ) -> (timestamp: TimeInterval, remainder: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let token: Substring
        let remainder: Substring
        if trimmed.first == "[", let closingBracket = trimmed.firstIndex(of: "]") {
            token = trimmed[trimmed.index(after: trimmed.startIndex)..<closingBracket]
            remainder = trimmed[trimmed.index(after: closingBracket)...]
        } else if let whitespace = trimmed.firstIndex(where: \.isWhitespace) {
            token = trimmed[..<whitespace]
            remainder = trimmed[whitespace...]
        } else {
            token = Substring(trimmed)
            remainder = ""
        }

        let startToken = token.split(separator: "-", maxSplits: 1).first ?? token
        let components = startToken.split(separator: ":")
        guard components.count == 2 || components.count == 3,
              components.allSatisfy({ $0.allSatisfy(\.isNumber) }) else {
            return nil
        }

        let values = components.compactMap { Double($0) }
        guard values.count == components.count else { return nil }

        let timestamp: TimeInterval
        if values.count == 3 {
            timestamp = values[0] * 3_600 + values[1] * 60 + values[2]
        } else {
            timestamp = values[0] * 60 + values[1]
        }

        return (
            timestamp,
            String(remainder).trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private func sanitizedLines(_ lines: [String]) -> String {
        AudioTranscriptionResult.sanitizedTranscriptText(
            lines.joined(separator: " ")
        )
    }
}
