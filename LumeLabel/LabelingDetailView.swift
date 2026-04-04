//
//  LabelingDetailView.swift
//  LumeLabel
//
//  Keyboard shortcuts:
//    1–7     Mark phase at playhead
//    Space   Play / Pause
//    ←  →   Seek ±10 seconds
//    ⌘S     Save
//

import SwiftUI

@MainActor
struct LabelingDetailView: View {
    @Environment(TrainingCorpusManager.self) private var corpus

    let fileID: LabeledFile.ID

    @State private var editor: LabelingDetailEditor?

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
            newEditor.preparePlayer()
            editor = newEditor
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
    }

    @ViewBuilder
    private func detailBody(_ editor: LabelingDetailEditor) -> some View {
        VStack(spacing: 0) {
            phaseArc(editor)
                .padding([.horizontal, .top])
                .padding(.bottom, 4)

            overviewStrip(editor)
                .padding(.horizontal)
                .padding(.bottom, 8)

            Divider()
            transportBar(editor).padding()
            Divider()

            HStack(alignment: .top, spacing: 0) {
                phaseButtons(editor)
                    .padding()
                    .frame(width: 180)
                Divider()
                phaseListPanel(editor).padding()
            }
            .frame(minHeight: 220)

            Divider()
            metadataBar(editor)
                .padding(.horizontal)
                .padding(.vertical, 8)
        }
        .navigationTitle(editor.draft.audioFilename)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Save") {
                    Task { await editor.save() }
                }
                .keyboardShortcut("s")
                .disabled(editor.isSaving)
            }
            ToolbarItem { statusBadge(editor) }
        }
    }
}
