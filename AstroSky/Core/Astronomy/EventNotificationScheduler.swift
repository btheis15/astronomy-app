//
//  EventNotificationScheduler.swift
//  AstroSky
//
//  Schedules a UNUserNotificationCenter notification the evening before each
//  upcoming sky event (conjunction, eclipse, meteor shower peak, moon phase).
//  Uses the "skyEvent." identifier prefix so it coexists safely with
//  PassNotificationScheduler's "pass-" notifications.
//

import Foundation
import UserNotifications

@MainActor
final class EventNotificationScheduler {
    private let center = UNUserNotificationCenter.current()
    private let identifierPrefix = "skyEvent."
    private let categoryID = "skyEvent"

    /// Request authorization if not yet determined. Returns whether granted.
    func requestAuthorization() async -> Bool {
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .authorized { return true }
        if settings.authorizationStatus == .notDetermined {
            return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        }
        return false
    }

    /// Schedule (or cancel + reschedule) notifications for upcoming events.
    /// Fires at 8 PM local time the evening before each event.
    func reschedule(events: [AstroEvent]) async {
        // Cancel only our own pending notifications (leave pass notifications intact).
        let pending = await center.pendingNotificationRequests()
        let idsToRemove = pending
            .filter { $0.identifier.hasPrefix(identifierPrefix) }
            .map(\.identifier)
        center.removePendingNotificationRequests(withIdentifiers: idsToRemove)

        let calendar = Calendar.current
        for event in events {
            // Fire at 8 PM local time the evening before the event.
            guard let notifyDay = calendar.date(byAdding: .day, value: -1, to: event.date),
                  let fireDate = calendar.date(bySettingHour: 20, minute: 0, second: 0, of: notifyDay),
                  fireDate > Date() else { continue }

            let content = UNMutableNotificationContent()
            content.title = event.title
            content.body = "Tomorrow: \(event.detail)"
            content.sound = .default
            content.categoryIdentifier = categoryID

            let comps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            let identifier = "\(identifierPrefix)\(event.id)"
            let request = UNNotificationRequest(identifier: identifier,
                                                content: content,
                                                trigger: trigger)
            try? await center.add(request)
        }
    }

    /// Cancel all sky-event notifications (leaves pass notifications intact).
    func cancelAll() async {
        let pending = await center.pendingNotificationRequests()
        let idsToRemove = pending
            .filter { $0.identifier.hasPrefix(identifierPrefix) }
            .map(\.identifier)
        center.removePendingNotificationRequests(withIdentifiers: idsToRemove)
    }
}
