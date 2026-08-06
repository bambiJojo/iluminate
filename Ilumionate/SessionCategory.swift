//
//  SessionCategory.swift
//  Ilumionate
//
//  The brainwave-category filter and its chips.
//
//  Extracted when the Create tab stopped embedding a session browser: the
//  browser section that used to live alongside these was dead once
//  BrowseSessionsView became the full-page browser, but the filter itself is
//  still what BrowseSessionsView filters by.
//

import SwiftUI

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
}

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
