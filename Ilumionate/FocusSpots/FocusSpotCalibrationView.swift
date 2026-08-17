//
//  FocusSpotCalibrationView.swift
//  Ilumionate
//
//  Dial the focus spots in against a real field, at true size.
//
//  Spacing that matches your own eyes cannot be chosen from a number in a
//  settings list, so the sliders live here, on top of what they control.
//
//  The field is STEADY, never strobing. A settings screen should not flash,
//  and a strobing preview would drag the photosensitivity warning into
//  Settings.
//

import SwiftUI

struct FocusSpotCalibrationView: View {
    let initialSettings: FocusSpotSettings
    let onSave: (FocusSpotSettings) -> Void
    let onCancel: () -> Void

    @State private var working: FocusSpotSettings

    /// Well below full: tuning the spots should not be a face full of light.
    private static let fieldOpacity: Double = 0.6
    /// Mid-scale blackbody, matching the swatch shown in Session Defaults.
    private static let previewColorTemperature = 3000

    init(
        initialSettings: FocusSpotSettings,
        onSave: @escaping (FocusSpotSettings) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.initialSettings = initialSettings
        self.onSave = onSave
        self.onCancel = onCancel
        _working = State(initialValue: initialSettings)
    }

    private var fieldColor: Color {
        FlashTintPreference.current().color(
            colorTemperature: Self.previewColorTemperature
        )
    }

    /// The tray gets out of the way of the spots rather than covering them.
    private var trayIsAtTop: Bool { working.verticalPosition > 0.5 }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            fieldColor.opacity(Self.fieldOpacity).ignoresSafeArea()

            FocusSpotField(settings: working)
                .ignoresSafeArea()
                .accessibilityHidden(true)

            controlTray
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: trayIsAtTop ? .top : .bottom
                )
                .animation(LiminalMotion.fade, value: trayIsAtTop)
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Tray

    private var controlTray: some View {
        VStack(spacing: TranceSpacing.list) {
            header

            sliderRow(
                title: "Vertical Position",
                value: verticalPositionBinding,
                range: FocusSpotSettings.verticalPositionRange,
                step: 0.01,
                display: verticalPositionLabel(working.verticalPosition)
            )

            sliderRow(
                title: "Horizontal Spacing",
                value: $working.horizontalSpacing,
                range: FocusSpotSettings.horizontalSpacingRange,
                step: 4,
                display: pointsLabel(working.horizontalSpacing)
            )

            sliderRow(
                title: "Diameter",
                value: $working.diameter,
                range: FocusSpotSettings.diameterRange,
                step: 2,
                display: pointsLabel(working.diameter)
            )
        }
        .padding(TranceSpacing.card)
        .background(.ultraThinMaterial, in: .rect(cornerRadius: TranceRadius.glassCard))
        .padding(TranceSpacing.screen)
    }

    private var header: some View {
        HStack {
            Button("Cancel") { onCancel() }
                .foregroundStyle(Color.textSecondary)

            Spacer()

            Text("Focus Spots")
                .font(TranceTypography.sectionTitle)
                .foregroundStyle(Color.textPrimary)

            Spacer()

            Button("Save") {
                TranceHaptics.shared.light()
                onSave(working)
            }
            .foregroundStyle(Color.roseGold)
            .bold()
        }
        .buttonStyle(.plain)
    }

    // MARK: - Bindings

    /// Snaps onto upper third / centre / lower third, with a tick as it
    /// arrives so the anchor is findable without looking.
    private var verticalPositionBinding: Binding<Double> {
        Binding(
            get: { working.verticalPosition },
            set: { newValue in
                let snapped = FocusSpotSettings.snappingVerticalPosition(newValue)
                let wasOnDetent = FocusSpotSettings.verticalDetents
                    .contains(working.verticalPosition)
                let isOnDetent = FocusSpotSettings.verticalDetents.contains(snapped)
                if isOnDetent, !wasOnDetent {
                    TranceHaptics.shared.selection()
                }
                working.verticalPosition = snapped
            }
        )
    }

    // MARK: - Rows

    private func sliderRow(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        display: String
    ) -> some View {
        VStack(alignment: .leading, spacing: TranceSpacing.micro) {
            HStack {
                Text(title)
                    .font(TranceTypography.body)
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                Text(display)
                    .font(TranceTypography.caption)
                    .foregroundStyle(Color.textSecondary)
            }

            CustomSlider(
                value: value,
                range: range,
                trackColor: .glassBorder,
                thumbColor: .roseGold,
                activeColor: .roseGold
            )
            .frame(height: 24)
        }
        // CustomSlider is drag-driven and invisible to VoiceOver on its own,
        // so the row carries the label, the value, and the adjustment.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(display)
        .accessibilityAdjustableAction { direction in
            let delta = direction == .increment ? step : -step
            let updated = value.wrappedValue + delta
            value.wrappedValue = min(max(updated, range.lowerBound), range.upperBound)
        }
    }

    // MARK: - Labels

    private func verticalPositionLabel(_ value: Double) -> String {
        if value == FocusSpotSettings.verticalDetents[0] { return "Upper Third" }
        if value == FocusSpotSettings.verticalDetents[1] { return "Centre" }
        if value == FocusSpotSettings.verticalDetents[2] { return "Lower Third" }
        return (value * 100).formatted(.number.precision(.fractionLength(0))) + "% down"
    }

    private func pointsLabel(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0))) + " pt"
    }
}

#Preview {
    FocusSpotCalibrationView(
        initialSettings: .default,
        onSave: { _ in },
        onCancel: {}
    )
}
