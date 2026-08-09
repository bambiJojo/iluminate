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
/// The gesture is attached with `.highPriorityGesture`, not
/// `.simultaneousGesture`: rows are wrapped in a `NavigationLink`, and with the
/// simultaneous variant the link swallowed the drag and pushed the detail
/// screen instead. High priority still leaves plain taps working, because the
/// drag needs 12pt of travel before it engages.
struct SwipeToDeleteRow<ID: Hashable>: ViewModifier {
    let id: ID
    /// Which row is open, shared across rows so only one opens at a time.
    @Binding var openRowID: ID?
    var isEnabled: Bool = true
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
            deleteAction
            content
                .offset(x: offset)
                .highPriorityGesture(dragGesture, isEnabled: isEnabled)
        }
        .onChange(of: isEnabled) { _, enabled in
            if !enabled { close() }
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
                // Ignore drags that are mostly vertical — those belong to the
                // enclosing ScrollView.
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                dragOffset = value.translation.width
            }
            .onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) else {
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
        onDelete: @escaping () -> Void
    ) -> some View {
        modifier(
            SwipeToDeleteRow(id: id, openRowID: openRowID, isEnabled: isEnabled, onDelete: onDelete)
        )
    }
}
