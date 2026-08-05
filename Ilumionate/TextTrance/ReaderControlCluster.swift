//  ReaderControlCluster.swift
//  Ilumionate
//
//  Revealed-state controls for the Text Trance reader, in the same grammar as
//  the audio player: a transport row (End · pause/resume · Sections) above a
//  fixed tray of large labelled tiles.
//
//  The tray mirrors PlayerControlTray — 72pt tiles, drag for continuous values
//  with a haptic tick every 10%, tap for everything else, and a slot list that
//  never changes, so nothing reflows under the user's finger. Deep settings —
//  including the visual picker and strength — stay in ReaderSettingsDrawer
//  behind the More tile.

import SwiftUI

struct ReaderControlCluster: View {
    @Bindable var session: TextTranceSession
    let onSections: () -> Void
    let onSettings: () -> Void
    let onEnd: () -> Void
    /// Restarts the controls idle timer on every touch. Without it the tray can
    /// auto-hide part way through a speed or strength drag, because the tiles
    /// consume their own gestures and never reach the reading surface's tap
    /// handler. Mirrors `PlayerControlTray.onInteraction`.
    var onInteraction: () -> Void = {}

    /// Transport sizing, tied to the tray so the two rows stay in proportion.
    /// `PlayerControlTile` is 72pt tall; the play button matches it and the
    /// ghosts step down one rung.
    private static let playSize: CGFloat = 72
    private static let ghostSize: CGFloat = 56
    private static let playSymbolSize: CGFloat = 26
    private static let ghostSymbolSize: CGFloat = 20

    @State private var speedDragStart: Double?
    @State private var strengthDragStart: Double?
    /// Restored when the visuals are switched back on, so turning them off and
    /// on returns the effect you were using rather than a default.
    @State private var lastEffect: ReaderVisual = .breath

    private var visualBinding: Binding<ReaderVisual> {
        Binding(
            get: { session.displayPreferences.visual },
            set: { newValue in
                var preferences = session.displayPreferences
                preferences.visual = newValue
                session.setDisplayPreferences(preferences)
            }
        )
    }

    private static let speedMapper = DragValueMapper(
        range: TextPacingEngine.minSpeedMultiplier...TextPacingEngine.maxSpeedMultiplier
    )
    private static let strengthMapper = DragValueMapper(
        range: ReaderVisualStrength.dragRange
    )

    /// Applies a dragged strength, switching the effect off below its minimum
    /// and back on above it.
    private func applyStrength(_ value: Double) {
        var preferences = session.displayPreferences
        if preferences.visual != .none { lastEffect = preferences.visual }

        let resolved = ReaderVisualStrength.resolve(
            draggedValue: value,
            current: preferences.visual,
            currentOpacity: preferences.visualOpacity,
            restoring: restorableEffect
        )
        preferences.visual = resolved.visual
        preferences.visualOpacity = resolved.opacity
        session.setDisplayPreferences(preferences)
    }

    private var visualOn: Bool { session.displayPreferences.visual != .none }

    /// The effect to come back to. Never `.none`, so switching the visuals on
    /// always actually shows something.
    private var restorableEffect: ReaderVisual {
        lastEffect == .none ? .breath : lastEffect
    }

    /// Strength as the Trance slider sees it: zero when the visuals are off, so
    /// a drag resuming from off starts at the bottom rather than jumping.
    private var currentStrength: Double {
        visualOn ? session.displayPreferences.clampedVisualOpacity : 0
    }

    var body: some View {
        VStack(spacing: TranceSpacing.cardMargin) {
            // Scaled to the tray's rhythm: the play button matches the 72pt tile
            // height and the ghosts take the glass surface, so the transport row
            // reads as the same family rather than leftovers from the old
            // satellite cluster.
            HStack(spacing: TranceSpacing.cardMargin) {
                ClusterGhostButton(
                    label: "End session",
                    systemImage: "xmark",
                    size: Self.ghostSize,
                    symbolSize: Self.ghostSymbolSize,
                    filled: true,
                    action: onEnd
                )

                ClusterPlayButton(
                    label: transportLabel,
                    systemImage: transportSystemImage,
                    size: Self.playSize,
                    symbolSize: Self.playSymbolSize
                ) {
                    onInteraction()
                    guard !session.isAttentionPaused else { return }
                    if session.isPaused { session.resume() } else { session.pause() }
                }

                ClusterGhostButton(
                    label: "Sections",
                    systemImage: "list.bullet.rectangle",
                    size: Self.ghostSize,
                    symbolSize: Self.ghostSymbolSize,
                    filled: true
                ) {
                    onInteraction()
                    TranceHaptics.shared.light()
                    onSections()
                }
                .disabled(session.sections.count <= 1)
                .opacity(session.sections.count <= 1 ? 0.35 : 1)
            }

            HStack(spacing: TranceSpacing.small) {
                ForEach(ReaderControlSlot.slots, id: \.self) { tile(for: $0) }
            }
        }
        .padding(.horizontal, TranceSpacing.screen)
        .padding(.bottom, TranceSpacing.statusBar)
    }

