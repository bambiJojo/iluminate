//
//  ContentTypeStyle.swift
//  Ilumionate
//
//  Single source of truth for a session's content-type color + icon, plus the
//  zone-tinted glow dot that replaces the old thumbnail boxes (spec §4).
//

import SwiftUI

enum ContentTypeStyle {
    static func color(for type: AudioContentType?) -> Color {
        switch type {
        case .hypnosis:       return .bwDelta
        case .eroticHypnosis: return .roseDeep
        case .sleepHypnosis:  return .bwDelta
        case .meditation:     return .bwAlpha
        case .brainwave:      return .bwGamma
        case .asmr:           return .warmAccent
        case .music:          return .bwBeta
        case .guidedImagery:  return .bwTheta
        case .affirmations:   return .warmAccent
        case .unknown, .none: return .roseGold
        }
    }

    static func icon(for type: AudioContentType?) -> String {
        switch type {
        case .hypnosis:       return "brain.head.profile"
        case .eroticHypnosis: return "flame"
        case .sleepHypnosis:  return "moon.zzz"
        case .meditation:     return "leaf"
        case .brainwave:      return "waveform.path.ecg"
        case .asmr:           return "ear"
        case .music:          return "music.note"
        case .guidedImagery:  return "figure.mind.and.body"
        case .affirmations:   return "quote.bubble"
        case .unknown, .none: return "waveform"
        }
    }
}

/// A zone-tinted glowing dot with the content-type icon — the Liminal replacement
/// for the old `RoundedRectangle().fill(color.opacity(0.18))` badge.
struct SessionGlowDot: View {
    let contentType: AudioContentType?
    var size: CGFloat = 40

    private var color: Color { ContentTypeStyle.color(for: contentType) }

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.18))
                .overlay(Circle().stroke(color.opacity(0.5), lineWidth: 1))
            Image(systemName: ContentTypeStyle.icon(for: contentType))
                .font(.system(size: size * 0.42, weight: .regular))
                .foregroundStyle(color)
        }
        .frame(width: size, height: size)
        .shadow(color: color.opacity(0.5), radius: 8, x: 0, y: 0)
    }
}

#Preview {
    ZStack {
        Color.bgPrimary.ignoresSafeArea()
        HStack(spacing: TranceSpacing.card) {
            SessionGlowDot(contentType: .hypnosis)
            SessionGlowDot(contentType: .meditation)
            SessionGlowDot(contentType: .music)
            SessionGlowDot(contentType: nil)
        }
    }
}
