//  CorpusKitReexport.swift
//  Ilumionate
//
//  TrancePhase and the corpus schema now live in the CorpusKit package.
//  Re-export so existing files referencing `TrancePhase` keep compiling
//  without per-file imports. `HypnosisMetadata.Phase` (typealias in
//  AudioFile.swift) continues to resolve to CorpusKit.TrancePhase.
@_exported import CorpusKit
