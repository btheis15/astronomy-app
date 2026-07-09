//
//  SGP4.swift
//  AstroSky
//
//  Near-earth SGP4 orbital propagator, ported from the reference
//  implementation in Vallado, Crawford, Hujsak & Kelso,
//  "Revisiting Spacetrack Report #3" (AIAA 2006-6753).
//
//  Every satellite this app tracks (ISS, Hubble, Starlink, the Celestrak
//  "visual" group) is a near-earth object (period < 225 min), so the
//  deep-space (SDP4) branch is intentionally omitted; TLEs for deep-space
//  objects are rejected at init.
//
//  Output position/velocity are in the TEME (True Equator, Mean Equinox)
//  frame in kilometers and km/s.
//

import Foundation
import simd

struct SGP4Error: Error {
    let message: String
}

struct SGP4 {
    // WGS-72 gravitational constants (the constants TLEs are generated with).
    private static let earthRadiusKm = 6378.135
    private static let mu = 398600.8                       // km^3/s^2
    private static let xke = 60.0 / (earthRadiusKm * earthRadiusKm * earthRadiusKm / mu).squareRoot()
    private static let j2 = 0.001082616
    private static let j3 = -0.00000253881
    private static let j4 = -0.00000165597
    private static let j3oj2 = j3 / j2

    let tle: TLE

    // Initialized terms (Vallado's sgp4init).
    private let noUnkozai: Double
    private let a0: Double
    private let isSimple: Bool
    private let cc1: Double
    private let cc4: Double
    private let cc5: Double
    private let d2: Double
    private let d3: Double
    private let d4: Double
    private let delmo: Double
    private let eta: Double
    private let argpdot: Double
    private let omgcof: Double
    private let sinmao: Double
    private let t2cof: Double
    private let t3cof: Double
    private let t4cof: Double
    private let t5cof: Double
    private let x1mth2: Double
    private let x7thm1: Double
    private let mdot: Double
    private let nodedot: Double
    private let xlcof: Double
    private let xmcof: Double
    private let nodecf: Double
    private let aycof: Double
    private let con41: Double
    private let cosio: Double
    private let sinio: Double

    struct State {
        /// TEME position in kilometers.
        var position: SIMD3<Double>
        /// TEME velocity in km/s.
        var velocity: SIMD3<Double>
    }

