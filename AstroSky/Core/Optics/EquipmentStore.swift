//
//  EquipmentStore.swift
//  AstroSky
//
//  The user's saved telescopes, eyepieces, active selection and mount type.
//  EquipmentLibrary is kept as a Codable struct for JSON persistence only.
//  EquipmentStore is the live @Observable model that AppState owns.
//

import Foundation
import Observation
import OSLog

private let logger = Logger(subsystem: "com.astrosky", category: "ephemeris")

struct EquipmentLibrary: Codable, Sendable {
    var telescopes: [Telescope]
    var eyepieces: [Eyepiece]
    var activeTelescopeID: UUID?
    var activeEyepieceID: UUID?
    var mountType: MountType

    static let empty = EquipmentLibrary(telescopes: [], eyepieces: [],
                                        activeTelescopeID: nil, activeEyepieceID: nil,
                                        mountType: .altAzimuth)
}

@MainActor
@Observable
final class EquipmentStore {
    private(set) var telescopes: [Telescope] = []
    private(set) var eyepieces: [Eyepiece] = []
    private(set) var activeTelescopeID: UUID?
    private(set) var activeEyepieceID: UUID?
    private(set) var mountType: MountType = .altAzimuth

    var activeTelescope: Telescope? { telescopes.first { $0.id == activeTelescopeID } }
    var activeEyepiece: Eyepiece? { eyepieces.first { $0.id == activeEyepieceID } }

    init() {
        guard let data = UserDefaults.standard.data(forKey: "equipmentLibrary") else { return }
        do {
            let library = try JSONDecoder().decode(EquipmentLibrary.self, from: data)
            telescopes = library.telescopes
            eyepieces = library.eyepieces
            activeTelescopeID = library.activeTelescopeID
            activeEyepieceID = library.activeEyepieceID
            mountType = library.mountType
        } catch {
            logger.error("Failed to decode equipment library: \(error.localizedDescription, privacy: .public)")
        }
    }

    func opticsResult(bortleClass: Int) -> OpticsResult? {
        guard let scope = activeTelescope, let eyepiece = activeEyepiece else { return nil }
        return TelescopeMath.result(scope: scope, eyepiece: eyepiece, bortleClass: bortleClass)
    }

    func addTelescope(_ scope: Telescope) {
        telescopes.append(scope)
        if activeTelescopeID == nil { activeTelescopeID = scope.id }
        persist()
    }

    func addEyepiece(_ eyepiece: Eyepiece) {
        eyepieces.append(eyepiece)
        if activeEyepieceID == nil { activeEyepieceID = eyepiece.id }
        persist()
    }

    func deleteTelescope(_ id: UUID) {
        telescopes.removeAll { $0.id == id }
        if activeTelescopeID == id { activeTelescopeID = telescopes.first?.id }
        persist()
    }

    func deleteEyepiece(_ id: UUID) {
        eyepieces.removeAll { $0.id == id }
        if activeEyepieceID == id { activeEyepieceID = eyepieces.first?.id }
        persist()
    }

    func setActiveTelescope(_ id: UUID) { activeTelescopeID = id; persist() }
    func setActiveEyepiece(_ id: UUID) { activeEyepieceID = id; persist() }
    func setMountType(_ mount: MountType) { mountType = mount; persist() }

    private func persist() {
        let library = EquipmentLibrary(telescopes: telescopes, eyepieces: eyepieces,
                                       activeTelescopeID: activeTelescopeID,
                                       activeEyepieceID: activeEyepieceID,
                                       mountType: mountType)
        if let data = try? JSONEncoder().encode(library) {
            UserDefaults.standard.set(data, forKey: "equipmentLibrary")
        }
    }
}
