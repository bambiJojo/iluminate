//
//  PullToRevealAffordance.swift
//  Ilumionate
//
//  Shows the reveal gesture while a finger is down: a circle at the touch
//  point and a target above it, with the target filling as the pull
//  progresses. Exists only during the touch, so the minimal overlay stays
//  empty the rest of the time.
//

import SwiftUI

struct PullToRevealAffordance: View {
    /// Where the finger went down, in the overlay's coordinate space.
    let origin: CGPoint
    /// 0 at rest, 1 on arrival.
    let progress: Double

    private let travel = MinimalOverlayGesture.revealThreshold
    private let puckSize: CGFloat = 52
    private let targetSize: CGFloat = 44

    /// A touch near the top would put the target off-screen, so hold the
    /// anchor far enough down that the target always has room.
    private var anchorY: CGFloat { max(origin.y, travel + targetSize) }

    var body: some View {
        ZStack {
            target
            puck
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var target: some View {
        Circle()
            .strokeBorder(
                Color.roseGold.opacity(0.35 + 0.25 * progress),
                style: StrokeStyle(lineWidth: 1.5, dash: [4, 4])
            )
            .overlay(
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        Color.roseGold,
                        style: StrokeStyle(lineWidth: 1.5, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
            )
            .frame(width: targetSize, height: targetSize)
            .position(x: origin.x, y: anchorY - travel)
    }

    private var puck: some View {
        Circle()
            .fill(Color.roseGold.opacity(0.14 + 0.20 * progress))
            .overlay(Circle().strokeBorder(Color.roseGold, lineWidth: 1.5))
            .frame(width: puckSize, height: puckSize)
            .overlay {
                Image(systemName: "chevron.up")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.roseGold.opacity(0.5 + 0.5 * progress))
            }
            .position(x: origin.x, y: anchorY - travel * progress)
    }
}