    @ViewBuilder
    private func tile(for slot: ReaderControlSlot) -> some View {
        let tile = PlayerControlTile(
            systemImage: slot.systemImage(
                colorMode: session.displayPreferences.colorMode,
                visualOn: visualOn
            ),
            label: slot.label,
            state: slot.state(visualOn: visualOn),
            value: value(for: slot),
            accessibilityValueText: accessibilityValue(for: slot),
            // A draggable tile still gets a tap handler: PlayerControlTile only
            // arms the drag when the tile is enabled, so the tap is what fires
            // in the disabled state.
            onTap: { tap(slot) },
            onDragChanged: slot.isDraggable ? { drag(slot, translation: $0) } : nil,
            onDragEnded: slot.isDraggable ? { endDrag(slot) } : nil
        )

        // Tap steps to the next effect; long press jumps straight to one. Six
        // effects is too many to reach by tapping alone, and the menu is also
        // the only place the effect names are written down.
        if slot == .visual {
            tile.contextMenu { visualMenu }
        } else {
            tile
        }
    }

    @ViewBuilder
    private var visualMenu: some View {
        // Effects only — turning the visuals off belongs to the Trance tile, so
        // there is exactly one control for on/off.
        Picker("Effect", selection: visualBinding) {
            ForEach(ReaderVisual.effects) { visual in
                Text(visual.displayName).tag(visual)
            }
        }
        Divider()
        Button("Visual settings…", systemImage: "slider.horizontal.3", action: onSettings)
    }

    // MARK: - Values

    /// 0...1 gauge fill, so speed and visual strength can both be read without
    /// touching anything.
    private func value(for slot: ReaderControlSlot) -> Double? {
        switch slot {
        case .speed:
            return normalized(session.speedMultiplier, in: Self.speedMapper.range)
        case .tranceMode:
            return ReaderVisualStrength.gauge(
                visual: session.displayPreferences.visual,
                opacity: session.displayPreferences.clampedVisualOpacity
            )
        default:
            return nil
        }
    }

    private func normalized(_ value: Double, in range: ClosedRange<Double>) -> Double {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return min(max((value - range.lowerBound) / span, 0), 1)
    }

    private func accessibilityValue(for slot: ReaderControlSlot) -> String? {
        switch slot {
        case .speed:
            return "\(TextPacingEngine.nominalWPM(forMultiplier: session.speedMultiplier)) words per minute"
        case .visual:
            return visualOn ? session.displayPreferences.visual.displayName : "Off"
        case .readerMode:
            return session.displayPreferences.colorMode.displayName
        case .tranceMode:
            guard visualOn else { return "Off" }
            return "\(Int((session.displayPreferences.clampedVisualOpacity * 100).rounded())) percent"
        case .more:
            return nil
        }
    }

    // MARK: - Actions

    private func tap(_ slot: ReaderControlSlot) {
        onInteraction()
        TranceHaptics.shared.light()
        switch slot {
        case .visual:
            // Reaching for the effect with the visuals off means you want them
            // — same rationale as the player's brightness tile.
            visualBinding.wrappedValue = visualOn
                ? session.displayPreferences.visual.nextEffect
                : restorableEffect

        case .readerMode:
            var preferences = session.displayPreferences
            preferences.colorMode = preferences.colorMode.next
            session.setDisplayPreferences(preferences)

        // Never fires: the tile stays enabled, so its drag is always armed.
        case .tranceMode:
            break

        case .more:
            onSettings()

        case .speed:
            break
        }
    }

    private func drag(_ slot: ReaderControlSlot, translation: CGFloat) {
        onInteraction()
        switch slot {
        case .speed:
            let start = speedDragStart ?? session.speedMultiplier
            if speedDragStart == nil {
                speedDragStart = start
                TranceHaptics.shared.selection()
            }
            let old = session.speedMultiplier
            let new = Self.speedMapper.value(from: start, translation: translation)
            session.setSpeed(multiplier: new)
            tick(from: old, to: new, in: Self.speedMapper.range)

        case .tranceMode:
            let start = strengthDragStart ?? currentStrength
            if strengthDragStart == nil {
                strengthDragStart = start
                TranceHaptics.shared.selection()
            }
            let old = currentStrength
            let new = Self.strengthMapper.value(from: start, translation: translation)
            applyStrength(new)
            tick(from: old, to: new, in: Self.strengthMapper.range)

        default:
            break
        }
    }

    private func endDrag(_ slot: ReaderControlSlot) {
        switch slot {
        case .speed:      speedDragStart = nil
        case .tranceMode: strengthDragStart = nil
        default:          break
        }
    }

    /// A haptic tick on every 10% crossing, so the value is legible without looking.
    private func tick(from old: Double, to new: Double, in range: ClosedRange<Double>) {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return }
        let oldStep = Int(((old - range.lowerBound) / span) * 10)
        let newStep = Int(((new - range.lowerBound) / span) * 10)
        if oldStep != newStep { TranceHaptics.shared.selection() }
    }

    private var transportLabel: String {
        if session.isAttentionPaused { return "Waiting" }
        return session.isPaused ? "Resume" : "Pause"
    }

    private var transportSystemImage: String {
        if session.isAttentionPaused { return "eye.slash.fill" }
        return session.isPaused ? "play.fill" : "pause.fill"
    }
}
