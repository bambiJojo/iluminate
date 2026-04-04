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
        for phase in editor.draft.phases {
            let startX = editor.timeToViewFrac(phase.startTime) * size.width
            let endX = editor.timeToViewFrac(phase.endTime) * size.width
            guard endX > startX else { continue }
            let topY = chartH * (1 - editor.phaseDepth(phase.phase))
            var path = Path()
            path.move(to: CGPoint(x: startX, y: chartH))
            path.addLine(to: CGPoint(x: startX, y: topY))
            path.addLine(to: CGPoint(x: endX, y: topY))
            path.addLine(to: CGPoint(x: endX, y: chartH))
            path.closeSubpath()
            ctx.fill(path, with: .color(editor.phaseColor(phase.phase).opacity(0.22)))
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
        for (index, phase) in editor.draft.phases.enumerated() {
            let boundX = editor.timeToViewFrac(phase.startTime) * size.width
            var line = Path()
            line.move(to: CGPoint(x: boundX, y: 0))
            line.addLine(to: CGPoint(x: boundX, y: chartH))
            ctx.stroke(line, with: .color(editor.phaseColor(phase.phase).opacity(0.4)), lineWidth: 1)

            let nextStart = index + 1 < editor.draft.phases.count
                ? editor.draft.phases[index + 1].startTime
                : editor.duration
            let endFrac = editor.timeToViewFrac(nextStart)
            let startFrac = editor.timeToViewFrac(phase.startTime)
            let blockWidth = (endFrac - startFrac) * size.width
            if blockWidth > 44 {
                let midX = ((startFrac + endFrac) / 2) * size.width
                ctx.draw(
                    Text(phase.phase.displayName)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(editor.phaseColor(phase.phase)),
                    at: CGPoint(x: midX, y: 13)
                )
            }
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
