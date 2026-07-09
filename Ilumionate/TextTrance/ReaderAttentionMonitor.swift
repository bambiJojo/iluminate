//  ReaderAttentionMonitor.swift
//  Ilumionate
//
//  Front-camera attention gate for the Text Trance reader. Uses ARKit face
//  tracking when available; unsupported or unauthorized devices report a
//  status that lets the reader disable the gate cleanly.

import Foundation

enum ReaderAttentionMonitorStatus: Equatable {
    case inactive
    case starting
    case running
    case unsupported
    case cameraDenied
    case cameraRestricted
    case failed(String)

    var disablesGate: Bool {
        switch self {
        case .unsupported, .cameraDenied, .cameraRestricted, .failed:
            true
        case .inactive, .starting, .running:
            false
        }
    }

    var displayText: String? {
        switch self {
        case .inactive:
            nil
        case .starting:
            "Starting attention check"
        case .running:
            "Attention check active"
        case .unsupported:
            "Attention check requires a TrueDepth front camera"
        case .cameraDenied:
            "Camera permission is needed for attention check"
        case .cameraRestricted:
            "Camera access is restricted on this device"
        case .failed(let message):
            message.isEmpty ? "Attention check unavailable" : message
        }
    }
}

#if os(iOS) && canImport(ARKit) && canImport(AVFoundation)
import ARKit
import AVFoundation

@MainActor
final class ReaderAttentionMonitor: NSObject {
    var onUpdate: (@MainActor (_ isLookingAtScreen: Bool, _ status: ReaderAttentionMonitorStatus) -> Void)?

    private let arSession = ARSession()
    private let faceLossGrace: TimeInterval = 0.85
    private var status: ReaderAttentionMonitorStatus = .inactive
    private var isLookingAtScreen = true
    private var lastFaceUpdate = ProcessInfo.processInfo.systemUptime
    private var faceLossTask: Task<Void, Never>?

    func start() async {
        guard status != .running, status != .starting else { return }
        guard ARFaceTrackingConfiguration.isSupported else {
            publish(isLookingAtScreen: true, status: .unsupported, force: true)
            return
        }

        publish(isLookingAtScreen: true, status: .starting)
        guard await cameraAccessIsAllowed() else { return }

        let configuration = ARFaceTrackingConfiguration()
        configuration.isLightEstimationEnabled = false
        lastFaceUpdate = ProcessInfo.processInfo.systemUptime
        arSession.delegate = self
        arSession.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        publish(isLookingAtScreen: true, status: .running)
        startFaceLossWatch()
    }

    func stop() {
        faceLossTask?.cancel()
        faceLossTask = nil
        arSession.pause()
        arSession.delegate = nil
        publish(isLookingAtScreen: true, status: .inactive)
    }

    private func cameraAccessIsAllowed() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return true
        case .notDetermined:
            let granted = await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .video) { granted in
                    continuation.resume(returning: granted)
                }
            }
            if !granted { publish(isLookingAtScreen: true, status: .cameraDenied, force: true) }
            return granted
        case .denied:
            publish(isLookingAtScreen: true, status: .cameraDenied, force: true)
            return false
        case .restricted:
            publish(isLookingAtScreen: true, status: .cameraRestricted, force: true)
            return false
        @unknown default:
            publish(isLookingAtScreen: true, status: .failed("Camera authorization status is unknown"), force: true)
            return false
        }
    }

    private func receiveFaceUpdate(isLookingAtScreen: Bool) {
        guard status == .running else { return }
        lastFaceUpdate = ProcessInfo.processInfo.systemUptime
        publish(isLookingAtScreen: isLookingAtScreen, status: .running)
    }

    private func fail(_ error: Error) {
        faceLossTask?.cancel()
        faceLossTask = nil
        arSession.pause()
        arSession.delegate = nil
        publish(isLookingAtScreen: true, status: .failed(error.localizedDescription), force: true)
    }

    private func startFaceLossWatch() {
        faceLossTask?.cancel()
        faceLossTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                self?.markFaceLostIfNeeded()
            }
        }
    }

    private func markFaceLostIfNeeded() {
        guard status == .running else { return }
        let elapsed = ProcessInfo.processInfo.systemUptime - lastFaceUpdate
        if elapsed >= faceLossGrace {
            publish(isLookingAtScreen: false, status: .running)
        }
    }

    private func publish(
        isLookingAtScreen: Bool,
        status: ReaderAttentionMonitorStatus,
        force: Bool = false
    ) {
        let changed = self.isLookingAtScreen != isLookingAtScreen || self.status != status
        self.isLookingAtScreen = isLookingAtScreen
        self.status = status
        if changed || force {
            onUpdate?(isLookingAtScreen, status)
        }
    }
}

extension ReaderAttentionMonitor: ARSessionDelegate {
    nonisolated func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        guard let faceAnchor = anchors.compactMap({ $0 as? ARFaceAnchor }).first else { return }
        let looking = ReaderAttentionHeuristic.isLookingAtScreen(faceAnchor)
        Task { @MainActor [weak self] in
            self?.receiveFaceUpdate(isLookingAtScreen: looking)
        }
    }

    nonisolated func session(_ session: ARSession, didFailWithError error: Error) {
        Task { @MainActor [weak self] in
            self?.fail(error)
        }
    }

    nonisolated func sessionWasInterrupted(_ session: ARSession) {
        Task { @MainActor [weak self] in
            self?.receiveFaceUpdate(isLookingAtScreen: false)
        }
    }
}

private enum ReaderAttentionHeuristic {
    nonisolated static func isLookingAtScreen(_ anchor: ARFaceAnchor) -> Bool {
        guard anchor.isTracked else { return false }

        let shapes = anchor.blendShapes
        let blink = max(blend(.eyeBlinkLeft, in: shapes), blend(.eyeBlinkRight, in: shapes))
        guard blink < 0.70 else { return false }

        let horizontalAway = max(
            blend(.eyeLookInLeft, in: shapes),
            blend(.eyeLookOutLeft, in: shapes),
            blend(.eyeLookInRight, in: shapes),
            blend(.eyeLookOutRight, in: shapes)
        )
        let verticalAway = max(
            blend(.eyeLookUpLeft, in: shapes),
            blend(.eyeLookDownLeft, in: shapes),
            blend(.eyeLookUpRight, in: shapes),
            blend(.eyeLookDownRight, in: shapes)
        )

        return horizontalAway < 0.55 && verticalAway < 0.65
    }

    nonisolated private static func blend(
        _ location: ARFaceAnchor.BlendShapeLocation,
        in shapes: [ARFaceAnchor.BlendShapeLocation: NSNumber]
    ) -> Double {
        shapes[location]?.doubleValue ?? 0
    }
}
#else
@MainActor
final class ReaderAttentionMonitor {
    var onUpdate: (@MainActor (_ isLookingAtScreen: Bool, _ status: ReaderAttentionMonitorStatus) -> Void)?

    func start() async {
        onUpdate?(true, .unsupported)
    }

    func stop() {
        onUpdate?(true, .inactive)
    }
}
#endif
