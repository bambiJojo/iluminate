//
//  ReadingSourceBrowserView.swift
//  Ilumionate
//
//  Embedded browser for a website the user added to Custom Sources.

import SwiftUI
import WebKit

struct ReadingSourceBrowserView: View {
    let source: ReadingSource
    let onImported: (TranceScript) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var webView: WKWebView?
    @State private var currentURL: URL?
    @State private var pageTitle = ""
    @State private var canGoBack = false
    @State private var canGoForward = false
    @State private var isLoading = false
    @State private var isImporting = false
    @State private var pageErrorMessage: String?
    @State private var importErrorMessage: String?
    @State private var showingRightsAcknowledgement = false

    var body: some View {
        VStack(spacing: 0) {
            browserTopBar

            ReadingSourceWebView(
                initialURL: source.url,
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
                    ReadingSourceBrowserErrorView(
                        message: pageErrorMessage,
                        reload: reload,
                        openInSafari: openCurrentPageInSafari
                    )
                }
            }

            browserBottomBar
        }
        .background(Color.bgPrimary.ignoresSafeArea())
        .alert("Only import content you may save", isPresented: $showingRightsAcknowledgement) {
            Button("Cancel", role: .cancel) {}
            Button("Continue") {
                Task { await importCurrentStory() }
            }
        } message: {
            Text("Only import content you created or have permission to save. Website access does not grant copying or redistribution rights.")
        }
        .alert("Could not import story", isPresented: importErrorPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importErrorMessage ?? "Try a different page or share selected text from Safari.")
        }
    }

    private var browserTopBar: some View {
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

                Text(displayURL)
                    .font(TranceTypography.caption)
                    .foregroundStyle(.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: TranceSpacing.inner)

            Button("Import Current Story", systemImage: "text.page.badge.magnifyingglass") {
                showingRightsAcknowledgement = true
            }
            .font(TranceTypography.caption.bold())
            .buttonStyle(.borderedProminent)
            .tint(.roseGold)
            .disabled(canImport == false)
        }
        .padding(.horizontal, TranceSpacing.screen)
        .padding(.vertical, TranceSpacing.list)
        .background(.ultraThinMaterial)
    }

    private var browserBottomBar: some View {
        HStack(spacing: TranceSpacing.card) {
            ReadingSourceBrowserControl(
                title: "Back",
                systemImage: "chevron.left",
                isEnabled: canGoBack
            ) {
                webView?.goBack()
            }

            ReadingSourceBrowserControl(
                title: "Forward",
                systemImage: "chevron.right",
                isEnabled: canGoForward
            ) {
                webView?.goForward()
            }

            ReadingSourceBrowserControl(
                title: isLoading ? "Stop" : "Reload",
                systemImage: isLoading ? "xmark" : "arrow.clockwise",
                isEnabled: true
            ) {
                if isLoading {
                    webView?.stopLoading()
                } else {
                    reload()
                }
            }

            ReadingSourceBrowserControl(
                title: "Open in Safari",
                systemImage: "safari",
                isEnabled: currentURL != nil
            ) {
                openCurrentPageInSafari()
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, TranceSpacing.screen)
        .padding(.vertical, TranceSpacing.list)
        .background(.ultraThinMaterial)
    }

    private var canImport: Bool {
        source.canImport
            && currentURL.map(Self.isWebURL) == true
            && webView != nil
            && isLoading == false
            && isImporting == false
    }

    private var displayTitle: String {
        let title = pageTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? source.title : title
    }

    private var displayURL: String {
        let url = currentURL ?? source.url
        return url.host(percentEncoded: false) ?? url.absoluteString
    }

    private var importErrorPresented: Binding<Bool> {
        Binding(
            get: { importErrorMessage != nil },
            set: { if $0 == false { importErrorMessage = nil } }
        )
    }

    private func reload() {
        pageErrorMessage = nil
        webView?.reload()
    }

    private func openCurrentPageInSafari() {
        guard let url = currentURL ?? webView?.url, Self.isWebURL(url) else { return }
        openURL(url)
    }

    private func importCurrentStory() async {
        guard let webView,
              let sourceURL = webView.url,
              Self.isWebURL(sourceURL),
              isImporting == false else {
            importErrorMessage = WebReadableTextImportError.unloadedPage.localizedDescription
            return
        }

        isImporting = true
        importErrorMessage = nil
        defer { isImporting = false }

        do {
            let html = try await currentDocumentHTML(from: webView)
            guard webView.url == sourceURL else {
                throw WebReadableTextImportError.unloadedPage
            }
            let script = try WebReadableTextImporter().importScript(
                html: html,
                title: webView.title ?? pageTitle,
                sourceURL: sourceURL
            )
            TranceHaptics.shared.light()
            onImported(script)
            dismiss()
        } catch let error as LocalizedError {
            importErrorMessage = error.errorDescription
                ?? WebReadableTextImportError.domExtractionFailed.localizedDescription
        } catch {
            importErrorMessage = WebReadableTextImportError.domExtractionFailed.localizedDescription
        }
    }

    private func currentDocumentHTML(from webView: WKWebView) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            webView.evaluateJavaScript("document.documentElement.outerHTML") { value, error in
                if error != nil {
                    continuation.resume(throwing: WebReadableTextImportError.domExtractionFailed)
                } else if let html = value as? String, html.isEmpty == false {
                    continuation.resume(returning: html)
                } else {
                    continuation.resume(throwing: WebReadableTextImportError.unloadedPage)
                }
            }
        }
    }

    fileprivate static func isWebURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return (scheme == "http" || scheme == "https") && url.host() != nil
    }
}

