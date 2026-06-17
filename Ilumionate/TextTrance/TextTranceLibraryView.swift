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
    @State private var showingWebImport = false
    @State private var importedSetupScript: TranceScript?

    var body: some View {
        ZStack {
            AuroraBackground()
            ScrollView {
                VStack(spacing: TranceSpacing.cardMargin) {
                    ThemeChipsRow(selection: $themeFilter)
                    Button {
                        TranceHaptics.shared.light()
                        showingWebImport = true
                    } label: {
                        WebImportEntryCard()
                    }
                    .buttonStyle(.plain)

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
                    // Clear the app's floating tab bar so the last card isn't cut off.
                    Color.clear.frame(height: TranceSpacing.tabBarClearance)
                }
                .padding(TranceSpacing.screen)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("Text Trance")
        .sheet(isPresented: $showingWebImport) {
            WebTextImportSheet { script in
                insertImportedScript(script)
                importedSetupScript = script
            }
        }
        .navigationDestination(for: TextTranceDestination.self) { destination in
            switch destination {
            case .setup(let id):
                if let script = scripts.first(where: { $0.id == id }) {
                    TextTranceSetupView(script: script)
                }
            case .readingSources:
                ReadingSourceDirectoryView(store: .shared) { script in
                    insertImportedScript(script)
                    importedSetupScript = script
                }
            }
        }
        .navigationDestination(isPresented: importedSetupPresented) {
            if let importedSetupScript {
                TextTranceSetupView(script: importedSetupScript)
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

    private var importedSetupPresented: Binding<Bool> {
        Binding(
            get: { importedSetupScript != nil },
            set: { if !$0 { importedSetupScript = nil } }
        )
    }

    private func insertImportedScript(_ script: TranceScript) {
        scripts.removeAll { $0.id == script.id }
        scripts.insert(script, at: 0)
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
        LiminalCard(label: nil) {
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
                    if script.source.kind == .importedWeb { TagChip(text: "Web") }
                    if script.source.reviewed { TagChip(text: "Reviewed") }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct GeneratePlaceholderCard: View {
    var body: some View {
        LiminalCard(label: nil) {
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

private struct WebImportEntryCard: View {
    var body: some View {
        GlassCard(label: nil) {
            HStack(spacing: TranceSpacing.list) {
                Image(systemName: "square.and.arrow.down")
                    .foregroundStyle(Color.bwTheta)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Import webpage")
                        .font(TranceTypography.sectionTitle)
                        .foregroundStyle(Color.textPrimary)
                    Text("Extract clean text for the reader.")
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

/// Entry point from the Read tab into the link-only Reading Sources directory.
private struct ReadingSourcesEntryCard: View {
    var body: some View {
        LiminalCard(label: nil) {
            HStack(spacing: TranceSpacing.list) {
                Image(systemName: "globe")
                    .foregroundStyle(Color.auroraTeal)
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
            .background(Color.auroraTeal.opacity(0.18), in: .capsule)
            .foregroundStyle(Color.auroraTeal)
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
                isOn ? Color.auroraTeal.opacity(0.22) : Color.glassBorder.opacity(0.4),
                in: .capsule
            )
            .foregroundStyle(isOn ? Color.auroraTeal : Color.textSecondary)
            .buttonStyle(.plain)
    }
}

private struct WebTextImportSheet: View {
    let importer: WebReadableTextImporter
    let onImported: (TranceScript) -> Void

    @State private var urlString = ""
    @State private var title = ""
    @State private var importState: ImportState = .idle

    @Environment(\.dismiss) private var dismiss

    init(importer: WebReadableTextImporter = WebReadableTextImporter(),
         onImported: @escaping (TranceScript) -> Void) {
        self.importer = importer
        self.onImported = onImported
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Page") {
                    TextField("URL", text: $urlString)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Title", text: $title)
                        .textInputAutocapitalization(.words)
                }

                if importState.isImporting {
                    Section {
                        ProgressView("Importing")
                    }
                }

                if case .failed(let message) = importState {
                    Section {
                        Text(message)
                            .font(TranceTypography.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Import Webpage")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .disabled(importState.isImporting)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Import") {
                        Task { await importPage() }
                    }
                    .fontWeight(.semibold)
                    .disabled(importDisabled)
                }
            }
        }
    }

    private var importDisabled: Bool {
        importState.isImporting || urlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func importPage() async {
        importState = .importing
        do {
            let script = try await importer.importScript(from: urlString, title: title)
            onImported(script)
            dismiss()
        } catch {
            importState = .failed(error.localizedDescription)
        }
    }

    private enum ImportState: Equatable {
        case idle
        case importing
        case failed(String)

        var isImporting: Bool {
            if case .importing = self { return true }
            return false
        }
    }
}

#Preview {
    NavigationStack { TextTranceLibraryView() }
}
