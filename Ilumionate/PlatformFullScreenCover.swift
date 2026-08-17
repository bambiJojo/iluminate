//
//  PlatformFullScreenCover.swift
//  Ilumionate
//
//  iOS presents immersive surfaces (players, the reader, onboarding, the
//  in-app browser) with `fullScreenCover`. macOS has no equivalent, so they
//  are presented as sheets.
//
//  A macOS sheet sizes itself to its content's ideal size, and every one of
//  these surfaces is a full-bleed composition with no intrinsic dimensions —
//  so an unsized sheet collapses to a sliver (the reader measured 48x18pt).
//  The macOS path therefore pins the sheet to the host window's content area,
//  which is the closest native analogue of a full-screen cover: it covers the
//  window, tracks live window resizes, and never overhangs the window edges.
//

import SwiftUI

extension View {
    @ViewBuilder
    func platformFullScreenCover<Content: View>(
        isPresented: Binding<Bool>,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        #if os(macOS)
        modifier(
            MacWindowFillingCover(isPresented: isPresented, onDismiss: onDismiss, coverContent: content)
        )
        #else
        fullScreenCover(isPresented: isPresented, onDismiss: onDismiss, content: content)
        #endif
    }

    @ViewBuilder
    func platformFullScreenCover<Item: Identifiable, Content: View>(
        item: Binding<Item?>,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping (Item) -> Content
    ) -> some View {
        #if os(macOS)
        modifier(
            MacWindowFillingItemCover(item: item, onDismiss: onDismiss, coverContent: content)
        )
        #else
        fullScreenCover(item: item, onDismiss: onDismiss, content: content)
        #endif
    }
}

#if os(macOS)
import AppKit

/// Smallest cover the app will present when the host window has not been
/// resolved yet. Stays within the app's minimum window content area (760x528)
/// so a fallback-sized sheet can never spill outside its window.
private enum MacCoverFallbackSize {
    static let width: CGFloat = 720
    static let height: CGFloat = 500
}

/// Live size of the window hosting a presenter, so a sheet can be sized to
/// fill it. `contentLayoutRect` excludes the title bar and toolbar, which is
/// exactly the region a sheet occupies.
@MainActor
@Observable
private final class HostWindowSize {
    var size: CGSize = .zero

    func update(to newSize: CGSize) {
        guard newSize != size else { return }
        size = newSize
    }
}

/// Reports the host window's content size on attach and on every resize.
/// Uses AppKit layout callbacks rather than notifications so no non-Sendable
/// notification has to cross an isolation boundary.
private final class HostWindowProbeView: NSView {
    var onWindowContentSizeChange: ((CGSize) -> Void)?
    private var lastReportedSize: CGSize?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        reportWindowContentSize()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        reportWindowContentSize()
    }

    private func reportWindowContentSize() {
        guard let window else { return }
        let size = window.contentLayoutRect.size
        guard size != lastReportedSize else { return }
        lastReportedSize = size

        // These callbacks fire inside an AppKit layout pass, which can itself
        // sit inside a SwiftUI update. Hand the value back on the next turn so
        // observable state is never mutated mid-update.
        Task { @MainActor [weak self] in
            self?.onWindowContentSizeChange?(size)
        }
    }
}

private struct HostWindowReader: NSViewRepresentable {
    let onWindowContentSizeChange: (CGSize) -> Void

    func makeNSView(context: Context) -> HostWindowProbeView {
        let view = HostWindowProbeView(frame: .zero)
        view.onWindowContentSizeChange = onWindowContentSizeChange
        return view
    }

    func updateNSView(_ nsView: HostWindowProbeView, context: Context) {
        nsView.onWindowContentSizeChange = onWindowContentSizeChange
    }
}

extension View {
    /// Fills the host window, falling back to a safe minimum until the window
    /// resolves. Sizing the *content* is what drives the sheet window's size.
    @ViewBuilder
    fileprivate func macCoverSized(to hostSize: CGSize) -> some View {
        if hostSize.width > 0, hostSize.height > 0 {
            frame(width: hostSize.width, height: hostSize.height)
        } else {
            frame(
                minWidth: MacCoverFallbackSize.width,
                minHeight: MacCoverFallbackSize.height
            )
        }
    }
}

private struct MacWindowFillingCover<CoverContent: View>: ViewModifier {
    let isPresented: Binding<Bool>
    let onDismiss: (() -> Void)?
    @ViewBuilder let coverContent: () -> CoverContent

    @State private var hostWindow = HostWindowSize()

    func body(content: Content) -> some View {
        content
            .background(HostWindowReader { hostWindow.update(to: $0) })
            .sheet(isPresented: isPresented, onDismiss: onDismiss) {
                coverContent().macCoverSized(to: hostWindow.size)
            }
    }
}

private struct MacWindowFillingItemCover<Item: Identifiable, CoverContent: View>: ViewModifier {
    let item: Binding<Item?>
    let onDismiss: (() -> Void)?
    @ViewBuilder let coverContent: (Item) -> CoverContent

    @State private var hostWindow = HostWindowSize()

    func body(content: Content) -> some View {
        content
            .background(HostWindowReader { hostWindow.update(to: $0) })
            .sheet(item: item, onDismiss: onDismiss) { item in
                coverContent(item).macCoverSized(to: hostWindow.size)
            }
    }
}
#endif
