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
//
//  The whole collection is tried first. That path is a single decode and covers
//  every healthy load; the per-element salvage below only runs once something has
//  actually failed. An earlier version always went element-by-element, rebuilding
//  each one through a type-erased tree and re-serialising it — three passes per
//  record on every read, which showed up on device as the dominant cost of
//  loading a large audio library.

import Foundation

nonisolated enum ResilientDecoding {

    /// Decode an array, dropping only the elements that fail.
    ///
    /// Returns the survivors and how many were lost, so a caller can rewrite the
    /// pruned collection and tell the difference between "empty" and "unreadable".
    static func array<T: Decodable>(
        _ type: T.Type,
        from data: Data,
        decoder: JSONDecoder = JSONDecoder()
    ) -> (values: [T], dropped: Int) {
        // Everything readable is the overwhelmingly common case, and it costs a
        // single decode. Salvage only runs once something is actually wrong.
        if let values = try? decoder.decode([T].self, from: data) {
            return (values, 0)
        }

        guard let elements = try? JSONSerialization.jsonObject(
            with: data, options: [.fragmentsAllowed]
        ) as? [Any] else {
            return ([], 0)
        }

        var values: [T] = []
        var dropped = 0
        for element in elements {
            guard let value = decodeElement(type, element, using: decoder) else {
                dropped += 1
                continue
            }
            values.append(value)
        }
        return (values, dropped)
    }

    /// Decode a keyed collection, dropping only the entries that fail.
    static func dictionary<T: Decodable>(
        _ type: T.Type,
        from data: Data,
        decoder: JSONDecoder = JSONDecoder()
    ) -> (values: [String: T], dropped: Int) {
        if let values = try? decoder.decode([String: T].self, from: data) {
            return (values, 0)
        }

        guard let elements = try? JSONSerialization.jsonObject(
            with: data, options: [.fragmentsAllowed]
        ) as? [String: Any] else {
            return ([:], 0)
        }

        var values: [String: T] = [:]
        var dropped = 0
        for (key, element) in elements {
            guard let value = decodeElement(type, element, using: decoder) else {
                dropped += 1
                continue
            }
            values[key] = value
        }
        return (values, dropped)
    }

    /// Re-serialises one already-parsed element and decodes it alone.
    private static func decodeElement<T: Decodable>(
        _ type: T.Type,
        _ element: Any,
        using decoder: JSONDecoder
    ) -> T? {
        guard let elementData = try? JSONSerialization.data(
            withJSONObject: element, options: [.fragmentsAllowed]
        ) else {
            return nil
        }
        return try? decoder.decode(type, from: elementData)
    }
}
