//
//  PlayerModeAnalytics.swift
//  Ilumionate
//
//  The analytics identity of a player mode.
//
//  Session telemetry already carried `source` (preset / generated / mindMachine)
//  and `category` (Focus / Trance / …), but never which player actually rendered.
//  With 8 of 35 measured sessions abandoned in their first quarter, the obvious
//  next question — which experience are people walking out of — had no answer.
//
//  Hand-written rather than derived from the case name: these strings are wire
//  format, and a Swift rename must not silently split a metric in two.
//

import Foundation

extension PlayerMode {
    var analyticsName: String {
        switch self {
        case .session:      "session"
        case .flashMode:    "flash"
        case .colorPulse:   "colorPulse"
        case .visualField:  "visualField"
        case .audioLight:   "audioLight"
        case .playlist:     "playlist"
        }
    }
}
