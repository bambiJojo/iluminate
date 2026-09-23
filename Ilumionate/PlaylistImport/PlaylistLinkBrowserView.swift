//
//  PlaylistLinkBrowserView.swift
//  Ilumionate
//
//  Browse-then-import surface for shared playlists, mirroring the reader's
//  SafariBrowserView: the user navigates to the playlist page and imports the
//  page they landed on, rather than pasting a link they had to find elsewhere.
//

import SwiftUI
import WebKit

struct PlaylistLinkBrowserView: View {
    let initialURL: URL
    let onPicked: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var webView: WKWebView?
    @State private var currentURL: URL?
    @State private var pageTitle = ""
    @State private var canGoBack = false
    @State private var canGoForward = false
    @State private var isLoading = false
    @State private var pageErrorMessage: String?

    init(
        initialURL: URL = URL(string: "https://bambicloud.com")!,
        onPicked: @escaping (String) -> Void
    ) {
        self.initialURL = initialURL
        self.onPicked = onPicked
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar

            PlaylistBrowserWebView(
                initialURL: initialURL,
                webView: $webView,
                currentURL: $currentURL,
                pageTitle: $pageTitle,
                canGoBack: $canGoBack,
                canGoForward: $canGoForward,
                isLoading: $isLoading,
                errorMessage: $pageErrorMessage
            )
            .overlay(alignment: .top) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(.linear)
                        .tint(.roseGold)
                }
            }
            .overlay {
                if let pageErrorMessage, isLoading == false {
                    PlaylistBrowserErrorView(message: pageErrorMessage, reload: reload)
                }
            }

            bottomBar
        }
        .background(Color.bgPrimary.ignoresSafeArea())
    }

    private var topBar: some View {
        HStack(spacing: TranceSpacing.inner) {
            Button("Close browser", systemImage: "xmark") {
                dismiss()
            }
            .labelStyle(.iconOnly)
            .font(.headline)
            .foregroundStyle(.textPrimary)
            .frame(width: 44, height: 44)
            .background(Color.glassBorder.opacity(0.16), in: .circle)

            VStack(alignment: .leading, spacing: TranceSpacing.micro) {
                Text(displayTitle)
                    .font(TranceTypography.body.bold())
                    .foregroundStyle(.textPrimary)
                    .lineLimit(1)

                Text(subtitle)
                    .font(TranceTypography.caption)
                    .foregroundStyle(isPlaylistPage ? Color.roseGold : Color.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: TranceSpacing.inner)

            Button("Import", systemImage: "square.and.arrow.down", action: importCurrentPage)
                .font(TranceTypography.caption.bold())
                .buttonStyle(.borderedProminent)
                .tint(.roseGold)
                .disabled(isPlaylistPage == false)
                .accessibilityLabel("Import this playlist")
        }
        .padding(.horizontal, TranceSpacing.screen)
        .padding(.top, TranceSpacing.inner)
        .padding(.bottom, TranceSpacing.list)
        .background(.ultraThinMaterial)
    }

    private var bottomBar: some View {
        HStack(spacing: TranceSpacing.card) {
            PlaylistBrowserControl(systemName: "chevron.left", label: "Back", isEnabled: canGoBack) {
                webView?.goBack()
            }

            PlaylistBrowserControl(systemName: "chevron.right", label: "Forward", isEnabled: canGoForward) {
                webView?.goForward()
            }

            PlaylistBrowserControl(
                systemName: isLoading ? "xmark" : "arrow.clockwise",
                label: isLoading ? "Stop" : "Reload",
                isEnabled: true
            ) {
                if isLoading {
                    webView?.stopLoading()
                } else {
                    reload()
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, TranceSpacing.screen)
        .padding(.vertical, TranceSpacing.list)
        .background(.ultraThinMaterial)
    }

    private var isPlaylistPage: Bool {
        Self.isImportable(currentURL)
    }

    /// Only a BambiCloud playlist page converts to playlist data. Every other
    /// page on the site is HTML the importer would reject, so offering Import
    /// there only leads to an error.
    nonisolated static func isImportable(_ url: URL?) -> Bool {
        guard let url else { return false }
        return BambiCloudPlaylistLink(url.absoluteString) != nil
    }

    /// Following a link while a page is still loading cancels that load. It is
    /// routine, not a failure, and must not cover the page with an error.
    nonisolated static func isReportableLoadFailure(_ error: any Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain != NSURLErrorDomain || nsError.code != NSURLErrorCancelled
    }

    private var displayTitle: String {
        let title = pageTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? "Find a Playlist" : title
    }

    private var subtitle: String {
        guard let currentURL else { return "Loading…" }
        if isPlaylistPage {
            return "Tap Import to load this playlist"
        }
        return currentURL.host(percentEncoded: false) ?? currentURL.absoluteString
    }

    /// A first load that fails — offline, typically — leaves the web view with
    /// no page to reload, so `reload()` alone would silently do nothing.
    private func reload() {
        guard let webView else { return }
        if webView.url == nil {
            webView.load(URLRequest(url: initialURL))
        } else {
            webView.reload()
        }
    }

    private func importCurrentPage() {
        guard let currentURL, isPlaylistPage else { return }
        TranceHaptics.shared.light()
        onPicked(currentURL.absoluteString)
        dismiss()
    }
}

private struct PlaylistBrowserControl: View {
    let systemName: String
    let label: String
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(label, systemImage: systemName, action: action)
            .labelStyle(.iconOnly)
            .font(.headline)
            .foregroundStyle(isEnabled ? Color.textPrimary : Color.textLight)
            .frame(width: 44, height: 44)
            .background(Color.glassBorder.opacity(0.16), in: .circle)
            .disabled(isEnabled == false)
    }
}

/// Without this, a page that fails to load leaves a blank web view and a
/// stopped progress bar — indistinguishable from a page that is still coming.
private struct PlaylistBrowserErrorView: View {
    let message: String
    let reload: () -> Void

    var body: some View {
        VStack(spacing: TranceSpacing.list) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title)
                .foregroundStyle(.warmAccent)

            Text("Page unavailable")
                .font(TranceTypography.sectionTitle)
                .foregroundStyle(.textPrimary)

            Text(message)
                .font(TranceTypography.body)
                .foregroundStyle(.textSecondary)
                .multilineTextAlignment(.center)

            Button("Reload", systemImage: "arrow.clockwise", action: reload)
                .buttonStyle(.borderedProminent)
                .tint(.roseGold)
        }
        .padding(TranceSpacing.screen)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.bgPrimary.opacity(0.96))
    }
}

