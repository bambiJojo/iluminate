//
//  SessionLockView.swift
//  Ilumionate
//
//  Created by Byron Quine on 2/9/26.
//

import SwiftUI

/// Invisible multi-touch unlock overlay that prevents accidental session exits.
/// Requires simultaneous touches on 3 specific screen regions to unlock.
/// COMPLETELY INVISIBLE - no UI shown until unlock is in progress.
struct SessionLockView: View {

    let onUnlock: () -> Void

    @State private var touchedPoints: Set<Int> = []
    @State private var unlockProgress: Double = 0.0

    // Number of points required to unlock
    private let requiredPoints = 3

    // Hold duration required (in seconds) for unlock
    private let holdDuration: Double = 0.5

    @State private var unlockTimer: Timer?

    // Only show UI when actively unlocking
    private var showUnlockUI: Bool {
        touchedPoints.count == requiredPoints
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Invisible touch zones (always present)
                invisibleTouchZones(size: geometry.size)

                // Unlock UI (only visible during unlock attempt)
                if showUnlockUI {
                    unlockProgressOverlay(size: geometry.size)
                        .transition(.opacity)
                        .animation(.easeOut(duration: 0.2), value: showUnlockUI)
                }
            }
        }
        .allowsHitTesting(true)
    }

    // MARK: - Invisible Touch Zones

    private func invisibleTouchZones(size: CGSize) -> some View {
        let pointSize: CGSize = CGSize(width: 120, height: 120)

        return ZStack {
            // Zone 1: Top Left
            Color.clear
                .frame(width: pointSize.width, height: pointSize.height)
                .position(x: size.width * 0.25, y: size.height * 0.35)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in handleTouch(point: 0, active: true) }
                        .onEnded { _ in handleTouch(point: 0, active: false) }
                )

            // Zone 2: Top Right
            Color.clear
                .frame(width: pointSize.width, height: pointSize.height)
                .position(x: size.width * 0.75, y: size.height * 0.35)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in handleTouch(point: 1, active: true) }
                        .onEnded { _ in handleTouch(point: 1, active: false) }
                )

            // Zone 3: Bottom Center
            Color.clear
                .frame(width: pointSize.width, height: pointSize.height)
                .position(x: size.width * 0.5, y: size.height * 0.65)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in handleTouch(point: 2, active: true) }
                        .onEnded { _ in handleTouch(point: 2, active: false) }
                )
        }
    }

    // MARK: - Unlock Progress Overlay

    private func unlockProgressOverlay(size: CGSize) -> some View {
        ZStack {
            // Subtle background only when unlocking
            Color.black.opacity(0.3)
                .ignoresSafeArea()

            // Touch point indicators
            let pointSize: CGFloat = 80

            // Point 1: Top Left
            TouchPointView(
                pointNumber: 0,
                isActive: touchedPoints.contains(0),
                progress: unlockProgress
            )
            .frame(width: pointSize, height: pointSize)
            .position(x: size.width * 0.25, y: size.height * 0.35)

            // Point 2: Top Right
            TouchPointView(
                pointNumber: 1,
                isActive: touchedPoints.contains(1),
                progress: unlockProgress
            )
            .frame(width: pointSize, height: pointSize)
            .position(x: size.width * 0.75, y: size.height * 0.35)

            // Point 3: Bottom Center
            TouchPointView(
                pointNumber: 2,
                isActive: touchedPoints.contains(2),
                progress: unlockProgress
            )
            .frame(width: pointSize, height: pointSize)
            .position(x: size.width * 0.5, y: size.height * 0.65)

            // Progress indicator at top
            VStack {
                HStack(spacing: 8) {
                    Image(systemName: "hand.tap.fill")
                        .font(.title3)

                    Text("Hold to exit")
                        .font(.headline)

                    ProgressView(value: unlockProgress, total: 1.0)
                        .frame(width: 100)
                        .tint(.white)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial)
                .cornerRadius(20)
                .padding(.top, 20)

                Spacer()
            }
        }
        .foregroundStyle(.white)
    }

    // MARK: - Touch Handling (UPDATED)

    private func handleTouch(point: Int, active: Bool) {
        if active {
            touchedPoints.insert(point)

            // Start unlock timer if all points are touched
            if touchedPoints.count == requiredPoints {
                startUnlockTimer()
            }
        } else {
            touchedPoints.remove(point)

            // Cancel unlock if any point is released
            if touchedPoints.count < requiredPoints {
                cancelUnlockTimer()
            }
        }
    }

    private func startUnlockTimer() {
        cancelUnlockTimer() // Clear any existing timer

        unlockProgress = 0.0
        let startTime = Date()

        unlockTimer = Timer.scheduledTimer(withTimeInterval: 0.016, repeats: true) { timer in
            let elapsed = Date().timeIntervalSince(startTime)
            unlockProgress = min(elapsed / holdDuration, 1.0)

            if unlockProgress >= 1.0 {
                timer.invalidate()
                performUnlock()
            }
        }
    }

    private func cancelUnlockTimer() {
        unlockTimer?.invalidate()
        unlockTimer = nil
        unlockProgress = 0.0
    }

    private func performUnlock() {
        // Haptic feedback
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)

        // Trigger unlock
        onUnlock()
    }
}

// MARK: - Touch Point View

struct TouchPointView: View {
    let pointNumber: Int
    let isActive: Bool
    let progress: Double

    var body: some View {
        ZStack {
            // Background circle
            Circle()
                .fill(Color.white.opacity(0.2))
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.5), lineWidth: 2)
                )

            // Active state
            if isActive {
                Circle()
                    .fill(Color.green.opacity(0.4))
                    .overlay(
                        Circle()
                            .stroke(Color.green, lineWidth: 4)
                    )
                    .scaleEffect(1.1)
            }

            // Progress ring
            if progress > 0 {
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        Color.green,
                        style: StrokeStyle(lineWidth: 6, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.016), value: progress)
            }

            // Point number
            Text("\(pointNumber + 1)")
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(isActive ? .green : .white.opacity(0.7))
        }
        .animation(.easeOut(duration: 0.2), value: isActive)
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        // Simulate entrainment session background
        LinearGradient(
            colors: [.blue, .purple],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()

        SessionLockView {
            print("Unlocked!")
        }
    }
}
