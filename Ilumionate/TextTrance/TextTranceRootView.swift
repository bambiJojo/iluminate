//  TextTranceRootView.swift
//  Ilumionate
//
//  NavigationStack host for the Text Trance (Read) tab.

import SwiftUI

struct TextTranceRootView: View {
    var body: some View {
        NavigationStack {
            TextTranceLibraryView()
        }
    }
}

#Preview { TextTranceRootView() }
