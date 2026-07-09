//
//  LocationService.swift
//  AstroSky
//
//  CoreLocation wrapper: one coarse fix is all astronomy needs.
//

import CoreLocation
import Foundation
import Observation

@MainActor
@Observable
final class LocationService: NSObject, CLLocationManagerDelegate {
    /// Current observer; falls back to a sensible default until a fix
    /// arrives or the user sets a manual location.
    private(set) var observer: Observer = Observer.default
    private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
    private(set) var placeName: String?
    /// True when `observer` came from an actual fix or manual entry.
    private(set) var hasRealLocation = false
    /// When set, GPS updates are ignored.
    var manualLocationEnabled = false

    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()

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
        default:
            break
        }
    }

    func setManualLocation(latitudeDegrees: Double, longitudeDegrees: Double, name: String? = nil) {
        manualLocationEnabled = true
        hasRealLocation = true
        observer = Observer(latitudeDegrees: latitudeDegrees, longitudeDegrees: longitudeDegrees)
        placeName = name ?? String(format: "%.2f°, %.2f°", latitudeDegrees, longitudeDegrees)
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
            self.reverseGeocode(location)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Keep the default/last observer; astronomy still works.
    }

    private func reverseGeocode(_ location: CLLocation) {
        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, _ in
            guard let self, let placemark = placemarks?.first else { return }
            Task { @MainActor in
                self.placeName = placemark.locality ?? placemark.administrativeArea ?? placemark.name
            }
        }
    }
}
