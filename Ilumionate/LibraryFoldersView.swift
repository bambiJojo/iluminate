//
//  LibraryFoldersView.swift
//  Ilumionate
//
//  Two sections: Smart Folders (auto by ContentType) and My Folders (user-created).
//

import SwiftUI

// MARK: - LibraryFoldersView

struct LibraryFoldersView: View {

    let audioFiles: [AudioFile]
    @Bindable var engine: LightEngine

    @Environment(FolderStore.self) private var folderStore

    @State private var showingNewFolder = false
    @State private var newFolderName = ""

    // MARK: Smart Folder definitions

    private struct SmartFolder: Identifiable {
        let id: String
        let name: String
        let icon: String
        let color: Color
        let contentType: AnalysisResult.ContentType?
    }

    private let smartFolders: [SmartFolder] = [
        SmartFolder(id: "hypnosis",     name: "Hypnosis",      icon: "brain.head.profile", color: .bwDelta,    contentType: .hypnosis),
        SmartFolder(id: "meditation",   name: "Meditation",    icon: "leaf",               color: .bwAlpha,    contentType: .meditation),
        SmartFolder(id: "music",        name: "Music",         icon: "music.note",         color: .bwBeta,     contentType: .music),
        SmartFolder(id: "guided",       name: "Guided Imagery",icon: "figure.mind.and.body", color: .bwTheta,  contentType: .guidedImagery),
        SmartFolder(id: "affirmations", name: "Affirmations",  icon: "quote.bubble",       color: .warmAccent, contentType: .affirmations),
        SmartFolder(id: "unanalyzed",   name: "Not Yet Analyzed", icon: "questionmark.circle", color: .textLight, contentType: nil),
    ]

    // MARK: Body

    var body: some View {
        ZStack {
            Color.bgPrimary.ignoresSafeArea()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: TranceSpacing.content) {

                    // Smart Folders
                    sectionCard(title: "Smart Folders") {
                        ForEach(smartFolders) { folder in
                            let files = smartFiles(for: folder)
                            if !files.isEmpty {
                                NavigationLink {
                                    FolderDetailView(
                                        name: folder.name,
                                        icon: folder.icon,
                                        iconColor: folder.color,
                                        audioFiles: files,
                                        engine: engine
                                    )
                                } label: {
                                    FolderRow(
                                        icon: folder.icon,
                                        iconColor: folder.color,
                                        name: folder.name,
                                        count: files.count
                                    )
                                }
                                .buttonStyle(PlainButtonStyle())

                                if folder.id != smartFolders.last(where: { !smartFiles(for: $0).isEmpty })?.id {
                                    rowDivider
                                }
                            }
                        }
                    }

                    // My Folders
                    VStack(alignment: .leading, spacing: TranceSpacing.inner) {
                        HStack {
                            Text("My Folders")
                                .font(TranceTypography.sectionTitle)
                                .fontWeight(.bold)
                                .foregroundColor(.textPrimary)
                            Spacer()
                            Button {
                                TranceHaptics.shared.light()
                                newFolderName = ""
                                showingNewFolder = true
                            } label: {
                                Image(systemName: "plus.circle.fill")
                                    .symbolRenderingMode(.hierarchical)
                                    .font(.system(size: 22))
                                    .foregroundColor(.roseGold)
                            }
                        }
                        .padding(.horizontal, TranceSpacing.screen)

                        if folderStore.folders.isEmpty {
                            emptyFolderHint
                        } else {
                            @Bindable var store = folderStore
                            VStack(spacing: 0) {
                                ForEach(folderStore.folders) { folder in
                                    let files = myFolderFiles(for: folder)
                                    NavigationLink {
                                        FolderDetailView(
                                            name: folder.name,
                                            icon: folder.icon,
                                            iconColor: colorForName(folder.colorName),
                                            audioFiles: files,
                                            engine: engine
                                        )
                                    } label: {
                                        FolderRow(
                                            icon: folder.icon,
                                            iconColor: colorForName(folder.colorName),
                                            name: folder.name,
                                            count: files.count
                                        )
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                    .swipeActions(edge: .trailing) {
                                        Button(role: .destructive) {
                                            folderStore.delete(folder)
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }

                                    if folder.id != folderStore.folders.last?.id {
                                        rowDivider
                                    }
                                }
                            }
                            .padding(.horizontal, TranceSpacing.screen)
                            .background(Color.bgCard)
                            .clipShape(RoundedRectangle(cornerRadius: TranceRadius.glassCard))
                            .overlay(RoundedRectangle(cornerRadius: TranceRadius.glassCard).strokeBorder(Color.glassBorder, lineWidth: 1))
                            .padding(.horizontal, TranceSpacing.screen)
                        }
                    }

                    Color.clear.frame(height: TranceSpacing.tabBarClearance)
                }
                .padding(.top, TranceSpacing.content)
            }
        }
        .navigationTitle("Folders")
        .alert("New Folder", isPresented: $showingNewFolder) {
            TextField("Folder name", text: $newFolderName)
            Button("Cancel", role: .cancel) {}
            Button("Create") {
                let name = newFolderName.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty {
                    folderStore.create(name: name)
                }
            }
        } message: {
            Text("Enter a name for your new folder.")
        }
    }

