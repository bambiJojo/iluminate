//
//  LabelingDetailView+Canvas.swift
//  LumeLabel
//
//  Canvas drawing methods for the phase arc timeline.
//

import SwiftUI

extension LabelingDetailView {
    func drawPhaseFills(_ ctx: inout GraphicsContext, size: CGSize, editor: LabelingDetailEditor) {
        let chartH = size.height * 0.82
        for segment in editor.labelingSegments {
            let startX = editor.timeToViewFrac(segment.startTime) * size.width
            let endX = editor.timeToViewFrac(segment.endTime) * size.width
            guard endX > startX else { continue }
            let topY = chartH * (1 - editor.phaseDepth(segment.phase))
            var path = Path()
            path.move(to: CGPoint(x: startX, y: chartH))
            path.addLine(to: CGPoint(x: startX, y: topY))
            path.addLine(to: CGPoint(x: endX, y: topY))
            path.addLine(to: CGPoint(x: endX, y: chartH))
            path.closeSubpath()
            ctx.fill(path, with: .color(editor.phaseColor(segment.phase).opacity(0.22)))
        }
    }

    func drawDepthCurve(_ ctx: inout GraphicsContext, size: CGSize, editor: LabelingDetailEditor) {
        let phasePoints = editor.phasePoints
        guard !phasePoints.isEmpty else { return }
        let chartH = size.height * 0.82

        let points: [CGPoint] = phasePoints.map { point in
            let xCoord = editor.timeToViewFrac(point.time) * size.width
            let yCoord = chartH * (1 - editor.phaseDepth(point.phase))
            return CGPoint(x: xCoord, y: yCoord)
        }

        if points.count >= 2 {
            var curve = Path()
            curve.move(to: points[0])

            for index in 0..<(points.count - 1) {
                let previous = index > 0 ? points[index - 1] : points[index]
                let current = points[index]
                let next = points[index + 1]
                let nextNext = index + 2 < points.count ? points[index + 2] : next

                let control1 = CGPoint(
                    x: current.x + (next.x - previous.x) / 6,
                    y: current.y + (next.y - previous.y) / 6
                )
                let control2 = CGPoint(
                    x: next.x - (nextNext.x - current.x) / 6,
                    y: next.y - (nextNext.y - current.y) / 6
                )

                curve.addCurve(to: next, control1: control1, control2: control2)
            }

            ctx.stroke(
                curve,
                with: .color(.primary.opacity(0.55)),
                style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
            )
        }

        for dotCenter in points {
            let dotRect = CGRect(x: dotCenter.x - 3, y: dotCenter.y - 3, width: 6, height: 6)
            ctx.fill(Path(ellipseIn: dotRect), with: .color(.primary.opacity(0.7)))
        }
    }

    func drawBoundaries(_ ctx: inout GraphicsContext, size: CGSize, editor: LabelingDetailEditor) {
        let chartH = size.height * 0.82
        for (index, segment) in editor.labelingSegments.enumerated() {
            if index > 0 {
                let boundX = editor.timeToViewFrac(segment.startTime) * size.width
                var line = Path()
                line.move(to: CGPoint(x: boundX, y: 0))
                line.addLine(to: CGPoint(x: boundX, y: chartH))
                ctx.stroke(line, with: .color(editor.phaseColor(segment.phase).opacity(0.4)), lineWidth: 1)
            }

            let nextStart = index + 1 < editor.labelingSegments.count
                ? editor.labelingSegments[index + 1].startTime
                : editor.duration
            let endFrac = editor.timeToViewFrac(nextStart)
            let startFrac = editor.timeToViewFrac(segment.startTime)
            let blockWidth = (endFrac - startFrac) * size.width
            if blockWidth > 44 {
                let midX = ((startFrac + endFrac) / 2) * size.width
                ctx.draw(
                    Text(editor.phaseDisplayName(segment.phase))
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(editor.phaseColor(segment.phase)),
                    at: CGPoint(x: midX, y: 13)
                )
            }
        }
    }

