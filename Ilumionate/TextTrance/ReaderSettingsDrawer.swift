//  ReaderSettingsDrawer.swift
//  Ilumionate
//
//  Mid-session live-settings sheet: binaural, subliminal, and (handoff) light.
//  Changes apply immediately via the session's live setters.

import SwiftUI

struct ReaderSettingsDrawer: View {
    @Bindable var session: TextTranceSession
    @Environment(\.dismiss) private var dismiss

    private var binauralBinding: Binding<Bool> {
        Binding(get: { session.binauralActive },
                set: { session.setBinaural(enabled: $0) })
    }
    private var subliminalBinding: Binding<Bool> {
        Binding(get: { session.subliminalEnabled },
                set: { session.setSubliminal(enabled: $0, speed: session.subliminalSpeed) })
    }
    private var subliminalSpeedBinding: Binding<TextPacingSettings.SubliminalSpeed> {
        Binding(get: { session.subliminalSpeed },
                set: { session.setSubliminal(enabled: session.subliminalEnabled, speed: $0) })
    }
    private var lightBinding: Binding<Bool> {
        Binding(get: { session.lightEnabledLive },
                set: { session.setLightEnabled($0) })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Binaural beats") {
                    Toggle("Enabled", isOn: binauralBinding)
                }
                Section("Subliminal flashing") {
                    Toggle("Flash suggestion words", isOn: subliminalBinding)
                    if session.subliminalEnabled {
                        Picker("Flash speed", selection: subliminalSpeedBinding) {
                            ForEach(TextPacingSettings.SubliminalSpeed.allCases) {
                                Text($0.displayName).tag($0)
                            }
                        }
                    }
                }
                if session.settings.arc == .handoff {
                    Section("After handoff") {
                        Toggle("Light pulse", isOn: lightBinding)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.bgPrimary.ignoresSafeArea())
            .tint(.auroraTeal)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
