//
//  AnalysisFailureMerge.swift
//  Ilumionate
//
//  Failures live in two places with different lifetimes. The durable manual
//  recovery survives relaunch and carries `dismissedAt`, but only exists for
//  `.manual` failures. The runtime list also holds `.automatic` and
//  `.unavailable`, but is lost on termination.
//

import Foundation

nonisolated enum AnalysisFailureMerge {

    /// Total over the union of both key sets. The durable record is
    /// authoritative on an equal `failedAt`; otherwise the later occurrence
    /// wins, because `markRequiresManualRetry` writes a fresh recovery per
    /// occurrence and a newer failure genuinely supersedes an older one.
    static func merge(
        durable: [UUID: AnalysisFailureSnapshot],
        runtime: [UUID: AnalysisFailureSnapshot]
    ) -> [UUID: AnalysisFailureSnapshot] {
        var merged = durable
        for (id, runtimeFailure) in runtime {
            guard let durableFailure = merged[id] else {
                merged[id] = runtimeFailure
                continue
            }
            if runtimeFailure.failedAt > durableFailure.failedAt {
                merged[id] = runtimeFailure
            }
        }
        return merged
    }
}
