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
    let onFileDownloaded: (AudioFile) -> Void

    @State private var urlText = "https://"
    @State private var isLoading = false
    @State private var downloadedFile: AudioFile?
    @State private var showingSuccessBanner = false
    @State private var errorMessage: String?
    @State private var webViewRef: BrowserWebViewCoordinator?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                // Web View
                BrowserWebView(
                    urlText: $urlText,
                    isLoading: $isLoading,
                    onFileDownloaded: handleDownload,
                    onError: { errorMessage = $0 }
                )
                .ignoresSafeArea(edges: .bottom)

                // Loading overlay at very top
                if isLoading {
                    ProgressView()
                        .progressViewStyle(.linear)
                        .tint(.roseGold)
                        .frame(height: 3)
                }

                // Success banner
                if showingSuccessBanner, let file = downloadedFile {
                    VStack {
                        Spacer()
                        successBanner(file: file)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    .ignoresSafeArea(edges: .bottom)
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
        .padding(.bottom, TranceSpacing.statusBar)
        .background(.ultraThinMaterial)
        .overlay(
            Rectangle()
                .fill(Color.roseGold.opacity(0.5))
                .frame(height: 1),
            alignment: .top
        )
    }
}

// MARK: - WKWebView Wrapper

struct BrowserWebView: UIViewRepresentable {
    @Binding var urlText: String
    @Binding var isLoading: Bool
    let onFileDownloaded: (AudioFile) -> Void
    let onError: (String) -> Void

    func makeCoordinator() -> BrowserWebViewCoordinator {
        BrowserWebViewCoordinator(
            urlText: $urlText,
            isLoading: $isLoading,
            onFileDownloaded: onFileDownloaded,
            onError: onError
        )
    }

    func makeUIView(context: Context) -> UIView {
        let container = UIView()

        // Configure WebView
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.translatesAutoresizingMaskIntoConstraints = false
        context.coordinator.webView = webView

        // URL bar + nav controls
        let toolbar = makeToolbar(coordinator: context.coordinator)
        toolbar.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(toolbar)
        container.addSubview(webView)

        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: container.safeAreaLayoutGuide.topAnchor),
            toolbar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            toolbar.heightAnchor.constraint(equalToConstant: 52),

            webView.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        // Load default search page
        loadURL("https://freemusicarchive.org", in: webView)
        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {}

