//
//  EyepieceSimulation.swift
//  AstroSky
//
//  Deterministic utilities shared by EyepiecePreviewView.
//

import Foundation

/// Small deterministic PRNG so each object renders identically every launch.
struct SeededRNG {
    var state: UInt64
    init(seed: UInt64) { state = seed == 0 ? 0x9E3779B97F4A7C15 : seed }
    mutating func next() -> Double {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Double(state >> 11) / Double(1 << 53)
    }
}

/// FNV-1a hash over the UTF-8 bytes of `string`.
func fnv1a(_ string: String) -> UInt64 {
    var hash: UInt64 = 1_469_598_103_934_665_603
    for byte in string.utf8 { hash = (hash ^ UInt64(byte)) &* 1_099_511_628_211 }
    return hash
}
