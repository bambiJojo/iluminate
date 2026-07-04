//
//  PlaylistEditorView.swift
//  LumeSync
//
//  Apple Music-style playlist editor:
//  gradient artwork, inline name editing, search-enabled session picker,
//  native drag-to-reorder and swipe-to-delete track list.
//

import SwiftUI

// MARK: - PlaylistEditorView

struct PlaylistEditorView: View {

    @Binding var playlist: Playlist
    var isNew: Bool
    var onSave: (Playlist) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var showingSessionPicker = false
    @State private var availableAudioFiles: [AudioFile] = []
    @State private var storedAudioFiles: [AudioFile] = []
    @State private var isQuickAnalyzing = false
    @State private var quickAnalysisAlert: PlaylistEditorAlert?
    @FocusState private var nameFieldFocused: Bool

    var body: some View {
        NavigationStack {
            List {
                // ── Artwork + Name header ──────────────────────────────────
                Section {
                    artworkHeader
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(.init(top: 0, leading: 0, bottom: 0, trailing: 0))
                }

                // ── Smart Transitions row ──────────────────────────────────
                Section {
                    HStack(spacing: TranceSpacing.list) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.roseGold.opacity(0.18))
                                .frame(width: 32, height: 32)
                            Image(systemName: "waveform.path.ecg")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.roseGold)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Smart Transitions")
                                .font(TranceTypography.body)
                                .foregroundColor(.textPrimary)
                            Text(playlist.smartTransitions
                                 ? "Crossfades audio and light between sessions"
                                 : "Sessions play back-to-back")
                                .font(TranceTypography.caption)
                                .foregroundColor(.textLight)
                        }
                        Spacer()
                        Toggle("", isOn: $playlist.smartTransitions)
                            .tint(.roseGold)
                            .labelsHidden()
                    }
                    .padding(.vertical, 4)
                }
                .listRowBackground(Color.bgCard)

                if !playlist.items.isEmpty {
                    Section {
                        wholeSessionAnalysisRow
                    }
                    .listRowBackground(Color.bgCard)
                }

                // ── Tracks section ─────────────────────────────────────────
                Section {
                    if playlist.items.isEmpty {
                        emptyTracksState
                        .listRowBackground(Color.bgCard)
                            .listRowSeparator(.hidden)
                    } else {
                        ForEach(playlist.items) { item in
                            TrackRow(item: item, audioFiles: storedAudioFiles)
                                .listRowBackground(Color.bgCard)
                                .listRowSeparator(.hidden)
                        }
                        .onMove(perform: moveItems)
                        .onDelete(perform: deleteItems)
                    }
                } header: {
                    tracksHeader
                } footer: {
                    if !playlist.items.isEmpty {
                        HStack {
                            Image(systemName: "clock")
                                .font(.caption2)
                            Text("Total \(playlist.totalDurationFormatted)")
                        }
                        .font(TranceTypography.caption)
                        .foregroundColor(.textLight)
                        .padding(.top, 4)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color.bgPrimary.ignoresSafeArea())
            .environment(\.editMode, .constant(playlist.items.isEmpty ? .inactive : .active))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .sheet(isPresented: $showingSessionPicker) {
                SessionPickerView(
                    audioFiles: availableAudioFiles,
                    existingItemIds: Set(playlist.items.map(\.audioFileId)),
                    onAddFiles: { files in
                        for file in files { addItem(from: file) }
                    }
                )
            }
            .alert(item: $quickAnalysisAlert) { alert in
                Alert(
                    title: Text(alert.title),
                    message: Text(alert.message),
                    dismissButton: .default(Text("OK"))
                )
            }
            .onAppear { loadAvailableFiles() }
        }
    }

    // MARK: - Artwork + Name Header

    private var artworkHeader: some View {
        VStack(spacing: TranceSpacing.content) {
            // Gradient artwork
            artworkView
                .frame(width: 200, height: 200)
                .clipShape(RoundedRectangle(cornerRadius: TranceRadius.pattern))
                .shadow(color: artworkTopColor.opacity(0.35), radius: 20, x: 0, y: 10)

            // Editable name
            TextField("Playlist Name", text: $playlist.name, axis: .vertical)
                .focused($nameFieldFocused)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
                .foregroundColor(.textPrimary)
                .submitLabel(.done)
                .onSubmit { nameFieldFocused = false }
                .tint(.roseGold)
                .onAppear {
                    if isNew { nameFieldFocused = true }
                }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, TranceSpacing.content)
    }

    // Gradient artwork — constraint-based mosaic shared with the library tab
    private var artworkView: some View {
        PlaylistArtworkView(types: dominantContentTypes,
                            cornerRadius: TranceRadius.pattern,
                            iconSize: 56)
    }

    private var dominantContentTypes: [AnalysisResult.ContentType] {
        // Collect unique content types from playlist items
        let allFiles = playlist.items.compactMap { item -> AudioFile? in
            storedAudioFiles.first { $0.id == item.audioFileId }
        }
        return PlaylistArtwork.distinctTypes(from: allFiles.map { $0.analysisResult?.contentType })
    }

    private var artworkTopColor: Color {
        PlaylistArtwork.dominantColor(for: dominantContentTypes)
    }

    // MARK: - Whole Session Analysis

    private var wholeSessionAnalysisRow: some View {
        HStack(spacing: TranceSpacing.list) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.bwTheta.opacity(0.16))
                    .frame(width: 36, height: 36)
                Image(systemName: "sparkles")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.bwTheta)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Whole Journey")
                    .font(TranceTypography.body)
                    .foregroundColor(.textPrimary)
                Text(wholeSessionAnalysisStatusText)
                    .font(TranceTypography.caption)
                    .foregroundColor(.textLight)
                    .lineLimit(2)
            }

            Spacer()

            Button {
                Task { @MainActor in
                    quickAnalyzePlaylist()
                }
            } label: {
                if isQuickAnalyzing {
                    ProgressView()
                        .tint(.roseGold)
                } else {
                    Label(wholeSessionAnalysisButtonTitle, systemImage: "waveform.path.ecg")
                        .font(TranceTypography.caption)
                        .fontWeight(.semibold)
                }
            }
            .foregroundColor(.roseGold)
            .buttonStyle(.bordered)
            .disabled(!canQuickAnalyzePlaylist || isQuickAnalyzing)
        }
        .padding(.vertical, 4)
    }

    private var wholeSessionAnalysisStatusText: String {
        if !missingAudioFileNames.isEmpty {
            return "\(missingAudioFileNames.count) session unavailable"
        }
        if !missingAnalysisNames.isEmpty {
            return "Needs \(missingAnalysisNames.count) analyzed session\(missingAnalysisNames.count == 1 ? "" : "s")"
        }
        guard let analysis = playlist.wholeSessionAnalysis else {
            return "Not built yet"
        }
        if analysis.isCurrent(for: playlist) {
            return analysis.phaseSummary.isEmpty ? "Ready" : "Ready: \(analysis.phaseSummary)"
        }
        return "Playlist changed; refresh needed"
    }

    private var wholeSessionAnalysisButtonTitle: String {
        guard let analysis = playlist.wholeSessionAnalysis else { return "Analyze" }
        return analysis.isCurrent(for: playlist) ? "Refresh" : "Update"
    }

    private var canQuickAnalyzePlaylist: Bool {
        missingAudioFileNames.isEmpty && missingAnalysisNames.isEmpty
    }

    private var missingAudioFileNames: [String] {
        playlist.items.compactMap { item in
            storedAudioFiles.contains(where: { $0.id == item.audioFileId }) ? nil : item.displayName
        }
    }

    private var missingAnalysisNames: [String] {
        playlist.items.compactMap { item in
            guard let file = storedAudioFiles.first(where: { $0.id == item.audioFileId }) else { return nil }
            return file.analysisResult == nil ? item.displayName : nil
        }
    }

    private func quickAnalyzePlaylist() {
        loadAvailableFiles()
        guard canQuickAnalyzePlaylist else {
            quickAnalysisAlert = PlaylistEditorAlert(
                title: "Whole Journey",
                message: wholeSessionAnalysisStatusText
            )
            return
        }

        isQuickAnalyzing = true
        defer { isQuickAnalyzing = false }

        do {
            let result = try PlaylistWholeSessionAnalyzer().build(
                playlist: playlist,
                audioFiles: storedAudioFiles
            )
            let session = SessionGenerator(config: AnalyzerConfigLoader.load().sessionGeneration)
                .generateSession(
                    from: result.virtualAudioFile,
                    analysis: result.analysis,
                    config: AnalysisPreferences.shared.generationConfig
                )
            try PlaylistGeneratedSessionStore.shared.save(session, for: playlist)
            playlist.wholeSessionAnalysis = result.summary
            TranceHaptics.shared.medium()
            quickAnalysisAlert = PlaylistEditorAlert(
                title: "Whole Journey Ready",
                message: result.summary.phaseSummary.isEmpty
                    ? "Built one light score across the playlist."
                    : "Built one light score across: \(result.summary.phaseSummary)"
            )
        } catch {
            quickAnalysisAlert = PlaylistEditorAlert(
                title: "Could Not Analyze Playlist",
                message: error.localizedDescription
            )
        }
    }

    // MARK: - Tracks Section Header

    private var tracksHeader: some View {
        HStack(alignment: .center) {
            Text("Sessions")
                .font(TranceTypography.sectionTitle)
                .fontWeight(.semibold)
                .foregroundColor(.textPrimary)
                .textCase(nil)

            if !playlist.items.isEmpty {
                Text("\(playlist.itemCount)")
                    .font(TranceTypography.caption)
                    .foregroundColor(.textLight)
                    .textCase(nil)
            }

            Spacer()

            Button {
                TranceHaptics.shared.light()
                loadAvailableFiles()
                showingSessionPicker = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .bold))
                    Text("Add")
                        .font(TranceTypography.caption)
                        .fontWeight(.semibold)
                }
                .foregroundColor(.roseGold)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(Color.roseGold.opacity(0.12))
                .clipShape(Capsule())
            }
            .textCase(nil)
        }
    }

    // MARK: - Empty Tracks State

    private var emptyTracksState: some View {
        VStack(spacing: TranceSpacing.card) {
            Image(systemName: "music.note.list")
                .font(.system(size: 40, weight: .ultraLight))
                .foregroundStyle(
                    LinearGradient(colors: [.roseGold, .bwTheta], startPoint: .top, endPoint: .bottom)
                )
                .padding(.top, TranceSpacing.content)

            Text("No Sessions Yet")
                .font(TranceTypography.body)
                .fontWeight(.semibold)
                .foregroundColor(.textPrimary)

            Text("Add analyzed sessions to build your playlist")
                .font(TranceTypography.caption)
                .foregroundColor(.textSecondary)
                .multilineTextAlignment(.center)

            Button {
                TranceHaptics.shared.medium()
                loadAvailableFiles()
                showingSessionPicker = true
            } label: {
                Label("Add Sessions", systemImage: "plus.circle.fill")
                    .font(TranceTypography.body)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .padding(.horizontal, TranceSpacing.content)
                    .padding(.vertical, TranceSpacing.card)
                    .background(
                        LinearGradient(colors: [.roseGold, .roseDeep],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: TranceRadius.button))
            }
            .buttonStyle(PlainButtonStyle())
            .padding(.bottom, TranceSpacing.content)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { dismiss() }
                .foregroundColor(.roseGold)
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("Done") {
                onSave(playlist)
                dismiss()
            }
            .fontWeight(.bold)
            .foregroundColor(.roseGold)
            .disabled(playlist.name.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    // MARK: - Actions

    private func addItem(from file: AudioFile) {
        guard !playlist.items.contains(where: { $0.audioFileId == file.id }) else { return }
        let item = PlaylistItem(audioFileId: file.id, filename: file.filename, duration: file.duration)
        playlist.items.append(item)
    }

    private func moveItems(from source: IndexSet, to destination: Int) {
        playlist.items.move(fromOffsets: source, toOffset: destination)
    }

    private func deleteItems(at offsets: IndexSet) {
        playlist.items.remove(atOffsets: offsets)
    }

    private func loadAvailableFiles() {
        guard let data = UserDefaults.standard.data(forKey: "audioFiles"),
              let files = try? JSONDecoder().decode([AudioFile].self, from: data) else { return }
        storedAudioFiles = files
        availableAudioFiles = files.filter { hasGeneratedSession(for: $0) }
    }

    private func hasGeneratedSession(for file: AudioFile) -> Bool {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let sessionsDir = docs.appendingPathComponent("GeneratedSessions", isDirectory: true)
        // Check both ID-based and name-based session file conventions
        let byId = sessionsDir.appendingPathComponent("\(file.id).json")
        let byName = sessionsDir.appendingPathComponent(
            file.filename
                .replacingOccurrences(of: ".mp3", with: "")
                .replacingOccurrences(of: ".m4a", with: "")
                .replacingOccurrences(of: ".wav", with: "")
                + "_session.json"
        )
        return FileManager.default.fileExists(atPath: byId.path)
            || FileManager.default.fileExists(atPath: byName.path)
    }
}

private struct PlaylistEditorAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

// MARK: - TrackRow

private struct TrackRow: View {
    let item: PlaylistItem
    let audioFiles: [AudioFile]

    private var audioFile: AudioFile? {
        audioFiles.first { $0.id == item.audioFileId }
    }

    private var contentType: AnalysisResult.ContentType {
        audioFile?.analysisResult?.contentType ?? .unknown
    }

    var body: some View {
        HStack(spacing: TranceSpacing.list) {
            SessionGlowDot(contentType: contentType, size: 44)

            // Title + metadata
            VStack(alignment: .leading, spacing: 3) {
                Text(item.displayName)
                    .font(TranceTypography.body)
                    .fontWeight(.medium)
                    .foregroundColor(.textPrimary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    if let creator = audioFile?.creator, !creator.isEmpty {
                        Text(creator)
                            .font(TranceTypography.caption)
                            .foregroundColor(.roseGold)
                        Text("·")
                            .font(TranceTypography.caption)
                            .foregroundColor(.textLight)
                    }
                    Text(item.durationFormatted)
                        .font(TranceTypography.caption)
                        .foregroundColor(.textLight)
                }
            }
        }
        .padding(.vertical, 6)
    }
}

// MARK: - SessionPickerView (Apple Music-style "Add Sessions" sheet)

struct SessionPickerView: View {

    let audioFiles: [AudioFile]
    let existingItemIds: Set<UUID>
    var onAddFiles: ([AudioFile]) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""
    @State private var selectedFilter: ContentFilterOption = .all
    @State private var selectedIds = Set<UUID>()

    enum ContentFilterOption: String, CaseIterable {
        case all = "All"
        case hypnosis = "Hypnosis"
        case meditation = "Meditation"
        case music = "Music"
        case guided = "Guided"
        case affirmations = "Affirmations"

        var icon: String {
            switch self {
            case .all:          return "list.bullet"
            case .hypnosis:     return "brain.head.profile"
            case .meditation:   return "leaf"
            case .music:        return "music.note"
            case .guided:       return "figure.mind.and.body"
            case .affirmations: return "quote.bubble"
            }
        }

        func matches(_ file: AudioFile) -> Bool {
            switch self {
            case .all: return true
            case .hypnosis:     return file.analysisResult?.contentType == .hypnosis
            case .meditation:   return file.analysisResult?.contentType == .meditation
            case .music:        return file.analysisResult?.contentType == .music
            case .guided:       return file.analysisResult?.contentType == .guidedImagery
            case .affirmations: return file.analysisResult?.contentType == .affirmations
            }
        }
    }

    private var filteredFiles: [AudioFile] {
        audioFiles.filter { file in
            let matchesSearch = searchText.isEmpty
                || file.displayName.localizedCaseInsensitiveContains(searchText)
                || (file.creator ?? "").localizedCaseInsensitiveContains(searchText)
            let matchesFilter = selectedFilter.matches(file)
            return matchesSearch && matchesFilter
        }
    }

    private var newlySelectedCount: Int {
        selectedIds.subtracting(existingItemIds).count
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Color.bgPrimary.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Search bar
                    HStack(spacing: TranceSpacing.inner) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.textLight)
                        TextField("Search sessions…", text: $searchText)
                            .foregroundColor(.textPrimary)
                            .font(TranceTypography.body)
                        if !searchText.isEmpty {
                            Button { searchText = "" } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.textLight)
                            }
                        }
                    }
                    .padding(TranceSpacing.card)
                    .background(Color.bgCard)
                    .clipShape(RoundedRectangle(cornerRadius: TranceRadius.button))
                    .overlay(RoundedRectangle(cornerRadius: TranceRadius.button)
                        .strokeBorder(Color.glassBorder, lineWidth: 1))
                    .padding(.horizontal, TranceSpacing.screen)
                    .padding(.top, TranceSpacing.card)

                    // Content type filter chips
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: TranceSpacing.inner) {
                            ForEach(ContentFilterOption.allCases, id: \.rawValue) { option in
                                FilterChip(
                                    icon: option.icon,
                                    title: option.rawValue,
                                    isActive: selectedFilter == option
                                ) {
                                    TranceHaptics.shared.light()
                                    selectedFilter = option
                                }
                            }
                        }
                        .padding(.horizontal, TranceSpacing.screen)
                        .padding(.vertical, TranceSpacing.inner)
                    }

                    // Session list
                    if filteredFiles.isEmpty {
                        Spacer()
                        VStack(spacing: TranceSpacing.card) {
                            Image(systemName: searchText.isEmpty ? "waveform.badge.exclamationmark" : "magnifyingglass")
                                .font(.system(size: 44, weight: .ultraLight))
                                .foregroundColor(.textLight)
                            Text(searchText.isEmpty
                                 ? "No sessions available"
                                 : "No results for \"\(searchText)\"")
                                .font(TranceTypography.body)
                                .foregroundColor(.textSecondary)
                            if searchText.isEmpty {
                                Text("Analyze audio files first to add them to a playlist")
                                    .font(TranceTypography.caption)
                                    .foregroundColor(.textLight)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, TranceSpacing.screen)
                            }
                        }
                        Spacer()
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(filteredFiles) { file in
                                    PickerSessionRow(
                                        file: file,
                                        isAlreadyAdded: existingItemIds.contains(file.id),
                                        isSelected: selectedIds.contains(file.id)
                                    ) {
                                        TranceHaptics.shared.light()
                                        if existingItemIds.contains(file.id) { return }
                                        if selectedIds.contains(file.id) {
                                            selectedIds.remove(file.id)
                                        } else {
                                            selectedIds.insert(file.id)
                                        }
                                    }

                                    if file.id != filteredFiles.last?.id {
                                        Rectangle()
                                            .fill(Color.glassBorder.opacity(0.25))
                                            .frame(height: 1)
                                            .padding(.leading, 60)
                                    }
                                }
                            }
                            .padding(.horizontal, TranceSpacing.screen)
                            .background(Color.bgCard)
                            .clipShape(RoundedRectangle(cornerRadius: TranceRadius.glassCard))
                            .overlay(RoundedRectangle(cornerRadius: TranceRadius.glassCard)
                                .strokeBorder(Color.glassBorder, lineWidth: 1))
                            .padding(.horizontal, TranceSpacing.screen)
                            .padding(.top, TranceSpacing.inner)
                            // Bottom pad for button
                            Color.clear.frame(height: 100)
                        }
                    }
                }

                // ── Floating "Add N Sessions" button ──────────────────────
                if newlySelectedCount > 0 {
                    Button {
                        let toAdd = filteredFiles.filter { selectedIds.contains($0.id)
                            && !existingItemIds.contains($0.id) }
                        onAddFiles(toAdd)
                        dismiss()
                    } label: {
                        Text("Add \(newlySelectedCount) \(newlySelectedCount == 1 ? "Session" : "Sessions")")
                            .font(TranceTypography.body)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, TranceSpacing.card)
                            .background(
                                LinearGradient(colors: [.roseGold, .roseDeep],
                                               startPoint: .topLeading, endPoint: .bottomTrailing)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: TranceRadius.button))
                            .shadow(color: Color.roseGold.opacity(0.35), radius: 12, x: 0, y: 6)
                    }
                    .padding(.horizontal, TranceSpacing.screen)
                    .padding(.bottom, TranceSpacing.content)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(.spring(response: 0.35, dampingFraction: 0.75), value: newlySelectedCount)
                }
            }
            .navigationTitle("Add Sessions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(.roseGold)
                }
            }
        }
    }
}

