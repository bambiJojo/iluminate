//  SafariBrowserView.swift
//  Ilumionate
//
//  In-app browser for reading sources. Wraps SFSafariViewController so external
//  reading material opens inside the app instead of switching to Safari.

import SafariServices
import SwiftUI

struct SafariBrowserView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let controller = SFSafariViewController(url: url)
        controller.preferredControlTintColor = UIColor(.roseGold)
        return controller
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
