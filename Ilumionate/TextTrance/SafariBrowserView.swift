//  SafariBrowserView.swift
//  Ilumionate
//
//  Full-screen reading-source browser. Uses WKWebView so the app can import
//  the page the user navigated to, not just the original source URL.

import SwiftUI
import WebKit

struct SafariBrowserView: View {
    let url: URL
    let suggestedTitle: String?
    let theme: ScriptTheme
    let allowsImport: Bool
    let onImported: ((TranceScript) -> Void)?

    @Environment(\.dismiss) private var dismiss

    @State private var webView: WKWebView?
    @State private var currentURL: URL?
    @State private var pageTitle = ""
    @State private var canGoBack = false
    @State private var canGoForward = false
    @State private var isLoading = false
    @State private var isImporting = false
    @State private var pageErrorMessage: String?
    @State private var importErrorMessage: String?

    init(url: URL,
         suggestedTitle: String? = nil,
         theme: ScriptTheme = .focus,
         allowsImport: Bool = true,
         onImported: ((TranceScript) -> Void)? = nil) {
        self.url = url
        self.suggestedTitle = suggestedTitle
        self.theme = theme
        self.allowsImport = allowsImport
        self.onImported = onImported
    }

    var body: some View {
        VStack(spacing: 0) {
            browserTopBar

            ReadingBrowserWebView(
                initialURL: url,
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
                    BrowserErrorOverlay(message: pageErrorMessage) {
                        self.pageErrorMessage = nil
                        webView?.reload()
                    }
                }
            }

            browserBottomBar
        }
        .background(Color.bgPrimary.ignoresSafeArea())
        .alert("Could not import page", isPresented: importErrorPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importErrorMessage ?? "Try a different page.")
        }
    }

    private var browserTopBar: some View {
        HStack(spacing: TranceSpacing.inner) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.textPrimary)
                    .frame(width: 42, height: 42)
                    .background(Color.glassBorder.opacity(0.16), in: Circle())
            }
            .accessibilityLabel("Close browser")

            VStack(alignment: .leading, spacing: 2) {
                Text(displayTitle)
                    .font(TranceTypography.body)
                    .fontWeight(.semibold)
                    .foregroundStyle(.textPrimary)
                    .lineLimit(1)

                Text(displayURL)
                    .font(TranceTypography.caption)
                    .foregroundStyle(.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: TranceSpacing.inner)

            if allowsImport {
                Button {
                    importCurrentPage()
                } label: {
                    HStack(spacing: TranceSpacing.icon) {
                        if isImporting {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "text.page.badge.magnifyingglass")
                        }
                        Text(isImporting ? "Reading" : "Read")
                    }
                    .font(TranceTypography.body)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, TranceSpacing.inner)
                    .frame(height: 42)
                    .background(
                        LinearGradient(
                            colors: [.roseGold, .roseDeep],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: Capsule()
                    )
                }
                .disabled(isImporting || currentURL == nil)
                .accessibilityLabel("Read current page")
            }
        }
        .padding(.horizontal, TranceSpacing.screen)
        .padding(.top, TranceSpacing.inner)
        .padding(.bottom, TranceSpacing.list)
        .background(.ultraThinMaterial)
    }

    private var browserBottomBar: some View {
        HStack(spacing: TranceSpacing.card) {
            BrowserControlButton(systemName: "chevron.left", label: "Back", isEnabled: canGoBack) {
                webView?.goBack()
            }

            BrowserControlButton(systemName: "chevron.right", label: "Forward", isEnabled: canGoForward) {
                webView?.goForward()
            }

            BrowserControlButton(systemName: isLoading ? "xmark" : "arrow.clockwise",
                                 label: isLoading ? "Stop" : "Reload",
                                 isEnabled: true) {
                if isLoading {
                    webView?.stopLoading()
                } else {
                    webView?.reload()
                }
            }

            if let currentURL {
                ShareLink(item: currentURL) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.textPrimary)
                        .frame(width: 42, height: 42)
                        .background(Color.glassBorder.opacity(0.16), in: Circle())
                }
                .accessibilityLabel("Share page")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, TranceSpacing.screen)
        .padding(.vertical, TranceSpacing.list)
        .background(.ultraThinMaterial)
    }

    private var displayTitle: String {
        let title = pageTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty == false { return title }

        if let suggestedTitle,
           suggestedTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            return suggestedTitle
        }

        return "Reading Source"
    }

    private var displayURL: String {
        let url = currentURL ?? self.url
        return url.host(percentEncoded: false) ?? url.absoluteString
    }

    private var importErrorPresented: Binding<Bool> {
        Binding(
            get: { importErrorMessage != nil },
            set: { if !$0 { importErrorMessage = nil } }
        )
    }

    private func importCurrentPage() {
        guard let currentURL, isImporting == false else { return }
        TranceHaptics.shared.light()
        isImporting = true
        importErrorMessage = nil

        Task {
            do {
                let script = try await WebReadableTextImporter().importScript(
                    from: currentURL,
                    title: suggestedTitle ?? pageTitle,
                    theme: theme
                )
                await MainActor.run {
                    do {
                        if let onImported {
                            onImported(script)
                        } else {
                            try ImportedTranceScriptStore.shared.save(script)
                        }
                        isImporting = false
                        dismiss()
                    } catch {
                        isImporting = false
                        importErrorMessage = error.localizedDescription
                    }
                }
            } catch {
                await MainActor.run {
                    isImporting = false
                    importErrorMessage = error.localizedDescription
                }
            }
        }
    }
}

