//
//  ClosedRange+Codable.swift
//  Ilumionate
//
//  Adds Codable conformance to ClosedRange when its Bound is Codable.
//  Required for AnalysisResult.suggestedFrequencyRange serialization.
//

import Foundation

extension ClosedRange: @retroactive Codable where Bound: Codable {
    private enum CodingKeys: String, CodingKey {
        case lowerBound
        case upperBound
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let lower = try container.decode(Bound.self, forKey: .lowerBound)
        let upper = try container.decode(Bound.self, forKey: .upperBound)
        self = lower...upper
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(lowerBound, forKey: .lowerBound)
        try container.encode(upperBound, forKey: .upperBound)
    }
}
