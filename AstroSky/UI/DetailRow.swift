//
//  DetailRow.swift
//  AstroSky
//
import SwiftUI

/// A label-value row used in detail views: secondary label on the left,
/// monospaced value on the right.
struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).monospacedDigit()
        }
        .font(.subheadline)
    }
}
