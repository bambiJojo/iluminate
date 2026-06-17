//
//  PhraseLibraryView.swift
//  Ilumionate
//
//  Corpus-wide browser for learned hypnosis phrase associations.
//

import SwiftUI

struct PhraseLibraryView: View {

    private enum PhaseFilter: String, CaseIterable, Identifiable {
        case all
        case preTalk
        case induction
        case deepening
        case therapy
        case suggestions
        case eroticSuggestions
        case brainwashing
        case conditioning
        case emergence

        var id: String { rawValue }

        var title: String {
            switch self {
            case .all: return "All Phases"
            case .preTalk: return HypnosisMetadata.Phase.preTalk.displayName
            case .induction: return HypnosisMetadata.Phase.induction.displayName
            case .deepening: return HypnosisMetadata.Phase.deepening.displayName
            case .therapy: return HypnosisMetadata.Phase.therapy.displayName
            case .suggestions: return HypnosisMetadata.Phase.suggestions.displayName
            case .eroticSuggestions: return HypnosisMetadata.Phase.eroticSuggestions.displayName
            case .brainwashing: return HypnosisMetadata.Phase.brainwashing.displayName
            case .conditioning: return HypnosisMetadata.Phase.conditioning.displayName
            case .emergence: return HypnosisMetadata.Phase.emergence.displayName
            }
        }

        var phase: HypnosisMetadata.Phase? {
            switch self {
            case .all: return nil
            case .preTalk: return .preTalk
            case .induction: return .induction
            case .deepening: return .deepening
            case .therapy: return .therapy
            case .suggestions: return .suggestions
            case .eroticSuggestions: return .eroticSuggestions
            case .brainwashing: return .brainwashing
            case .conditioning: return .conditioning
            case .emergence: return .emergence
            }
        }
    }

    private enum OriginFilter: String, CaseIterable, Identifiable {
        case all
        case blended
        case corpus
        case curated

        var id: String { rawValue }

        var title: String {
            switch self {
            case .all: return "All"
            case .blended: return "Blended"
            case .corpus: return "Corpus"
            case .curated: return "Research"
            }
        }

        var origin: HypnosisPhraseEvidenceOrigin? {
            switch self {
            case .all: return nil
            case .blended: return .blended
            case .corpus: return .corpus
            case .curated: return .curated
            }
        }
    }

    private enum SourceFilter: String, CaseIterable, Identifiable {
        case all
        case bambi
        case other

        var id: String { rawValue }

        var title: String {
            switch self {
            case .all: return "All Sources"
            case .bambi: return "Bambi"
            case .other: return "Other"
            }
        }

        func includes(_ association: HypnosisPhraseAssociation) -> Bool {
            switch self {
            case .all:
                return true
            case .bambi:
                return association.sourcePackIDs.contains("bambi")
            case .other:
                return !association.sourcePackIDs.contains("bambi")
            }
        }
    }

    @State private var searchText = ""
    @State private var phaseFilter: PhaseFilter = .all
    @State private var originFilter: OriginFilter = .all
    @State private var sourceFilter: SourceFilter = .all

    private var knowledge: CorpusPhaseKnowledge {
        CorpusPhaseKnowledgeCache.shared.knowledge()
    }

    private var allAssociations: [HypnosisPhraseAssociation] {
        knowledge.phraseAssociations
            .flatMap(\.value)
            .sorted { lhs, rhs in
                if abs(lhs.weight - rhs.weight) < 0.0001 { return lhs.phrase < rhs.phrase }
                return lhs.weight > rhs.weight
            }
    }

    private var filteredAssociations: [HypnosisPhraseAssociation] {
        allAssociations.filter { association in
            let phaseMatches = phaseFilter.phase.map { association.phase == $0 } ?? true
            let originMatches = originFilter.origin.map { association.origin == $0 } ?? true
            let sourceMatches = sourceFilter.includes(association)
            let searchMatches = searchText.isEmpty
                || association.phrase.localizedCaseInsensitiveContains(searchText)
                || association.phase.displayName.localizedCaseInsensitiveContains(searchText)
                || (association.sourceLabel?.localizedCaseInsensitiveContains(searchText) ?? false)
            return phaseMatches && originMatches && sourceMatches && searchMatches
        }
    }