// MARK: - PickerSessionRow

private struct PickerSessionRow: View {
    let file: AudioFile
    let isAlreadyAdded: Bool
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: TranceSpacing.list) {
                SessionGlowDot(contentType: file.analysisResult?.contentType, size: 44)

                // Info
                VStack(alignment: .leading, spacing: 3) {
                    Text(file.displayName)
                        .font(TranceTypography.body)
                        .fontWeight(.medium)
                        .foregroundColor(.textPrimary)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        if let creator = file.creator, !creator.isEmpty {
                            Text(creator)
                                .font(TranceTypography.caption)
                                .foregroundColor(.roseGold)
                            Text("·")
                                .font(TranceTypography.caption)
                                .foregroundColor(.textLight)
                        }
                        Text(file.durationFormatted)
                            .font(TranceTypography.caption)
                            .foregroundColor(.textLight)
                    }
                }

                Spacer()

                // State indicator
                Group {
                    if isAlreadyAdded {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 22))
                            .foregroundColor(.textLight)
                    } else if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 22))
                            .foregroundColor(.roseGold)
                    } else {
                        Image(systemName: "circle")
                            .font(.system(size: 22))
                            .foregroundColor(.textLight)
                    }
                }
                .animation(.spring(response: 0.25), value: isSelected)
            }
            .padding(.vertical, TranceSpacing.card)
            .opacity(isAlreadyAdded ? 0.45 : 1.0)
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(isAlreadyAdded)
    }
}

// MARK: - FilterChip

private struct FilterChip: View {
    let icon: String
    let title: String
    let isActive: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                Text(title)
                    .font(TranceTypography.caption)
                    .fontWeight(.medium)
            }
            .foregroundColor(isActive ? .roseGold : .textSecondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(isActive ? Color.roseGold.opacity(0.12) : Color.glassBorder.opacity(0.08))
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(
                isActive ? Color.roseGold.opacity(0.5) : Color.glassBorder.opacity(0.25),
                lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}
