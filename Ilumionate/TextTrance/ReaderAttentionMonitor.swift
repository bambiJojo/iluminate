//  ReaderAttentionMonitor.swift
//  Ilumionate
//
//  Front-camera attention gate for the Text Trance reader. Uses ARKit face
//  tracking when available; unsupported or unauthorized devices report a
//  status that lets the reader disable the gate cleanly.

import Foundation

/// Smooths noisy face-tracking observations. ARKit can report a handful of
/// false gaze frames during an ordinary blink, so loss of attention must be
/// sustained before it reaches the reader session. Returning attention is
/// accepted immediately so an attention pause never feels sticky.
struct ReaderAttentionStabilizer {
    let lossGrace: TimeInterval

    private(set) var isLookingAtScreen = true
    private var lastAttentiveUpdate: TimeInterval

    init(lossGrace: TimeInterval, now: TimeInterval) {
        self.lossGrace = lossGrace
        self.lastAttentiveUpdate = now
    }

    mutating func reset(at now: TimeInterval) {
        lastAttentiveUpdate = now
        isLookingAtScreen = true
    }

    mutating func observe(isLookingAtScreen observation: Bool, at now: TimeInterval) -> Bool {
        if observation {
            lastAttentiveUpdate = now
            isLookingAtScreen = true
        } else if now - lastAttentiveUpdate >= lossGrace {
            isLookingAtScreen = false
        }
        return isLookingAtScreen
    }
}

/// A single face-tracking observation. `isLookingAtScreen` is the raw
/// per-frame decision (before the stabilizer smooths it); the remaining fields
/// expose the signals behind that decision so a debug readout can show why the
/// gate did or did not trip.
struct ReaderAttentionSample: Sendable, Equatable {
    let isLookingAtScreen: Bool
    let faceTracked: Bool
    /// Dot product of the head's forward axis and the direction to the camera.
    /// 1 means the face points straight at the screen; 0 is side-on.
    let headFacing: Double
    /// How closed both eyes are (0 open, 1 fully shut). Only counts when *both*
    /// eyes are closed, so a wink or one-eye tracking noise won't trip it.
    let eyesClosed: Double

    static let faceLost = ReaderAttentionSample(
        isLookingAtScreen: false, faceTracked: false, headFacing: 0, eyesClosed: 0
    )

    /// Pure gate decision, factored out of the ARKit heuristic so it can be
    /// exercised without a live face anchor: the reader is engaged when a face
    /// is tracked, both eyes aren't shut, and the head faces the screen.
    static func isLooking(headFacing: Double, eyesClosed: Double, faceTracked: Bool) -> Bool {
        faceTracked
            && eyesClosed < ReaderAttentionThresholds.eyesClosed
            && headFacing > ReaderAttentionThresholds.facing
    }
}

/// Tunable thresholds for the attention gate, kept out of the ARKit-only block
/// so a debug readout (and tests) can reference them on any platform.
enum ReaderAttentionThresholds {
    /// Minimum alignment between the head's forward axis and the direction to
    /// the camera. 1.0 is dead-on; ~0.5 is a generous ~60° cone. Kept loose on
    /// purpose so normal reading posture never trips the gate.
    static let facing: Double = 0.5
    /// Both eyes must exceed this closed amount to count as "not reading"
    /// (drowsy / eyes shut). A wink or one-eye tracking noise won't trip it.
    static let eyesClosed: Double = 0.85
}

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
import simd

@MainActor
final class ReaderAttentionMonitor: NSObject {
    var onUpdate: (@MainActor (_ isLookingAtScreen: Bool, _ status: ReaderAttentionMonitorStatus, _ sample: ReaderAttentionSample?) -> Void)?

    /// Fires on every face frame (not just when the gate flips) so a debug
    /// overlay can watch the raw signals live. Left unset in release UI.
    var onSample: (@MainActor (_ sample: ReaderAttentionSample) -> Void)?

    /// Debug-only lifecycle breadcrumbs (session started / interrupted /
    /// watchdog firing) so a stuck gate can be diagnosed on-device.
    var onDebugEvent: (@MainActor (_ event: String) -> Void)?

