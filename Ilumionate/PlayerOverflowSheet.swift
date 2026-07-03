//
//  PlayerOverflowSheet.swift
//  Ilumionate
//
//  The "···" sheet holding relocated mode extras: sync options (session+audio),
//  bilateral / binaural (flash), smart transitions + track list (playlist).
//

import SwiftUI

struct PlayerOverflowSheet: View {
    @Bindable var viewModel: UnifiedPlayerViewModel
    @Environment(\.dismiss) private var dismiss

    private var smartTransitionsBinding: Binding<Bool> {
        Binding(get: { viewModel.smartTransitions },
                set: { viewModel.smartTransitions = $0 })
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: TranceSpacing.cardMargin) {
                if viewModel.mode.hasSyncOptions {
                    GlassCard(label: "SYNC OPTIONS") {
                        SyncToggle(isOn: $viewModel.isSyncEnabled)
                    }
                }

                if viewModel.mode.hasBilateralToggle || viewModel.mode.hasBinauralToggle {
                    GlassCard(label: "LIGHT & AUDIO") {
                        HStack(spacing: 32) {
                            if viewModel.mode.hasBilateralToggle {
                                PlayerBilateralSection(viewModel: viewModel)
                            }
                            if viewModel.mode.hasBinauralToggle {
                                PlayerBinauralSection(viewModel: viewModel)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                }

                if viewModel.mode.hasSmartTransitions {
                    Toggle("Smart Transitions", isOn: smartTransitionsBinding)
                        .tint(.roseGold)
                }

                if viewModel.mode.hasTrackList {
                    Button("Track List", systemImage: "list.number") {
                        dismiss()
                        viewModel.showingTrackList = true
                    }
                    .foregroundStyle(Color.textPrimary)
                }

                Spacer()
            }
            .padding(TranceSpacing.screen)
            .background(Color.bgPrimary.ignoresSafeArea())
            .navigationTitle("Options")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
        .presentationBackground(Color.bgPrimary)
    }
}