#if os(macOS)
private typealias PlaylistBrowserRepresentable = NSViewRepresentable
#else
private typealias PlaylistBrowserRepresentable = UIViewRepresentable
#endif

private struct PlaylistBrowserWebView: PlaylistBrowserRepresentable {
    let initialURL: URL

    @Binding var webView: WKWebView?
    @Binding var currentURL: URL?
    @Binding var pageTitle: String
    @Binding var canGoBack: Bool
    @Binding var canGoForward: Bool
    @Binding var isLoading: Bool
    @Binding var errorMessage: String?

    func makeCoordinator() -> Coordinator {
        Coordinator(
            currentURL: $currentURL,
            pageTitle: $pageTitle,
            canGoBack: $canGoBack,
            canGoForward: $canGoForward,
            isLoading: $isLoading,
            errorMessage: $errorMessage
        )
    }

    private func makeWebView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        #if !os(macOS)
        configuration.allowsInlineMediaPlayback = true
        #endif

        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.allowsBackForwardNavigationGestures = true
        #if !os(macOS)
        view.scrollView.contentInsetAdjustmentBehavior = .never
        #endif
        context.coordinator.startObserving(view)
        view.load(URLRequest(url: initialURL))

        Task { @MainActor in
            webView = view
            currentURL = initialURL
        }