private struct BrowserControlButton: View {
    let systemName: String
    let label: String
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(isEnabled ? .textPrimary : .textLight)
                .frame(width: 42, height: 42)
                .background(Color.glassBorder.opacity(0.16), in: Circle())
        }
        .disabled(isEnabled == false)
        .accessibilityLabel(label)
    }
}

private struct BrowserErrorOverlay: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: TranceSpacing.list) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(.warmAccent)

            VStack(spacing: TranceSpacing.micro) {
                Text("Page unavailable")
                    .font(TranceTypography.sectionTitle)
                    .foregroundStyle(.textPrimary)

                Text(message)
                    .font(TranceTypography.body)
                    .foregroundStyle(.textSecondary)
                    .multilineTextAlignment(.center)
            }

            Button(action: retry) {
                Label("Reload", systemImage: "arrow.clockwise")
                    .font(TranceTypography.body)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, TranceSpacing.card)
                    .frame(height: 44)
                    .background(
                        LinearGradient(
                            colors: [.roseGold, .roseDeep],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: RoundedRectangle(cornerRadius: TranceRadius.button)
                    )
            }
        }
        .padding(TranceSpacing.screen)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.bgPrimary.opacity(0.94))
    }
}

private struct ReadingBrowserWebView: UIViewRepresentable {
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

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true

        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.allowsBackForwardNavigationGestures = true
        view.scrollView.contentInsetAdjustmentBehavior = .never
        view.load(URLRequest(url: initialURL))

        DispatchQueue.main.async {
            webView = view
            currentURL = initialURL
        }

        return view
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        uiView.navigationDelegate = nil
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        @Binding private var currentURL: URL?
        @Binding private var pageTitle: String
        @Binding private var canGoBack: Bool
        @Binding private var canGoForward: Bool
        @Binding private var isLoading: Bool
        @Binding private var errorMessage: String?

        init(currentURL: Binding<URL?>,
             pageTitle: Binding<String>,
             canGoBack: Binding<Bool>,
             canGoForward: Binding<Bool>,
             isLoading: Binding<Bool>,
             errorMessage: Binding<String?>) {
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

        func webView(_ webView: WKWebView,
                     didFail navigation: WKNavigation!,
                     withError error: Error) {
            updateState(from: webView)
            isLoading = false
            errorMessage = error.localizedDescription
        }

        func webView(_ webView: WKWebView,
                     didFailProvisionalNavigation navigation: WKNavigation!,
                     withError error: Error) {
            updateState(from: webView)
            isLoading = false
            errorMessage = error.localizedDescription
        }

        private func updateState(from webView: WKWebView) {
            currentURL = webView.url
            pageTitle = webView.title ?? ""
            canGoBack = webView.canGoBack
            canGoForward = webView.canGoForward
            isLoading = webView.isLoading
        }
    }
}