    private var groupedAssociations: [(phase: HypnosisMetadata.Phase, phrases: [HypnosisPhraseAssociation])] {
        let phases = phaseFilter.phase.map { [$0] } ?? HypnosisMetadata.Phase.allCases.filter {
            ![.fractionation, .confusion, .transitional].contains($0)
        }
        return phases.compactMap { phase in
            let phrases = filteredAssociations.filter { $0.phase == phase }
            guard !phrases.isEmpty else { return nil }
            return (phase, phrases)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TranceSpacing.content) {
                summarySection
                filterSection
                librarySection
                Color.clear.frame(height: TranceSpacing.tabBarClearance)
            }
            .padding(.horizontal, TranceSpacing.screen)
            .padding(.top, TranceSpacing.content)
        }
        .background(Color.bgPrimary.ignoresSafeArea())
        .navigationTitle("Phrase Library")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search phrases, phases, or sources")
    }

    private var summarySection: some View {
        GlassCard(label: "Corpus Phrase Map") {
            VStack(alignment: .leading, spacing: TranceSpacing.list) {
                Text("Browse the hypnosis phrase database learned from your labeled corpus and blended with curated reference phrases.")
                    .font(TranceTypography.caption)
                    .foregroundStyle(Color.textSecondary)

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 118), spacing: TranceSpacing.inner)],
                    alignment: .leading,
                    spacing: TranceSpacing.inner
                ) {
                    summaryBadge(
                        title: "Phrases",
                        value: allAssociations.count.formatted(),
                        tint: .phaseDeepener
                    )
                    summaryBadge(
                        title: "Corpus-Backed",
                        value: allAssociations.filter { $0.exampleCount > 0 }.count.formatted(),
                        tint: .bwGamma
                    )
                    summaryBadge(
                        title: "Blended",
                        value: allAssociations.filter { $0.origin == .blended }.count.formatted(),
                        tint: .roseGold
                    )
                    summaryBadge(
                        title: "Bambi",
                        value: allAssociations.filter { $0.sourcePackIDs.contains("bambi") }.count.formatted(),
                        tint: .orange
                    )
                }
            }
        }
    }

    private func summaryBadge(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title.uppercased())
                .font(TranceTypography.cardLabel)
                .foregroundStyle(Color.textLight)
            Text(value)
                .font(TranceTypography.body.weight(.semibold))
                .foregroundStyle(Color.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(tint.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(tint.opacity(0.2), lineWidth: 1)
        )
    }

    private var filterSection: some View {
        GlassCard(label: "Filters") {
            VStack(alignment: .leading, spacing: TranceSpacing.list) {
                Menu {
                    ForEach(PhaseFilter.allCases) { option in
                        Button(option.title) { phaseFilter = option }
                    }
                } label: {
                    HStack {
                        Text(phaseFilter.title)
                            .font(TranceTypography.caption.weight(.semibold))
                            .foregroundStyle(Color.textPrimary)
                        Spacer()
                        Image(systemName: "chevron.down")
                            .font(.caption.bold())
                            .foregroundStyle(Color.textSecondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.white.opacity(0.06))
                    )
                }
                .buttonStyle(.plain)

                Picker("Evidence", selection: $originFilter) {
                    ForEach(OriginFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.segmented)

                Picker("Source", selection: $sourceFilter) {
                    ForEach(SourceFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
    }

    private var librarySection: some View {
        VStack(alignment: .leading, spacing: TranceSpacing.list) {
            if groupedAssociations.isEmpty {
                ContentUnavailableView(
                    "No Phrases Found",
                    systemImage: "magnifyingglass",
                    description: Text("Try a different phase or evidence filter.")
                )
            } else {
                ForEach(groupedAssociations, id: \.phase) { group in
                    GlassCard(label: group.phase.displayName) {
                        VStack(alignment: .leading, spacing: TranceSpacing.list) {
                            ForEach(group.phrases) { association in
                                phraseRow(association)
                                if association.id != group.phrases.last?.id {
                                    Divider()
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func phraseRow(_ association: HypnosisPhraseAssociation) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: TranceSpacing.inner) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(association.phrase)
                        .font(TranceTypography.sectionTitle)
                        .foregroundStyle(Color.textPrimary)
                    Text(association.phase.displayName)
                        .font(TranceTypography.caption)
                        .foregroundStyle(phaseColor(association.phase))
                }
                Spacer()
                originBadge(association.origin)
            }

            HStack(spacing: TranceSpacing.inner) {
                metricPill("Weight", value: String(format: "%.1f", association.weight))
                metricPill("Files", value: association.exampleCount.formatted())
                metricPill("Windows", value: association.sectionCount.formatted())
                if association.corpusSupport > 0 {
                    metricPill("Corpus", value: String(format: "%.1f", association.corpusSupport))
                }
            }

            if let sourceLabel = association.sourceLabel, !sourceLabel.isEmpty {
                if let sourceURL = association.sourceURL,
                   sourceURL.hasPrefix("http"),
                   let url = URL(string: sourceURL) {
                    Link(destination: url) {
                        Label(sourceLabel, systemImage: "link")
                            .font(TranceTypography.caption)
                            .foregroundStyle(Color.roseGold)
                    }
                    .buttonStyle(.plain)
                } else {
                    Text(sourceLabel)
                        .font(TranceTypography.caption)
                        .foregroundStyle(Color.textSecondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func originBadge(_ origin: HypnosisPhraseEvidenceOrigin) -> some View {
        let tint: Color
        let label: String
        switch origin {
        case .curated:
            tint = .roseGold
            label = "Research"
        case .corpus:
            tint = .bwGamma
            label = "Corpus"
        case .blended:
            tint = .phaseDeepener
            label = "Blended"
        }

        return Text(label)
            .font(TranceTypography.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(tint.opacity(0.12))
            )
    }

    private func metricPill(_ title: String, value: String) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(Color.textSecondary)
            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.textPrimary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
    }

    private func phaseColor(_ phase: HypnosisMetadata.Phase) -> Color {
        switch phase {
        case .preTalk: return .bwAlpha
        case .induction: return .phaseInduction
        case .fractionation: return .phaseFractionation
        case .deepening: return .phaseDeepener
        case .confusion: return .mint
        case .therapy, .suggestions: return .phaseSuggestion
        case .eroticSuggestions: return .roseDeep
        case .brainwashing: return .orange
        case .conditioning: return .bwGamma
        case .emergence: return .bwBeta
        case .transitional: return .textLight
        }
    }
}
