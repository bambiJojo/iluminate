//
//  TranceTabBar.swift
//  Ilumionate
//
//  Floating capsule tab bar with matchedGeometryEffect sliding indicator
//  and SF Symbol bounce animations — inspired by Kavsoft.
//

import SwiftUI

// MARK: - Tab Enum

enum TranceTab: String, CaseIterable {
    case home    = "home"
    case library = "library"
    case read    = "read"
    case create  = "create"

    var title: String {
        switch self {
        case .home:    "Home"
        case .library: "Library"
        case .read:    "Read"
        case .create:  "Create"
        }
    }

    var sfSymbol: String {
        switch self {
        case .home:    "house.fill"
        case .library: "books.vertical.fill"
        case .read:    "text.aligncenter"
        case .create:  "lightbulb.fill"
        }
    }
}

// MARK: - Tab Bar View

struct TranceTabBar: View {
    @Binding var selected: TranceTab
    @Namespace private var tabAnimation

    var body: some View {
        HStack(spacing: 0) {
            ForEach(TranceTab.allCases, id: \.self) { tab in
                tabItem(tab)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 10)
        .liminalGlass(.capsule)
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
    }

    // MARK: - Single Tab Item

    @ViewBuilder
    private func tabItem(_ tab: TranceTab) -> some View {
        let isSelected = selected == tab

        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                selected = tab
            }
            TranceHaptics.shared.light()
        } label: {
            VStack(spacing: 2) {
                Image(systemName: tab.sfSymbol)
                    .font(.system(size: 18, weight: isSelected ? .semibold : .regular))
                    .symbolEffect(.bounce, value: selected)

                Text(tab.title)
                    .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
            }
            .foregroundStyle(isSelected ? tabAccentColor : Color.textGhost)
            .scaleEffect(isSelected ? 1.05 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.65), value: selected)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background {
                if isSelected {
                    Capsule()
                        .fill(tabAccentColor.opacity(0.18))
                        .matchedGeometryEffect(id: "TAB_INDICATOR", in: tabAnimation)
                        .shadow(color: tabAccentColor.opacity(0.4), radius: 10)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // The tint for the active tab — `.roseGold` now resolves to the Liminal aurora teal
    private var tabAccentColor: Color { .roseGold }
}

// MARK: - Preview

#Preview {
    struct Preview: View {
        @State private var selectedTab: TranceTab = .home

        var body: some View {
            ZStack(alignment: .bottom) {
                Color.bgPrimary
                    .ignoresSafeArea()

                VStack {
                    Spacer()
                    Text("Tab: \(selectedTab.title)")
                        .font(TranceTypography.body)
                        .foregroundStyle(.textPrimary)
                    Spacer()
                }

                TranceTabBar(selected: $selectedTab)
            }
        }
    }

    return Preview()
}