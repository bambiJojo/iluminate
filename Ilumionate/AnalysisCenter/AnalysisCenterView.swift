//
//  AnalysisCenterView.swift
//  Ilumionate
//
//  The one place every analysis state is addressable. Presented as a sheet from
//  every entry point, so it behaves identically from any tab.
//
//  Rows are already tier-ordered by the projection; this view groups them for
//  reading and never re-sorts.
//

import SwiftUI

struct AnalysisCenterView: View {

    @Bindable var engine: LightEngine
    @Environment(AnalysisCenterModel.self) private var center
    @Environment(\.dismiss) private var dismiss

    @State private var analysisManager = AnalysisStateManager.shared
    @State private var showingClearQueueConfirm = false
    @State private var readyPlayerItem: SyncPlayerItem?

    var body: some View {
        ZStack {
            Color.bgPrimary.ignoresSafeArea()
            content
        }
        .navigationTitle("Analysis")
        .platformLargeNavigationTitle()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if analysisManager.currentAnalysis != nil || !analysisManager.analysisQueue.isEmpty {
                    Button(role: .destructive) {
                        showingClearQueueConfirm = true
                    } label: {
                        Label("Clear Queue", systemImage: "xmark.circle")
                            .font(.caption)
                    }
                    .foregroundStyle(Color.roseGold)
                }
            }
        }
        .confirmationDialog(
            "Clear all queued analyses?",
            isPresented: $showingClearQueueConfirm,
            titleVisibility: .visible
        ) {
            Button("Clear Queue", role: .destructive) { analysisManager.clearQueue() }
            Button("Cancel", role: .cancel) {}
        }
        .onAppear { UsageAnalytics.shared.screen(.analysisQueue) }
        .platformFullScreenCover(item: $readyPlayerItem) { item in
            if let session = item.lightSession {
                UnifiedPlayerView(
                    mode: .session(session: session, audioFile: item.audioFile),
                    engine: engine
                )
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        // `nil` is "still loading"; `[]` is "nothing to show". Distinguishing
        // them is why the snapshot is optional.
        if let tasks = center.tasks {
            if tasks.isEmpty {
                idleCard
            } else {
                ScrollView {
                    VStack(spacing: TranceSpacing.list) {
                        ForEach(tasks) { task in
                            AnalysisTaskRow(
                                task: task,
                                onRetry: { retry(task) },
                                onCancel: { analysisManager.cancelCurrentAnalysis() },
                                onRemoveFromQueue: {
                                    analysisManager.removeFromQueue(audioFile: task.audioFile)
                                },
                                onDismissFailure: { dismissFailure(task) },
                                onRemoveFailure: { removeFailure(task) },
                                onPlay: { play(task) }
                            )
                        }
                    }
                    .padding(.horizontal, TranceSpacing.screen)
                    .padding(.top, TranceSpacing.card)
                    .padding(.bottom, TranceSpacing.tabBarClearance + 20)
                }
            }
        } else {
            ProgressView()
                .controlSize(.large)
                .tint(.roseGold)
        }
    }

    private var idleCard: some View {
        LiminalCard {
            VStack(spacing: TranceSpacing.list) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(Color.bwGamma)
                Text("Nothing to analyze")
                    .font(TranceTypography.sectionTitle)
                    .foregroundStyle(Color.textPrimary)
                Text("Queue a file from your library to begin.")
                    .font(TranceTypography.caption)
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(TranceSpacing.screen)
    }

    // MARK: Actions

    private func retry(_ task: AnalysisTask) {
        Task {
            await analysisManager.queueForAnalysis(task.audioFile)
        }
    }

    private func dismissFailure(_ task: AnalysisTask) {
        guard let failure = task.lastFailure else { return }
        Task {
            TranceHaptics.shared.light()
            await analysisManager.dismissFailure(
                fileID: task.id,
                failedAt: failure.failedAt,
                retryState: failure.retryState
            )
            center.invalidateStructure()
        }
    }

    private func removeFailure(_ task: AnalysisTask) {
        guard let failure = task.lastFailure else { return }
        Task {
            await analysisManager.removeFailure(
                fileID: task.id,
                failedAt: failure.failedAt,
                retryState: failure.retryState
            )
            center.invalidateStructure()
        }
    }

    private func play(_ task: AnalysisTask) {
        // The player item is resolved on tap rather than held in the snapshot:
        // SyncPlayerItem regenerates its id per instance, so keeping one would
        // break snapshot equality.
        guard let session = GeneratedSessionStore.shared.load(for: task.audioFile) else { return }
        TranceHaptics.shared.medium()
        UsageAnalytics.shared.analysisReadyAction(.play)
        readyPlayerItem = SyncPlayerItem(audioFile: task.audioFile, lightSession: session)
    }
}
