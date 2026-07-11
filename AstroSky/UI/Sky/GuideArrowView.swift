//
//  GuideArrowView.swift
//  AstroSky
//

import SwiftUI

struct GuideArrowView: View {
    let guide: GuideReadout
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            if guide.isOnTarget {
                Label("On target: \(guide.targetName)", systemImage: "scope")
                    .font(.subheadline.weight(.semibold))
            } else {
                Image(systemName: "arrow.right")
                    .font(.system(size: 34, weight: .bold))
                    // Screen angle: 0 = right, π/2 = up; SwiftUI rotation is
                    // clockwise, so negate.
                    .rotationEffect(.radians(-guide.arrowAngle))
                Text(guide.isBelowHorizon
                    ? "\(guide.targetName) is below the horizon"
                    : "Turn toward \(guide.targetName)")
                    .font(.footnote)
            }
            Button("Stop guiding", action: onDismiss)
                .font(.caption)
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .foregroundStyle(guide.isOnTarget ? .green : .primary)
    }
}