    private let arSession = ARSession()
    private let attentionLossGrace: TimeInterval = 1.5
    /// How long the camera may go silent, or the face stay un-tracked, before
    /// the watchdog re-runs the AR session to recover. ARKit occasionally stops
    /// delivering face anchors after an interruption and never re-acquires on
    /// its own; re-running the session is Apple's documented recovery.
    private let recoveryThreshold: TimeInterval = 3.0
    private var status: ReaderAttentionMonitorStatus = .inactive
    private var isLookingAtScreen = true
    /// Last time any camera frame arrived (face or not) — distinguishes a dead
    /// camera pipeline from a live camera that simply can't find the face.
    private var lastFrameArrival = ProcessInfo.processInfo.systemUptime
    /// Last time a frame carried a tracked face.
    private var lastFaceUpdate = ProcessInfo.processInfo.systemUptime
    private var lastRestartAttempt: TimeInterval = 0
    private var lastSample: ReaderAttentionSample?
    private var stabilizer = ReaderAttentionStabilizer(
        lossGrace: 1.5,
        now: ProcessInfo.processInfo.systemUptime
    )
    private var faceLossTask: Task<Void, Never>?

    func start() async {
        guard status != .running, status != .starting else { return }
        guard ARFaceTrackingConfiguration.isSupported else {
            publish(isLookingAtScreen: true, status: .unsupported, force: true)
            return
        }

        publish(isLookingAtScreen: true, status: .starting)
        guard await cameraAccessIsAllowed() else { return }

        let now = ProcessInfo.processInfo.systemUptime
        lastFrameArrival = now
        lastFaceUpdate = now
        lastRestartAttempt = now
        stabilizer.reset(at: now)
        arSession.delegate = self
        runFaceTracking()
        publish(isLookingAtScreen: true, status: .running)
        onDebugEvent?("AR session started")
        startFaceLossWatch()
    }

    private func runFaceTracking() {
        let configuration = ARFaceTrackingConfiguration()
        configuration.isLightEstimationEnabled = false
        arSession.run(configuration, options: [.resetTracking, .removeExistingAnchors])
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

    /// Every camera frame lands here; `sample` is nil when the frame carried no
    /// face anchor. Frame arrival is recorded unconditionally so the watchdog
    /// can tell "camera dead" apart from "camera fine, face not found".
    private func receiveFrame(_ sample: ReaderAttentionSample?) {
        guard status == .running else { return }
        let now = ProcessInfo.processInfo.systemUptime
        lastFrameArrival = now

        let resolved = sample ?? .faceLost
        lastSample = resolved
        onSample?(resolved)

        if resolved.faceTracked {
            lastFaceUpdate = now
        }
        let stabilized = stabilizer.observe(isLookingAtScreen: resolved.isLookingAtScreen, at: now)
        publish(isLookingAtScreen: stabilized, status: .running)
    }

    /// Camera interruption means we can no longer confirm attention; feed the
    /// stabilizer a "not looking" observation so its grace period still applies
    /// before the reader actually pauses.
    private func receiveFaceLost() {
        guard status == .running else { return }
        let now = ProcessInfo.processInfo.systemUptime
        lastSample = .faceLost
        let stabilized = stabilizer.observe(isLookingAtScreen: false, at: now)
        publish(isLookingAtScreen: stabilized, status: .running)
    }

    private func fail(_ error: Error) {
        faceLossTask?.cancel()
        faceLossTask = nil
        arSession.pause()
        arSession.delegate = nil
        onDebugEvent?("AR session failed: \(error.localizedDescription)")
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
        let now = ProcessInfo.processInfo.systemUptime
        let framesSilent = now - lastFrameArrival
        let faceSilent = now - lastFaceUpdate

        if framesSilent >= attentionLossGrace {
            // Camera pipeline is dead — no frames at all. Mark attention lost
            // and re-run the session to bring the camera back.
            lastSample = .faceLost
            onDebugEvent?("camera stalled \(Int(framesSilent))s — restarting")
            let stabilized = stabilizer.observe(isLookingAtScreen: false, at: now)
            publish(isLookingAtScreen: stabilized, status: .running)
            restartIfCooledDown(at: now)
        } else if faceSilent >= recoveryThreshold {
            // Camera is delivering frames but ARKit hasn't tracked a face in a
            // while. Normally it re-acquires on its own; when it doesn't, a
            // tracking reset un-sticks it. Harmless if the reader is truly
            // away — the session is already running and attention stays lost.
            onDebugEvent?("no face \(Int(faceSilent))s — resetting tracking")
            restartIfCooledDown(at: now)
        }
    }

    private func restartIfCooledDown(at now: TimeInterval) {
        guard now - lastRestartAttempt >= recoveryThreshold else { return }
        lastRestartAttempt = now
        runFaceTracking()
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
            onUpdate?(isLookingAtScreen, status, lastSample)
        }
    }
}

