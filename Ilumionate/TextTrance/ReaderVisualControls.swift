//  ReaderVisualControls.swift
//  Ilumionate
//
//  The ONE place the reader's background-visual settings are expressed.
//
//  Both surfaces that edit reader display preferences embed this: the
//  pre-session setup screen and the in-session settings drawer. They previously
//  each had their own copy of every control, in different idioms, with nothing
//  linking them — which is exactly how the visual picker ended up on one and
//  not the other. Anything added here (speed, direction, colour override,
//  density) appears on both surfaces by construction.
//
//  Only the layout differs between hosts, so only the layout branches.

import SwiftUI

struct ReaderVisualControls: View {

    /// How the host wants these controls laid out.
    enum Style {
        /// Rows inside a `LiminalCard` on the setup screen: title-and-picker
        /// rows with monospaced value labels.
        case setupCard
        /// Rows inside a `Form` `Section` in the settings drawer.
        case formSection
    }

    @Binding var preferences: ReaderDisplayPreferences
    var style: Style = .formSection

    var body: some View {
        switch style {
        case .setupCard:   setupCardBody
        case .formSection: formSectionBody
        }
    }

    // MARK: - Shared state

    private var opacityBinding: Binding<Double> {
        Binding(
            get: { preferences.clampedVisualOpacity },
            set: { preferences.visualOpacity = $0 }
        )
    }

    /// Whether the strength control applies at all. `.none` means no effect is
    /// drawn, so its opacity would be meaningless.
    private var showsStrength: Bool { preferences.visual != .none }

    private var strengthValue: String {
        preferences.clampedVisualOpacity
            .formatted(.percent.precision(.fractionLength(0)))
    }

    // MARK: - Setup card layout

    @ViewBuilder
    private var setupCardBody: some View {
        HStack {
            Text("Effect")
                .font(TranceTypography.body)
                .foregroundStyle(Color.textPrimary)
            Spacer()
            visualPicker
                .tint(.roseGold)
        }

        HStack {
            Text(preferences.visual.summary)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(Color.textSecondary)
            Spacer()
        }

        if showsStrength {
            HStack {
                Text("Strength \(strengthValue)")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Color.textSecondary)
                Spacer()
            }
            strengthSlider
                .tint(.roseDeep)
        }
    }

    // MARK: - Form section layout

    @ViewBuilder
    private var formSectionBody: some View {
        visualPicker

        Text(preferences.visual.summary)
            .font(TranceTypography.caption)
            .foregroundStyle(Color.textSecondary)

        if showsStrength {
            LabeledContent("Strength", value: strengthValue)
            strengthSlider
        }
    }

    // MARK: - Shared controls

    private var visualPicker: some View {
        Picker("Effect", selection: $preferences.visual) {
            ForEach(TranceVisual.allCases) {
                Text($0.displayName).tag($0)
            }
        }
    }

    private var strengthSlider: some View {
        Slider(
            value: opacityBinding,
            in: ReaderDisplayPreferences.visualOpacityRange
        )
        .accessibilityLabel("Visual strength")
        .accessibilityValue(strengthValue)
    }
}
