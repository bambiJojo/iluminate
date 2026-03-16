//
//  InAppBrowserView.swift
//  Ilumionate
//
//  In-app browser that intercepts audio file downloads
//

import SwiftUI
import WebKit
import AVFoundation

// MARK: - In-App Browser View

struct InAppBrowserView: View {
    let initialURL: String
    let onFileDownloaded: (AudioFile) -> Void

    @State private var urlText: String

    @State private var isLoading = false
    @State private var estimatedProgress: Double = 0.0
    @State private var canGoBack = false
    @State private var canGoForward = false
    
    @State private var downloadedFile: AudioFile?
    @State private var showingSuccessBanner = false
    @State private var errorMessage: String?
    
    // We hold a reference to the web view to trigger navigations from the SwiftUI bar
    @State private var webView: WKWebView?

    @Environment(\.dismiss) private var dismiss
    
    init(initialURL: String = "https://google.com", onFileDownloaded: @escaping (AudioFile) -> Void) {
        self.initialURL = initialURL
        self.onFileDownloaded = onFileDownloaded
        _urlText = State(initialValue: initialURL)
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                // Background color extending behind safe area
                Color.bgPrimary.ignoresSafeArea()
                
                // Web View
                BrowserWebView(
                    initialURL: initialURL,
                    urlText: $urlText,
                    isLoading: $isLoading,
                    estimatedProgress: $estimatedProgress,
                    canGoBack: $canGoBack,
                    canGoForward: $canGoForward,
                    webViewRef: $webView,
                    onFileDownloaded: handleDownload,
                    onError: { errorMessage = $0 }
                )
                .ignoresSafeArea(edges: .bottom)

                // Floating Address Bar
                FloatingAddressBar(
                    urlText: $urlText,
                    isLoading: isLoading,
                    estimatedProgress: estimatedProgress,
                    canGoBack: canGoBack,
                    canGoForward: canGoForward,
                    onGoBack: { webView?.goBack() },
                    onGoForward: { webView?.goForward() },
                    onReload: { webView?.reload() },
                    onSubmit: { urlString in
                        loadURL(urlString)
                    }
                )
                .padding(.horizontal, TranceSpacing.content)
                .padding(.bottom, TranceSpacing.content) // Added padding so it sits properly above screen edge
                
                // Success banner (if needed) overlaying at the top instead of bottom so it doesn't conflict with floating bar
                if showingSuccessBanner, let file = downloadedFile {
                    VStack {
                        successBanner(file: file)
                            .transition(.move(edge: .top).combined(with: .opacity))
                        Spacer()
                    }
                }
            }
            .navigationTitle("Browse Audio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") { dismiss() }
                        .foregroundColor(.roseGold)
                }
            }
            .alert("Download Error", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                if let msg = errorMessage { Text(msg) }
            }
        }
    }

    private func loadURL(_ urlString: String) {
        var cleaned = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        // If it looks like a search query, use DuckDuckGo
        if !cleaned.contains(".") || cleaned.contains(" ") {
            let encoded = cleaned.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            cleaned = "https://duckduckgo.com/?q=\(encoded)"
        } else if !cleaned.hasPrefix("http://") && !cleaned.hasPrefix("https://") {
            cleaned = "https://" + cleaned
        }
        if let url = URL(string: cleaned) {
            webView?.load(URLRequest(url: url))
        }
        urlText = cleaned
    }

    private func handleDownload(_ file: AudioFile) {
        downloadedFile = file
        withAnimation(.spring(response: 0.4)) {
            showingSuccessBanner = true
        }
        onFileDownloaded(file)

        // Hide banner after 4 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            withAnimation { showingSuccessBanner = false }
        }
    }

    private func successBanner(file: AudioFile) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title2)
                .foregroundColor(.green)

            VStack(alignment: .leading, spacing: 2) {
                Text("Downloaded!")
                    .font(TranceTypography.body)
                    .fontWeight(.semibold)
                    .foregroundColor(.textPrimary)

                Text(file.displayName)
                    .font(TranceTypography.caption)
                    .foregroundColor(.textSecondary)
                    .lineLimit(1)
            }

            Spacer()

            Button { withAnimation { showingSuccessBanner = false } } label: {
                Image(systemName: "xmark")
                    .font(.caption)
                    .foregroundColor(.textLight)
            }
        }
        .padding(.horizontal, TranceSpacing.content)
        .padding(.vertical, TranceSpacing.card)
        .padding(.top, TranceSpacing.statusBar)
        .background(.ultraThinMaterial)
        .overlay(
            Rectangle()
                .fill(Color.roseGold.opacity(0.5))
                .frame(height: 1),
            alignment: .bottom
        )
    }
}