private struct ReadingSourceBrowserControl: View {
    let title: String
    let systemImage: String
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(title, systemImage: systemImage, action: action)
            .labelStyle(.iconOnly)
            .font(.headline)
            .foregroundStyle(isEnabled ? Color.textPrimary : Color.textLight)
            .frame(width: 44, height: 44)
            .background(Color.glassBorder.opacity(0.16), in: .circle)
            .disabled(isEnabled == false)
    }
}

private struct ReadingSourceBrowserErrorView: View {
    let message: String
    let reload: () -> Void
    let openInSafari: () -> Void

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

            Text("You can open the page in Safari and share selected text with LumeSync.")
                .font(TranceTypography.caption)
                .foregroundStyle(.textLight)
                .multilineTextAlignment(.center)

            HStack(spacing: TranceSpacing.list) {
                Button("Reload", systemImage: "arrow.clockwise", action: reload)
                    .buttonStyle(.borderedProminent)
                    .tint(.roseGold)
                Button("Open in Safari", systemImage: "safari", action: openInSafari)
                    .buttonStyle(.bordered)
            }
        }
        .padding(TranceSpacing.screen)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.bgPrimary.opacity(0.96))
    }
}

#if os(macOS)
private typealias ReadingSourceWebRepresentable = NSViewRepresentable
#else
private typealias ReadingSourceWebRepresentable = UIViewRepresentable
#endif

private struct ReadingSourceWebView: ReadingSourceWebRepresentable {
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
        view.uiDelegate = context.coordinator
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
        nsView.uiDelegate = nil
    }
    #else
    func makeUIView(context: Context) -> WKWebView {
        makeWebView(context: context)
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        coordinator.stopObserving()
        uiView.navigationDelegate = nil
        uiView.uiDelegate = nil
    }
    #endif

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        @Binding private var currentURL: URL?
        @Binding private var pageTitle: String
        @Binding private var canGoBack: Bool
        @Binding private var canGoForward: Bool
        @Binding private var isLoading: Bool
        @Binding private var errorMessage: String?

        private var observations: [NSKeyValueObservation] = []

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

        func startObserving(_ webView: WKWebView) {
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

        func stopObserving() {
            observations.removeAll()
        }

        private nonisolated static func scheduleUpdate(
            of webView: WKWebView,
            on coordinator: Coordinator
        ) {
            Task { @MainActor [weak webView] in
                guard let webView else { return }
                coordinator.updateState(from: webView)
            }
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
        ) {
            guard navigationAction.shouldPerformDownload == false,
                  let url = navigationAction.request.url,
                  ReadingSourceBrowserView.isWebURL(url) else {
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationResponse: WKNavigationResponse,
            decisionHandler: @escaping @MainActor @Sendable (WKNavigationResponsePolicy) -> Void
        ) {
            guard navigationResponse.canShowMIMEType,
                  let url = navigationResponse.response.url,
                  ReadingSourceBrowserView.isWebURL(url) else {
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if navigationAction.targetFrame == nil,
               let url = navigationAction.request.url,
               ReadingSourceBrowserView.isWebURL(url) {
                webView.load(navigationAction.request)
            }
            return nil
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

        private func handleFailure(_ error: Error, in webView: WKWebView) {
            updateState(from: webView)
            isLoading = false
            let nsError = error as NSError
            guard nsError.domain != NSURLErrorDomain || nsError.code != NSURLErrorCancelled else {
                return
            }
            errorMessage = error.localizedDescription
        }

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
