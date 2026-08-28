//  MarkdownTextCleanerTests.swift
//  IlumionateTests

import Foundation
import Testing
@testable import Ilumionate

struct MarkdownTextCleanerTests {

    @Test func stripsHeadingMarkers() {
        #expect(MarkdownTextCleaner.plainText(from: "## Deep Rest") == "Deep Rest")
    }

    @Test func stripsEmphasisMarkers() {
        let cleaned = MarkdownTextCleaner.plainText(from: "You feel **calm** and _steady_ now.")
        #expect(cleaned == "You feel calm and steady now.")
    }

    @Test func keepsLinkTextAndDropsTheURL() {
        let cleaned = MarkdownTextCleaner.plainText(from: "Read [the guide](https://example.com) later.")
        #expect(cleaned == "Read the guide later.")
    }

    @Test func stripsListBulletsAndBlockquoteMarkers() {
        let cleaned = MarkdownTextCleaner.plainText(from: "- breathe in\n- breathe out\n> settle")
        #expect(cleaned == "breathe in\nbreathe out\nsettle")
    }

    @Test func stripsCodeFencesAndInlineBackticks() {
        let cleaned = MarkdownTextCleaner.plainText(from: "```\nlet x = 1\n```\nSay `now` softly.")
        #expect(cleaned == "let x = 1\nSay now softly.")
    }

    @Test func stripsHorizontalRules() {
        #expect(MarkdownTextCleaner.plainText(from: "one\n---\ntwo") == "one\ntwo")
    }

    /// An asterisk that is not emphasis must survive, or ordinary prose gets
    /// mangled.
    @Test func leavesLoneAsterisksAlone() {
        #expect(MarkdownTextCleaner.plainText(from: "2 * 3 = 6") == "2 * 3 = 6")
    }
}