// MARK: - Floating Address Bar

struct FloatingAddressBar: View {
    @Binding var urlText: String
    
    let isLoading: Bool
    let estimatedProgress: Double
    let canGoBack: Bool
    let canGoForward: Bool
    
    let onGoBack: () -> Void
    let onGoForward: () -> Void
    let onReload: () -> Void
    let onSubmit: (String) -> Void
    
    @FocusState private var isFocused: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: TranceSpacing.small) {
                // Back Button
                Button(action: {
                    TranceHaptics.shared.light()
                    onGoBack()
                }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(canGoBack ? .roseGold : .textLight.opacity(0.5))
                        .frame(width: 32, height: 32)
                }
                .disabled(!canGoBack)
                
                // Forward Button
                Button(action: {
                    TranceHaptics.shared.light()
                    onGoForward()
                }) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(canGoForward ? .roseGold : .textLight.opacity(0.5))
                        .frame(width: 32, height: 32)
                }
                .disabled(!canGoForward)

                // URL Field
                HStack {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.textLight)
                    
                    TextField("Search or enter website", text: $urlText)
                        .font(TranceTypography.body)
                        .foregroundColor(.textPrimary)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .submitLabel(.go)
                        .focused($isFocused)
                        .onSubmit {
                            onSubmit(urlText)
                        }
                    
                    if isLoading {
                        Button(action: {
                            TranceHaptics.shared.light()
                            // No stop loading exposed yet, just reload for now
                            onReload()
                        }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.textLight)
                                .padding(4)
                                .background(Color.glassBorder.opacity(0.2), in: Circle())
                        }
                    } else if !urlText.isEmpty && isFocused {
                        Button(action: { urlText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.textLight)
                        }
                    } else {
                        Button(action: {
                            TranceHaptics.shared.light()
                            onReload()
                        }) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.textLight)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.glassBorder.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(12)
            
            // Progress Bar
            if isLoading {
                GeometryReader { geo in
                    Rectangle()
                        .fill(Color.roseGold)
                        .frame(width: geo.size.width * CGFloat(estimatedProgress))
                        .animation(.linear(duration: 0.2), value: estimatedProgress)
                }
                .frame(height: 2)
                .background(Color.clear)
            } else {
                Spacer().frame(height: 2)
            }
        }
        .background(.ultraThinMaterial)
        .background(Color.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: TranceRadius.glassCard))
        .overlay(
            RoundedRectangle(cornerRadius: TranceRadius.glassCard)
                .stroke(Color.glassBorder, lineWidth: 1)
        )
        .shadow(
            color: TranceShadow.card.color,
            radius: TranceShadow.card.radius,
            x: TranceShadow.card.x,
            y: TranceShadow.card.y
        )
    }
}

// MARK: - WKWebView Wrapper

struct BrowserWebView: UIViewRepresentable {
    let initialURL: String
    @Binding var urlText: String
    @Binding var isLoading: Bool
    @Binding var estimatedProgress: Double
    @Binding var canGoBack: Bool
    @Binding var canGoForward: Bool
    @Binding var webViewRef: WKWebView?
    
    let onFileDownloaded: (AudioFile) -> Void
    let onError: (String) -> Void