    // MARK: - Helpers

    private func smartFiles(for folder: SmartFolder) -> [AudioFile] {
        audioFiles.filter { file in
            if let contentType = folder.contentType {
                return file.analysisResult?.contentType == contentType
            } else {
                return !file.isAnalyzed
            }
        }
        .sorted { $0.displayName < $1.displayName }
    }

    private func myFolderFiles(for folder: Folder) -> [AudioFile] {
        audioFiles.filter { folder.audioFileIds.contains($0.id) }
            .sorted { $0.displayName < $1.displayName }
    }

    private func colorForName(_ colorName: String) -> Color {
        switch colorName {
        case "roseGold":   return .roseGold
        case "lavender":   return .lavender
        case "warmAccent": return .warmAccent
        case "bwTheta":    return .bwTheta
        case "bwDelta":    return .bwDelta
        case "bwAlpha":    return .bwAlpha
        default:           return .roseGold
        }
    }

    @ViewBuilder
    private func sectionCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: TranceSpacing.inner) {
            Text(title)
                .font(TranceTypography.sectionTitle)
                .fontWeight(.bold)
                .foregroundColor(.textPrimary)
                .padding(.horizontal, TranceSpacing.screen)

            VStack(spacing: 0) {
                content()
            }
            .padding(.horizontal, TranceSpacing.screen)
            .background(Color.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: TranceRadius.glassCard))
            .overlay(RoundedRectangle(cornerRadius: TranceRadius.glassCard).strokeBorder(Color.glassBorder, lineWidth: 1))
            .padding(.horizontal, TranceSpacing.screen)
        }
    }

    private var emptyFolderHint: some View {
        HStack(spacing: TranceSpacing.list) {
            Image(systemName: "folder.badge.plus")
                .font(.title2)
                .foregroundColor(.textLight)
            Text("Tap  +  to create a folder")
                .font(TranceTypography.body)
                .foregroundColor(.textSecondary)
        }
        .padding(TranceSpacing.content)
        .padding(.horizontal, TranceSpacing.screen)
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(Color.glassBorder.opacity(0.3))
            .frame(height: 1)
            .padding(.leading, 56)
    }
}

// MARK: - FolderRow

private struct FolderRow: View {
    let icon: String
    let iconColor: Color
    let name: String
    let count: Int

    var body: some View {
        HStack(spacing: TranceSpacing.list) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(iconColor.opacity(0.18))
                    .frame(width: 40, height: 40)
                Image(systemName: icon)
                    .font(.system(size: 17))
                    .foregroundColor(iconColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(TranceTypography.body)
                    .foregroundColor(.textPrimary)
                Text("\(count) \(count == 1 ? "session" : "sessions")")
                    .font(TranceTypography.caption)
                    .foregroundColor(.textLight)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.textLight)
        }
        .padding(.vertical, TranceSpacing.card)
    }
}

// MARK: - FolderDetailView

struct FolderDetailView: View {
    let name: String
    let icon: String
    let iconColor: Color
    let audioFiles: [AudioFile]
    @Bindable var engine: LightEngine

    @State private var syncPlayerItem: SyncPlayerItem?

    var body: some View {
        ZStack {
            Color.bgPrimary.ignoresSafeArea()

            if audioFiles.isEmpty {
                VStack(spacing: TranceSpacing.card) {
                    Image(systemName: icon)
                        .font(.system(size: 56, weight: .ultraLight))
                        .foregroundColor(iconColor)
                    Text("No Sessions")
                        .font(TranceTypography.greeting)
                        .foregroundColor(.textPrimary)
                    Text("Sessions you add to this folder will appear here")
                        .font(TranceTypography.body)
                        .foregroundColor(.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(TranceSpacing.screen)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(audioFiles) { file in
                            LibrarySessionRow(file: file) { playWithLights(file) }
                            if file.id != audioFiles.last?.id {
                                Rectangle().fill(Color.glassBorder.opacity(0.3)).frame(height: 1)
                                    .padding(.leading, 56)
                            }
                        }
                        Color.clear.frame(height: TranceSpacing.tabBarClearance)
                    }
                    .padding(.horizontal, TranceSpacing.screen)
                    .padding(.top, TranceSpacing.card)
                    .background(Color.bgCard)
                    .clipShape(RoundedRectangle(cornerRadius: TranceRadius.glassCard))
                    .overlay(RoundedRectangle(cornerRadius: TranceRadius.glassCard).strokeBorder(Color.glassBorder, lineWidth: 1))
                    .padding(.horizontal, TranceSpacing.screen)
                    .padding(.top, TranceSpacing.content)
                }
            }
        }
        .navigationTitle(name)
        .fullScreenCover(item: $syncPlayerItem) { item in
            UnifiedPlayerView(mode: .audioLight(audioFile: item.audioFile), engine: engine)
        }
    }

    private func playWithLights(_ file: AudioFile) {
        Task {
            let sessionsDir = URL.documentsDirectory.appending(path: "GeneratedSessions")
            let sessionURL = sessionsDir.appending(path: "\(file.id).json")
            if let session = try? LightScoreReader.loadSession(from: sessionURL) {
                await MainActor.run { syncPlayerItem = SyncPlayerItem(audioFile: file, lightSession: session) }
            }
        }
    }
}
