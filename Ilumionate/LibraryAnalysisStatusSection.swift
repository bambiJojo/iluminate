import SwiftUI

struct LibraryAnalysisStatusSection: View {
    let manager: AnalysisStateManager
    let partialFiles: [AudioFile]
    let onOpen: () -> Void

    var body: some View {
        if hasStatus {
            VStack(alignment: .leading, spacing: TranceSpacing.list) {
                LibraryShelfSectionHeader(title: "Personal Audio Analysis") {
                    onOpen()
                }

                Button(action: onOpen) {
                    LiminalCard {
                        VStack(alignment: .leading, spacing: TranceSpacing.list) {
                            if let active = manager.currentAnalysis {
                                statusRow(
                                    title: active.audioFile.displayName,
                                    detail: AnalysisStageFeedback.stageSummary(active.stage),
                                    systemImage: "waveform",
                                    tint: .roseGold
                                )
                            }

                            ForEach(manager.analysisQueue.prefix(2)) { file in
                                statusRow(
                                    title: file.displayName,
                                    detail: "Waiting in queue",
                                    systemImage: "clock",
                                    tint: .textSecondary
                                )
                            }

                            ForEach(manager.failedAnalyses.suffix(2)) { failure in
                                statusRow(
                                    title: failure.audioFile.displayName,
                                    detail: failure.presentation.statusMessage ?? failure.presentation.title,
                                    systemImage: "exclamationmark.triangle.fill",
                                    tint: .roseDeep
                                )
                            }

                            ForEach(partialFiles.prefix(2)) { file in
                                statusRow(
                                    title: file.displayName,
                                    detail: "Transcript ready · analysis continuing",
                                    systemImage: "text.quote",
                                    tint: .bwAlpha
                                )
                            }
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var hasStatus: Bool {
        manager.currentAnalysis != nil
            || manager.analysisQueue.isEmpty == false
            || manager.failedAnalyses.isEmpty == false
            || partialFiles.isEmpty == false
    }

    private func statusRow(title: String, detail: String, systemImage: String, tint: Color) -> some View {
        HStack(spacing: TranceSpacing.list) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(TranceTypography.body)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                Text(detail)
                    .font(TranceTypography.caption)
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(2)
            }
            Spacer()
        }
    }
}
