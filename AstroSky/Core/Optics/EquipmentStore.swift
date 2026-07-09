//
//  EquipmentStore.swift
//  AstroSky
//
//  The user's saved telescopes, eyepieces, active selection and mount type,
//  persisted as JSON in UserDefaults (see AppState.equipment).
//

import Foundation

struct EquipmentLibrary: Codable, Sendable {
    var telescopes: [Telescope]
    var eyepieces: [Eyepiece]
    var activeTelescopeID: UUID?
    var activeEyepieceID: UUID?
    var mountType: MountType

    static let empty = EquipmentLibrary(telescopes: [], eyepieces: [],
                                        activeTelescopeID: nil, activeEyepieceID: nil,
                                        mountType: .altAzimuth)

    var activeTelescope: Telescope? { telescopes.first { $0.id == activeTelescopeID } }
    var activeEyepiece: Eyepiece? { eyepieces.first { $0.id == activeEyepieceID } }

    /// Optics for the active pair, or nil if either is unset.
    func opticsResult(bortleClass: Int) -> OpticsResult? {
        guard let scope = activeTelescope, let eyepiece = activeEyepiece else { return nil }
        return TelescopeMath.result(scope: scope, eyepiece: eyepiece, bortleClass: bortleClass)
    }
}
