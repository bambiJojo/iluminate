//
//  LabelingDetailView+Subviews.swift
//  LumeLabel
//
//  All SwiftUI subview properties for LabelingDetailView.
//

import SwiftUI

extension LabelingDetailView {
    func phaseArc(_ editor: LabelingDetailEditor) -> some View {
        GeometryReader { geo in
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .underPageBackgroundColor))

                Canvas { context, size in
                    drawPhaseFills(&context, size: size, editor: editor)
                    drawDepthCurve(&context, size: size, editor: editor)
                    drawBoundaries(&context, size: size, editor: editor)
                    drawPlayhead(&context, size: size, editor: editor)
                    drawRuler(&context, size: size, editor: editor)
                }

                phasePointHandles(editor, size: geo.size)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let frac = value.location.x / max(geo.size.width, 1)
                        editor.seek(to: (editor.viewStart + frac * editor.viewSpan) * editor.duration)
                    }
            )
            .simultaneousGesture(
                MagnifyGesture()
                    .onChanged { value in
                        let delta = value.magnification / editor.lastMagnification
                        editor.lastMagnification = value.magnification
                        editor.zoomAround(editor.currentTime / editor.duration, scale: delta)
                    }
                    .onEnded { _ in
                        editor.lastMagnification = 1
                    }
            )
        }
        .frame(height: 140)
    }

    func phasePointHandles(_ editor: LabelingDetailEditor, size: CGSize) -> some View {
        let chartHeight = size.height * 0.82

        return ForEach(editor.phasePoints) { point in
            let xPosition = editor.timeToViewFrac(point.time) * size.width
            let yPosition = chartHeight * (1 - editor.phaseDepth(point.phase))
            let isVisible = xPosition >= 0 && xPosition <= size.width

            Circle()
                .fill(editor.phaseColor(point.phase))
                .overlay(
                    Circle()
                        .strokeBorder(.white.opacity(0.85), lineWidth: 1.5)
                )
                .frame(width: editor.draggingPointID == point.id ? 16 : 13,
                       height: editor.draggingPointID == point.id ? 16 : 13)
                .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
                .contentShape(Rectangle().inset(by: -10))
                .position(x: xPosition, y: yPosition)
                .opacity(isVisible ? 1 : 0)
                .allowsHitTesting(isVisible)
                .highPriorityGesture(
                    DragGesture(minimumDistance: 2)
                        .onChanged { value in
                            editor.draggingPointID = point.id
                            let time = editor.timeForViewX(value.location.x, width: size.width)
                            let phase = editor.phaseForCanvasY(value.location.y, chartHeight: chartHeight)
                            editor.updatePhasePoint(id: point.id, time: time, phase: phase)
                        }
                        .onEnded { value in
                            let time = editor.timeForViewX(value.location.x, width: size.width)
                            let phase = editor.phaseForCanvasY(value.location.y, chartHeight: chartHeight)
                            editor.updatePhasePoint(id: point.id, time: time, phase: phase)
                            editor.draggingPointID = nil
                        }
                )
                .contextMenu {
                    ForEach(editor.orderedPhases, id: \.self) { phase in
                        Button {
                            editor.setPhase(ofPointID: point.id, to: phase)
                        } label: {
                            if phase == point.phase {
                                Label(phase.displayName, systemImage: "checkmark")
                            } else {
                                Text(phase.displayName)
                            }
                        }
                    }

                    Divider()

                    Button("Delete Point", role: .destructive) {
                        editor.deletePhasePoint(id: point.id)
                    }
                }
        }
    }

    func overviewStrip(_ editor: LabelingDetailEditor) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(nsColor: .underPageBackgroundColor))

                ForEach(editor.draft.phases) { phase in
                    let startFrac = phase.startTime / editor.duration
                    let widthFrac = (phase.endTime - phase.startTime) / editor.duration
                    Rectangle()
                        .fill(editor.phaseColor(phase.phase).opacity(0.7))
                        .frame(width: max(2, geo.size.width * widthFrac))
                        .offset(x: geo.size.width * startFrac)
                }

                Rectangle()
                    .fill(Color.primary.opacity(0.08))
                    .overlay(
                        Rectangle().strokeBorder(Color.primary.opacity(0.45), lineWidth: 1)
                    )
                    .frame(width: max(4, geo.size.width * editor.viewSpan))
                    .offset(x: geo.size.width * editor.viewStart)
                    .allowsHitTesting(false)

                Rectangle()
                    .fill(Color.white.opacity(0.9))
                    .frame(width: 1.5)
                    .offset(x: (editor.currentTime / editor.duration) * geo.size.width)
                    .allowsHitTesting(false)
            }
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let frac = max(0, min(1, value.location.x / max(geo.size.width, 1)))
                        editor.seek(to: frac * editor.duration)
                        let newStart = max(0, min(1 - editor.viewSpan, frac - editor.viewSpan / 2))
                        editor.viewStart = newStart
                        editor.viewEnd = newStart + editor.viewSpan
                    }
            )
        }
        .frame(height: 24)
    }

    func transportBar(_ editor: LabelingDetailEditor) -> some View {
        VStack(spacing: 8) {
            HStack {
                Text(editor.formatTime(editor.currentTime))
                    .monospacedDigit()
                    .font(.callout)

                Spacer()

                HStack(spacing: 6) {
                    Button("Zoom In", systemImage: "plus.magnifyingglass") { editor.zoomIn() }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.plain)
                    Button("Zoom Out", systemImage: "minus.magnifyingglass") { editor.zoomOut() }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.plain)
                    Button("Fit All", systemImage: "arrow.left.and.right.magnifyingglass") {
                        editor.zoomFit()
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                }

                Spacer()

                Text(editor.formatTime(editor.draft.audioDuration))
                    .monospacedDigit()
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                Button { editor.seekRelative(-300) } label: {
                    Text("−5m").monospacedDigit().font(.callout)
                }
                Button { editor.seekRelative(-60) } label: {
                    Text("−1m").monospacedDigit().font(.callout)
                }
                Button("Back 10s", systemImage: "gobackward.10") { editor.seekRelative(-10) }
                    .labelStyle(.iconOnly)
                    .keyboardShortcut(.leftArrow, modifiers: [])

                Button(
                    editor.isPlaying ? "Pause" : "Play",
                    systemImage: editor.isPlaying ? "pause.fill" : "play.fill"
                ) {
                    editor.togglePlayback()
                }
                .font(.title2)
                .keyboardShortcut(KeyEquivalent(" "), modifiers: [])

                Button("Forward 10s", systemImage: "goforward.10") { editor.seekRelative(10) }
                    .labelStyle(.iconOnly)
                    .keyboardShortcut(.rightArrow, modifiers: [])
                Button { editor.seekRelative(60) } label: {
                    Text("+1m").monospacedDigit().font(.callout)
                }
                Button { editor.seekRelative(300) } label: {
                    Text("+5m").monospacedDigit().font(.callout)
                }
            }
            .buttonStyle(.plain)
        }
    }

    func phaseButtons(_ editor: LabelingDetailEditor) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Mark phase at playhead")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.bottom, 2)

            ForEach(Array(editor.orderedPhases.enumerated()), id: \.element) { index, phase in
                Button {
                    editor.markPhaseStart(phase)
                } label: {
                    HStack(spacing: 6) {
                        Text("\(index + 1)")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 12, alignment: .trailing)
                        Circle()
                            .fill(editor.phaseColor(phase))
                            .frame(width: 8, height: 8)
                        Text(phase.displayName)
                            .font(.callout)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: [])
            }

            Spacer()

            Button("Clear All Phases", role: .destructive) {
                editor.clearAllPhases()
            }
            .font(.caption)
            .foregroundStyle(.red)
        }
    }

    func phaseListPanel(_ editor: LabelingDetailEditor) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Phases (\(editor.draft.phases.count))")
                .font(.caption)
                .foregroundStyle(.secondary)

            if editor.draft.phases.isEmpty {
                Text("No phases marked yet.\nPlay and press 1–7 at each boundary.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(editor.draft.phases.enumerated()), id: \.element.id) { index, phase in
                            phaseRow(phase: phase, index: index, editor: editor)
                            if index < editor.draft.phases.count - 1 { Divider() }
                        }
                    }
                }
            }
        }
    }

    func phaseRow(
        phase: LabeledFile.LabeledPhase,
        index: Int,
        editor: LabelingDetailEditor
    ) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(editor.phaseColor(phase.phase))
                .frame(width: 8, height: 8)
            Text(phase.phase.displayName)
                .bold()
                .font(.callout)
            Spacer()
            Button("Jump", systemImage: "arrow.right.to.line") {
                editor.jumpToPhase(phase)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .font(.caption)
            Text("\(editor.formatTime(phase.startTime)) – \(editor.formatTime(phase.endTime))")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Button("Remove", systemImage: "minus.circle") {
                editor.removePhase(at: index)
            }
            .labelStyle(.iconOnly)
            .foregroundStyle(.secondary)
            .font(.caption)
            .buttonStyle(.plain)
        }
        .padding(.vertical, 5)
    }

    func metadataBar(_ editor: LabelingDetailEditor) -> some View {
        HStack(spacing: 16) {
            Picker("Type", selection: Binding(
                get: { editor.draft.expectedContentType },
                set: { editor.draft.expectedContentType = $0 }
            )) {
                ForEach(AudioContentType.allCases, id: \.self) { type in
                    Text(type.rawValue.capitalized).tag(type)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: 160)

            Menu {
                Button("Delta/Theta  0.5–6 Hz") {
                    editor.draft.expectedFrequencyBand = .init(lower: 0.5, upper: 6.0)
                }
                Button("Theta  4–8 Hz") {
                    editor.draft.expectedFrequencyBand = .init(lower: 4.0, upper: 8.0)
                }
                Button("Low Alpha  6–8 Hz") {
                    editor.draft.expectedFrequencyBand = .init(lower: 6.0, upper: 8.0)
                }
                Button("Alpha  8–12 Hz") {
                    editor.draft.expectedFrequencyBand = .init(lower: 8.0, upper: 12.0)
                }
                Button("Upper Alpha  9–11 Hz") {
                    editor.draft.expectedFrequencyBand = .init(lower: 9.0, upper: 11.0)
                }
                Button("SMR/Beta  12–18 Hz") {
                    editor.draft.expectedFrequencyBand = .init(lower: 12.0, upper: 18.0)
                }
            } label: {
                let lower = editor.draft.expectedFrequencyBand.lower
                    .formatted(.number.precision(.fractionLength(1)))
                let upper = editor.draft.expectedFrequencyBand.upper
                    .formatted(.number.precision(.fractionLength(1)))
                Label("\(lower)–\(upper) Hz", systemImage: "waveform")
            }

            TextField("Notes…", text: Binding(
                get: { editor.draft.labelerNotes },
                set: { editor.draft.labelerNotes = $0 }
            ))
            .textFieldStyle(.roundedBorder)
        }
    }

    func statusBadge(_ editor: LabelingDetailEditor) -> some View {
        let (label, color): (String, Color) = switch editor.draft.status {
        case .unlabeled: ("Unlabeled", .secondary)
        case .rough:     ("Rough", .orange)
        case .refined:   ("Refined", .green)
        }
        return Text(label)
            .font(.caption)
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15), in: Capsule())
    }
}
