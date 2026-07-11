//  ReaderQuickActionsBar.swift
//  Ilumionate
//
//  Persistent Reader library actions that collapse to icons while scrolling.

import SwiftUI

struct ReaderQuickActionsBar: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let collapseProgress: CGFloat
    let onImportFile: () -> Void
    let onLoadWebsite: () -> Void
    let onFindScripts: () -> Void
    let onHistory: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            actionButton(
                title: "Import File",
                accessibilityTitle: "Import file",
                hint: "Choose a PDF or ePub",
                systemImage: "doc.badge.plus",
                tint: .bwBeta,
                action: onImportFile
            )
            divider
            actionButton(
                title: "Load Website",
                accessibilityTitle: "Load website",
                hint: "Import readable text from a webpage",
                systemImage: "square.and.arrow.down",
                tint: .bwTheta,
                action: onLoadWebsite
            )
            divider
            actionButton(
                title: "Find Scripts",
                accessibilityTitle: "Find more scripts online",
                hint: "Browse the reading source directory",
                systemImage: "globe",
                tint: .auroraTeal,
                action: onFindScripts
            )
            divider
            actionButton(
                title: "History",
                accessibilityTitle: "Reading history",
                hint: "Show saved reading progress",
                systemImage: "clock.arrow.circlepath",
                tint: .bwAlpha,
                action: onHistory
            )
        }
        .padding(.horizontal, TranceSpacing.micro)
        .padding(.vertical, TranceSpacing.micro)
        .frame(height: surfaceHeight)
        .liminalGlass(
            .roundedRect(cornerRadius: TranceRadius.button),
            tintOpacity: 0.78 + (0.1 * Double(progress)),
            glow: false
        )
        .frame(height: 64, alignment: .top)
    }

    private var divider: some View {
        Divider()
            .frame(height: 34 - (10 * progress))
            .overlay(Color.glassBorder)
    }

    private var progress: CGFloat {
        min(max(collapseProgress, 0), 1)
    }

    private var motionProgress: CGFloat {
        reduceMotion ? 0 : progress
    }

    private var surfaceHeight: CGFloat {
        64 - (16 * progress)
    }

    private var labelOpacity: Double {
        let fadeProgress = min(max((progress - 0.15) / 0.6, 0), 1)
        return 1 - Double(fadeProgress)
    }

    private func actionButton(
        title: String,
        accessibilityTitle: String,
        hint: String,
        systemImage: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            TranceHaptics.shared.light()
            action()
        } label: {
            VStack(spacing: TranceSpacing.micro) {
                Image(systemName: systemImage)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(height: 22)
                    .scaleEffect(1 + (0.05 * motionProgress))

                Text(title)
                    .font(TranceTypography.caption.weight(.medium))
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                    .opacity(labelOpacity)
                    .offset(y: -4 * motionProgress)
                    .frame(height: 14 * (1 - progress), alignment: .top)
                    .clipped()
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(.rect)
        }
        .buttonStyle(ReaderQuickActionButtonStyle())
        .accessibilityLabel(accessibilityTitle)
        .accessibilityHint(hint)
    }
}

private struct ReaderQuickActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.68 : 1)
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

#Preview {
    ZStack {
        AuroraBackground()
        VStack(spacing: TranceSpacing.card) {
            ReaderQuickActionsBar(
                collapseProgress: 0,
                onImportFile: {},
                onLoadWebsite: {},
                onFindScripts: {},
                onHistory: {}
            )
            ReaderQuickActionsBar(
                collapseProgress: 1,
                onImportFile: {},
                onLoadWebsite: {},
                onFindScripts: {},
                onHistory: {}
            )
        }
        .padding(TranceSpacing.screen)
    }
}
