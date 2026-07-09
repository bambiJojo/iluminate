//  ReaderSectionIndexTests.swift
//  IlumionateTests

import Testing
@testable import Ilumionate

struct ReaderSectionIndexTests {
    private func script(_ text: String,
                        arcs: [ScriptArc] = [.fullText],
                        segments: [TranceScriptSegment]? = nil) -> TranceScript {
        TranceScript(
            schemaVersion: 1,
            id: "sections",
            title: "Sections",
            theme: .focus,
            supportedArcs: arcs,
            language: "en",
            source: ScriptSource(kind: .importedWeb, generator: nil, reviewed: false),
            segments: segments ?? [
                TranceScriptSegment(
                    phase: .induction,
                    text: text,
                    pacing: SegmentPacing(baseWPM: 150),
                    arcs: nil,
                    triggersHandoff: nil
                )
            ]
        )
    }

    @Test func detectsBookHeadingsAndMapsToWordIndexes() {
        let text = """
        Preface

        Before the story begins here.

        Chapter 1

        The first chapter starts now.

        Chapter 2: Deeper

        The second chapter follows.
        """

        let sections = ReaderSectionIndex.sections(for: script(text), arc: .fullText)

        #expect(sections.map(\.title) == ["Preface", "Chapter 1", "Chapter 2: Deeper"])
        #expect(sections.map(\.wordIndex) == [0, 6, 13])
    }

    @Test func insertsBeginningWhenFirstDetectedHeadingStartsLater() {
        let text = """
        This opening paragraph appears before any chapter heading.

        Chapter One

        The chapter body starts after the heading.
        """

        let sections = ReaderSectionIndex.sections(for: script(text), arc: .fullText)

        #expect(sections.map(\.title) == ["Beginning", "Chapter One"])
        #expect(sections.map(\.wordIndex) == [0, 8])
    }

    @Test func fallsBackToPlayableSegmentBoundariesWhenNoHeadingsExist() {
        let segments = [
            TranceScriptSegment(
                phase: .induction,
                text: "Soft words begin here.",
                pacing: nil,
                arcs: nil,
                triggersHandoff: nil
            ),
            TranceScriptSegment(
                phase: .deepening,
                text: "The next phase follows.",
                pacing: nil,
                arcs: nil,
                triggersHandoff: nil
            )
        ]

        let sections = ReaderSectionIndex.sections(
            for: script("", segments: segments),
            arc: .fullText
        )

        #expect(sections.map(\.title) == ["Induction", "Deepening"])
        #expect(sections.map(\.wordIndex) == [0, 4])
    }

    @Test func handoffArcDoesNotIndexAfterTriggerSegment() {
        let segments = [
            TranceScriptSegment(
                phase: .induction,
                text: "Chapter 1\n\nRead this first.",
                pacing: nil,
                arcs: nil,
                triggersHandoff: nil
            ),
            TranceScriptSegment(
                phase: .transitional,
                text: "Chapter 2\n\nStop reading here.",
                pacing: nil,
                arcs: [.handoff],
                triggersHandoff: true
            ),
            TranceScriptSegment(
                phase: .emergence,
                text: "Chapter 3\n\nThis should be excluded.",
                pacing: nil,
                arcs: [.handoff],
                triggersHandoff: nil
            )
        ]

        let sections = ReaderSectionIndex.sections(
            for: script("", arcs: [.fullText, .handoff], segments: segments),
            arc: .handoff
        )

        #expect(sections.map(\.title) == ["Chapter 1", "Chapter 2"])
    }
}