    private func makeToolbar(coordinator: BrowserWebViewCoordinator) -> UIView {
        let container = UIView()
        container.backgroundColor = UIColor(Color.bgPrimary)

        // Border bottom
        let border = UIView()
        border.backgroundColor = UIColor(Color.glassBorder).withAlphaComponent(0.3)
        border.translatesAutoresizingMaskIntoConstraints = false

        // Back button
        let backBtn = UIButton(type: .system)
        backBtn.setImage(UIImage(systemName: "chevron.left"), for: .normal)
        backBtn.tintColor = UIColor(Color.roseGold)
        backBtn.addTarget(coordinator, action: #selector(BrowserWebViewCoordinator.goBack), for: .touchUpInside)
        backBtn.translatesAutoresizingMaskIntoConstraints = false
        coordinator.backButton = backBtn

        // Forward button
        let fwdBtn = UIButton(type: .system)
        fwdBtn.setImage(UIImage(systemName: "chevron.right"), for: .normal)
        fwdBtn.tintColor = UIColor(Color.roseGold)
        fwdBtn.addTarget(coordinator, action: #selector(BrowserWebViewCoordinator.goForward), for: .touchUpInside)
        fwdBtn.translatesAutoresizingMaskIntoConstraints = false
        coordinator.forwardButton = fwdBtn

        // URL field
        let urlField = UITextField()
        urlField.text = urlText
        urlField.font = UIFont.systemFont(ofSize: 14)
        urlField.textColor = UIColor(Color.textPrimary)
        urlField.backgroundColor = UIColor(Color.glassBorder).withAlphaComponent(0.15)
        urlField.layer.cornerRadius = 10
        urlField.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 10, height: 0))
        urlField.leftViewMode = .always
        urlField.rightView = UIView(frame: CGRect(x: 0, y: 0, width: 10, height: 0))
        urlField.rightViewMode = .always
        urlField.returnKeyType = .go
        urlField.autocorrectionType = .no
        urlField.autocapitalizationType = .none
        urlField.keyboardType = .URL
        urlField.delegate = coordinator
        urlField.translatesAutoresizingMaskIntoConstraints = false
        coordinator.urlField = urlField

        // Reload button
        let reloadBtn = UIButton(type: .system)
        reloadBtn.setImage(UIImage(systemName: "arrow.clockwise"), for: .normal)
        reloadBtn.tintColor = UIColor(Color.roseGold)
        reloadBtn.addTarget(coordinator, action: #selector(BrowserWebViewCoordinator.reload), for: .touchUpInside)
        reloadBtn.translatesAutoresizingMaskIntoConstraints = false
        coordinator.reloadButton = reloadBtn

        container.addSubview(border)
        container.addSubview(backBtn)
        container.addSubview(fwdBtn)
        container.addSubview(urlField)
        container.addSubview(reloadBtn)

        NSLayoutConstraint.activate([
            border.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            border.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            border.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            border.heightAnchor.constraint(equalToConstant: 1),

            backBtn.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            backBtn.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            backBtn.widthAnchor.constraint(equalToConstant: 36),
            backBtn.heightAnchor.constraint(equalToConstant: 36),

            fwdBtn.leadingAnchor.constraint(equalTo: backBtn.trailingAnchor, constant: 2),
            fwdBtn.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            fwdBtn.widthAnchor.constraint(equalToConstant: 36),
            fwdBtn.heightAnchor.constraint(equalToConstant: 36),

            urlField.leadingAnchor.constraint(equalTo: fwdBtn.trailingAnchor, constant: 8),
            urlField.trailingAnchor.constraint(equalTo: reloadBtn.leadingAnchor, constant: -8),
            urlField.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            urlField.heightAnchor.constraint(equalToConstant: 36),

            reloadBtn.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
            reloadBtn.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            reloadBtn.widthAnchor.constraint(equalToConstant: 36),
            reloadBtn.heightAnchor.constraint(equalToConstant: 36),
        ])

        return container
    }

    private func loadURL(_ urlString: String, in webView: WKWebView) {
        var cleaned = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleaned.hasPrefix("http://") && !cleaned.hasPrefix("https://") {
            cleaned = "https://" + cleaned
        }
        if let url = URL(string: cleaned) {
            webView.load(URLRequest(url: url))
        }
    }
}

// MARK: - Coordinator (WKNavigationDelegate + UITextFieldDelegate + WKDownloadDelegate)

@MainActor
final class BrowserWebViewCoordinator: NSObject, WKNavigationDelegate, UITextFieldDelegate, WKDownloadDelegate {
    @Binding var urlText: String
    @Binding var isLoading: Bool
    let onFileDownloaded: (AudioFile) -> Void
    let onError: (String) -> Void

    weak var webView: WKWebView?
    weak var backButton: UIButton?
    weak var forwardButton: UIButton?
    weak var urlField: UITextField?
    weak var reloadButton: UIButton?

    private var downloadDestinationURL: URL?

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
        onFileDownloaded: @escaping (AudioFile) -> Void,
        onError: @escaping (String) -> Void
    ) {
        _urlText = urlText
        _isLoading = isLoading
        self.onFileDownloaded = onFileDownloaded
        self.onError = onError
    }

    // MARK: - Button Actions

    @objc func goBack() {
        webView?.goBack()
    }

    @objc func goForward() {
        webView?.goForward()
    }

    @objc func reload() {
        webView?.reload()
    }

    private func updateNavButtons() {
        backButton?.isEnabled = webView?.canGoBack ?? false
        forwardButton?.isEnabled = webView?.canGoForward ?? false
        backButton?.alpha = (webView?.canGoBack ?? false) ? 1.0 : 0.35
        forwardButton?.alpha = (webView?.canGoForward ?? false) ? 1.0 : 0.35
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        isLoading = true
        if let url = webView.url {
            urlField?.text = url.absoluteString
        }
        updateNavButtons()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isLoading = false
        if let url = webView.url {
            urlField?.text = url.absoluteString
            urlText = url.absoluteString
        }
        updateNavButtons()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        isLoading = false
        updateNavButtons()
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

    // MARK: - UITextFieldDelegate

    nonisolated func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        let text = textField.text ?? ""
        Task { @MainActor in
            var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
            // If it looks like a search query, use DuckDuckGo
            if !cleaned.contains(".") || cleaned.contains(" ") {
                let encoded = cleaned.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                cleaned = "https://duckduckgo.com/?q=\(encoded)"
            } else if !cleaned.hasPrefix("http://") && !cleaned.hasPrefix("https://") {
                cleaned = "https://" + cleaned
            }
            if let url = URL(string: cleaned) {
                self.webView?.load(URLRequest(url: url))
            }
        }
        return true
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
                url: uniqueURL,
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
