//
//  ObjectPhotoView.swift
//  AstroSky
//
//  Async, cached, downsampled object photos:
//   • ObjectPhotoView — one image (fills its frame), fades in off-main.
//   • ObjectPhotoGallery — swipeable multi-source hero with per-photo credits.
//   • TelescopePhotoTile — a circular "what you'd see" crop, zoomed so the real
//     image matches the selected eyepiece's true field of view.
//

import SwiftUI

/// Loads one bundled photo (by key/subdir) off the main thread and fills its frame.
struct ObjectPhotoView: View {
    let key: String
    let subdir: String
    var maxPixel: CGFloat = 700

    @State private var image: UIImage?
    @State private var didAttempt = false

    var body: some View {
        ZStack {
            Rectangle().fill(Color(red: 0.04, green: 0.05, blue: 0.10))
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else if !didAttempt {
                ProgressView().tint(.secondary)
            } else {
                Image(systemName: "sparkles").font(.largeTitle).foregroundStyle(.secondary)
            }
        }
        .task(id: key) {
            if image != nil { return }
            didAttempt = false
            let loaded = await ObjectImagery.imageAsync(key: key, subdir: subdir, maxPixel: maxPixel)
            withAnimation(.easeIn(duration: 0.25)) {
                image = loaded
                didAttempt = true
            }
        }
    }
}

/// Swipeable hero: shows every bundled photo of an object, each with its credit.
struct ObjectPhotoGallery: View {
    let object: any CelestialObject
    var height: CGFloat = 230
    @State private var selection = 0

    var body: some View {
        let photos = ObjectImagery.photos(for: object)
        Group {
            if photos.count <= 1 {
                if let photo = photos.first { page(photo) }
            } else {
                TabView(selection: $selection) {
                    ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                        page(photo).tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
            }
        }
        .frame(height: height)
    }

    private func page(_ photo: ObjectPhoto) -> some View {
        ObjectPhotoView(key: photo.key, subdir: photo.subdir, maxPixel: 1000)
            .clipped()
            .overlay(alignment: .topLeading) {
                HStack(spacing: 5) {
                    Text(photo.caption).fontWeight(.semibold)
                    Text("·").foregroundStyle(.white.opacity(0.6))
                    Text(photo.credit).foregroundStyle(.white.opacity(0.85))
                }
                .font(.caption2)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(.black.opacity(0.5), in: Capsule())
                .foregroundStyle(.white)
                .padding(8)
            }
    }
}

/// A circular real-photo crop matched to the eyepiece's true field of view, so
/// it sits beside the simulated eyepiece view at the same angular scale.
struct TelescopePhotoTile: View {
    let photo: ObjectPhoto
    /// Crop-in factor (≥1): survey-cutout FOV ÷ eyepiece true FOV.
    let zoom: CGFloat

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Circle().fill(Color(red: 0.02, green: 0.02, blue: 0.05))
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .scaleEffect(zoom)
            } else {
                ProgressView().tint(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(1, contentMode: .fit)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(.gray.opacity(0.55), lineWidth: 2))
        .task(id: photo.key) {
            image = await ObjectImagery.imageAsync(key: photo.key, subdir: photo.subdir, maxPixel: 800)
        }
    }
}