    func makeCoordinator() -> BrowserWebViewCoordinator {
        BrowserWebViewCoordinator(
            urlText: $urlText,
            isLoading: $isLoading,
            estimatedProgress: $estimatedProgress,
            canGoBack: $canGoBack,
            canGoForward: $canGoForward,
            onFileDownloaded: onFileDownloaded,
            onError: onError
        )
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        
        // Add KVO Observers
        context.coordinator.setupObservers(for: webView)
        
        // Load initial page
        if let url = URL(string: initialURL) {
            webView.load(URLRequest(url: url))
        }
        
        DispatchQueue.main.async {
            self.webViewRef = webView
        }
        
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
    
    static func dismantleUIView(_ uiView: WKWebView, coordinator: BrowserWebViewCoordinator) {
        coordinator.removeObservers(from: uiView)
    }
}

// MARK: - Coordinator (WKNavigationDelegate + WKDownloadDelegate)

@MainActor
final class BrowserWebViewCoordinator: NSObject, WKNavigationDelegate, WKDownloadDelegate {
    @Binding var urlText: String
    @Binding var isLoading: Bool
    @Binding var estimatedProgress: Double
    @Binding var canGoBack: Bool
    @Binding var canGoForward: Bool
    
    let onFileDownloaded: (AudioFile) -> Void
    let onError: (String) -> Void

    private var downloadDestinationURL: URL?
    
    private var progressObserver: NSKeyValueObservation?
    private var canGoBackObserver: NSKeyValueObservation?
    private var canGoForwardObserver: NSKeyValueObservation?
    private var urlObserver: NSKeyValueObservation?

    // Recognized audio MIME types and extensions
    private let audioMIMETypes: Set<String> = [
        "audio/mpeg", "audio/mp3", "audio/mp4", "audio/m4a",
        "audio/x-m4a", "audio/wav", "audio/x-wav", "audio/wave",
        "audio/aac", "audio/flac", "audio/ogg", "audio/vorbis",
        "application/octet-stream" // common fallback for binary downloads
    ]
    private let audioExtensions: Set<String> = ["mp3", "m4a", "wav", "aac", "flac", "ogg"]

    init(
        urlText: Binding<String>,
        isLoading: Binding<Bool>,
        estimatedProgress: Binding<Double>,
        canGoBack: Binding<Bool>,
        canGoForward: Binding<Bool>,
        onFileDownloaded: @escaping (AudioFile) -> Void,
        onError: @escaping (String) -> Void
    ) {
        _urlText = urlText
        _isLoading = isLoading
        _estimatedProgress = estimatedProgress
        _canGoBack = canGoBack
        _canGoForward = canGoForward
        self.onFileDownloaded = onFileDownloaded
        self.onError = onError
    }
    
    func setupObservers(for webView: WKWebView) {
        progressObserver = webView.observe(\.estimatedProgress, options: [.new]) { [weak self] _, change in
            if let progress = change.newValue {
                Task { @MainActor [weak self] in self?.estimatedProgress = progress }
            }
        }
        canGoBackObserver = webView.observe(\.canGoBack, options: [.new]) { [weak self] _, change in
            if let canGoBack = change.newValue {
                Task { @MainActor [weak self] in self?.canGoBack = canGoBack }
            }
        }
        canGoForwardObserver = webView.observe(\.canGoForward, options: [.new]) { [weak self] _, change in
            if let canGoForward = change.newValue {
                Task { @MainActor [weak self] in self?.canGoForward = canGoForward }
            }
        }
        urlObserver = webView.observe(\.url, options: [.new]) { [weak self] _, change in
            if let url = change.newValue, let urlString = url?.absoluteString {
                Task { @MainActor [weak self] in self?.urlText = urlString }
            }
        }
    }
    
    func removeObservers(from webView: WKWebView) {
        progressObserver?.invalidate()
        canGoBackObserver?.invalidate()
        canGoForwardObserver?.invalidate()
        urlObserver?.invalidate()
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        isLoading = true
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isLoading = false
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        isLoading = false
    }

    /// Intercept navigation actions — if it's a direct link to an audio file, trigger download
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }

