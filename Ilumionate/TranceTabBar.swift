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
    case home      = "home"
    case library   = "library"
    case machine   = "machine"
    case playlists = "playlists"
    case store     = "store"

    var title: String {
        switch self {
        case .home:      "Home"
        case .library:   "Library"
        case .machine:   "Machine"
        case .playlists: "Playlists"
        case .store:     "Store"
        }
    }

    var sfSymbol: String {
        switch self {
        case .home:      "house.fill"
        case .library:   "books.vertical.fill"
        case .machine:   "lightbulb.fill"
        case .playlists: "music.note.list"
        case .store:     "bag.fill"
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
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.25), radius: 16, x: 0, y: 8)
        }
        .overlay {
            Capsule()
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        }
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
            VStack(spacing: 3) {
                Image(systemName: tab.sfSymbol)
                    .font(.system(size: 18, weight: isSelected ? .semibold : .regular))
                    .symbolEffect(.bounce, value: selected)
                    .foregroundStyle(isSelected ? tabAccentColor : .white.opacity(0.45))
                    .scaleEffect(isSelected ? 1.1 : 1.0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.65), value: selected)

                Text(tab.title)
                    .font(.system(size: 9, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? tabAccentColor : .white.opacity(0.45))
                    .animation(.easeInOut(duration: 0.2), value: selected)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background {
                if isSelected {
                    Capsule()
                        .fill(tabAccentColor.opacity(0.18))
                        .matchedGeometryEffect(id: "TAB_INDICATOR", in: tabAnimation)
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
    }

    // The tint for the active tab — uses the design system's rose-gold
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
                        .foregroundColor(.textPrimary)
                    Spacer()
                }

                TranceTabBar(selected: $selectedTab)
            }
        }
    }

    return Preview()
}