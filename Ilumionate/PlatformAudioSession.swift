//
//  PlatformAudioSession.swift
//  Ilumionate
//
//  AVAudioSession is an iOS concept. macOS audio engines run without it.
//

import AVFoundation
import Foundation

enum PlatformAudioSession {
    static var interruptionNotification: Notification.Name {
        #if os(iOS)
        AVAudioSession.interruptionNotification
        #else
        Notification.Name("LumeSyncAudioSessionInterruption")
        #endif
    }

    static func interruptionBegan(_ notification: Notification) -> Bool {
        #if os(iOS)
        guard let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt else {
            return false
        }
        return AVAudioSession.InterruptionType(rawValue: rawType) == .began
        #else
        _ = notification
        return false
        #endif
    }
}
