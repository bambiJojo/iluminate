//  TextTranceRootView.swift
//  Ilumionate
//
//  NavigationStack host for the Text Trance (Read) tab.

import SwiftUI

struct TextTranceRootView: View {
    var sharedImportTrigger = 0

    var body: some View {
        NavigationStack {
            TextTranceLibraryView(sharedImportTrigger: sharedImportTrigger)
        }
    }
}

#Preview { TextTranceRootView() }
