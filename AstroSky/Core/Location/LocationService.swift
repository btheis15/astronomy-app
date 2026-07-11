//
//  LocationService.swift
//  AstroSky
//
//  CoreLocation wrapper: one coarse fix is all astronomy needs.
//

import CoreLocation
import Foundation
import MapKit
import Observation

@MainActor
@Observable
final class LocationService: NSObject, CLLocationManagerDelegate {
    /// Current observer; falls back to a sensible default until a fix
    /// arrives or the user sets a manual location.
    private(set) var observer: Observer = Observer.default
    private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
    private(set) var placeName: String?
    /// Compass heading accuracy in degrees (± value), or nil when heading is
    /// unavailable or uncalibrated. Small values mean a well-calibrated compass.
    private(set) var headingAccuracy: Double?
    /// Most recent true heading in degrees CW from North (0–360). Negative means invalid.
    private(set) var trueHeadingDegrees: Double = -1
    /// True when `observer` came from an actual fix or manual entry.
    private(set) var hasRealLocation = false
    /// When set, GPS updates are ignored.
    var manualLocationEnabled = false

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func requestLocation() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
            startHeadingIfAvailable()
        default:
            break
        }
    }

    private func startHeadingIfAvailable() {
        guard CLLocationManager.headingAvailable() else { return }
        manager.headingFilter = 1
        manager.startUpdatingHeading()
    }

    func setManualLocation(latitudeDegrees: Double, longitudeDegrees: Double, name: String? = nil) {
        manualLocationEnabled = true
        hasRealLocation = true
        observer = Observer(latitudeDegrees: latitudeDegrees, longitudeDegrees: longitudeDegrees)
        placeName = name ?? String(format: "%.2f°, %.2f°", latitudeDegrees, longitudeDegrees)
        Observer.persistLastKnown(observer)
    }

    func useAutomaticLocation() {
        manualLocationEnabled = false
        requestLocation()
    }

    // MARK: CLLocationManagerDelegate

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorizationStatus = status
            if status == .authorizedWhenInUse || status == .authorizedAlways {
                self.manager.requestLocation()
                self.startHeadingIfAvailable()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            guard !self.manualLocationEnabled else { return }
            self.observer = Observer(latitudeDegrees: location.coordinate.latitude,
                                     longitudeDegrees: location.coordinate.longitude,
                                     altitude: location.altitude)
            self.hasRealLocation = true
            Observer.persistLastKnown(self.observer)
            await self.reverseGeocode(location)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Keep the default/last observer; astronomy still works.
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        // Negative accuracy means the heading is invalid/uncalibrated.
        let accuracy = newHeading.headingAccuracy
        let trueHeading = newHeading.trueHeading
        Task { @MainActor in
            self.headingAccuracy = accuracy >= 0 ? accuracy : nil
            self.trueHeadingDegrees = trueHeading
        }
    }

    nonisolated func locationManagerShouldDisplayHeadingCalibration(_ manager: CLLocationManager) -> Bool {
        // Allow iOS to show the figure-8 calibration panel whenever needed.
        return true
    }

    private func reverseGeocode(_ location: CLLocation) async {
        guard let request = MKReverseGeocodingRequest(location: location),
              let mapItems = try? await request.mapItems,
              let item = mapItems.first else { return }
        placeName = item.addressRepresentations?.cityName
            ?? item.addressRepresentations?.cityWithContext
            ?? item.name
    }
}
