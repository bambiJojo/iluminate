//
//  AppCommands.swift
//  Ilumionate
//
//  Menu-bar commands for the platforms that show a menu bar. iOS puts every one
//  of these gestures on screen already, so nothing here is built for it.
//

import SwiftUI

#if os(macOS) || targetEnvironment(macCatalyst)

// MARK: - Focused Values

/// The window's current tab. Published by `ContentView` so the menu bar can move
/// between sections without the commands owning navigation state themselves.
private struct TabSelectionKey: FocusedValueKey {
    typealias Value = Binding<TranceTab>
}

/// Moves keyboard focus to the Library search field. Absent while the Library is
/// not on screen, which is what leaves ⌘F correctly greyed out elsewhere.
private struct LibrarySearchFocusKey: FocusedValueKey {
    typealias Value = () -> Void
}

extension FocusedValues {
    var tabSelection: Binding<TranceTab>? {
        get { self[TabSelectionKey.self] }
        set { self[TabSelectionKey.self] = newValue }
    }

    var focusLibrarySearch: (() -> Void)? {
        get { self[LibrarySearchFocusKey.self] }
        set { self[LibrarySearchFocusKey.self] = newValue }
    }
}

// MARK: - Commands

/// Playback transport in the menu bar.
///
/// The labels are deliberately static. `Commands` bodies do not re-evaluate on
/// every observable change the way a `View` body does, so a title that swapped
/// between "Play" and "Pause" would go stale against the real playback state;
/// one item that toggles cannot be wrong.
struct PlaybackCommands: Commands {
    var body: some Commands {
        CommandMenu("Playback") {
            Button("Play / Pause") {
                NowPlayingState.shared.viewModel?.togglePlayPause()
            }
            .keyboardShortcut("p", modifiers: [.command, .shift])

            Button("End Session") {
                NowPlayingState.shared.viewModel?.stopAll(reason: .userStopped)
            }
            .keyboardShortcut(".", modifiers: .command)
        }
    }
}

/// ⌘1–⌘4 for the four sections, and ⌘F for Library search.
struct NavigationCommands: Commands {
    @FocusedValue(\.tabSelection) private var tabSelection
    @FocusedValue(\.focusLibrarySearch) private var focusLibrarySearch

    var body: some Commands {
        CommandGroup(after: .sidebar) {
            Divider()

            ForEach(Array(TranceTab.allCases.enumerated()), id: \.element) { index, tab in
                Button(tab.title) {
                    tabSelection?.wrappedValue = tab
                }
                .keyboardShortcut(
                    KeyEquivalent(Character("\(index + 1)")),
                    modifiers: .command
                )
                .disabled(tabSelection == nil)
            }
        }

        CommandGroup(after: .textEditing) {
            Button("Find in Library") {
                focusLibrarySearch?()
            }
            .keyboardShortcut("f", modifiers: .command)
            .disabled(focusLibrarySearch == nil)
        }
    }
}

#endif
