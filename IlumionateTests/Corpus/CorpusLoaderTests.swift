//  CorpusLoaderTests.swift
//  IlumionateTests
//
//  Loads corpus JSON from the repo-root `Corpus/<subdirectory>/` directory.
//
import Foundation
import Testing
@testable import Ilumionate

struct CorpusLoaderTests {

    @Test("Loads cases from the fixtures subdirectory")
    func loadsFixtures() throws {
        let cases = try CorpusLoader.load(subdirectory: "fixtures")
        #expect(cases.contains { $0.id == "loader-smoke" })
    }

    @Test("Returns empty for an empty/missing subdirectory")
    func emptyForMissing() throws {
        let cases = try CorpusLoader.load(subdirectory: "definitely-not-here")
        #expect(cases.isEmpty)
    }
}
