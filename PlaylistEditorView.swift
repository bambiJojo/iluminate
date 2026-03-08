//
//  PlaylistEditorView.swift
//  Ilumionate
//
//  Create and edit playlists: name, add/remove/reorder audio files, toggle transitions
//

import SwiftUI

struct PlaylistEditorView: View {

    @Binding var playlist: Playlist
    var isNew: Bool
    var onSave: (Playlist) -> Void
    @Environment(\.dismiss) private var dismiss
    
    @Environment(\.colorScheme) private var colorScheme

    @State private var showingAudioPicker = false
    @State private var availableAudioFiles: [AudioFile] = []

    var body: some View {
        NavigationStack {
            ZStack {
                // Theme-aware background
                Color.bgPrimary
                    .ignoresSafeArea()

                List {
                    // Name section
                    Section {
                    TextField("Playlist Name", text: $playlist.name)
                        .font(.headline)
                } header: {
                    Text("Name")
                }

                // Transitions toggle
                Section {
                    Toggle("Smart Transitions", isOn: $playlist.smartTransitions)
                } header: {
                    Text("Playback")
                } footer: {
                    Text(playlist.smartTransitions
                         ? "Audio and lights will crossfade adaptively between tracks."
                         : "Tracks will play back-to-back with no overlap.")
                }

                // Tracks section
                Section {
                    if playlist.items.isEmpty {
                        ContentUnavailableView {
                            Label("No Tracks", systemImage: "music.note.list")
                        } description: {
                            Text("Add audio files to build your playlist")
                        }
                        .listRowBackground(Color.clear)
                    } else {
                        ForEach(playlist.items) { item in
                            HStack {
                                Image(systemName: "line.3.horizontal")
                                    .symbolRenderingMode(.hierarchical)
                                    .foregroundStyle(.tertiary)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.filename)
                                        .font(.body)
                                        .foregroundStyle(Color.textPrimary)
                                        .lineLimit(1)
                                    Text(item.durationFormatted)
                                        .font(.caption)
                                        .foregroundStyle(Color.textSecondary)
                                }

                                Spacer()

                                Button {
                                    removeItem(item)
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .symbolRenderingMode(.hierarchical)
                                        .foregroundStyle(.red)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .onMove(perform: moveItems)
                    }

                    Button {
                        loadAvailableFiles()
                        showingAudioPicker = true
                    } label: {
                        Label("Add Audio", systemImage: "plus.circle.fill")
                    }
                } header: {
                    HStack {
                        Text("Tracks")
                        Spacer()
                        Text("\(playlist.itemCount) tracks")
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                    }
                }

                // Summary
                if !playlist.items.isEmpty {
                    Section {
                        HStack {
                            Label("Total Duration", systemImage: "clock")
                            Spacer()
                            Text(playlist.totalDurationFormatted)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle(isNew ? "New Playlist" : "Edit Playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.title3)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(Color.textPrimary)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(playlist)
                        dismiss()
                    }
                    .disabled(playlist.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .environment(\.editMode, .constant(.active))
            .sheet(isPresented: $showingAudioPicker) {
                AudioPickerView(
                    audioFiles: availableAudioFiles,
                    existingItemIds: Set(playlist.items.map(\.audioFileId)),
                    onAdd: { file in
                        addItem(from: file)
                    }
                )
            }
                .scrollContentBackground(.hidden)
            }
        }
    }

    // MARK: - Actions

    private func addItem(from file: AudioFile) {
        let item = PlaylistItem(
            audioFileId: file.id,
            filename: file.filename,
            duration: file.duration
        )
        playlist.items.append(item)
    }

    private func removeItem(_ item: PlaylistItem) {
        playlist.items.removeAll { $0.id == item.id }
    }

    private func moveItems(from source: IndexSet, to destination: Int) {
        playlist.items.move(fromOffsets: source, toOffset: destination)
    }

    private func loadAvailableFiles() {
        if let data = UserDefaults.standard.data(forKey: "audioFiles"),
           let files = try? JSONDecoder().decode([AudioFile].self, from: data) {
            // Only show files that have generated sessions
            availableAudioFiles = files.filter { file in
                hasGeneratedSession(for: file)
            }
        }
    }

    private func hasGeneratedSession(for file: AudioFile) -> Bool {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let sessionsURL = documentsURL.appendingPathComponent("GeneratedSessions", isDirectory: true)
        let baseName = file.filename
            .replacingOccurrences(of: ".mp3", with: "")
            .replacingOccurrences(of: ".m4a", with: "")
            .replacingOccurrences(of: ".wav", with: "")
        let sessionFile = sessionsURL.appendingPathComponent("\(baseName)_session.json")
        return FileManager.default.fileExists(atPath: sessionFile.path)
    }
}

// MARK: - Audio Picker (sheet for adding files)

struct AudioPickerView: View {
    let audioFiles: [AudioFile]
    let existingItemIds: Set<UUID>
    var onAdd: (AudioFile) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if audioFiles.isEmpty {
                    ContentUnavailableView {
                        Label("No Audio Available", systemImage: "waveform.badge.exclamationmark")
                    } description: {
                        Text("Analyze audio files first to make them available for playlists.")
                    }
                } else {
                    ForEach(audioFiles) { file in
                        let alreadyAdded = existingItemIds.contains(file.id)

                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(file.filename)
                                    .font(.body)
                                    .lineLimit(1)

                                HStack(spacing: 8) {
                                    Label(file.durationFormatted, systemImage: "clock")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)

                                    Label(file.fileSizeFormatted, systemImage: "doc")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Spacer()

                            if alreadyAdded {
                                Image(systemName: "checkmark.circle.fill")
                                    .symbolRenderingMode(.hierarchical)
                                    .foregroundStyle(.green)
                            } else {
                                Button {
                                    onAdd(file)
                                } label: {
                                    Image(systemName: "plus.circle.fill")
                                        .symbolRenderingMode(.hierarchical)
                                        .font(.title2)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Add Audio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
