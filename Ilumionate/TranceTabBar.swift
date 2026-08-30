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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            ForEach(TranceTab.allCases, id: \.self) { tab in
                tabItem(tab)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 10)
        // Four labels share one capsule across the screen width. Past `.xxLarge` they wrap
        // and the bar grows tall enough to cover the content behind it, so growth is capped
        // here — UIKit's own tab bar clamps its labels the same way and hands the full-size
        // text to the large-content HUD instead.
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .liminalGlass(.capsule)
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
    }

    // MARK: - Single Tab Item

    @ViewBuilder
    private func tabItem(_ tab: TranceTab) -> some View {
        let isSelected = selected == tab

        Button {
            if reduceMotion {
                selected = tab
            } else {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                    selected = tab
                }
            }
            TranceHaptics.shared.light()
        } label: {
            VStack(spacing: 2) {
                Image(systemName: tab.sfSymbol)
                    .font(.system(size: 18, weight: isSelected ? .semibold : .regular))
                    .symbolEffect(.bounce, value: reduceMotion ? tab : selected)

                Text(tab.title)
                    .font(.system(.caption2, weight: isSelected ? .semibold : .regular))
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? tabAccentColor : Color.textLight)
            .scaleEffect(isSelected && !reduceMotion ? 1.05 : 1.0)
            .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.65), value: selected)
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
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
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