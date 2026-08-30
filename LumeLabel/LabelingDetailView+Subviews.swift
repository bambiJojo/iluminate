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
                    drawTransitionCandidates(&context, size: size, editor: editor)
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
                    .onEnded { value in
                        guard abs(value.translation.width) < 4,
                              abs(value.translation.height) < 4 else { return }
                        let time = editor.timeForViewX(value.location.x, width: geo.size.width)
                        let tolerance = max(0.5, editor.viewSpan * editor.duration * 0.015)
                        editor.selectNearestTransitionCandidate(to: time, tolerance: tolerance)
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
                .opacity(isVisible ? (editor.isAnalyzerReviewMode ? 0.65 : 1) : 0)
                .allowsHitTesting(isVisible && !editor.isAnalyzerReviewMode)
                .highPriorityGesture(
                    DragGesture(minimumDistance: 2)
                        .onChanged { value in
                            editor.draggingPointID = point.id
                            let time = editor.timeForViewX(value.location.x, width: size.width)
                            editor.movePhasePoint(id: point.id, to: time)
                        }
                        .onEnded { value in
                            let time = editor.timeForViewX(value.location.x, width: size.width)
                            editor.movePhasePoint(id: point.id, to: time)
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

                    if !point.isInitial {
                        Divider()

                        Button("Delete Boundary", role: .destructive) {
                            editor.deletePhasePoint(id: point.id)
                        }
                    }
                }
        }
    }

    func overviewStrip(_ editor: LabelingDetailEditor) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(nsColor: .underPageBackgroundColor))

                ForEach(editor.labelingSegments) { segment in
                    let startFrac = segment.startTime / editor.duration
                    let widthFrac = (segment.endTime - segment.startTime) / editor.duration
                    Rectangle()
                        .fill(editor.phaseColor(segment.phase).opacity(0.7))
                        .frame(width: max(2, geo.size.width * widthFrac))
                        .offset(x: geo.size.width * startFrac)
                }

                ForEach(editor.transitionCandidates) { candidate in
                    let decision = editor.candidateDecision(for: candidate.id)
                    Rectangle()
                        .fill(
                            transitionCandidateColor(candidate, decision: decision)
                                .opacity(decision == .dismissed ? 0.12 : 0.85)
                        )
                        .frame(width: editor.selectedTransitionCandidateID == candidate.id ? 3 : 2)
                        .offset(x: (candidate.time / editor.duration) * geo.size.width)
                        .allowsHitTesting(false)
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
                    Button("Fit All", systemImage: "arrow.left.and.right") {
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
                if editor.isAudioPreparing {
                    ProgressView()
                        .controlSize(.small)
                        .help("Preparing audio in the background")
                }

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
        VStack(alignment: .leading, spacing: 8) {
            if editor.isAnalyzerReviewMode {
                Label("Analyzer review", systemImage: "lock.shield.fill")
                    .font(.headline)

                Text("The saved blind timeline is locked. Review suggestions against what you already labeled; they cannot edit it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                transitionCandidateReviewPanel(editor)
            } else {
                switch editor.labelingPass {
                case .boundaries:
                    Label("1. Find transitions", systemImage: "timeline.selection")
                        .font(.headline)

                    Text("Scrub through the file. When you find a transition, place the playhead precisely and press B to mark it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button("Mark at Playhead", systemImage: "plus") {
                        editor.markBoundaryAtPlayhead()
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut("b", modifiers: [])

                    Text("\(editor.boundaryCount) transition\(editor.boundaryCount == 1 ? "" : "s") marked")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button("Name Phase Segments", systemImage: "arrow.right") {
                        editor.beginPhaseNaming()
                    }
                    .buttonStyle(.bordered)

                case .phaseNames:
                    Label("2. Name segments", systemImage: "tag")
                        .font(.headline)

                    if let selectedSegment = editor.selectedSegment {
                        Text("Selected: \(editor.formatTime(selectedSegment.startTime))–\(editor.formatTime(selectedSegment.endTime))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }

                    if editor.unassignedSegmentCount == 0 {
                        Label("All segments named", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(editor.isReadyToSave ? .green : .orange)
                    } else {
                        Text("\(editor.unassignedSegmentCount) remaining")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }

                    if let validationMessage = editor.labelValidationMessage,
                       editor.unassignedSegmentCount == 0 {
                        Label(validationMessage, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }

                    ForEach(Array(editor.orderedPhases.enumerated()), id: \.element) { index, phase in
                        if let shortcut = editor.keyboardShortcutLabel(for: index) {
                            Button {
                                editor.assignSelectedPhase(phase)
                            } label: {
                                phaseButtonLabel(
                                    title: phase.displayName,
                                    color: editor.phaseColor(phase),
                                    shortcut: shortcut
                                )
                            }
                            .buttonStyle(.plain)
                            .keyboardShortcut(KeyEquivalent(Character(shortcut)), modifiers: [])
                            .disabled(editor.selectedSegment == nil)
                        }
                    }

                    Button("Back to Transitions", systemImage: "arrow.left") {
                        editor.resumeBoundaryMarking()
                    }
                    .buttonStyle(.bordered)
                }

                Spacer()

                if editor.canEnterAnalyzerReview {
                    Divider()

                    Button("Review Analyzer", systemImage: "lock.open") {
                        isConfirmingAnalyzerReview = true
                    }
                    .buttonStyle(.borderedProminent)

                    Text("Reveals model suggestions only after preserving these saved labels as the blind baseline.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Button("Clear Timeline", role: .destructive) {
                    editor.clearAllPhases()
                }
                .font(.caption)
                .foregroundStyle(.red)
            }
        }
    }

    @ViewBuilder
    func transitionCandidateReviewPanel(_ editor: LabelingDetailEditor) -> some View {
        Divider()

        Label("Candidate review", systemImage: "scope")
            .font(.subheadline.weight(.semibold))

        Text("Cyan marks tone changes; purple marks meaning changes. Record whether each suggestion matches the locked labels.")
            .font(.caption2)
            .foregroundStyle(.secondary)

        VStack(alignment: .leading, spacing: 6) {
            Button(
                editor.backgroundToneAnalysis == nil ? "Scan Background Tones" : "Rescan Background Tones",
                systemImage: "waveform.and.magnifyingglass"
            ) {
                Task { await editor.analyzeBackgroundTones() }
            }
            .controlSize(.small)
            .disabled(editor.isBackgroundToneAnalysisRunning)

            if editor.hasTranscript {
                Button(
                    editor.semanticPhaseAnalysis == nil ? "Scan Transcript Meaning" : "Rescan Transcript Meaning",
                    systemImage: "brain.head.profile"
                ) {
                    Task { await editor.analyzeSemanticWindows() }
                }
                .controlSize(.small)
                .disabled(editor.isSemanticPhaseAnalysisRunning)
            }
        }

        if editor.isBackgroundToneAnalysisRunning || editor.isSemanticPhaseAnalysisRunning {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Finding candidates…")
                    .font(.caption)
                Spacer(minLength: 0)
                Button("Cancel") {
                    editor.cancelBackgroundToneAnalysis()
                    editor.cancelSemanticPhaseAnalysis()
                }
                .font(.caption)
            }
        }

        if editor.transitionCandidates.isEmpty == false {
            Text(
                "\(editor.pendingTransitionCandidates.count) pending · \(editor.acceptedCandidateCount) matched · \(editor.dismissedCandidateCount) dismissed"
            )
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Button("Previous", systemImage: "chevron.left") {
                    editor.jumpToPreviousTransitionCandidate()
                }
                .labelStyle(.iconOnly)
                .keyboardShortcut("[", modifiers: [])
                .help("Previous pending candidate ([)")

                Menu(
                    editor.selectedTransitionCandidate.map {
                        "\($0.source.displayName) · \(editor.formatTime($0.time))"
                    } ?? "Choose candidate"
                ) {
                    ForEach(editor.pendingTransitionCandidates) { candidate in
                        Button(
                            "\(candidate.source.displayName) · \(editor.formatTime(candidate.time))"
                        ) {
                            editor.jumpToTransitionCandidate(candidate)
                        }
                    }
                }
                .menuStyle(.borderlessButton)

                Button("Next", systemImage: "chevron.right") {
                    editor.jumpToNextTransitionCandidate()
                }
                .labelStyle(.iconOnly)
                .keyboardShortcut("]", modifiers: [])
                .help("Next pending candidate (])")
            }

            if let candidate = editor.selectedTransitionCandidate {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(transitionCandidateColor(candidate, decision: nil))
                            .frame(width: 7, height: 7)
                        Text(candidate.source.displayName)
                            .font(.caption.weight(.semibold))
                        Spacer(minLength: 0)
                        Text(editor.formatTime(candidate.time))
                            .font(.caption.monospacedDigit())
                    }

                    if let suggestedPhase = candidate.suggestedPhase {
                        Text("Likely next phase: \(suggestedPhase.displayName)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 6) {
                        Button("Matches") {
                            editor.acceptSelectedTransitionCandidate()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .keyboardShortcut("m", modifiers: [])
                        .help("Record that this matches the locked labels (M)")

                        Button("Dismiss") {
                            editor.dismissSelectedTransitionCandidate()
                        }
                        .controlSize(.small)
                        .keyboardShortcut("d", modifiers: [])
                        .help("Record that this does not match the locked labels (D)")
                    }
                }
                .padding(8)
                .background(
                    transitionCandidateColor(candidate, decision: nil).opacity(0.08),
                    in: RoundedRectangle(cornerRadius: 8)
                )
            } else if editor.pendingTransitionCandidates.isEmpty == false {
                Text("Press ] for the next candidate, or click a marker on the timeline.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }

        if let status = editor.backgroundToneStatusMessage {
            Text(status)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }

        if let error = editor.backgroundToneErrorMessage {
            Text(error)
                .font(.caption2)
                .foregroundStyle(.red)
        }

        if let error = editor.semanticPhaseErrorMessage {
            Text(error)
                .font(.caption2)
                .foregroundStyle(.red)
        }
    }

    func phaseListPanel(_ editor: LabelingDetailEditor) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Segments (\(editor.labelingSegments.count))")
                Spacer()
                if editor.isAnalyzerReviewMode {
                    Label("Blind baseline", systemImage: "lock.fill")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(editor.labelingSegments.enumerated()), id: \.element.id) { index, segment in
                        phaseRow(segment: segment, index: index, editor: editor)
                        if index < editor.labelingSegments.count - 1 {
                            Divider()
                                .padding(.leading, 16)
                        }
                    }
                }
            }
        }
    }

    func phaseRow(
        segment: TransitionLabelingDraft.Segment,
        index: Int,
        editor: LabelingDetailEditor
    ) -> some View {
        let isSelected = editor.selectedPhaseID == segment.id
        let color = editor.phaseColor(segment.phase)

        return HStack(spacing: 8) {
            Button {
                editor.selectPhase(id: segment.id)
            } label: {
                HStack(spacing: 8) {
                    Circle()
                        .fill(color)
                        .frame(width: 8, height: 8)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(editor.phaseDisplayName(segment.phase))
                            .bold()
                            .font(.callout)
                        Text("\(editor.formatTime(segment.startTime)) – \(editor.formatTime(segment.endTime))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }

                    Spacer()
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isSelected ? color.opacity(0.12) : .clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isSelected ? color.opacity(0.35) : .clear, lineWidth: 1)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button("Jump", systemImage: "arrow.right.to.line") {
                editor.jumpToSegment(segment)
                editor.selectPhase(id: segment.id)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .font(.caption)

            if index > 0 && !editor.isAnalyzerReviewMode {
                Button("Remove Boundary", systemImage: "minus.circle") {
                    editor.removePhase(at: index)
                }
                .labelStyle(.iconOnly)
                .foregroundStyle(.secondary)
                .font(.caption)
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 5)
    }

    func transcriptInspector(_ editor: LabelingDetailEditor) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(editor.phaseDisplayName(editor.selectedSegment?.phase))
                        .font(.headline)
                    if let insight = editor.activeTranscriptInsight {
                        Text("\(editor.formatTime(insight.startTime)) – \(editor.formatTime(insight.endTime))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    } else {
                        Text("Generate or load a transcript to inspect section language.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 8) {
                    Button(editor.hasTranscript ? "Refresh Transcript" : "Generate Transcript") {
                        Task { await editor.generateTranscript() }
                    }
                    .disabled(editor.isTranscriptLoading)

                    if editor.isAnalyzerReviewMode && editor.hasTranscript {
                        Button(editor.suggestedPhaseTimeline == nil ? "Suggest Phases" : "Refresh Suggestions") {
                            Task { await editor.generatePhaseSuggestions() }
                        }
                        .disabled(editor.isSuggestionLoading)
                    }

                    if editor.isAnalyzerReviewMode && editor.hasTranscript && editor.isReadyToSave {
                        if editor.isDiagnosticsLoading {
                            Button("Cancel Analysis", role: .cancel) {
                                editor.cancelAnalyzerDiagnostics()
                            }
                        } else {
                            Button(editor.analyzerDiagnostics == nil ? "Analyze vs Labels" : "Refresh Diagnostics") {
                                Task { await editor.refreshAnalyzerDiagnostics() }
                            }
                        }
                    }
                }
            }

            if let transcriptStatusMessage = editor.transcriptStatusMessage, !transcriptStatusMessage.isEmpty {
                Label(transcriptStatusMessage, systemImage: editor.isTranscriptLoading ? "waveform" : "text.alignleft")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if editor.isAnalyzerReviewMode,
               let diagnosticsStatusMessage = editor.diagnosticsStatusMessage,
               !diagnosticsStatusMessage.isEmpty {
                Label(
                    diagnosticsStatusMessage,
                    systemImage: editor.isDiagnosticsLoading ? "waveform.and.magnifyingglass" : "chart.bar.doc.horizontal"
                )
                .font(.caption)
                .foregroundStyle(editor.diagnosticsAreStale ? .orange : .secondary)

                if let progress = editor.diagnosticsProgress {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                }
            }

            if editor.isAnalyzerReviewMode,
               let suggestionStatusMessage = editor.suggestionStatusMessage,
               !suggestionStatusMessage.isEmpty {
                Label(
                    suggestionStatusMessage,
                    systemImage: editor.isSuggestionLoading ? "wand.and.stars.inverse" : "sparkles.rectangle.stack"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if editor.isAnalyzerReviewMode,
               let semanticPhaseStatusMessage = editor.semanticPhaseStatusMessage,
               !semanticPhaseStatusMessage.isEmpty {
                Label(
                    semanticPhaseStatusMessage,
                    systemImage: editor.isSemanticPhaseAnalysisRunning
                        ? "brain.head.profile"
                        : "text.bubble"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if let transcriptErrorMessage = editor.transcriptErrorMessage, !transcriptErrorMessage.isEmpty {
                ContentUnavailableView(
                    "Transcript Unavailable",
                    systemImage: "exclamationmark.triangle",
                    description: Text(transcriptErrorMessage)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if editor.isTranscriptLoading {
                VStack(alignment: .leading, spacing: 10) {
                    ProgressView()
                    Text("WhisperKit is generating a transcript for this audio so the selected section can be analyzed.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else if let insight = editor.activeTranscriptInsight {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        transcriptMetrics(insight, editor: editor)
                        if editor.isAnalyzerReviewMode {
                            phaseSuggestionsSection(editor)
                            semanticPhaseSection(editor)
                            analyzerDiagnosticsSection(editor)
                        }
                        topWordSection(insight)
                        excerptSection(insight, editor: editor)
                    }
                    .padding(.vertical, 2)
                }
            } else {
                ContentUnavailableView(
                    "No Transcript Yet",
                    systemImage: "text.alignleft",
                    description: Text("Generate a transcript to review language, word frequency, pace, and section-level stats.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    func transcriptMetrics(
        _ insight: LabelingDetailEditor.PhaseTranscriptInsight,
        editor: LabelingDetailEditor
    ) -> some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 120), spacing: 10)],
            alignment: .leading,
            spacing: 10
        ) {
            transcriptMetricCard("Words", value: insight.wordCount.formatted(), systemImage: "textformat.abc")
            transcriptMetricCard("Unique", value: insight.uniqueWordCount.formatted(), systemImage: "number")
            transcriptMetricCard("Word Rate", value: "\(Int(insight.wordsPerMinute.rounded())) WPM", systemImage: "speedometer")
            transcriptMetricCard(
                "Pace vs Avg",
                value: relativeMetricText(for: insight.normalizedWordsPerMinute),
                systemImage: "speedometer"
            )
            transcriptMetricCard("Speech", value: insight.speechCoverage.formatted(.percent.precision(.fractionLength(0))), systemImage: "waveform")
            transcriptMetricCard(
                "Speech vs Avg",
                value: relativeMetricText(for: insight.normalizedSpeechCoverage),
                systemImage: "waveform"
            )
            transcriptMetricCard("Longest Pause", value: editor.formatTime(insight.longestPause), systemImage: "pause.circle")
            transcriptMetricCard(
                "Avg Segment",
                value: "\(insight.averageSegmentDuration.formatted(.number.precision(.fractionLength(1))))s",
                systemImage: "rectangle.split.1x2"
            )
            transcriptMetricCard(
                "Variety",
                value: insight.lexicalDiversity.formatted(.percent.precision(.fractionLength(0))),
                systemImage: "chart.bar.doc.horizontal"
            )
            transcriptMetricCard(
                "Variety vs Avg",
                value: relativeMetricText(for: insight.normalizedLexicalDiversity),
                systemImage: "chart.bar.doc.horizontal"
            )
            transcriptMetricCard(
                "Repetition",
                value: insight.repetitionDensity.formatted(.percent.precision(.fractionLength(0))),
                systemImage: "repeat"
            )
            transcriptMetricCard(
                "Repetition vs Avg",
                value: relativeMetricText(for: insight.normalizedRepetitionDensity),
                systemImage: "repeat"
            )
            transcriptMetricCard("Chunks", value: insight.excerpts.count.formatted(), systemImage: "list.bullet.rectangle")
        }
    }

    func phaseSuggestionsSection(_ editor: LabelingDetailEditor) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Phrase-Library Suggestions")
                    .font(.headline)
                Spacer()
                if !editor.suggestedPhaseSegments.isEmpty {
                    Label("Read-only", systemImage: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let suggestionErrorMessage = editor.suggestionErrorMessage, !suggestionErrorMessage.isEmpty {
                Text(suggestionErrorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
            } else if editor.isSuggestionLoading {
                VStack(alignment: .leading, spacing: 8) {
                    ProgressView()
                    Text("Scanning transcript windows for hypnosis way-markers, phrase-library matches, and likely phase transitions.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            } else if let suggestionTimeline = editor.suggestedPhaseTimeline, !editor.suggestedPhaseSegments.isEmpty {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 140), spacing: 10)],
                    alignment: .leading,
                    spacing: 10
                ) {
                    transcriptMetricCard("Suggested Segments", value: editor.suggestedPhaseSegments.count.formatted(), systemImage: "timeline.selection")
                    transcriptMetricCard("Evidence Windows", value: suggestionTimeline.windows.count.formatted(), systemImage: "rectangle.split.3x1")
                    transcriptMetricCard(
                        "Avg Confidence",
                        value: suggestionTimeline.averageConfidence.formatted(.percent.precision(.fractionLength(0))),
                        systemImage: "sparkles"
                    )
                    transcriptMetricCard(
                        "Current Labels",
                        value: editor.labelingSegments.count.formatted(),
                        systemImage: "checklist"
                    )
                }

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(editor.suggestedPhaseSegments) { segment in
                        suggestedPhaseRow(segment, editor: editor)
                    }
                }
            } else if editor.canSuggestPhases {
                Text("Run suggestions to decode the transcript into a forward-moving hypnosis timeline using phrase evidence, way-markers, and session position.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Text("Generate a transcript before building phrase-driven suggestions.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    func suggestedPhaseRow(
        _ segment: LabelingDetailEditor.SuggestedPhaseSegment,
        editor: LabelingDetailEditor
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(editor.phaseColor(segment.phase))
                .frame(width: 9, height: 9)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(segment.phase.displayName)
                        .font(.callout.weight(.semibold))
                    Spacer()
                    Text(segment.confidence.formatted(.percent.precision(.fractionLength(0))))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                Text("\(editor.formatTime(segment.startTime)) – \(editor.formatTime(segment.endTime))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()

                if let rationale = segment.rationale, !rationale.isEmpty {
                    Text(rationale)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Button("Jump", systemImage: "arrow.right.to.line") {
                editor.jumpToSuggestedPhase(segment)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(Color(nsColor: .underPageBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
    }

    func semanticPhaseSection(_ editor: LabelingDetailEditor) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Semantic Window Experiment")
                    .font(.headline)
                Text("Experimental")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.purple.opacity(0.14), in: Capsule())
                    .foregroundStyle(.purple)
                Spacer()

                if editor.isSemanticPhaseAnalysisRunning {
                    Button("Cancel") {
                        editor.cancelSemanticPhaseAnalysis()
                    }
                    .controlSize(.small)
                } else {
                    Button(editor.semanticPhaseAnalysis == nil ? "Analyze Meaning" : "Analyze Again") {
                        Task { await editor.analyzeSemanticWindows() }
                    }
                    .controlSize(.small)
                    .disabled(editor.hasTranscript == false)
                }
            }

            Text("Compares overlapping 28-word transcript windows with excerpts from your hand-labeled phases using Apple's on-device sentence embedding. These results never change labels automatically.")
                .font(.callout)
                .foregroundStyle(.secondary)

            if let semanticPhaseErrorMessage = editor.semanticPhaseErrorMessage,
               !semanticPhaseErrorMessage.isEmpty {
                Text(semanticPhaseErrorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
            } else if editor.isSemanticPhaseAnalysisRunning {
                ProgressView()
            } else if let analysis = editor.semanticPhaseAnalysis {
                if analysis.exampleCount == 0 {
                    Text("No hand-labeled transcript excerpts are available. Label and transcribe more phase sections before evaluating semantic matching.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 140), spacing: 10)],
                        alignment: .leading,
                        spacing: 10
                    ) {
                        transcriptMetricCard(
                            "Labeled Examples",
                            value: analysis.exampleCount.formatted(),
                            systemImage: "text.quote"
                        )
                        transcriptMetricCard(
                            "Meaning Windows",
                            value: analysis.windows.count.formatted(),
                            systemImage: "rectangle.split.3x1"
                        )
                        transcriptMetricCard(
                            "Tentative Runs",
                            value: analysis.segments.count.formatted(),
                            systemImage: "timeline.selection"
                        )
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(analysis.segments.prefix(30))) { segment in
                            semanticPhaseSegmentRow(segment, editor: editor)
                        }
                    }

                    if analysis.segments.count > 30 {
                        Text("Showing the first 30 of \(analysis.segments.count) tentative runs.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Text("Run this independently from phrase-library suggestions so their results can be compared by ear.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    func semanticPhaseSegmentRow(
        _ segment: SemanticPhaseAnalyzer.Segment,
        editor: LabelingDetailEditor
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(editor.phaseColor(segment.phase))
                .frame(width: 9, height: 9)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(segment.phase.displayName)
                        .font(.callout.weight(.semibold))
                    Spacer()
                    Text(segment.confidence.formatted(.percent.precision(.fractionLength(0))))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                Text("\(editor.formatTime(segment.startTime)) – \(editor.formatTime(segment.endTime)) · \(segment.windowCount) windows")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()

                Text("Closest labeled excerpt: \(segment.matchedExampleText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Button("Jump", systemImage: "arrow.right.to.line") {
                editor.jumpToSemanticSegment(segment)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(Color.purple.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
    }

    func analyzerDiagnosticsSection(_ editor: LabelingDetailEditor) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Analyzer Diagnostics")
                    .font(.headline)

                if editor.diagnosticsAreStale {
                    Text("Stale")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.orange.opacity(0.15), in: Capsule())
                        .foregroundStyle(.orange)
                }
            }

            if let diagnosticsErrorMessage = editor.diagnosticsErrorMessage, !diagnosticsErrorMessage.isEmpty {
                Text(diagnosticsErrorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
            } else if editor.isDiagnosticsLoading {
                VStack(alignment: .leading, spacing: 8) {
                    ProgressView()
                    Text("Comparing the analyzer's predicted phase timeline against your labeled sections.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            } else if let diagnostics = editor.analyzerDiagnostics {
                analyzerDiagnosticsSummary(diagnostics, editor: editor)

                if let comparison = editor.selectedPhaseComparison {
                    selectedPhaseComparisonCard(comparison, editor: editor)
                }

                comparisonRows(diagnostics.comparisons, editor: editor)
                techniqueMarkerSection(diagnostics, editor: editor)
            } else if editor.canRunAnalyzerDiagnostics {
                Text("Run diagnostics to compare the current analyzer output against your labels and inspect where boundaries or phase names disagree.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Text("Add labels and a transcript to compare the analyzer against your hand-labeled phase timeline.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    func analyzerDiagnosticsSummary(
        _ diagnostics: LabelingDetailEditor.AnalyzerDiagnostics,
        editor: LabelingDetailEditor
    ) -> some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 140), spacing: 10)],
            alignment: .leading,
            spacing: 10
        ) {
            transcriptMetricCard("Engine", value: diagnostics.engine.displayName, systemImage: "cpu")
            transcriptMetricCard(
                "Matches",
                value: "\(diagnostics.labeledMatchCount)/\(diagnostics.comparisons.count)",
                systemImage: "checkmark.circle"
            )
            transcriptMetricCard(
                "Mismatches",
                value: diagnostics.mismatchCount.formatted(),
                systemImage: "exclamationmark.triangle"
            )
            transcriptMetricCard(
                "Avg Boundary Error",
                value: diagnostics.averageBoundaryError.map(editor.formatTime) ?? "N/A",
                systemImage: "arrow.left.and.right"
            )
            transcriptMetricCard(
                "Predicted Segments",
                value: diagnostics.predictedPhases.count.formatted(),
                systemImage: "timeline.selection"
            )
            transcriptMetricCard(
                "Technique Markers",
                value: diagnostics.techniqueMarkers.count.formatted(),
                systemImage: "sparkles"
            )
        }
    }

    func selectedPhaseComparisonCard(
        _ comparison: LabelingDetailEditor.AnalyzerPhaseComparison,
        editor: LabelingDetailEditor
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Selected Phase Check")
                .font(.headline)

            HStack(alignment: .top, spacing: 12) {
                comparisonPill(title: "Labeled", value: comparison.labeledPhase.displayName, color: editor.phaseColor(comparison.labeledPhase))
                comparisonPill(
                    title: "Predicted",
                    value: comparison.predictedPhase?.displayName ?? "None",
                    color: comparison.predictedPhase.map(editor.phaseColor) ?? .gray
                )
                comparisonPill(
                    title: "Overlap",
                    value: comparison.overlapFraction.formatted(.percent.precision(.fractionLength(0))),
                    color: comparison.isMatch ? .green : .orange
                )
            }

            if let predictedRationale = comparison.predictedRationale, !predictedRationale.isEmpty {
                Text(predictedRationale)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if !comparison.evidenceWords.isEmpty {
                HStack {
                    ForEach(comparison.evidenceWords) { keyword in
                        Text(keyword.word)
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(Color(nsColor: .underPageBackgroundColor), in: Capsule())
                    }
                }
            }
        }
        .padding(12)
        .background(Color(nsColor: .underPageBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
    }

    func comparisonPill(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout.weight(.semibold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
    }

    func comparisonRows(
        _ comparisons: [LabelingDetailEditor.AnalyzerPhaseComparison],
        editor: LabelingDetailEditor
    ) -> some View {
        AnalyzerComparisonRowsView(comparisons: comparisons, editor: editor)
    }

    func techniqueMarkerSection(
        _ diagnostics: LabelingDetailEditor.AnalyzerDiagnostics,
        editor: LabelingDetailEditor
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Detected Techniques")
                .font(.headline)

            if diagnostics.techniqueMarkers.isEmpty {
                Text("No technique markers were detected in this transcript yet.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(diagnostics.techniqueMarkers.prefix(12))) { marker in
                    HStack(alignment: .top, spacing: 10) {
                        Text(editor.formatTime(marker.timestamp))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 54, alignment: .leading)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(marker.type.rawValue.replacingOccurrences(of: "_", with: " ").capitalized)
                                .font(.callout.weight(.medium))
                            if let snippet = marker.textSnippet, !snippet.isEmpty {
                                Text(snippet)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()

                        Text("\(Int((marker.strength * 100).rounded()))%")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .padding(10)
                    .background(Color(nsColor: .underPageBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                }
            }
        }
    }

    func topWordSection(_ insight: LabelingDetailEditor.PhaseTranscriptInsight) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Most Used Words")
                .font(.headline)

            if insight.topWords.isEmpty {
                Text("No meaningful repeated words were found in this section yet.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 150), spacing: 8)],
                    alignment: .leading,
                    spacing: 8
                ) {
                    ForEach(insight.topWords) { keyword in
                        HStack {
                            Text(keyword.word)
                                .font(.callout.weight(.medium))
                            Spacer(minLength: 8)
                            Text(keyword.count.formatted())
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(Color(nsColor: .underPageBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                    }
                }
            }

            if insight.phase != nil {
                Text("Distinctive Words")
                    .font(.headline)
                    .padding(.top, 6)

                if insight.topDistinctiveWords.isEmpty {
                    Text("No standout words rose meaningfully above this file's baseline in this section.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 170), spacing: 8)],
                        alignment: .leading,
                        spacing: 8
                    ) {
                        ForEach(insight.topDistinctiveWords) { keyword in
                            HStack(alignment: .firstTextBaseline) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(keyword.word)
                                        .font(.callout.weight(.medium))
                                    if let relativeWeight = keyword.relativeWeight {
                                        Text(relativeMetricText(for: relativeWeight))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer(minLength: 8)
                                Text(keyword.count.formatted())
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(Color(nsColor: .underPageBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }
            }
        }
    }

    func excerptSection(
        _ insight: LabelingDetailEditor.PhaseTranscriptInsight,
        editor: LabelingDetailEditor
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Section Transcript")
                .font(.headline)

            if insight.excerpts.isEmpty {
                Text("No transcript text overlaps this labeled section.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(insight.excerpts) { excerpt in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(editor.formatTime(excerpt.startTime)) – \(editor.formatTime(excerpt.endTime))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                            Text(excerpt.text)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(10)
                        .background(Color(nsColor: .underPageBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
        }
    }

    func transcriptMetricCard(
        _ title: String,
        value: String,
        systemImage: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: systemImage)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color(nsColor: .underPageBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
    }

    func relativeMetricText(for value: Double) -> String {
        let percent = Int((value * 100).rounded())
        if abs(value - 1) < 0.05 {
            return "\(percent)% of avg"
        }
        if value > 1 {
            return "\(percent)% of avg, above"
        }
        return "\(percent)% of avg, below"
    }

    func phaseButtonLabel(
        title: String,
        color: Color,
        shortcut: String?
    ) -> some View {
        HStack(spacing: 6) {
            Text(shortcut ?? "•")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 12, alignment: .trailing)
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(title)
                .font(.callout)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    func metadataBar(_ editor: LabelingDetailEditor) -> some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Corpus")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Label("Hypnosis", systemImage: "brain.head.profile")
                    .font(.callout)
            }
            .frame(maxWidth: 160, alignment: .leading)
            .help("This labeler corpus is for hypnosis sessions. Capture style differences in phases, techniques, and notes.")

            Menu {
                Button("Delta/Theta  0.5–6 Hz") {
                    editor.setExpectedFrequencyBand(.init(lower: 0.5, upper: 6.0))
                }
                Button("Theta  4–8 Hz") {
                    editor.setExpectedFrequencyBand(.init(lower: 4.0, upper: 8.0))
                }
                Button("Low Alpha  6–8 Hz") {
                    editor.setExpectedFrequencyBand(.init(lower: 6.0, upper: 8.0))
                }
                Button("Alpha  8–12 Hz") {
                    editor.setExpectedFrequencyBand(.init(lower: 8.0, upper: 12.0))
                }
                Button("Upper Alpha  9–11 Hz") {
                    editor.setExpectedFrequencyBand(.init(lower: 9.0, upper: 11.0))
                }
                Button("SMR/Beta  12–18 Hz") {
                    editor.setExpectedFrequencyBand(.init(lower: 12.0, upper: 18.0))
                }
            } label: {
                let lower = editor.draft.expectedFrequencyBand.lower
                    .formatted(.number.precision(.fractionLength(1)))
                let upper = editor.draft.expectedFrequencyBand.upper
                    .formatted(.number.precision(.fractionLength(1)))
                Label("\(lower)–\(upper) Hz", systemImage: "waveform")
            }
            .disabled(editor.isAnalyzerReviewMode)

            TextField("Notes…", text: Binding(
                get: { editor.draft.labelerNotes },
                set: { editor.setLabelerNotes($0) }
            ))
            .textFieldStyle(.roundedBorder)
            .disabled(editor.isAnalyzerReviewMode)
        }
    }

    func saveStateBadge(_ editor: LabelingDetailEditor) -> some View {
        let presentation: (label: String, symbol: String, color: Color)
        switch editor.saveState {
        case .saved:
            presentation = ("Saved", "checkmark.circle.fill", .green)
        case .draftSaved:
            presentation = ("Draft saved", "checkmark.circle", .blue)
        case .saving:
            presentation = ("Saving…", "arrow.trianglehead.2.clockwise.rotate.90", .secondary)
        case .unsaved:
            presentation = ("Unsaved", "circle", .orange)
        case .failed:
            presentation = ("Save failed", "exclamationmark.triangle.fill", .red)
        }

        return Label(presentation.label, systemImage: presentation.symbol)
            .font(.caption)
            .foregroundStyle(presentation.color)
            .help(editor.saveFailureMessage ?? "Labeling changes are saved automatically.")
    }

    func statusBadge(_ editor: LabelingDetailEditor) -> some View {
        let (label, color): (String, Color)
        if editor.isAnalyzerReviewMode {
            (label, color) = ("Analyzer review", .purple)
        } else if editor.isReadyToSave {
            (label, color) = ("Ready", .green)
        } else if editor.unassignedSegmentCount == editor.labelingSegments.count {
            (label, color) = ("Transitions", .secondary)
        } else if editor.unassignedSegmentCount == 0 {
            (label, color) = ("Needs review", .orange)
        } else {
            (label, color) = ("\(editor.unassignedSegmentCount) unnamed", .orange)
        }
        return Text(label)
            .font(.caption)
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15), in: Capsule())
    }
}

private struct AnalyzerComparisonRowsView: View {
    let comparisons: [LabelingDetailEditor.AnalyzerPhaseComparison]
    let editor: LabelingDetailEditor

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Labeled vs Predicted")
                .font(.headline)

            Text(summaryText)
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color(nsColor: .underPageBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private var summaryText: String {
        comparisons.map { comparison in
            var parts: [String] = [
                "\(comparison.labeledPhase.displayName) -> \(comparison.predictedPhase?.displayName ?? "No prediction")",
                "\(editor.formatTime(comparison.labeledStartTime))-\(editor.formatTime(comparison.labeledEndTime))",
                "overlap \(comparison.overlapFraction.formatted(.percent.precision(.fractionLength(0))))"
            ]
            if let boundaryError = comparison.averageBoundaryError {
                parts.append("boundary \(editor.formatTime(boundaryError))")
            }
            if let predictedConfidence = comparison.predictedConfidence {
                parts.append("confidence \(predictedConfidence.rawValue.capitalized)")
            }
            return "• " + parts.joined(separator: " • ")
        }
        .joined(separator: "\n")
    }
}