    init(tle: TLE) throws {
        guard tle.isNearEarth else {
            throw SGP4Error(message: "\(tle.name): deep-space orbits are not supported")
        }
        guard tle.eccentricity < 1.0, tle.eccentricity >= 0 else {
            throw SGP4Error(message: "\(tle.name): invalid eccentricity")
        }
        self.tle = tle

        let ecco = tle.eccentricity
        let inclo = tle.inclination
        let no = tle.meanMotionRadPerMin

        let cosio = cos(inclo)
        let sinio = sin(inclo)
        let theta2 = cosio * cosio
        let x3thm1 = 3.0 * theta2 - 1.0
        let eosq = ecco * ecco
        let betao2 = 1.0 - eosq
        let betao = betao2.squareRoot()

        // Un-Kozai the mean motion.
        let ak = pow(Self.xke / no, 2.0 / 3.0)
        let d1 = 0.75 * Self.j2 * x3thm1 / (betao * betao2)
        var del = d1 / (ak * ak)
        let adel = ak * (1.0 - del * del - del * (1.0 / 3.0 + 134.0 * del * del * del / 81.0))
        del = d1 / (adel * adel)
        let noUnkozai = no / (1.0 + del)

        let ao = pow(Self.xke / noUnkozai, 2.0 / 3.0)
        let po = ao * betao2
        let con42 = 1.0 - 5.0 * theta2
        let con41 = -con42 - 2.0 * theta2   // == 3θ² − 1
        let posq = po * po
        let rp = ao * (1.0 - ecco)

        // Density function constants; s4 & qzms24 depend on perigee height.
        let perigeeKm = (rp - 1.0) * Self.earthRadiusKm
        var sfour = 78.0
        var qzms24 = pow((120.0 - 78.0) / Self.earthRadiusKm, 4.0)
        if perigeeKm < 156.0 {
            sfour = perigeeKm - 78.0
            if perigeeKm < 98.0 { sfour = 20.0 }
            qzms24 = pow((120.0 - sfour) / Self.earthRadiusKm, 4.0)
            sfour = sfour / Self.earthRadiusKm + 1.0
        } else {
            sfour = sfour / Self.earthRadiusKm + 1.0
        }
        let pinvsq = 1.0 / posq

        let tsi = 1.0 / (ao - sfour)
        let eta = ao * ecco * tsi
        let etasq = eta * eta
        let eeta = ecco * eta
        let psisq = abs(1.0 - etasq)
        let coef = qzms24 * pow(tsi, 4.0)
        let coef1 = coef / pow(psisq, 3.5)
        let cc2 = coef1 * noUnkozai
            * (ao * (1.0 + 1.5 * etasq + eeta * (4.0 + etasq))
                + 0.375 * Self.j2 * tsi / psisq * con41
                * (8.0 + 3.0 * etasq * (8.0 + etasq)))
        let cc1 = tle.bstar * cc2
        var cc3 = 0.0
        if ecco > 1.0e-4 {
            cc3 = -2.0 * coef * tsi * Self.j3oj2 * noUnkozai * sinio / ecco
        }
        let x1mth2 = 1.0 - theta2
        let cc4 = 2.0 * noUnkozai * coef1 * ao * betao2
            * (eta * (2.0 + 0.5 * etasq) + ecco * (0.5 + 2.0 * etasq)
                - Self.j2 * tsi / (ao * psisq)
                * (-3.0 * con41 * (1.0 - 2.0 * eeta + etasq * (1.5 - 0.5 * eeta))
                    + 0.75 * x1mth2 * (2.0 * etasq - eeta * (1.0 + etasq))
                    * cos(2.0 * tle.argumentOfPerigee)))
        let cc5 = 2.0 * coef1 * ao * betao2
            * (1.0 + 2.75 * (etasq + eeta) + eeta * etasq)

        let cosio4 = theta2 * theta2
        let temp1 = 1.5 * Self.j2 * pinvsq * noUnkozai
        let temp2 = 0.5 * temp1 * Self.j2 * pinvsq
        let temp3 = -0.46875 * Self.j4 * pinvsq * pinvsq * noUnkozai
        let mdot = noUnkozai + 0.5 * temp1 * betao * con41
            + 0.0625 * temp2 * betao * (13.0 - 78.0 * theta2 + 137.0 * cosio4)
        let argpdot = -0.5 * temp1 * con42
            + 0.0625 * temp2 * (7.0 - 114.0 * theta2 + 395.0 * cosio4)
            + temp3 * (3.0 - 36.0 * theta2 + 49.0 * cosio4)
        let xhdot1 = -temp1 * cosio
        let nodedot = xhdot1
            + (0.5 * temp2 * (4.0 - 19.0 * theta2)
                + 2.0 * temp3 * (3.0 - 7.0 * theta2)) * cosio

        let omgcof = tle.bstar * cc3 * cos(tle.argumentOfPerigee)
        var xmcof = 0.0
        if ecco > 1.0e-4 {
            xmcof = -(2.0 / 3.0) * coef * tle.bstar / eeta
        }
        let nodecf = 3.5 * betao2 * xhdot1 * cc1
        let t2cof = 1.5 * cc1
        // Avoid division by zero for inclination near 180°.
        let xlcof: Double
        if abs(cosio + 1.0) > 1.5e-12 {
            xlcof = -0.25 * Self.j3oj2 * sinio * (3.0 + 5.0 * cosio) / (1.0 + cosio)
        } else {
            xlcof = -0.25 * Self.j3oj2 * sinio * (3.0 + 5.0 * cosio) / 1.5e-12
        }
        let aycof = -0.5 * Self.j3oj2 * sinio
        let delmo = pow(1.0 + eta * cos(tle.meanAnomaly), 3.0)
        let sinmao = sin(tle.meanAnomaly)
        let x7thm1 = 7.0 * theta2 - 1.0

        // Non-simple propagation terms (skipped for very low perigee).
        let isSimple = (rp < (220.0 / Self.earthRadiusKm + 1.0))
        var d2 = 0.0, d3 = 0.0, d4 = 0.0
        var t3cof = 0.0, t4cof = 0.0, t5cof = 0.0
        if !isSimple {
            let cc1sq = cc1 * cc1
            d2 = 4.0 * ao * tsi * cc1sq
            let temp = d2 * tsi * cc1 / 3.0
            d3 = (17.0 * ao + sfour) * temp
            d4 = 0.5 * temp * ao * tsi * (221.0 * ao + 31.0 * sfour) * cc1
            t3cof = d2 + 2.0 * cc1sq
            t4cof = 0.25 * (3.0 * d3 + cc1 * (12.0 * d2 + 10.0 * cc1sq))
            t5cof = 0.2 * (3.0 * d4 + 12.0 * cc1 * d3 + 6.0 * d2 * d2
                + 15.0 * cc1sq * (2.0 * d2 + cc1sq))
        }

        self.noUnkozai = noUnkozai
        self.a0 = ao
        self.isSimple = isSimple
        self.cc1 = cc1
        self.cc4 = cc4
        self.cc5 = cc5
        self.d2 = d2
        self.d3 = d3
        self.d4 = d4
        self.delmo = delmo
        self.eta = eta
        self.argpdot = argpdot
        self.omgcof = omgcof
        self.sinmao = sinmao
        self.t2cof = t2cof
        self.t3cof = t3cof
        self.t4cof = t4cof
        self.t5cof = t5cof
        self.x1mth2 = x1mth2
        self.x7thm1 = x7thm1
        self.mdot = mdot
        self.nodedot = nodedot
        self.xlcof = xlcof
        self.xmcof = xmcof
        self.nodecf = nodecf
        self.aycof = aycof
        self.con41 = con41
        self.cosio = cosio
        self.sinio = sinio
    }

