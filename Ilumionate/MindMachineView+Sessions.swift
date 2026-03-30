//
//  MindMachineView+Sessions.swift
//  Ilumionate
//
//  Research sessions browser embedded in the Mind Machine tab.
//  Displays all bundled sessions organised by brainwave category,
//  with a category filter bar and compact rows that launch SessionPlayerView.
//

import SwiftUI

// MARK: - Category Filter State

extension MindMachineView {

    // MARK: Sessions Browser Section

    var sessionsBrowserSection: some View {
        GlassCard(label: "Research Sessions") {
            VStack(spacing: TranceSpacing.list) {
                // Category filter tabs
                SessionCategoryBar(selected: $model.sessionCategory)

                Divider()
                    .background(Color.glassBorder)

                // Session rows
                let filtered = filteredSessions
                if filtered.isEmpty {
                    Text("No sessions in this category")
                        .font(TranceTypography.caption)
                        .foregroundStyle(Color.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, TranceSpacing.list)
                } else {
                    ForEach(filtered.enumerated().map { $0 }, id: \.element.id) { pair in
                        if pair.offset > 0 {
                            Rectangle()
                                .fill(Color.glassBorder.opacity(0.4))
                                .frame(height: 1)
                        }
                        CompactSessionRow(
                            session: pair.element,
                            index: pair.offset
                        ) {
                            TranceHaptics.shared.heavy()
                            selectedSession = pair.element
                        }
                    }
                }
            }
        }
    }

    // MARK: Filtering

    private var filteredSessions: [LightSession] {
        guard model.sessionCategory != .all else { return sessions }
        return sessions.filter { session in
            switch model.sessionCategory {
            case .all:
                return true
            case .sleep:
                return session.brainwaveCategory == .sleep
            case .relax:
                return session.brainwaveCategory == .relax
            case .focus:
                return session.brainwaveCategory == .focus || session.brainwaveCategory == .energy
            case .trance:
                return session.brainwaveCategory == .trance ||
                       session.displayName.localizedCaseInsensitiveContains("hypnos") ||
                       session.displayName.localizedCaseInsensitiveContains("trance") ||
                       session.displayName.localizedCaseInsensitiveContains("peniston")
            }
        }
    }
}

// MARK: - Session Category Filter Enum

extension MindMachineModel {
    enum SessionCategory: String, CaseIterable {
        case all    = "All"
        case sleep  = "Sleep"
        case relax  = "Relax"
        case focus  = "Focus"
        case trance = "Trance"

        var icon: String {
            switch self {
            case .all:    return "square.grid.2x2"
            case .sleep:  return "moon.stars"
            case .relax:  return "leaf"
            case .focus:  return "target"
            case .trance: return "sparkles"
            }
        }

        var color: Color {
            switch self {
            case .all:    return .roseGold
            case .sleep:  return .bwDelta
            case .relax:  return .bwTheta
            case .focus:  return .bwAlpha
            case .trance: return .bwGamma
            }
        }
    }

    // Add to model — default to .all
    // (stored via computed property backed by rawValue to keep Sendable conformance)
}

// MARK: - Add sessionCategory to MindMachineModel

extension MindMachineModel {
    // swiftlint:disable:next identifier_name
    static let _sessionCategoryKey = "mindMachineSessionCategory"
}

// NOTE: sessionCategory is declared directly in MindMachineView.swift to satisfy
// @Observable mutation rules.

// MARK: - Category Filter Bar

struct SessionCategoryBar: View {
    @Binding var selected: MindMachineModel.SessionCategory

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: TranceSpacing.inner) {
                ForEach(MindMachineModel.SessionCategory.allCases, id: \.rawValue) { category in
                    SessionCategoryChip(
                        category: category,
                        isSelected: selected == category
                    ) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selected = category
                        }
                        TranceHaptics.shared.selection()
                    }
                }
            }
            .padding(.vertical, TranceSpacing.micro)
        }
    }
}

// MARK: - Category Chip

struct SessionCategoryChip: View {
    let category: MindMachineModel.SessionCategory
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: category.icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(category.rawValue)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
            }
            .foregroundStyle(isSelected ? Color.white : category.color)
            .padding(.horizontal, TranceSpacing.inner)
            .padding(.vertical, 7)
            .background(isSelected ? category.color : category.color.opacity(0.1))
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(isSelected ? Color.clear : category.color.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.2), value: isSelected)
    }
}
