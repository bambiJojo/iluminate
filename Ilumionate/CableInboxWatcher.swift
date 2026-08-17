//
//  CableInboxWatcher.swift
//  Ilumionate
//
//  Finder writes into the Documents root while the app is running, so intake
//  driven only by launch, foregrounding, and a button will miss anything that
//  lands afterwards. A small transfer happens to complete before the app
//  foregrounds; a large one does not, and its files are then invisible until
//  something else triggers a scan.
//
//  This watches the directory itself and reports arrivals.
//

import Foundation
import os

@MainActor
final class CableInboxWatcher {

    /// A copy of twenty files produces a burst of write events. Coalescing them
    /// avoids starting twenty scans, and — more importantly — keeps the scan
    /// out of an in-flight transfer. Moving a file Finder still references
    /// fails the whole drag with "required file cannot be found", so the
    /// directory must go quiet before anything is touched.
    private let debounce: Duration

    private var source: (any DispatchSourceFileSystemObject)?
    private var descriptor: CInt = -1
    private var pendingNotification: Task<Void, Never>?

    init(debounce: Duration = .seconds(5)) {
        self.debounce = debounce
    }

    var isWatching: Bool { source != nil }

    /// Begins watching `url`. Safe to call repeatedly; a second call replaces
    /// the first watch rather than stacking another descriptor.
    func start(url: URL, onChange: @escaping @MainActor () -> Void) {
        stop()

        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else {
            Log.audio.error(
                "Could not watch the transfer inbox: errno \(errno, privacy: .public)"
            )
            return
        }
        descriptor = fd

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .rename],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            self?.scheduleNotification(onChange)
        }
        source.setCancelHandler { [descriptor] in
            if descriptor >= 0 { close(descriptor) }
        }
        source.resume()
        self.source = source
    }

    func stop() {
        pendingNotification?.cancel()
        pendingNotification = nil
        source?.cancel()
        source = nil
        descriptor = -1
    }

    /// Restarts the debounce window on every event, so the callback fires once
    /// the directory has been quiet for `debounce` rather than once per file.
    private func scheduleNotification(_ onChange: @escaping @MainActor () -> Void) {
        pendingNotification?.cancel()
        pendingNotification = Task { @MainActor [debounce] in
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled else { return }
            onChange()
        }
    }

    deinit {
        source?.cancel()
    }
}
