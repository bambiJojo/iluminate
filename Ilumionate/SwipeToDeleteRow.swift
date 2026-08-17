//
//  SwipeToDeleteRow.swift
//  Ilumionate
//

import SwiftUI

/// Swipe-left-to-reveal-delete for rows in a custom stack.
///
/// `List`'s `.swipeActions` only works inside a `List`, and the audio library
/// draws its rows in a `LazyVStack` inside a `GlassCard` to keep the Trance
/// styling. This reproduces the gesture without giving that up.
///
/// The revealed action is sized to exactly the strip the row vacates, so it
/// never shows through the row's transparent background.
///
/// Most rows attach the gesture simultaneously with their enclosing scroll
/// view. A high-priority `DragGesture` claims vertical drags as soon as it
/// recognizes, even when its callbacks later ignore them, which makes the
/// surrounding vertical list appear frozen. Navigation-link rows can opt into
/// high priority because their link otherwise consumes the horizontal drag.
struct SwipeToDeleteRow<ID: Hashable>: ViewModifier {
    let id: ID
    /// Which row is open, shared across rows so only one opens at a time.
    @Binding var openRowID: ID?
    var isEnabled: Bool = true
    var prioritizesSwipeOverNavigation = false
    let onDelete: () -> Void

    @State private var dragOffset: CGFloat = 0

    private static var actionWidth: CGFloat { 76 }
    private static var triggerDistance: CGFloat { 40 }

    private var isOpen: Bool { openRowID == id }

    /// Resting position plus whatever the finger is currently adding, clamped
    /// so the row never slides right past its home position.
    private var offset: CGFloat {
        let resting = isOpen ? -Self.actionWidth : 0
        return min(0, max(-Self.actionWidth, resting + dragOffset))
    }

    func body(content: Content) -> some View {
        ZStack(alignment: .trailing) {
            // A zero-width clipped action still creates render work. In the
            // 144-row library it produced roughly two offscreen passes per
            // dormant row, matching the 299–309-pass frames in PERF-04.
            if offset < 0 {
                deleteAction
            }
            interactiveContent(content)
        }
        .onChange(of: isEnabled) { _, enabled in
            if !enabled { close() }
        }
    }

    @ViewBuilder
    private func interactiveContent(_ content: Content) -> some View {
        let row = content.offset(x: offset)
        if prioritizesSwipeOverNavigation {
            row.highPriorityGesture(dragGesture, isEnabled: isEnabled)
        } else {
            row.simultaneousGesture(dragGesture, isEnabled: isEnabled)
        }
    }

    private var deleteAction: some View {
        Button(role: .destructive) {
            close()
            onDelete()
        } label: {
            Color.red
                .overlay {
                    Image(systemName: "trash.fill")
                        .font(.title3)
                        .foregroundStyle(.white)
                }
                // Exactly the width the row has vacated.
                .frame(width: max(0, -offset))
                .clipShape(.rect(cornerRadius: TranceRadius.thumbnail))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Delete")
        .allowsHitTesting(isOpen)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                switch SwipeDragAxis.classify(value.translation) {
                case .horizontal:
                    dragOffset = value.translation.width
                case .vertical, .undecided:
                    // Give vertical movement entirely to the enclosing list and
                    // discard any earlier diagonal movement of the row.
                    dragOffset = 0
                }
            }
            .onEnded { value in
                guard SwipeDragAxis.classify(value.translation) == .horizontal else {
                    dragOffset = 0
                    return
                }
                let settled = offset
                withAnimation(.snappy(duration: 0.22)) {
                    dragOffset = 0
                    openRowID = settled < -Self.triggerDistance ? id : nil
                }
            }
    }

    private func close() {
        withAnimation(.snappy(duration: 0.22)) {
            dragOffset = 0
            if isOpen { openRowID = nil }
        }
    }
}

extension View {
    /// Reveals a delete action when the row is swiped left.
    func swipeToDelete<ID: Hashable>(
        id: ID,
        openRowID: Binding<ID?>,
        isEnabled: Bool = true,
        prioritizesSwipeOverNavigation: Bool = false,
        onDelete: @escaping () -> Void
    ) -> some View {
        modifier(
            SwipeToDeleteRow(
                id: id,
                openRowID: openRowID,
                isEnabled: isEnabled,
                prioritizesSwipeOverNavigation: prioritizesSwipeOverNavigation,
                onDelete: onDelete
            )
        )
    }
}

nonisolated enum SwipeDragAxis: Equatable {
    case horizontal
    case vertical
    case undecided

    static func classify(_ translation: CGSize) -> Self {
        if translation == .zero { return .undecided }
        return abs(translation.width) > abs(translation.height) ? .horizontal : .vertical
    }
}