extension ReaderAttentionMonitor: ARSessionDelegate {
    // Frame-based so the camera pose is available for the head-orientation
    // check. Values are extracted synchronously; the ARFrame is never captured
    // by the hop to the main actor, so it can't stall face tracking.
    nonisolated func session(_ session: ARSession, didUpdate frame: ARFrame) {
        let faceAnchor = frame.anchors.compactMap { $0 as? ARFaceAnchor }.first
        let sample = faceAnchor.map { ReaderAttentionHeuristic.evaluate($0, camera: frame.camera) }
        Task { @MainActor [weak self] in
            self?.receiveFrame(sample)
        }
    }

    nonisolated func session(_ session: ARSession, didFailWithError error: Error) {
        Task { @MainActor [weak self] in
            self?.fail(error)
        }
    }

    nonisolated func sessionWasInterrupted(_ session: ARSession) {
        Task { @MainActor [weak self] in
            self?.onDebugEvent?("AR session interrupted")
            self?.receiveFaceLost()
        }
    }

    nonisolated func sessionInterruptionEnded(_ session: ARSession) {
        Task { @MainActor [weak self] in
            guard let self, self.status == .running else { return }
            self.onDebugEvent?("AR interruption ended — restarting")
            // ARKit claims to auto-resume, but face tracking has been observed
            // to come back with no frame delivery. Re-run explicitly.
            self.lastRestartAttempt = ProcessInfo.processInfo.systemUptime
            self.runFaceTracking()
        }
    }
}

/// Decides "is the reader engaged with the screen" from head orientation rather
/// than eyeball gaze. Eye-gaze blend shapes swing wildly during ordinary
/// reading (vergence at close range, downward gaze, constant saccades), so they
/// can't tell "reading" from "looking away". Whether the head is *facing* the
/// device is a far steadier signal and is what actually distinguishes a reader
/// from someone who has turned away or set the phone down.
private enum ReaderAttentionHeuristic {
    nonisolated static func evaluate(_ anchor: ARFaceAnchor, camera: ARCamera) -> ReaderAttentionSample {
        guard anchor.isTracked else { return .faceLost }

        let shapes = anchor.blendShapes
        let eyesClosed = min(
            blend(.eyeBlinkLeft, in: shapes),
            blend(.eyeBlinkRight, in: shapes)
        )

        // Head-forward axis (face-local +Z points out of the face) expressed in
        // world space, versus the direction from the face to the camera.
        let facePosition = simd_make_float3(anchor.transform.columns.3)
        let faceForward = simd_normalize(simd_make_float3(anchor.transform.columns.2))
        let cameraPosition = simd_make_float3(camera.transform.columns.3)
        let toCamera = simd_normalize(cameraPosition - facePosition)
        let headFacing = Double(simd_dot(faceForward, toCamera))

        let looking = ReaderAttentionSample.isLooking(
            headFacing: headFacing, eyesClosed: eyesClosed, faceTracked: true
        )
        return ReaderAttentionSample(
            isLookingAtScreen: looking,
            faceTracked: true,
            headFacing: headFacing,
            eyesClosed: eyesClosed
        )
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
    var onUpdate: (@MainActor (_ isLookingAtScreen: Bool, _ status: ReaderAttentionMonitorStatus, _ sample: ReaderAttentionSample?) -> Void)?
    var onSample: (@MainActor (_ sample: ReaderAttentionSample) -> Void)?
    var onDebugEvent: (@MainActor (_ event: String) -> Void)?

    func start() async {
        onUpdate?(true, .unsupported, nil)
    }

    func stop() {
        onUpdate?(true, .inactive, nil)
    }
}
#endif
