//
//  PerformanceTrace.swift
//  Ilumionate
//
//  Low-overhead landmarks for Instruments. Keep these at user-visible seams;
//  high-frequency work such as playback clocks and render callbacks should not
//  emit signposts because the measurement would add noise to the trace.
//

import os.signpost

nonisolated struct PerformanceInterval: @unchecked Sendable {
    fileprivate let name: StaticString
    fileprivate let id: OSSignpostID
}

nonisolated enum PerformanceTrace {
    private static let log = OSLog(
        subsystem: "com.byronquine.lumenSync",
        category: .pointsOfInterest
    )

    @inline(__always)
    static func begin(_ name: StaticString) -> PerformanceInterval {
        let id = OSSignpostID(log: log)
        os_signpost(.begin, log: log, name: name, signpostID: id)
        return PerformanceInterval(name: name, id: id)
    }

    @inline(__always)
    static func end(_ interval: PerformanceInterval) {
        os_signpost(
            .end,
            log: log,
            name: interval.name,
            signpostID: interval.id
        )
    }

    @inline(__always)
    static func event(_ name: StaticString) {
        os_signpost(.event, log: log, name: name)
    }
}
