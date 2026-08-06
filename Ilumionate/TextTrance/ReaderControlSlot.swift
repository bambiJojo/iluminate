//  ReaderControlSlot.swift
//  Ilumionate
//
//  Which control tiles the reader shows. Mirrors PlayerControlSlot so the
//  reader and the audio player speak one control language.

import Foundation

enum ReaderControlSlot: Equatable, CaseIterable {
    case speed
    case visual
    case readerMode
    case tranceMode
    case more

    // MARK: - Composition

    /// The tray is deliberately **mode-invariant**.
    ///
    /// The trance toggle lives in the tray, so a mode-dependent tray would
    /// reshuffle the tiles around the user's finger at the exact moment they
    /// tapped one — the failure `PlayerControlSlot` is written to prevent. The
    /// layer toggles (binaural, light) moved to the drawer to make room; they
    /// are session-shape choices, not the moment-to-moment adjustments.
    static let slots: [ReaderControlSlot] = [.speed, .visual, .readerMode, .tranceMode, .more]

    // MARK: - Presentation

    /// Whether this tile is adjusted by dragging rather than tapping.
    ///
    /// Trance drags to set visual strength, and its travel runs below
    /// `visualOpacityRange.lowerBound` down to fully off — so the one gesture
    /// covers strength *and* on/off, and you can drag straight back up again.
    var isDraggable: Bool { self == .speed || self == .tranceMode }

    /// Labels stay constant so the tray never reflows and muscle memory holds;
    /// on/off is carried by state, not by the text.
    var label: String {
        switch self {
        case .speed:      return "Speed"
        case .visual:     return "Visual"
        case .readerMode: return "Display"
        case .tranceMode: return "Trance"
        case .more:       return "More"
        }
    }

    /// The Visual tile keeps one icon: which effect is running is already
    /// visible on screen behind the words, and the long-press menu carries the
    /// names. Six invented symbol names would only risk silent blanks.
    func systemImage(colorMode: ReaderColorMode, visualOn: Bool) -> String {
        switch self {
        case .speed:      return "speedometer"
        case .visual:     return "sparkles"
        case .readerMode: return colorMode.controlSystemImage
        case .tranceMode: return visualOn ? "moon.stars.fill" : "moon.stars"
        case .more:       return "ellipsis"
        }
    }

    /// Trance stays live even at zero: disabling it would strip its drag gesture
    /// the instant it reached off, stranding the user with no way to drag back
    /// up. An empty gauge is the "off" signal instead.
    ///
    /// Visual has nothing to cycle while the visuals are off, so it does read as
    /// unavailable — and tapping it anyway switches them on, the same rationale
    /// as the player's brightness tile with the lights off.
    func state(visualOn: Bool) -> PlayerControlTile.State {
        switch self {
        case .visual: return visualOn ? .normal : .disabled
        case .speed, .tranceMode, .readerMode, .more: return .normal
        }
    }
}

extension ReaderColorMode {
    /// Icon for the display tile — shows what you are currently in.
    var controlSystemImage: String {
        switch self {
        case .followApp: return "circle.lefthalf.filled"
        case .light:     return "sun.max.fill"
        case .dark:      return "moon.fill"
        }
    }

    /// Tapping the display tile cycles Auto → Light → Dark → Auto.
    var next: ReaderColorMode {
        switch self {
        case .followApp: return .light
        case .light:     return .dark
        case .dark:      return .followApp
        }
    }
}

extension TranceVisual {
    /// The selectable effects — everything except "off", which the Trance tile
    /// owns.
    static var effects: [TranceVisual] { allCases.filter { $0 != .none } }

    /// Tapping the Visual tile steps to the next effect. `.none` is deliberately
    /// not in this cycle: turning the visuals off is the Trance tile's job, so
    /// cycling can never strand you on a blank background.
    var nextEffect: TranceVisual {
        let effects = Self.effects
        guard let index = effects.firstIndex(of: self) else { return effects.first ?? .breath }
        return effects[(index + 1) % effects.count]
    }
}
