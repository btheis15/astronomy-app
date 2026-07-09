//
//  ObservationLogEntry.swift
//  AstroSky
//
//  A persisted observing-log entry (SwiftData). Captures what was seen, when,
//  under what conditions, and from where.
//

import Foundation
import SwiftData

@Model
final class ObservationLogEntry {
    var objectID: String
    var objectName: String
    var date: Date
    var notes: String
    /// Seeing/quality rating 1–5 (0 = unrated).
    var seeingRating: Int
    var latitude: Double
    var longitude: Double
    /// True when the object is a Messier object (for the "seen" progress ring).
    var isMessier: Bool

    init(objectID: String, objectName: String, date: Date = Date(),
         notes: String = "", seeingRating: Int = 0,
         latitude: Double = 0, longitude: Double = 0, isMessier: Bool = false) {
        self.objectID = objectID
        self.objectName = objectName
        self.date = date
        self.notes = notes
        self.seeingRating = seeingRating
        self.latitude = latitude
        self.longitude = longitude
        self.isMessier = isMessier
    }
}
