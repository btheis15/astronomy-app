//
//  PassNotifications.swift
//  AstroSky
//
//  Local notifications ~10 minutes before a favorited satellite makes a
//  visible pass. The request-building logic is pure (and unit-tested); the
//  scheduler wraps UNUserNotificationCenter.
//

import Foundation
import UserNotifications

enum PassNotifications {
    /// Minutes-before-start that we alert.
    static let leadTime: TimeInterval = 10 * 60
    /// Cap on pending notifications (system-friendly).
    static let maxPending = 20

    /// Build notification requests for the visible passes still in the future,
    /// firing `leadTime` before each starts, capped and time-ordered.
    static func requests(for passes: [SatellitePass], now: Date) -> [UNNotificationRequest] {
        let upcoming = passes
            .filter { $0.isVisible }
            .compactMap { pass -> (Date, UNNotificationRequest)? in
                let fireDate = pass.start.addingTimeInterval(-leadTime)
                guard fireDate > now else { return nil }
                let interval = fireDate.timeIntervalSince(now)

                let content = UNMutableNotificationContent()
                content.title = "\(pass.satelliteName) pass in 10 min"
                var body = "Peaks at \(Int((pass.maxAltitude * 180 / .pi).rounded()))° altitude."
                if let magnitude = pass.peakMagnitude {
                    body += String(format: " ~mag %.1f.", magnitude)
                }
                content.body = body
                content.sound = .default

                let trigger = UNTimeIntervalNotificationTrigger(
                    timeInterval: max(1, interval), repeats: false)
                let request = UNNotificationRequest(identifier: "pass-\(pass.id)",
                                                    content: content, trigger: trigger)
                return (fireDate, request)
            }
            .sorted { $0.0 < $1.0 }
            .prefix(maxPending)
            .map(\.1)
        return Array(upcoming)
    }
}

@MainActor
final class PassNotificationScheduler {
    private let center = UNUserNotificationCenter.current()

    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    /// Replace all pending pass notifications with a fresh set.
    func reschedule(passes: [SatellitePass]) async {
        center.removeAllPendingNotificationRequests()
        for request in PassNotifications.requests(for: passes, now: Date()) {
            try? await center.add(request)
        }
    }

    func cancelAll() {
        center.removeAllPendingNotificationRequests()
    }
}
