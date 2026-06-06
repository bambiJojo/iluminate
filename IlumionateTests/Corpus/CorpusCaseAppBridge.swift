//  CorpusCaseAppBridge.swift
//  IlumionateTests
//
//  Bridges the pure CorpusKit DTO to app types used by the harness:
//  the typed content type and AudioTranscriptionSegment conversion.
//
import Foundation
import CorpusKit
@testable import Ilumionate

extension CorpusCase {
    /// App-typed content type, bridged from the raw string.
    var expectedContentType: AnalysisResult.ContentType? {
        expectedContentTypeRaw.flatMap(AnalysisResult.ContentType.init(rawValue:))
    }

    /// App-typed transcription segments for feeding the analyzer.
    var transcriptionSegments: [AudioTranscriptionSegment] {
        segments.map {
            AudioTranscriptionSegment(
                text: $0.text, timestamp: $0.timestamp,
                duration: $0.duration, confidence: $0.confidence
            )
        }
    }
}
