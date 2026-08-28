//  CableInboxFileKindTests.swift
//  IlumionateTests

import Foundation
import Testing
@testable import Ilumionate

struct CableInboxFileKindTests {

    @Test func classifiesAudioExtensions() {
        #expect(CableInboxFileKind(url: URL(filePath: "/tmp/Session.mp3")) == .audio)
        #expect(CableInboxFileKind(url: URL(filePath: "/tmp/Session.m4a")) == .audio)
    }

    @Test func classifiesReaderDocumentExtensions() {
        #expect(CableInboxFileKind(url: URL(filePath: "/tmp/Script.txt")) == .readerDocument)
        #expect(CableInboxFileKind(url: URL(filePath: "/tmp/Script.md")) == .readerDocument)
        #expect(CableInboxFileKind(url: URL(filePath: "/tmp/Book.pdf")) == .readerDocument)
        #expect(CableInboxFileKind(url: URL(filePath: "/tmp/Book.epub")) == .readerDocument)
    }

    @Test func classifiesAnythingElseAsUnrecognized() {
        #expect(CableInboxFileKind(url: URL(filePath: "/tmp/photo.heic")) == .unrecognized)
        #expect(CableInboxFileKind(url: URL(filePath: "/tmp/README")) == .unrecognized)
    }

    @Test func ignoresExtensionCasing() {
        #expect(CableInboxFileKind(url: URL(filePath: "/tmp/Book.PDF")) == .readerDocument)
        #expect(CableInboxFileKind(url: URL(filePath: "/tmp/Session.MP3")) == .audio)
    }
}
