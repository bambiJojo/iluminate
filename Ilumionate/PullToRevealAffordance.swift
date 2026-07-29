//
//  PullToRevealAffordance.swift
//  Ilumionate
//
//  Shows the reveal gesture while a finger is down: a circle at the touch
//  point and a target angled toward the centre of the screen, with the target
//  filling as the pull progresses. Exists only during the touch, so the
//  minimal overlay stays empty the rest of the time.
//
//  Purely presentational — all geometry comes from MinimalOverlayGesture so
//  the picture and the behaviour cannot drift apart.
//

import SwiftUI

struct PullToRevealAffordance: View {
    /// Where the finger went down, in the overlay's coordinate space.
    let origin: CGPoint
    /// The overlay's size, used to aim the target at the centre line.
    let containerSize: CGSize
    /// 0 at rest, 1 on arrival.
    let progress: Double

    private let puckSize: CGFloat = 52
    private let targetSize: CGFloat = 44

    private var start: CGPoint { MinimalOverlayGesture.anchor(for: origin) }
    private var goal: CGPoint { MinimalOverlayGesture.target(for: origin, in: containerSize) }

    /// The puck rides the line between the touch and the target.
    private var puckPosition: CGPoint {
        CGPoint(
            x: start.x + (goal.x - start.x) * progress,
            y: start.y + (goal.y - start.y) * progress
        )
    }

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
            .position(goal)
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
            .position(puckPosition)
    }
}
