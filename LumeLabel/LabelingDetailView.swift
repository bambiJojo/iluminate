//
//  LabelingDetailView.swift
//  LumeLabel
//
//  Keyboard shortcuts:
//    B       Mark transition at playhead
//    1–9     Name selected segment
//    Space   Play / Pause
//    ←  →   Seek ±10 seconds
//    [  ]    Previous / next pending candidate
//    M / D   Matches / dismiss selected candidate
//    ⌘S     Save
//

import SwiftUI

@MainActor
struct LabelingDetailView: View {
    @Environment(TrainingCorpusManager.self) private var corpus
    @Environment(LabelingSprintController.self) private var labelingSprint

    let fileID: LabeledFile.ID
    let onSavedAndNext: (LabeledFile.ID) -> Void
    let onDefer: (LabeledFile.ID) -> Void

    @State private var editor: LabelingDetailEditor?
    @State var isConfirmingAnalyzerReview = false

    var body: some View {
        Group {
            if let editor {
                detailBody(editor)
            } else if corpus.file(withID: fileID) == nil {
                ContentUnavailableView(
                    "File Missing",
                    systemImage: "exclamationmark.triangle",
                    description: Text("This labeled file no longer exists in the training corpus.")
                )
            } else {
                ProgressView("Loading label editor…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: fileID) {
            guard let file = corpus.file(withID: fileID) else {
                editor = nil
                return
            }
            let newEditor = LabelingDetailEditor(file: file, corpus: corpus)
            await newEditor.restoreWorkInProgressIfAvailable()
            guard !Task.isCancelled else { return }
            newEditor.preparePlayer()
            editor = newEditor

            // Let the selection and first detail layout finish before doing
            // transcript work. A rapid second selection cancels this task at
            // the yield instead of finishing work for a detail view that is
            // already disappearing.
            await Task.yield()
            guard !Task.isCancelled else { return }
            await newEditor.loadTranscriptIfAvailable()
        }
        .onDisappear {
            editor?.cleanup()
        }
        .alert("Labeling Error", isPresented: Binding(
            get: { editor?.alertMessage != nil },
            set: { if !$0 { editor?.clearAlert() } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(editor?.alertMessage ?? "")
        }
        .confirmationDialog(
            "Reveal analyzer suggestions?",
            isPresented: $isConfirmingAnalyzerReview,
            titleVisibility: .visible
        ) {
            Button("Lock Labels and Reveal") {
                _ = editor?.enterAnalyzerReview()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The current saved timeline will become the preserved blind baseline. Analyzer review is read-only, so suggestions cannot alter those labels.")
        }
    }

    @ViewBuilder
    private func detailBody(_ editor: LabelingDetailEditor) -> some View {
        VStack(spacing: 0) {
            PlaybackUpdateScope {
                phaseArc(editor)
                    .padding([.horizontal, .top])
                    .padding(.bottom, 4)
            }

            PlaybackUpdateScope {
                overviewStrip(editor)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
            }

            Divider()
            PlaybackUpdateScope {
                transportBar(editor).padding()
            }
            Divider()

            HStack(alignment: .top, spacing: 0) {
                phaseButtons(editor)
                    .padding()
                    .frame(width: 190)
                Divider()
                phaseListPanel(editor)
                    .padding()
                    .frame(width: 300)
                Divider()
                transcriptInspector(editor)
                    .padding()
            }
            .frame(minHeight: 220)

            if !labelingSprint.isActive {
                Divider()
                metadataBar(editor)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
            }
        }
        .navigationTitle(editor.draft.audioFilename)
        .toolbar {
            if labelingSprint.isActive {
                ToolbarItem(placement: .secondaryAction) {
                    Button("Defer", systemImage: "arrow.right.to.line") {
                        onDefer(fileID)
                    }
                    .disabled(editor.isSaving)
                    .help("Move this file out of the sprint and replace it with another.")
                }
            }

            ToolbarItem(placement: .primaryAction) {
                Button(labelingSprint.isActive ? "Save & Next" : "Save") {
                    Task {
                        let didSave = await editor.save()
                        if didSave, labelingSprint.isActive {
                            onSavedAndNext(fileID)
                        }
                    }
                }
                .keyboardShortcut("s")
                .disabled(editor.isAnalyzerReviewMode || editor.isSaving || !editor.isReadyToSave)
                .help(
                    editor.isAnalyzerReviewMode
                        ? "The blind timeline is locked during analyzer review."
                        : (editor.isReadyToSave
                            ? (labelingSprint.isActive ? "Save labels and open the next sprint file" : "Save labels")
                            : (editor.labelValidationMessage ?? "Review the phase timeline"))
                )
            }
            ToolbarItem { saveStateBadge(editor) }
            ToolbarItem { statusBadge(editor) }
        }
    }
}

/// Keeps rapidly changing playback state from invalidating the entire detail
/// editor. Observable reads performed by `content` belong to this small view's
/// body instead of `LabelingDetailView.body`.
private struct PlaybackUpdateScope<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
    }
}
