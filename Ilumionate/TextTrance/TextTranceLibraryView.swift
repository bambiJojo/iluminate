//  TextTranceLibraryView.swift
//  Ilumionate
//
//  Script picker: theme filter + cards. Tapping a card pushes setup.

import SwiftUI
import os

/// Typed navigation values for the Text Trance stack (avoids bare-String
/// destination collisions as more destinations join this stack).
enum TextTranceDestination: Hashable {
    case setup(scriptID: String)
    case readingSources
}

struct TextTranceLibraryView: View {
    @State private var importedStore = ImportedTranceScriptStore.shared
    @State private var scripts: [TranceScript] = []
    @State private var themeFilter: ScriptTheme?
    @State private var showingWebImport = false
    @State private var importedSetupScript: TranceScript?

    var body: some View {
        ZStack {
            AuroraBackground()
            ScrollView {
                LazyVStack(spacing: TranceSpacing.cardMargin) {
                    ScriptLibrarySummaryCard(scripts: scripts)
                    ThemeChipsRow(selection: $themeFilter)
                    Button {
                        TranceHaptics.shared.light()
                        showingWebImport = true
                    } label: {
                        WebImportEntryCard()
                    }
                    .buttonStyle(.plain)

                    if filteredScripts.isEmpty {
                        EmptyScriptLibraryCard()
                    } else {
                        ForEach(filteredScripts) { script in
                            NavigationLink(value: TextTranceDestination.setup(scriptID: script.id)) {
                                ScriptCard(script: script)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    NavigationLink(value: TextTranceDestination.readingSources) {
                        ReadingSourcesEntryCard()
                    }
                    .buttonStyle(.plain)
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
            if scripts.isEmpty { reloadScripts() }
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
        do {
            try importedStore.save(script)
            reloadScripts()
            return
        } catch {
            Log.ui.info("[TextTranceLibraryView] Import was not persisted: \(error.localizedDescription)")
        }

        scripts.removeAll { $0.id == script.id }
        scripts.insert(script, at: 0)
    }

    private func reloadScripts() {
        let importedScripts = importedStore.importedScripts
        let importedIDs = Set(importedScripts.map(\.id))
        scripts = importedScripts + TranceScriptLibrary.bundled().filter { script in
            importedIDs.contains(script.id) == false
        }
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
                HStack(alignment: .top, spacing: TranceSpacing.list) {
                    ScriptThemeIcon(theme: script.theme)

                    VStack(alignment: .leading, spacing: TranceSpacing.micro) {
                        Text(script.title)
                            .font(TranceTypography.sectionTitle)
                            .foregroundStyle(Color.textPrimary)
                        Text(script.theme.displayName)
                            .font(TranceTypography.caption)
                            .foregroundStyle(Color.textSecondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(TranceTypography.caption)
                        .foregroundStyle(Color.textSecondary)
                }

                Text(script.librarySummary)
                    .font(TranceTypography.body)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 6) {
                    MetricPill(systemImage: "clock", text: script.durationSummary)
                    MetricPill(systemImage: "textformat", text: script.wordCountSummary)
                }

                Text(script.phaseSummary)
                    .font(TranceTypography.caption)
                    .foregroundStyle(Color.textLight)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    TagChip(text: script.arcSummary)
                    if script.source.kind == .importedWeb { TagChip(text: "Web") }
                    if script.source.reviewed { TagChip(text: "Reviewed") }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct ScriptLibrarySummaryCard: View {
    let scripts: [TranceScript]

    var body: some View {
        LiminalCard(label: "Script library") {
            HStack(spacing: TranceSpacing.list) {
                SummaryValue(value: scripts.count.formatted(.number), label: "sessions")
                Divider()
                    .frame(height: 32)
                    .overlay(Color.glassBorder)
                SummaryValue(value: themeCount.formatted(.number), label: "themes")
                Divider()
                    .frame(height: 32)
                    .overlay(Color.glassBorder)
                SummaryValue(value: durationRange, label: "read time")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var themeCount: Int {
        Set(scripts.map(\.theme.rawValue)).count
    }

    private var durationRange: String {
        let durations = scripts.flatMap { script in
            script.supportedArcs.map { script.metrics(for: $0).estimatedDuration }
        }
        let minutes = durations.map { max(1, Int(($0 / 60).rounded())) }
        guard let min = minutes.min(), let max = minutes.max() else { return "0 min" }
        if min == max { return min == 1 ? "1 min" : "\(min) min" }
        return "\(min)-\(max) min"
    }
}

private struct SummaryValue: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(TranceTypography.sectionTitle)
                .foregroundStyle(Color.textPrimary)
            Text(label)
                .font(TranceTypography.caption)
                .foregroundStyle(Color.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct EmptyScriptLibraryCard: View {
    var body: some View {
        GlassCard(label: nil) {
            HStack(spacing: TranceSpacing.list) {
                Image(systemName: "text.magnifyingglass")
                    .foregroundStyle(Color.textSecondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("No scripts here")
                        .font(TranceTypography.sectionTitle)
                        .foregroundStyle(Color.textPrimary)
                    Text("Import or reading sources can add one.")
                        .font(TranceTypography.caption)
                        .foregroundStyle(Color.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
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

private struct MetricPill: View {
    let systemImage: String
    let text: String

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(TranceTypography.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.glassBorder.opacity(0.28), in: .capsule)
            .foregroundStyle(Color.textSecondary)
    }
}

private struct ScriptThemeIcon: View {
    let theme: ScriptTheme

    var body: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(theme.accent.opacity(0.18))
            .frame(width: 40, height: 40)
            .overlay {
                Image(systemName: theme.symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(theme.accent)
            }
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

private extension ScriptTheme {
    var symbol: String {
        switch self {
        case .relaxation: return "wind"
        case .sleep:      return "moon.zzz"
        case .focus:      return "scope"
        case .suggestion: return "sparkles"
        }
    }

    var accent: Color {
        switch self {
        case .relaxation: return .auroraTeal
        case .sleep:      return .bwDelta
        case .focus:      return .bwBeta
        case .suggestion: return .auroraPink
        }
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
