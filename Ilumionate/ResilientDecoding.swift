//  ResilientDecoding.swift
//  Ilumionate
//
//  Decoding a stored collection element-by-element instead of all-or-nothing.
//
//  Every store in the app persists a whole collection as one JSON blob and
//  reloads it with `try? JSONDecoder().decode([...].self)`. That reads well
//  until a single element fails — a field added without a default, a value
//  written by a newer build, one corrupted entry — at which point the decode
//  throws, `try?` swallows it, and the fallback replaces the ENTIRE collection
//  with an empty one. One bad audio file silently empties the whole library.
//
//  These helpers decode each element separately so a bad entry costs one entry.

import Foundation

enum ResilientDecoding {

    /// Decode an array, dropping only the elements that fail.
    ///
    /// Returns the survivors and how many were lost, so a caller can rewrite the
    /// pruned collection and tell the difference between "empty" and "unreadable".
    static func array<T: Decodable>(
        _ type: T.Type,
        from data: Data,
        decoder: JSONDecoder = JSONDecoder()
    ) -> (values: [T], dropped: Int) {
        // Decode to a container of raw JSON first: one element's failure must not
        // abort its siblings.
        guard let raw = try? decoder.decode([RawJSON].self, from: data) else {
            return ([], 0)
        }
        var values: [T] = []
        var dropped = 0
        for element in raw {
            if let value = element.decode(type, using: decoder) {
                values.append(value)
            } else {
                dropped += 1
            }
        }
        return (values, dropped)
    }

    /// Decode a keyed collection, dropping only the entries that fail.
    static func dictionary<T: Decodable>(
        _ type: T.Type,
        from data: Data,
        decoder: JSONDecoder = JSONDecoder()
    ) -> (values: [String: T], dropped: Int) {
        guard let raw = try? decoder.decode([String: RawJSON].self, from: data) else {
            return ([:], 0)
        }
        var values: [String: T] = [:]
        var dropped = 0
        for (key, element) in raw {
            if let value = element.decode(type, using: decoder) {
                values[key] = value
            } else {
                dropped += 1
            }
        }
        return (values, dropped)
    }
}

/// One element captured as re-encodable JSON, so it can be decoded on its own.
private struct RawJSON: Decodable {
    let data: Data?

    init(from decoder: Decoder) throws {
        // `JSONSerialization` round-trips an arbitrary element without needing to
        // know its shape. A fragment that cannot be re-serialised is treated as
        // undecodable rather than throwing out the collection.
        let container = try decoder.singleValueContainer()
        if let object = try? container.decode(AnyCodable.self) {
            data = try? JSONSerialization.data(
                withJSONObject: object.value,
                options: [.fragmentsAllowed]
            )
        } else {
            data = nil
        }
    }

    func decode<T: Decodable>(_ type: T.Type, using decoder: JSONDecoder) -> T? {
        guard let data else { return nil }
        return try? decoder.decode(type, from: data)
    }
}

/// Minimal type-erased JSON value, used only to re-serialise one element.
private struct AnyCodable: Decodable {
    let value: Any

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let v = try? container.decode([String: AnyCodable].self) {
            value = v.mapValues(\.value)
        } else if let v = try? container.decode([AnyCodable].self) {
            value = v.map(\.value)
        } else if let v = try? container.decode(Bool.self) {
            value = v
        } else if let v = try? container.decode(Int.self) {
            value = v
        } else if let v = try? container.decode(Double.self) {
            value = v
        } else if let v = try? container.decode(String.self) {
            value = v
        } else if container.decodeNil() {
            value = NSNull()
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported JSON value"
            )
        }
    }
}
