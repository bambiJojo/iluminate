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

                // Filter and Sort controls
                filterSortSection

                // Audio files list
                audioFilesGrid

                // Bottom spacing for selection toolbar or tab bar clearance
                Rectangle()
                    .fill(Color.clear)
                    .frame(height: isSelectionMode ? TranceSpacing.tabBarClearance + 80 : TranceSpacing.tabBarClearance)
            }
        }
        .fullScreenCover(item: $playerFile) { file in
            AudioLightPlayerView(audioFile: file, engine: engine)
        }
    }

    // MARK: - Search Section

    var searchSection: some View {
        GlassCard {
            HStack(spacing: TranceSpacing.list) {
                Image(systemName: "magnifyingglass")
                    .font(TranceTypography.body)
                    .foregroundColor(.textLight)

                TextField(searchTranscription ? "Search content & transcriptions..." : "Search audio files...", text: $searchText)
                    .font(TranceTypography.body)
                    .foregroundColor(.textPrimary)

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(TranceTypography.body)
                            .foregroundColor(.textLight)
                    }
                }
            }
        }
        .padding(.horizontal, TranceSpacing.screen)
        .padding(.top, TranceSpacing.card)
    }

    // MARK: - Filter & Sort Section

    var filterSortSection: some View {
        VStack(spacing: TranceSpacing.inner) {
            // Quick Filters Row 1 - Content & Favorites
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: TranceSpacing.inner) {
                    // Content Type Filter
                    Menu {
                        Picker("Content Type", selection: $contentFilter) {
                            ForEach(ContentFilter.allCases, id: \.self) { filter in
                                HStack {
                                    Text(filter.rawValue)
                                    if filter != .all {
                                        Text("(\(filteredCount(for: filter)))")
                                            .foregroundColor(.secondary)
                                    }
                                }.tag(filter)
                            }
                        }
                    } label: {
                        filterChipView(
                            icon: contentFilterIcon(contentFilter),
                            title: contentFilter.rawValue,
                            isActive: contentFilter != .all
                        )
                    }

                    // Duration Filter
                    Menu {
                        Picker("Duration", selection: $durationFilter) {
                            ForEach(DurationFilter.allCases, id: \.self) { filter in
                                Text(filter.rawValue).tag(filter)
                            }
                        }
                    } label: {
                        filterChipView(
                            icon: "clock",
                            title: durationFilter.rawValue,
                            isActive: durationFilter != .all
                        )
                    }

                    // Trance Depth Filter (only show if we have analyzed files)
                    if audioFiles.contains(where: { $0.isAnalyzed && $0.analysisResult?.contentType == .hypnosis }) {
                        Menu {
                            Picker("Trance Depth", selection: $tranceDepthFilter) {
                                ForEach(TranceDepthFilter.allCases, id: \.self) { filter in
                                    Text(filter.rawValue).tag(filter)
                                }
                            }
                        } label: {
                            filterChipView(
                                icon: "brain.head.profile",
                                title: tranceDepthFilter == .all ? "Depth" : tranceDepthFilter.rawValue,
                                isActive: tranceDepthFilter != .all
                            )
                        }
                    }

                    // Favorites Toggle
                    Button {
                        TranceHaptics.shared.light()
                        withAnimation(.spring(response: 0.3)) {
                            showFavoritesOnly.toggle()
                        }
                    } label: {
                        filterChipView(
                            icon: showFavoritesOnly ? "heart.fill" : "heart",
                            title: "Favorites",
                            isActive: showFavoritesOnly
                        )
                    }
                }
                .padding(.horizontal, TranceSpacing.screen)
            }

            // Sort & Search Options Row 2
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: TranceSpacing.inner) {
                    // Sort Menu
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
                        .foregroundColor(.textSecondary)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule().strokeBorder(Color.glassBorder.opacity(0.3), lineWidth: 1)
                        )
                    }

                    // Search in Transcription Toggle
                    if audioFiles.contains(where: { $0.hasTranscription }) {
                        Button {
                            TranceHaptics.shared.light()
                            withAnimation(.spring(response: 0.3)) {
                                searchTranscription.toggle()
                            }
                        } label: {
                            filterChipView(
                                icon: "doc.text.magnifyingglass",
                                title: "Search Content",
                                isActive: searchTranscription
                            )
                        }
                    }

                    // Clear All Filters (only show if any filters are active)
                    if contentFilter != .all || durationFilter != .all || tranceDepthFilter != .all || showFavoritesOnly {
                        Button {
                            TranceHaptics.shared.light()
                            withAnimation(.spring(response: 0.3)) {
                                contentFilter = .all
                                durationFilter = .all
                                tranceDepthFilter = .all
                                showFavoritesOnly = false
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "xmark.circle.fill")
                                Text("Clear")
                            }
                            .font(TranceTypography.caption)
                            .fontWeight(.medium)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.red.opacity(0.15))
                            .foregroundColor(.red)
                            .clipShape(Capsule())
                        }
                    }
                }
                .padding(.horizontal, TranceSpacing.screen)
            }
        }
        .padding(.top, TranceSpacing.inner)
    }

    // MARK: - Filter Chip Helper

    func filterChipView(icon: String, title: String, isActive: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundColor(isActive ? .roseGold : .textSecondary)
            Text(title)
        }
        .font(TranceTypography.caption)
        .fontWeight(.medium)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(isActive ? Color.roseGold.opacity(0.15) : Color.glassBorder.opacity(0.1))
        .foregroundColor(isActive ? .roseGold : .textSecondary)
        .clipShape(Capsule())
        .overlay(
            Capsule().strokeBorder(isActive ? Color.roseGold.opacity(0.5) : Color.glassBorder.opacity(0.3), lineWidth: 1)
        )
    }

    func contentFilterIcon(_ filter: ContentFilter) -> String {
        switch filter {
        case .all: return "list.bullet"
        case .hypnosis: return "brain.head.profile"
        case .meditation: return "leaf"
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
            case .meditation: return file.analysisResult?.contentType == .meditation
            case .music: return file.analysisResult?.contentType == .music
            case .guided: return file.analysisResult?.contentType == .guidedImagery
            case .affirmations: return file.analysisResult?.contentType == .affirmations
            case .analyzed: return file.isAnalyzed
            case .unanalyzed: return !file.isAnalyzed
            }
        }.count
    }

}