    /// Propagate to `minutesSinceEpoch` minutes after the TLE epoch.
    func propagate(minutesSinceEpoch t: Double) throws -> State {
        let ecco = tle.eccentricity
        let inclo = tle.inclination

        // Secular gravity and atmospheric drag.
        let xmdf = tle.meanAnomaly + mdot * t
        let argpdf = tle.argumentOfPerigee + argpdot * t
        let nodedf = tle.raan + nodedot * t
        var argpm = argpdf
        var mm = xmdf
        let t2 = t * t
        var nodem = nodedf + nodecf * t2
        var tempa = 1.0 - cc1 * t
        var tempe = tle.bstar * cc4 * t
        var templ = t2cof * t2

        if !isSimple {
            let delomg = omgcof * t
            let delm = xmcof * (pow(1.0 + eta * cos(xmdf), 3.0) - delmo)
            let temp = delomg + delm
            mm = xmdf + temp
            argpm = argpdf - temp
            let t3 = t2 * t
            let t4 = t3 * t
            tempa -= d2 * t2 + d3 * t3 + d4 * t4
            tempe += tle.bstar * cc5 * (sin(mm) - sinmao)
            templ += t3cof * t3 + t4 * (t4cof + t * t5cof)
        }

        let nm = noUnkozai
        let am = pow(Self.xke / nm, 2.0 / 3.0) * tempa * tempa
        let nmUpdated = Self.xke / pow(am, 1.5)
        var em = ecco - tempe

        if em >= 1.0 || em < -0.001 || am < 0.95 {
            throw SGP4Error(message: "\(tle.name): orbit decayed")
        }
        if em < 1.0e-6 { em = 1.0e-6 }

        mm += noUnkozai * templ
        var xlm = mm + argpm + nodem
        nodem = AstroMath.normalizedRadians(nodem)
        argpm = AstroMath.normalizedRadians(argpm)
        xlm = AstroMath.normalizedRadians(xlm)
        mm = AstroMath.normalizedRadians(xlm - argpm - nodem)

        // Long-period periodics.
        let sinim = sin(inclo)
        let cosim = cos(inclo)
        let axnl = em * cos(argpm)
        var temp = 1.0 / (am * (1.0 - em * em))
        let aynl = em * sin(argpm) + temp * aycof
        let xl = mm + argpm + nodem + temp * xlcof * axnl

        // Kepler's equation for (xl - nodem).
        let u = AstroMath.normalizedRadians(xl - nodem)
        var eo1 = u
        var tem5 = 9999.9
        var iteration = 0
        var sineo1 = sin(eo1)
        var coseo1 = cos(eo1)
        while abs(tem5) >= 1.0e-12 && iteration < 10 {
            sineo1 = sin(eo1)
            coseo1 = cos(eo1)
            tem5 = 1.0 - coseo1 * axnl - sineo1 * aynl
            tem5 = (u - aynl * coseo1 + axnl * sineo1 - eo1) / tem5
            if abs(tem5) >= 0.95 {
                tem5 = tem5 > 0 ? 0.95 : -0.95
            }
            eo1 += tem5
            iteration += 1
        }

        // Short-period periodics.
        let ecose = axnl * coseo1 + aynl * sineo1
        let esine = axnl * sineo1 - aynl * coseo1
        let el2 = axnl * axnl + aynl * aynl
        let pl = am * (1.0 - el2)
        guard pl > 0 else {
            throw SGP4Error(message: "\(tle.name): semi-latus rectum < 0")
        }

        let rl = am * (1.0 - ecose)
        let rdotl = am.squareRoot() * esine / rl
        let rvdotl = pl.squareRoot() / rl
        let betal = (1.0 - el2).squareRoot()
        temp = esine / (1.0 + betal)
        let sinu = am / rl * (sineo1 - aynl - axnl * temp)
        let cosu = am / rl * (coseo1 - axnl + aynl * temp)
        var su = atan2(sinu, cosu)
        let sin2u = (cosu + cosu) * sinu
        let cos2u = 1.0 - 2.0 * sinu * sinu
        temp = 1.0 / pl
        let temp1 = 0.5 * Self.j2 * temp
        let temp2 = temp1 * temp

        let mrt = rl * (1.0 - 1.5 * temp2 * betal * con41) + 0.5 * temp1 * x1mth2 * cos2u
        su -= 0.25 * temp2 * x7thm1 * sin2u
        let xnode = nodem + 1.5 * temp2 * cosim * sin2u
        let xinc = inclo + 1.5 * temp2 * cosim * sinim * cos2u
        let mvt = rdotl - nmUpdated * temp1 * x1mth2 * sin2u / Self.xke
        let rvdot = rvdotl + nmUpdated * temp1 * (x1mth2 * cos2u + 1.5 * con41) / Self.xke

        // Orientation vectors.
        let sinsu = sin(su)
        let cossu = cos(su)
        let snod = sin(xnode)
        let cnod = cos(xnode)
        let sini = sin(xinc)
        let cosi = cos(xinc)
        let xmx = -snod * cosi
        let xmy = cnod * cosi
        let ux = xmx * sinsu + cnod * cossu
        let uy = xmy * sinsu + snod * cossu
        let uz = sini * sinsu
        let vx = xmx * cossu - cnod * sinsu
        let vy = xmy * cossu - snod * sinsu
        let vz = sini * cossu

        // Position (km) and velocity (km/s).
        let vkmpersec = Self.earthRadiusKm * Self.xke / 60.0
        let position = SIMD3(mrt * ux, mrt * uy, mrt * uz) * Self.earthRadiusKm
        let velocity = SIMD3(mvt * ux + rvdot * vx,
                             mvt * uy + rvdot * vy,
                             mvt * uz + rvdot * vz) * vkmpersec

        guard mrt >= 1.0 else {
            throw SGP4Error(message: "\(tle.name): satellite decayed below Earth's surface")
        }
        return State(position: position, velocity: velocity)
    }

    /// Propagate to an absolute Julian Date (UTC).
    func propagate(julianDate jd: Double) throws -> State {
        try propagate(minutesSinceEpoch: (jd - tle.epochJD) * 1440.0)
    }
}