        return view
    }

    #if os(macOS)
    func makeNSView(context: Context) -> WKWebView {
        makeWebView(context: context)
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    static func dismantleNSView(_ nsView: WKWebView, coordinator: Coordinator) {
        coordinator.stopObserving()
        nsView.navigationDelegate = nil
    }
    #else
    func makeUIView(context: Context) -> WKWebView {
        makeWebView(context: context)
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        coordinator.stopObserving()
        uiView.navigationDelegate = nil
    }
    #endif

    final class Coordinator: NSObject, WKNavigationDelegate {
        @Binding private var currentURL: URL?
        @Binding private var pageTitle: String
        @Binding private var canGoBack: Bool
        @Binding private var canGoForward: Bool
        @Binding private var isLoading: Bool
        @Binding private var errorMessage: String?

        private var observations: [NSKeyValueObservation] = []

        /// Playlist sites route client-side, and a pushState navigation never
        /// reaches the navigation delegate. Observing the web view's own
        /// properties is what keeps the address — and the Import button — in
        /// step with the page the user is actually looking at.
        func startObserving(_ webView: WKWebView) {
            // No `.initial`: that fires synchronously inside makeUIView, which
            // SwiftUI runs mid-update, and writing bindings there is the
            // "Modifying state during view update" undefined behaviour.
            observations = [
                webView.observe(\.url, options: [.new]) { view, _ in
                    Self.scheduleUpdate(of: view, on: self)
                },
                webView.observe(\.title, options: [.new]) { view, _ in
                    Self.scheduleUpdate(of: view, on: self)
                },
                webView.observe(\.canGoBack, options: [.new]) { view, _ in
                    Self.scheduleUpdate(of: view, on: self)
                },
                webView.observe(\.canGoForward, options: [.new]) { view, _ in
                    Self.scheduleUpdate(of: view, on: self)
                },
                webView.observe(\.isLoading, options: [.new]) { view, _ in
                    Self.scheduleUpdate(of: view, on: self)
                }
            ]
        }

        /// KVO can land inside a layout pass driven by a view update, so the
        /// binding writes are deferred to their own main-actor turn.
        /// `nonisolated` because KVO delivers on whatever thread changed the
        /// property, and this is the hop point — the body immediately enters the
        /// main actor. Leaving it main-actor-isolated made every observation
        /// closure an isolation violation for a function whose whole job is to
        /// cross that boundary safely.
        private nonisolated static func scheduleUpdate(
            of webView: WKWebView,
            on coordinator: Coordinator
        ) {
            Task { @MainActor [weak webView] in
                guard let webView else { return }
                coordinator.updateState(from: webView)
            }
        }

        func stopObserving() {
            observations.removeAll()
        }

        init(
            currentURL: Binding<URL?>,
            pageTitle: Binding<String>,
            canGoBack: Binding<Bool>,
            canGoForward: Binding<Bool>,
            isLoading: Binding<Bool>,
            errorMessage: Binding<String?>
        ) {
            _currentURL = currentURL
            _pageTitle = pageTitle
            _canGoBack = canGoBack
            _canGoForward = canGoForward
            _isLoading = isLoading
            _errorMessage = errorMessage
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            errorMessage = nil
            updateState(from: webView)
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            errorMessage = nil
            updateState(from: webView)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            errorMessage = nil
            updateState(from: webView)
        }

        func webView(
            _ webView: WKWebView,
            didFail navigation: WKNavigation!,
            withError error: Error
        ) {
            handleFailure(error, in: webView)
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            handleFailure(error, in: webView)
        }

        private func handleFailure(_ error: any Error, in webView: WKWebView) {
            updateState(from: webView)
            isLoading = false
            guard PlaylistLinkBrowserView.isReportableLoadFailure(error) else { return }
            errorMessage = error.localizedDescription
        }

        /// Writes only what actually changed — five observers firing on one
        /// navigation would otherwise push five redundant view updates each.
        fileprivate func updateState(from webView: WKWebView) {
            if currentURL != webView.url {
                currentURL = webView.url
            }
            let title = webView.title ?? ""
            if pageTitle != title {
                pageTitle = title
            }
            if canGoBack != webView.canGoBack {
                canGoBack = webView.canGoBack
            }
            if canGoForward != webView.canGoForward {
                canGoForward = webView.canGoForward
            }
            if isLoading != webView.isLoading {
                isLoading = webView.isLoading
            }
        }
    }
}