        let ext = url.pathExtension.lowercased()
        if audioExtensions.contains(ext) {
            // It's a direct link to an audio file — cancel navigation and download instead
            decisionHandler(.cancel)
            downloadDirectly(from: url)
        } else {
            decisionHandler(.allow)
        }
    }

    /// Handle HTTP response — decide whether to download or render
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
    ) {
        guard let mimeType = navigationResponse.response.mimeType?.lowercased() else {
            decisionHandler(.allow)
            return
        }

        // Check for audio MIME types that aren't browser-renderable
        let isAudio = mimeType.hasPrefix("audio/") ||
                      (mimeType == "application/octet-stream" &&
                       audioExtensions.contains(navigationResponse.response.url?.pathExtension.lowercased() ?? ""))

        if isAudio {
            decisionHandler(.download)
        } else {
            decisionHandler(.allow)
        }
    }

    /// WKNavigationDelegate — called when a download starts from decidePolicyFor response
    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        download.delegate = self
    }

    /// WKNavigationDelegate — called when a download starts from decidePolicyFor action
    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        download.delegate = self
    }

    // MARK: - WKDownloadDelegate

    nonisolated func download(
        _ download: WKDownload,
        decideDestinationUsing response: URLResponse,
        suggestedFilename: String,
        completionHandler: @escaping (URL?) -> Void
    ) {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(suggestedFilename)
        Task { @MainActor in
            self.downloadDestinationURL = tempURL
        }
        completionHandler(tempURL)
    }

    nonisolated func downloadDidFinish(_ download: WKDownload) {
        Task { @MainActor in
            guard let tempURL = self.downloadDestinationURL else { return }
            await self.importDownloadedFile(from: tempURL)
        }
    }

    nonisolated func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        Task { @MainActor in
            self.onError("Download failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Direct Download (for audio URL extension links)

    private func downloadDirectly(from url: URL) {
        isLoading = true
        Task {
            do {
                let (tempURL, response) = try await URLSession.shared.download(from: url)
                guard let httpResp = response as? HTTPURLResponse,
                      (200...299).contains(httpResp.statusCode) else {
                    onError("The server returned an error.")
                    isLoading = false
                    return
                }
                await importDownloadedFile(from: tempURL, suggestedName: url.lastPathComponent)
            } catch {
                onError("Download failed: \(error.localizedDescription)")
                isLoading = false
            }
        }
    }

    // MARK: - Import downloaded file

    private func importDownloadedFile(from tempURL: URL, suggestedName: String? = nil) async {
        let name = suggestedName ?? tempURL.lastPathComponent
        let ext = URL(fileURLWithPath: name).pathExtension.lowercased()
        let validExts: Set<String> = ["mp3", "m4a", "wav", "aac", "flac", "ogg"]
        let finalExt = validExts.contains(ext) ? ext : "mp3"
        let baseName = (name as NSString).deletingPathExtension
        let finalName = validExts.contains(ext) ? name : "\(baseName).\(finalExt)"

        let destURL = URL.documentsDirectory.appending(path: finalName)
        var uniqueURL = destURL
        var counter = 1
        while FileManager.default.fileExists(atPath: uniqueURL.path) {
            let nameWithoutExt = (finalName as NSString).deletingPathExtension
            uniqueURL = URL.documentsDirectory.appending(path: "\(nameWithoutExt) (\(counter)).\(finalExt)")
            counter += 1
        }

        do {
            try FileManager.default.moveItem(at: tempURL, to: uniqueURL)

            // Get duration
            let asset = AVURLAsset(url: uniqueURL)
            let durationSeconds: Double
            do {
                let duration = try await asset.load(.duration)
                durationSeconds = duration.seconds.isFinite ? duration.seconds : 0
            } catch {
                durationSeconds = 0
            }

            let resources = try? uniqueURL.resourceValues(forKeys: [.fileSizeKey])
            let fileSize = Int64(resources?.fileSize ?? 0)

            let audioFile = AudioFile(
                filename: uniqueURL.lastPathComponent,
                duration: durationSeconds,
                fileSize: fileSize
            )

            isLoading = false
            onFileDownloaded(audioFile)
        } catch {
            onError("Could not save the file: \(error.localizedDescription)")
            isLoading = false
        }
    }
}
