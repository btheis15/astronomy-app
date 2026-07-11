//
//  PhotoCapture.swift
//  AstroSky
//

import SwiftUI

struct CapturedPhoto: Identifiable {
    let id = UUID()
    let image: UIImage
}

/// UIKit share-sheet bridge.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
