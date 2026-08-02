//
//  PlatformViewModifiers.swift
//  Ilumionate
//
//  Keeps shared views source-compatible when an iOS-only presentation hint
//  has no native macOS equivalent.
//

import SwiftUI

extension View {
    @ViewBuilder
    func platformInlineNavigationTitle() -> some View {
        #if os(macOS)
        self
        #else
        navigationBarTitleDisplayMode(.inline)
        #endif
    }

    @ViewBuilder
    func platformLargeNavigationTitle() -> some View {
        #if os(macOS)
        self
        #else
        navigationBarTitleDisplayMode(.large)
        #endif
    }

    @ViewBuilder
    func platformStatusBarHidden(_ hidden: Bool = true) -> some View {
        #if os(macOS)
        self
        #else
        statusBarHidden(hidden)
        #endif
    }

    @ViewBuilder
    func platformPersistentSystemOverlaysHidden() -> some View {
        #if os(macOS)
        self
        #else
        persistentSystemOverlays(.hidden)
        #endif
    }

    @ViewBuilder
    func platformURLKeyboard() -> some View {
        #if os(macOS)
        self
        #else
        keyboardType(.URL)
        #endif
    }

    @ViewBuilder
    func platformNeverAutocapitalized() -> some View {
        #if os(macOS)
        self
        #else
        textInputAutocapitalization(.never)
        #endif
    }

    @ViewBuilder
    func platformWordsAutocapitalized() -> some View {
        #if os(macOS)
        self
        #else
        textInputAutocapitalization(.words)
        #endif
    }

    @ViewBuilder
    func platformAutocorrectionDisabled() -> some View {
        #if os(macOS)
        self
        #else
        autocorrectionDisabled()
        #endif
    }

    @ViewBuilder
    func platformGoSubmitLabel() -> some View {
        #if os(macOS)
        self
        #else
        submitLabel(.go)
        #endif
    }

    @ViewBuilder
    func platformSearchSubmitLabel() -> some View {
        #if os(macOS)
        self
        #else
        submitLabel(.search)
        #endif
    }

    @ViewBuilder
    func platformDoneSubmitLabel() -> some View {
        #if os(macOS)
        self
        #else
        submitLabel(.done)
        #endif
    }

    @ViewBuilder
    func platformInsetGroupedListStyle() -> some View {
        #if os(macOS)
        listStyle(.inset)
        #else
        listStyle(.insetGrouped)
        #endif
    }

    // `platformFullScreenCover` lives in PlatformFullScreenCover.swift — the
    // macOS path needs window-sizing plumbing that does not belong here.

    @ViewBuilder
    func platformPagedTabViewStyle() -> some View {
        #if os(macOS)
        self
        #else
        tabViewStyle(.page(indexDisplayMode: .never))
        #endif
    }

    @ViewBuilder
    func platformSearchable(
        text: Binding<String>,
        prompt: String
    ) -> some View {
        #if os(macOS)
        searchable(text: text, placement: .toolbar, prompt: Text(prompt))
        #else
        searchable(
            text: text,
            placement: .navigationBarDrawer(displayMode: .automatic),
            prompt: Text(prompt)
        )
        #endif
    }

    @ViewBuilder
    func platformEditMode(isActive: Bool) -> some View {
        #if os(macOS)
        self
        #else
        environment(\.editMode, .constant(isActive ? .active : .inactive))
        #endif
    }

    @ViewBuilder
    func platformNavigationBarHidden() -> some View {
        #if os(macOS)
        self
        #else
        toolbar(.hidden, for: .navigationBar)
        #endif
    }
}