    func drawTransitionCandidates(
        _ ctx: inout GraphicsContext,
        size: CGSize,
        editor: LabelingDetailEditor
    ) {
        let chartHeight = size.height * 0.82
        for candidate in editor.transitionCandidates {
            let xPosition = editor.timeToViewFrac(candidate.time) * size.width
            guard xPosition >= 0, xPosition <= size.width else { continue }

            let decision = editor.candidateDecision(for: candidate.id)
            let isSelected = editor.selectedTransitionCandidateID == candidate.id
            let color = transitionCandidateColor(candidate, decision: decision)
            let opacity: Double = if isSelected {
                1
            } else if decision == .dismissed {
                0.16
            } else if decision == .accepted {
                0.7
            } else {
                0.48
            }

            var line = Path()
            line.move(to: CGPoint(x: xPosition, y: 0))
            line.addLine(to: CGPoint(x: xPosition, y: chartHeight))
            ctx.stroke(
                line,
                with: .color(color.opacity(opacity)),
                style: StrokeStyle(
                    lineWidth: isSelected ? 3 : 1.5,
                    dash: decision == .accepted ? [] : [5, 3]
                )
            )

            var marker = Path()
            marker.move(to: CGPoint(x: xPosition, y: chartHeight - 10))
            marker.addLine(to: CGPoint(x: xPosition - 5, y: chartHeight))
            marker.addLine(to: CGPoint(x: xPosition + 5, y: chartHeight))
            marker.closeSubpath()
            ctx.fill(marker, with: .color(color.opacity(opacity)))
        }
    }

    func transitionCandidateColor(
        _ candidate: TransitionCandidateReview.Candidate,
        decision: TransitionCandidateReview.Decision?
    ) -> Color {
        if decision == .accepted {
            return .green
        }
        if decision == .dismissed {
            return .gray
        }
        switch candidate.source {
        case .backgroundTone: return .cyan
        case .semantic: return .purple
        }
    }

    func drawPlayhead(_ ctx: inout GraphicsContext, size: CGSize, editor: LabelingDetailEditor) {
        let headX = editor.timeToViewFrac(editor.currentTime) * size.width
        guard headX >= 0 && headX <= size.width else { return }
        let chartH = size.height * 0.82

        var line = Path()
        line.move(to: CGPoint(x: headX, y: 0))
        line.addLine(to: CGPoint(x: headX, y: chartH))
        ctx.stroke(line, with: .color(.primary), lineWidth: 2)

        var triangle = Path()
        triangle.move(to: CGPoint(x: headX, y: 6))
        triangle.addLine(to: CGPoint(x: headX - 5, y: 0))
        triangle.addLine(to: CGPoint(x: headX + 5, y: 0))
        triangle.closeSubpath()
        ctx.fill(triangle, with: .color(.primary))
    }

    func drawRuler(_ ctx: inout GraphicsContext, size: CGSize, editor: LabelingDetailEditor) {
        let visibleDuration = editor.viewSpan * editor.duration
        let startSeconds = editor.viewStart * editor.duration
        let endSeconds = editor.viewEnd * editor.duration
        let interval = editor.niceInterval(for: visibleDuration)
        var tickTime = ceil(startSeconds / interval) * interval

        while tickTime <= endSeconds {
            let tickX = ((tickTime - startSeconds) / visibleDuration) * size.width
            var tick = Path()
            tick.move(to: CGPoint(x: tickX, y: size.height * 0.82))
            tick.addLine(to: CGPoint(x: tickX, y: size.height))
            ctx.stroke(tick, with: .color(.secondary.opacity(0.35)), lineWidth: 1)
            ctx.draw(
                Text(editor.formatTime(tickTime)).font(.system(size: 8)).foregroundStyle(.secondary),
                at: CGPoint(x: tickX, y: size.height - 9)
            )
            tickTime += interval
        }
    }
}
