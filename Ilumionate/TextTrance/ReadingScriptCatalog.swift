//  ReadingScriptCatalog.swift
//  Ilumionate
//
//  Curated metadata for externally hosted scripts. Entries are links plus
//  discovery metadata; script text is fetched only after the user taps Import.

import Foundation

enum ReadingScriptKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case induction
    case deepening
    case subject
    case selfHypnosis
    case story
    case book

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .induction:     return "Induction"
        case .deepening:     return "Deepening"
        case .subject:       return "Subject"
        case .selfHypnosis:  return "Self-Hypnosis"
        case .story:         return "Story"
        case .book:          return "Book"
        }
    }
}

enum ReadingScriptLength: String, Codable, CaseIterable, Identifiable, Sendable {
    case short
    case medium
    case long

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .short:  return "Short"
        case .medium: return "Medium"
        case .long:   return "Long"
        }
    }
}

struct ReadingScriptCatalogEntry: Identifiable, Codable, Hashable, Sendable {
    let id: String
    var title: String
    var url: URL
    var sourceID: String
    var sourceTitle: String
    var kind: ReadingScriptKind
    var theme: ScriptTheme
    var length: ReadingScriptLength
    var summary: String
    var tags: [String]
    var importPolicy: ReadingSourceImportPolicy
    var contentRating: ReadingSourceContentRating
    var licenseNote: String

    var canImport: Bool {
        importPolicy == .userInitiatedImport || importPolicy == .catalogPlanned
    }

    func matches(_ query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return true }

        return title.localizedCaseInsensitiveContains(trimmed)
            || sourceTitle.localizedCaseInsensitiveContains(trimmed)
            || summary.localizedCaseInsensitiveContains(trimmed)
            || kind.displayName.localizedCaseInsensitiveContains(trimmed)
            || theme.displayName.localizedCaseInsensitiveContains(trimmed)
            || tags.contains { $0.localizedCaseInsensitiveContains(trimmed) }
    }
}

enum ReadingScriptCatalog {
    static let curatedEntries: [ReadingScriptCatalogEntry] = [
        entry(
            id: "fhs-progressive-relaxation",
            title: "Progressive Relaxation",
            path: "induction-script/progressive-relaxation/",
            kind: .induction,
            theme: .relaxation,
            length: .short,
            summary: "A short progressive body-relaxation induction.",
            tags: ["body scan", "relaxation", "muscle release", "calm"]
        ),
        entry(
            id: "fhs-relaxation-deepener",
            title: "Relaxation",
            path: "deepening-script/relaxation/",
            kind: .deepening,
            theme: .relaxation,
            length: .short,
            summary: "A compact deepener using repeated relaxation cues.",
            tags: ["deepener", "relaxation", "drowsy", "calm"]
        ),
        entry(
            id: "fhs-anxiety-control",
            title: "Anxiety Control",
            path: "subject-script/anxiety-control/",
            kind: .subject,
            theme: .relaxation,
            length: .medium,
            summary: "A subject script focused on calming anxious responses.",
            tags: ["anxiety", "calm", "control", "stress"]
        ),
        entry(
            id: "fhs-concentration",
            title: "Concentration",
            path: "subject-script/concentration/",
            kind: .subject,
            theme: .focus,
            length: .medium,
            summary: "A focus-oriented script for attention and concentration.",
            tags: ["focus", "study", "attention", "clarity"]
        ),
        entry(
            id: "fhs-ego-strengthener",
            title: "Ego Strengthener",
            path: "subject-script/ego-strengthener/",
            kind: .subject,
            theme: .suggestion,
            length: .medium,
            summary: "Confidence and self-strengthening suggestions.",
            tags: ["confidence", "self worth", "resilience", "strength"]
        ),
        entry(
            id: "fhs-insomnia",
            title: "Insomnia",
            path: "subject-script/insomnia/",
            kind: .subject,
            theme: .sleep,
            length: .medium,
            summary: "A sleep-oriented subject script for settling at night.",
            tags: ["sleep", "insomnia", "night", "rest"]
        ),
        entry(
            id: "fhs-sleep-easy",
            title: "Sleep Easy",
            path: "subject-script/sleep-easy/",
            kind: .subject,
            theme: .sleep,
            length: .medium,
            summary: "Gentle sleep suggestions for an easy bedtime flow.",
            tags: ["sleep", "bedtime", "rest", "calm"]
        ),
        entry(
            id: "fhs-goal-achievement",
            title: "Goal Achievement",
            path: "subject-script/goal-achievement/",
            kind: .subject,
            theme: .suggestion,
            length: .medium,
            summary: "Motivational suggestions for goals and achievement.",
            tags: ["goals", "motivation", "achievement", "planning"]
        ),
        entry(
            id: "fhs-self-hypnosis-induction",
            title: "Self Hypnosis - Induction Script",
            path: "self-hypnosis/self-hypnosis-induction-script/",
            kind: .selfHypnosis,
            theme: .relaxation,
            length: .medium,
            summary: "A self-hypnosis induction for personal practice.",
            tags: ["self hypnosis", "induction", "practice", "relaxation"]
        ),
        entry(
            id: "fhs-self-hypnosis-stress-management",
            title: "Self Hypnosis - Stress Management",
            path: "self-hypnosis/self-hypnosis-stress-management/",
            kind: .selfHypnosis,
            theme: .relaxation,
            length: .medium,
            summary: "Self-hypnosis suggestions for stress management.",
            tags: ["self hypnosis", "stress", "calm", "management"]
        )
    ]

    static func entries(kind: ReadingScriptKind? = nil,
                        theme: ScriptTheme? = nil,
                        query: String = "") -> [ReadingScriptCatalogEntry] {
        curatedEntries.filter { entry in
            (kind == nil || entry.kind == kind)
                && (theme == nil || entry.theme == theme)
                && entry.matches(query)
        }
    }

    private static func entry(id: String,
                              title: String,
                              path: String,
                              kind: ReadingScriptKind,
                              theme: ScriptTheme,
                              length: ReadingScriptLength,
                              summary: String,
                              tags: [String]) -> ReadingScriptCatalogEntry {
        ReadingScriptCatalogEntry(
            id: id,
            title: title,
            url: URL(string: "https://freehypnosisscripts.info/\(path)")!,
            sourceID: "free-hypnosis-scripts-info",
            sourceTitle: "Free Hypnosis Scripts",
            kind: kind,
            theme: theme,
            length: length,
            summary: summary,
            tags: tags,
            importPolicy: .userInitiatedImport,
            contentRating: .mixed,
            licenseNote: "Review the script page and site terms before use."
        )
    }
}
