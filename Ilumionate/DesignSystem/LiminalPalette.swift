//
//  LiminalPalette.swift
//  Ilumionate
//
//  Single source of truth for the Liminal identity's raw colors.
//  Semantic tokens in TranceDesignSystem.swift resolve to these.
//

import SwiftUI

/// Raw Liminal hex strings. Kept as strings so they can be unit-tested
/// without constructing UIColors on a background thread.
enum LiminalHex {
    // Void backgrounds
    static let voidDeep     = "03040C"
    static let voidPrimary  = "070D1F"
    static let voidElevated = "0D1428"

    // Aurora accents
    static let auroraTeal   = "7EE8D8"
    static let auroraBlue   = "7C9EFF"
    static let auroraViolet = "B07DC8"
    static let auroraPink   = "E87CB8"

    // Text
    static let textBright   = "E6EEFF"
    static let textDim      = "8FA3CC"
    static let textGhost    = "5A6A8A"
}

extension Color {
    static let voidDeep     = Color(hex: LiminalHex.voidDeep)
    static let voidPrimary  = Color(hex: LiminalHex.voidPrimary)
    static let voidElevated = Color(hex: LiminalHex.voidElevated)
    static let auroraTeal   = Color(hex: LiminalHex.auroraTeal)
    static let auroraBlue   = Color(hex: LiminalHex.auroraBlue)
    static let auroraViolet = Color(hex: LiminalHex.auroraViolet)
    static let auroraPink   = Color(hex: LiminalHex.auroraPink)
    static let textBright   = Color(hex: LiminalHex.textBright)
    static let textDim      = Color(hex: LiminalHex.textDim)
    static let textGhost    = Color(hex: LiminalHex.textGhost)
}

extension ShapeStyle where Self == Color {
    static var voidDeep: Color     { .voidDeep }
    static var voidPrimary: Color  { .voidPrimary }
    static var voidElevated: Color { .voidElevated }
    static var auroraTeal: Color   { .auroraTeal }
    static var auroraBlue: Color   { .auroraBlue }
    static var auroraViolet: Color { .auroraViolet }
    static var auroraPink: Color   { .auroraPink }
    static var textBright: Color   { .textBright }
    static var textDim: Color      { .textDim }
    static var textGhost: Color    { .textGhost }
}
