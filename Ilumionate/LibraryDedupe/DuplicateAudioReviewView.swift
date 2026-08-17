//
//  DuplicateAudioReviewView.swift
//  Ilumionate
//

import SwiftUI

struct DuplicateAudioReviewView: View {
    @State private var viewModel: DuplicateAudioReviewViewModel
    private let onMerge: (DuplicateAudioReviewViewModel.Resolution) -> Void

    @Environment(\.dismiss) private var dismiss

    init(
        audioFiles: [AudioFile],
        onMerge: @escaping (DuplicateAudioReviewViewModel.Resolution) -> Void
    ) {
        _viewModel = State(initialValue: DuplicateAudioReviewViewModel(audioFiles: audioFiles))
        self.onMerge = onMerge
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.hasDuplicates {
                    groupList
                } else {
                    ContentUnavailableView(
                        "No Duplicates",
                        systemImage: "checkmark.seal",
                        description: Text("Every file in your library holds different audio.")
                    )
                }
            }
            .navigationTitle("Duplicates")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .tint(.roseGold)
                }

                ToolbarItem(placement: .primaryAction) {
                    if viewModel.hasDuplicates {
                        Button("Merge \(viewModel.removableCount)") {
                            onMerge(viewModel.resolution())
                            dismiss()
                        }
                        .tint(.roseGold)
                        .disabled(viewModel.removableCount == 0)
                    }
                }
            }
        }
    }

    private var groupList: some View {
        List(viewModel.groups) { group in
            DuplicateAudioGroupRow(
                group: group,
                isSelected: viewModel.isSelected(group.id),
                onToggle: {
                    viewModel.setSelected(!viewModel.isSelected(group.id), groupID: group.id)
                }
            )
        }
        .scrollIndicators(.hidden)
    }
}

/// One duplicate group: the copy that survives, and the copies that go.
private struct DuplicateAudioGroupRow: View {
    let group: DuplicateAudioGroup
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(alignment: .top, spacing: TranceSpacing.list) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.roseGold : Color.textLight)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: TranceSpacing.micro) {
                    Text(group.keeper.displayName)
                        .font(TranceTypography.body)
                        .foregroundStyle(.textPrimary)

                    Text(keptDescription)
                        .font(TranceTypography.caption)
                        .foregroundStyle(.textLight)

                    ForEach(group.redundant) { file in
                        Text("Removes “\(file.displayName)”")
                            .font(TranceTypography.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
            .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            "\(group.keeper.displayName), removes \(group.redundant.count) copy or copies"
        )
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var keptDescription: String {
        if group.keeper.isAnalyzed {
            return "Keeps the analyzed copy"
        }
        if group.keeper.hasTranscription {
            return "Keeps the transcribed copy"
        }
        return "Keeps the earliest copy"
    }
}
