//
//  LibraryFilterBar.swift
//  Ilumionate
//
//  Search-first browse controls shared by the Library tab and the pushed
//  browse screen: a glass search field and a chip row of quick filters with
//  counts. Pure presentation — all state lives in the hosting view.
//

import SwiftUI

// MARK: - Search Field

/// Glass capsule search field with a clear affordance. `prompt` names what is
/// actually searched so the field does not over-promise.
struct LibrarySearchField: View {
    @Binding var text: String
    var prompt: String = "Search titles, artists, types"

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: TranceSpacing.inner) {
            Image(systemName: "magnifyingglass")
                .font(TranceTypography.body)
                .foregroundStyle(isFocused ? Color.roseGold : Color.textLight)

            TextField(prompt, text: $text)
                .font(TranceTypography.body)
                .foregroundStyle(Color.textPrimary)
                .textFieldStyle(.plain)
                .platformAutocorrectionDisabled()
                .platformNeverAutocapitalized()
                .platformSearchSubmitLabel()
                .focused($isFocused)

            if text.isEmpty == false {
                Button {
                    text = ""
                    TranceHaptics.shared.light()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(TranceTypography.body)
                        .foregroundStyle(Color.textLight)
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, TranceSpacing.card)
        .padding(.vertical, TranceSpacing.list)
        .liminalGlass(.capsule, glow: false)
        .overlay {
            Capsule()
                .strokeBorder(Color.roseGold.opacity(isFocused ? 0.55 : 0), lineWidth: 1)
        }
        .animation(.easeOut(duration: 0.18), value: isFocused)
    }
}

// MARK: - Quick Filter Chips

/// Horizontally scrolling quick filters. Counts come from the data, so a chip
/// never offers a dead end.
struct LibraryFilterChipRow: View {
    let chips: [LibraryFilterChip]
    @Binding var selection: LibraryQuickFilter

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: TranceSpacing.inner) {
                ForEach(chips) { chip in
                    Button {
                        TranceHaptics.shared.light()
                        selection = chip.filter
                    } label: {
                        LibraryFilterChipLabel(
                            chip: chip,
                            isSelected: selection == chip.filter
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(chip.filter.label), \(chip.count) items")
                    .accessibilityAddTraits(selection == chip.filter ? [.isSelected] : [])
                }
            }
            .padding(.horizontal, TranceSpacing.screen)
            .padding(.vertical, TranceSpacing.micro)
        }
        .scrollIndicators(.hidden)
    }
}

private struct LibraryFilterChipLabel: View {
    let chip: LibraryFilterChip
    let isSelected: Bool

    private var tint: Color {
        if case .contentType(let type) = chip.filter {
            return ContentTypeStyle.color(for: type)
        }
        return .roseGold
    }

    var body: some View {
        HStack(spacing: TranceSpacing.icon) {
            Image(systemName: chip.filter.systemImage)
                .font(.system(size: 11, weight: .semibold))

            Text(chip.filter.label)
                .font(TranceTypography.caption)
                .fontWeight(.semibold)

            Text(chip.count, format: .number)
                .font(TranceTypography.caption)
                .monospacedDigit()
                .foregroundStyle(isSelected ? Color.bgDeep.opacity(0.65) : Color.textLight)
        }
        .foregroundStyle(isSelected ? Color.bgDeep : Color.textSecondary)
        .padding(.horizontal, TranceSpacing.list)
        .padding(.vertical, TranceSpacing.inner)
        .background {
            if isSelected {
                Capsule().fill(tint)
            } else {
                Capsule()
                    .fill(Color.glassBorder.opacity(0.12))
                    .overlay(Capsule().strokeBorder(Color.glassBorder.opacity(0.4), lineWidth: 1))
            }
        }
    }
}

// MARK: - Sort Menu

/// Compact sort control matching the chip row's visual weight.
struct LibrarySortMenu: View {
    @Binding var selection: LibrarySortOption

    var body: some View {
        Menu {
            Picker("Sort By", selection: $selection) {
                ForEach(LibrarySortOption.allCases, id: \.self) { option in
                    Text(option.label).tag(option)
                }
            }
        } label: {
            HStack(spacing: TranceSpacing.micro) {
                Image(systemName: "arrow.up.arrow.down")
                Text(selection.label)
            }
            .font(TranceTypography.caption)
            .fontWeight(.medium)
            .foregroundStyle(Color.textSecondary)
            .padding(.horizontal, TranceSpacing.list)
            .padding(.vertical, TranceSpacing.inner)
            .liminalGlass(.capsule, glow: false)
        }
        .accessibilityLabel("Sort by \(selection.label)")
    }
}

// MARK: - Result Summary

/// "24 of 144" style readout so a narrowed list always states its own scope.
struct LibraryResultSummary: View {
    let shown: Int
    let total: Int
    var noun: String = "files"

    var body: some View {
        Text(shown == total
             ? "\(total) \(noun)"
             : "\(shown) of \(total) \(noun)")
            .font(TranceTypography.caption)
            .foregroundStyle(Color.textLight)
    }
}

// MARK: - Empty Results

/// Shown when a search or filter yields nothing, with a way back out.
struct LibraryNoResultsView: View {
    let query: String
    let onClear: () -> Void

    var body: some View {
        VStack(spacing: TranceSpacing.card) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 40, weight: .ultraLight))
                .foregroundStyle(Color.textLight)

            Text(query.isEmpty ? "Nothing matches that filter" : "No results for “\(query)”")
                .font(TranceTypography.sectionTitle)
                .foregroundStyle(Color.textPrimary)
                .multilineTextAlignment(.center)

            Button("Clear", systemImage: "xmark.circle", action: onClear)
                .font(TranceTypography.caption)
                .foregroundStyle(Color.roseGold)
                .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, TranceSpacing.statusBar)
    }
}
