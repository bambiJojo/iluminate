//  ResilientDecodingTests.swift
//  IlumionateTests
//
//  One bad element must cost one element, never the whole collection.

import Foundation
import Testing
@testable import Ilumionate

@Suite("Resilient decoding")
struct ResilientDecodingTests {

    private struct Item: Codable, Equatable {
        let id: String
        let count: Int
    }

    // MARK: - Arrays

    @Test("A good array decodes intact")
    func arrayRoundTrips() throws {
        let items = [Item(id: "a", count: 1), Item(id: "b", count: 2)]
        let data = try JSONEncoder().encode(items)
        let (values, dropped) = ResilientDecoding.array(Item.self, from: data)
        #expect(values == items)
        #expect(dropped == 0)
    }

    /// The bug this exists to prevent: whole-collection decoding turned one
    /// unreadable entry into a wiped library.
    @Test("One bad element loses one element, not the collection")
    func arraySurvivesOneBadElement() throws {
        let json = """
        [{"id":"a","count":1},{"id":"b"},{"id":"c","count":3}]
        """.data(using: .utf8) ?? Data()

        // Whole-collection decoding loses everything…
        let naive = try? JSONDecoder().decode([Item].self, from: json)
        #expect(naive == nil)

        // …element-wise keeps the survivors.
        let (values, dropped) = ResilientDecoding.array(Item.self, from: json)
        #expect(values.count == 2)
        #expect(dropped == 1)
        #expect(values.map(\.id) == ["a", "c"])
    }

    @Test("Order is preserved among survivors")
    func arrayKeepsOrder() throws {
        let json = """
        [{"id":"a","count":1},{"id":"bad"},{"id":"c","count":3},{"id":"d","count":4}]
        """.data(using: .utf8) ?? Data()
        let (values, _) = ResilientDecoding.array(Item.self, from: json)
        #expect(values.map(\.id) == ["a", "c", "d"])
    }

    @Test("Unreadable data yields empty rather than crashing")
    func arrayHandlesGarbage() {
        let (values, dropped) = ResilientDecoding.array(Item.self, from: Data("not json".utf8))
        #expect(values.isEmpty)
        #expect(dropped == 0)
    }

    @Test("Nested objects and arrays survive the round trip")
    func arrayHandlesNesting() throws {
        struct Nested: Codable, Equatable {
            let id: String
            let tags: [String]
            let meta: [String: String]
            let optional: Double?
        }
        let items = [
            Nested(id: "a", tags: ["x", "y"], meta: ["k": "v"], optional: 1.5),
            Nested(id: "b", tags: [], meta: [:], optional: nil)
        ]
        let data = try JSONEncoder().encode(items)
        let (values, dropped) = ResilientDecoding.array(Nested.self, from: data)
        #expect(values == items)
        #expect(dropped == 0)
    }

    // MARK: - Dictionaries

    @Test("A good dictionary decodes intact")
    func dictionaryRoundTrips() throws {
        let items = ["one": Item(id: "a", count: 1), "two": Item(id: "b", count: 2)]
        let data = try JSONEncoder().encode(items)
        let (values, dropped) = ResilientDecoding.dictionary(Item.self, from: data)
        #expect(values == items)
        #expect(dropped == 0)
    }

    @Test("One bad entry loses one key, not every key")
    func dictionarySurvivesOneBadEntry() throws {
        let json = """
        {"one":{"id":"a","count":1},"two":{"id":"b"},"three":{"id":"c","count":3}}
        """.data(using: .utf8) ?? Data()

        let naive = try? JSONDecoder().decode([String: Item].self, from: json)
        #expect(naive == nil)

        let (values, dropped) = ResilientDecoding.dictionary(Item.self, from: json)
        #expect(values.count == 2)
        #expect(dropped == 1)
        #expect(values["one"] != nil)
        #expect(values["three"] != nil)
        #expect(values["two"] == nil)
    }

    // MARK: - The real types

    /// ReaderDisplayPreferences now decodes every field optionally, so an entry
    /// missing fields degrades to defaults instead of taking the store with it.
    @Test("A preset missing display fields degrades to defaults")
    func readerPresetDegradesGracefully() throws {
        let json = """
        {"scriptA":{"speedTraining":{},"displayPreferences":{"theme":"void"}}}
        """.data(using: .utf8) ?? Data()
        let (values, _) = ResilientDecoding.dictionary(ReaderPreset.self, from: json)
        if let preset = values["scriptA"] {
            #expect(preset.displayPreferences.font == ReaderDisplayPreferences.standard.font)
            #expect(preset.displayPreferences.visual == ReaderDisplayPreferences.standard.visual)
            #expect(preset.mode == nil)
        }
    }

    @Test("A preset with an unknown enum value does not take the store with it")
    func unknownEnumIsIsolated() throws {
        let good = ReaderPreset(displayPreferences: .standard)
        let goodJSON = String(
            data: try JSONEncoder().encode(["good": good]),
            encoding: .utf8
        ) ?? "{}"
        let merged = goodJSON.replacingOccurrences(
            of: "{\"good\"",
            with: "{\"bad\":{\"speedTraining\":{},\"displayPreferences\":{\"font\":\"NOT_A_FONT\"}},\"good\""
        )
        let data = Data(merged.utf8)

        let (values, _) = ResilientDecoding.dictionary(ReaderPreset.self, from: data)
        // The good entry survives regardless of what happened to the bad one.
        #expect(values["good"] != nil)
    }
}
