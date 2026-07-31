// AudioLibraryView+Sections.swift
// Ilumionate
//

import SwiftUI

extension AudioLibraryView {

    // MARK: - Empty State

    var emptyState: some View {
        ScrollView {
            VStack(spacing: TranceSpacing.content) {
                // Header
                VStack(spacing: TranceSpacing.card) {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 56, weight: .ultraLight))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.roseGold, .roseDeep],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .shadow(color: Color.roseGold.opacity(0.25), radius: 16, x: 0, y: 8)

                    VStack(spacing: TranceSpacing.inner) {
                        Text("No Audio Yet")
                            .font(TranceTypography.greeting)
                            .foregroundStyle(Color.textPrimary)

                        Text("Add your first audio file to get started")
                            .font(TranceTypography.body)
                            .foregroundStyle(Color.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.top, TranceSpacing.statusBar)

                // Import options surfaced inline
                importOptionsSection

                // AI hint
                HStack(spacing: TranceSpacing.icon) {
                    Image(systemName: "sparkles")
                        .font(.caption)
                        .foregroundStyle(Color.roseGold)
                    Text("AI will analyze your audio to create custom light sessions")
                        .font(TranceTypography.caption)
                        .foregroundStyle(Color.textLight)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, TranceSpacing.screen)
                .padding(.bottom, TranceSpacing.tabBarClearance)
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Audio Library Content

    var audioLibraryContent: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                // Search bar
                searchSection

                // Sort + Filters controls
                filterSortSection

                // Audio files list
                audioFilesGrid

                // Bottom spacing for selection toolbar or tab bar clearance
                Rectangle()
                    .fill(Color.clear)
                    .frame(height: isSelectionMode ? TranceSpacing.tabBarClearance + 80 : TranceSpacing.tabBarClearance)
            }
        }
        .platformFullScreenCover(item: $playerFile) { file in
            UnifiedPlayerView(mode: .audioLight(audioFile: file), engine: engine)
        }
    }

    // MARK: - Search Section

    var searchSection: some View {
        GlassCard {
            HStack(spacing: TranceSpacing.list) {
                Image(systemName: "magnifyingglass")
                    .font(TranceTypography.body)
                    .foregroundStyle(.textLight)

                TextField(searchTranscription ? "Search content & transcriptions..." : "Search audio files...", text: $searchText)
                    .font(TranceTypography.body)
                    .foregroundStyle(.textPrimary)

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(TranceTypography.body)
                            .foregroundStyle(.textLight)
                    }
                }
            }
        }
        .padding(.horizontal, TranceSpacing.screen)
        .padding(.top, TranceSpacing.card)
    }

    // MARK: - Sort + Filters Section

    /// A single compact row: the sort control, plus one "Filters" button that
    /// opens a sheet holding every filter option. This replaces the previous two
    /// horizontally-scrolling chip rows, where options scrolled off-screen and
    /// were hard to discover.
    var filterSortSection: some View {
        HStack(spacing: TranceSpacing.inner) {
            // Sort menu
            Menu {
                Picker("Sort By", selection: $sortOption) {
                    ForEach(SortOption.allCases, id: \.self) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.up.arrow.down")
                    Text(sortOption.rawValue)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                }
                .font(TranceTypography.caption)
                .fontWeight(.medium)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.glassBorder.opacity(0.1))
                .foregroundStyle(.textSecondary)
                .clipShape(Capsule())
                .overlay(
                    Capsule().strokeBorder(Color.glassBorder.opacity(0.3), lineWidth: 1)
                )
            }

            Spacer()

            // Filters button — count badge when filters are active
            Button {
                TranceHaptics.shared.light()
                showingFilters = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: activeFilterCount > 0 ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    Text("Filters")
                    if activeFilterCount > 0 {
                        Text("\(activeFilterCount)")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.roseGold, in: Capsule())
                    }
                }
                .font(TranceTypography.caption)
                .fontWeight(.medium)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(activeFilterCount > 0 ? Color.roseGold.opacity(0.15) : Color.glassBorder.opacity(0.1))
                .foregroundStyle(activeFilterCount > 0 ? .roseGold : .textSecondary)
                .clipShape(Capsule())
                .overlay(
                    Capsule().strokeBorder(activeFilterCount > 0 ? Color.roseGold.opacity(0.5) : Color.glassBorder.opacity(0.3), lineWidth: 1)
                )
            }
        }
        .padding(.horizontal, TranceSpacing.screen)
        .padding(.top, TranceSpacing.inner)
    }

    /// Number of non-default filters currently applied (drives the badge).
    var activeFilterCount: Int {
        var count = 0
        if contentFilter != .all { count += 1 }
        if durationFilter != .all { count += 1 }
        if tranceDepthFilter != .all { count += 1 }
        if showFavoritesOnly { count += 1 }
        if searchTranscription { count += 1 }
        return count
    }

    // MARK: - Filters Sheet

    /// All filter controls collected into one discoverable sheet.
    var filtersSheet: some View {
        NavigationStack {
            Form {
                Section("Content Type") {
                    Picker("Content Type", selection: $contentFilter) {
                        ForEach(ContentFilter.allCases, id: \.self) { filter in
                            Label {
                                if filter == .all {
                                    Text(filter.rawValue)
                                } else {
                                    Text("\(filter.rawValue) (\(filteredCount(for: filter)))")
                                }
                            } icon: {
                                Image(systemName: contentFilterIcon(filter))
                            }
                            .tag(filter)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                Section("Duration") {
                    Picker("Duration", selection: $durationFilter) {
                        ForEach(DurationFilter.allCases, id: \.self) { filter in
                            Text(filter.rawValue).tag(filter)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(.roseGold)
                }

                if audioFiles.contains(where: { $0.isAnalyzed && ($0.analysisResult.map { $0.contentType.isHypnosisLike } ?? false) }) {
                    Section("Trance Depth") {
                        Picker("Trance Depth", selection: $tranceDepthFilter) {
                            ForEach(TranceDepthFilter.allCases, id: \.self) { filter in
                                Text(filter.rawValue).tag(filter)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(.roseGold)
                    }
                }

                Section {
                    Toggle("Favorites Only", isOn: $showFavoritesOnly)
                        .tint(.roseGold)
                    if audioFiles.contains(where: { $0.hasTranscription }) {
                        Toggle("Search Transcriptions", isOn: $searchTranscription)
                            .tint(.roseGold)
                    }
                }

                if activeFilterCount > 0 {
                    Section {
                        Button(role: .destructive) {
                            TranceHaptics.shared.light()
                            contentFilter = .all
                            durationFilter = .all
                            tranceDepthFilter = .all
                            showFavoritesOnly = false
                            searchTranscription = false
                        } label: {
                            Label("Clear All Filters", systemImage: "xmark.circle")
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.bgPrimary.ignoresSafeArea())
            .navigationTitle("Filters")
            .platformInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showingFilters = false }
                        .foregroundStyle(.roseGold)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Filter Helpers

    func contentFilterIcon(_ filter: ContentFilter) -> String {
        switch filter {
        case .all: return "list.bullet"
        case .hypnosis: return "brain.head.profile"
        case .eroticHypnosis: return "flame"
        case .sleepHypnosis: return "moon.zzz"
        case .meditation: return "leaf"
        case .brainwave: return "waveform.path.ecg"
        case .asmr: return "ear"
        case .music: return "music.note"
        case .guided: return "figure.mind.and.body"
        case .affirmations: return "quote.bubble"
        case .analyzed: return "sparkles"
        case .unanalyzed: return "questionmark.circle"
        }
    }

    func filteredCount(for filter: ContentFilter) -> Int {
        audioFiles.filter { file in
            switch filter {
            case .all: return true
            case .hypnosis: return file.analysisResult?.contentType == .hypnosis
            case .eroticHypnosis: return file.analysisResult?.contentType == .eroticHypnosis
            case .sleepHypnosis: return file.analysisResult?.contentType == .sleepHypnosis
            case .meditation: return file.analysisResult?.contentType == .meditation
            case .brainwave: return file.analysisResult?.contentType == .brainwave
            case .asmr: return file.analysisResult?.contentType == .asmr
            case .music: return file.analysisResult?.contentType == .music
            case .guided: return file.analysisResult?.contentType == .guidedImagery
            case .affirmations: return file.analysisResult?.contentType == .affirmations
            case .analyzed: return file.isAnalyzed
            case .unanalyzed: return !file.isAnalyzed
            }
        }.count
    }

}
