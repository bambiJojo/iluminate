//
//  TranceTabBar.swift
//  Ilumionate
//
//  Five-tab navigation with glass morphism styling
//

import SwiftUI

enum TranceTab: String, CaseIterable {
    case home      = "🏠"
    case library   = "📚"
    case machine   = "💡"
    case playlists = "🎵"
    case store     = "🛒"
    case profile   = "👤"

    var title: String {
        switch self {
        case .home:    "Home"
        case .library: "Library"
        case .machine:   "Machine"
        case .playlists: "Playlists"
        case .store:     "Store"
        case .profile:   "Profile"
        }
    }

    var sfSymbol: String {
        switch self {
        case .home:    "house.fill"
        case .library: "books.vertical.fill"
        case .machine:   "lightbulb.fill"
        case .playlists: "music.note.list"
        case .store:     "bag.fill"
        case .profile:   "person.fill"
        }
    }
}

struct TranceTabBar: View {
    @Binding var selected: TranceTab

    var body: some View {
        HStack {
            ForEach(TranceTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selected = tab
                        TranceHaptics.shared.light()
                    }
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: tab.sfSymbol)
                            .font(.system(size: 20))
                        Text(tab.title)
                            .font(TranceTypography.tabLabel)
                    }
                    .foregroundColor(selected == tab ? .roseGold : .textLight)
                    .padding(.vertical, 4)
                    .padding(.horizontal, TranceSpacing.small)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, TranceSpacing.small)
        .padding(.bottom, TranceSpacing.statusBar) // safe area
        .background(.ultraThinMaterial)
        .background(Color.bgPrimary.opacity(0.9))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.glassBorder)
                .frame(height: 1)
        }
    }
}

// MARK: - Preview

#Preview {
    struct TranceTabBarPreview: View {
        @State private var selectedTab: TranceTab = .home

        var body: some View {
            VStack {
                Spacer()

                Text("Selected: \(selectedTab.title)")
                    .font(TranceTypography.body)
                    .foregroundColor(.textPrimary)

                Spacer()

                TranceTabBar(selected: $selectedTab)
            }
            .background(Color.bgPrimary)
        }
    }

    return TranceTabBarPreview()
}