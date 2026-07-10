//
//  ObjectPhotoView.swift
//  AstroSky
//
//  Async, cached, downsampled photo of a celestial object. Fills its frame
//  (scaledToFill) over a dark placeholder and fades in when decoded off the
//  main thread — so pushing into a detail page never hitches on image decode.
//

import SwiftUI

struct ObjectPhotoView: View {
    let object: any CelestialObject
    var maxPixel: CGFloat = 700

    @State private var image: UIImage?
    @State private var didAttempt = false

    var body: some View {
        ZStack {
            Rectangle().fill(Color(red: 0.04, green: 0.05, blue: 0.10))
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if !didAttempt {
                ProgressView().tint(.secondary)
            } else {
                // Load finished with no usable image — a quiet fallback beats
                // a spinner that never stops.
                Image(systemName: "sparkles")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
            }
        }
        .task(id: object.id) {
            if image != nil { return }
            didAttempt = false
            guard let resource = ObjectImagery.resource(for: object) else { didAttempt = true; return }
            let loaded = await ObjectImagery.imageAsync(key: resource.key, subdir: resource.subdir,
                                                        maxPixel: maxPixel)
            withAnimation(.easeIn(duration: 0.25)) {
                image = loaded
                didAttempt = true
            }
        }
    }
}
