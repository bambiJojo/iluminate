//  TextTranceLibraryView.swift
//  Ilumionate
//
//  Script picker: theme filter + cards. Tapping a card pushes setup.

import SwiftUI

/// Typed navigation values for the Text Trance stack (avoids bare-String
/// destination collisions as more destinations join this stack).
enum TextTranceDestination: Hashable {
    case setup(scriptID: String)
    case readingSources
}

struct TextTranceLibraryView: View {
    @State private var scripts: [TranceScript] = []
    @State private var themeFilter: ScriptTheme?

    var body: some View {
        ScrollView {
            VStack(spacing: TranceSpacing.cardMargin) {
                ThemeChipsRow(selection: $themeFilter)
                ForEach(filteredScripts) { script in
                    NavigationLink(value: TextTranceDestination.setup(scriptID: script.id)) {
                        ScriptCard(script: script)
                    }
                    .buttonStyle(.plain)
                }
                NavigationLink(value: TextTranceDestination.readingSources) {
                    ReadingSourcesEntryCard()
                }
                .buttonStyle(.plain)
                GeneratePlaceholderCard()
            }
            .padding(TranceSpacing.screen)
        }
        .scrollIndicators(.hidden)
        .background(Color.bgPrimary.ignoresSafeArea())
        .navigationTitle("Text Trance")
        .navigationDestination(for: TextTranceDestination.self) { destination in
            switch destination {
            case .setup(let id):
                if let script = scripts.first(where: { $0.id == id }) {
                    TextTranceSetupView(script: script)
                }
            case .readingSources:
                ReadingSourceDirectoryView(store: .shared)
            }
        }
        .task {
            if scripts.isEmpty { scripts = TranceScriptLibrary.bundled() }
        }
    }

    private var filteredScripts: [TranceScript] {
        guard let themeFilter else { return scripts }
        return scripts.filter { $0.theme == themeFilter }
    }
}

private struct ThemeChipsRow: View {
    @Binding var selection: ScriptTheme?

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: TranceSpacing.list) {
                FilterChip(title: "All", isOn: selection == nil) { selection = nil }
                ForEach(ScriptTheme.allCases) { theme in
                    FilterChip(title: theme.displayName, isOn: selection == theme) {
                        selection = theme
                    }
                }
            }
            .padding(.vertical, TranceSpacing.micro)
        }
        .scrollIndicators(.hidden)
    }
}

private struct ScriptCard: View {
    let script: TranceScript

    var body: some View {
        GlassCard(label: nil) {
            VStack(alignment: .leading, spacing: TranceSpacing.list) {
                Text(script.title)
                    .font(TranceTypography.sectionTitle)
                    .foregroundStyle(Color.textPrimary)
                Text(script.theme.displayName)
                    .font(TranceTypography.caption)
                    .foregroundStyle(Color.textSecondary)
                HStack(spacing: 6) {
                    ForEach(script.supportedArcs) { arc in
                        TagChip(text: arc.displayName)
                    }
                    if script.source.reviewed { TagChip(text: "Reviewed") }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct GeneratePlaceholderCard: View {
    var body: some View {
        GlassCard(label: nil) {
            HStack {
                Image(systemName: "sparkles")
                VStack(alignment: .leading) {
                    Text("Generate new script")
                        .font(TranceTypography.sectionTitle)
                    Text("Coming soon")
                        .font(TranceTypography.caption)
                        .foregroundStyle(Color.textSecondary)
                }
                Spacer()
            }
            .foregroundStyle(Color.textSecondary)
        }
        .opacity(0.6)
    }
}

/// Entry point from the Read tab into the link-only Reading Sources directory.
private struct ReadingSourcesEntryCard: View {
    var body: some View {
        GlassCard(label: nil) {
            HStack(spacing: TranceSpacing.list) {
                Image(systemName: "globe")
                    .foregroundStyle(Color.roseGold)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Find more scripts online")
                        .font(TranceTypography.sectionTitle)
                        .foregroundStyle(Color.textPrimary)
                    Text("Public-domain libraries & script sites. Opens in your browser.")
                        .font(TranceTypography.caption)
                        .foregroundStyle(Color.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(TranceTypography.caption)
                    .foregroundStyle(Color.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct TagChip: View {
    let text: String
    var body: some View {
        Text(text)
            .font(TranceTypography.caption)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Color.roseGold.opacity(0.18), in: .capsule)
            .foregroundStyle(Color.roseGold)
    }
}

private struct FilterChip: View {
    let title: String
    let isOn: Bool
    let action: () -> Void
    var body: some View {
        Button(title, action: action)
            .font(TranceTypography.caption)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(
                isOn ? Color.roseGold.opacity(0.22) : Color.glassBorder.opacity(0.4),
                in: .capsule
            )
            .foregroundStyle(isOn ? Color.roseGold : Color.textSecondary)
            .buttonStyle(.plain)
    }
}

#Preview {
    NavigationStack { TextTranceLibraryView() }
}
