import Foundation

/// Where the sun and moon are, to about a degree: enough to tell golden hour, blue hour, night and
/// whether the moon is up. Low-precision formulas (Astronomical Almanac / Meeus), no network.
enum Astronomy {
    struct Sky: Equatable {
        /// Degrees above the horizon (negative below).
        var sunAltitude: Double
        var moonAltitude: Double
        /// 0 = new moon, 1 = full.
        var moonIllumination: Double
    }

    static func sky(at date: Date, latitude: Double, longitude: Double) -> Sky {
        let d = date.timeIntervalSince1970 / 86400 + 2440587.5 - 2451545.0   // days since J2000.0
        let obliquity = rad(23.439 - 0.0000004 * d)

        // Sun: mean anomaly and longitude, then the equation of centre.
        let g = rad(normalized(357.529 + 0.98560028 * d))
        let q = normalized(280.459 + 0.98564736 * d)
        let sunLongitude = rad(q + 1.915 * sin(g) + 0.020 * sin(2 * g))
        let sun = equatorial(longitude: sunLongitude, latitude: 0, obliquity: obliquity)

        // Moon: mean longitude, anomaly and argument of latitude with the largest terms.
        let l = normalized(218.316 + 13.176396 * d)
        let m = rad(normalized(134.963 + 13.064993 * d))
        let f = rad(normalized(93.272 + 13.229350 * d))
        let moonLongitude = rad(l + 6.289 * sin(m))
        let moonLatitude = rad(5.128 * sin(f))
        let moon = equatorial(longitude: moonLongitude, latitude: moonLatitude, obliquity: obliquity)

        let siderealTime = rad(normalized(280.46061837 + 360.98564736629 * d + longitude))
        let lat = rad(latitude)
        func altitude(_ body: (ra: Double, dec: Double)) -> Double {
            let hourAngle = siderealTime - body.ra
            return deg(asin(sin(lat) * sin(body.dec) + cos(lat) * cos(body.dec) * cos(hourAngle)))
        }
        // The sunlit fraction follows from the angle between them as seen from Earth.
        let elongation = acos(cos(moonLatitude) * cos(moonLongitude - sunLongitude))
        return Sky(sunAltitude: altitude(sun), moonAltitude: altitude(moon),
                   moonIllumination: (1 - cos(elongation)) / 2)
    }

    private static func equatorial(longitude: Double, latitude: Double, obliquity: Double) -> (ra: Double, dec: Double) {
        let ra = atan2(sin(longitude) * cos(obliquity) - tan(latitude) * sin(obliquity), cos(longitude))
        let dec = asin(sin(latitude) * cos(obliquity) + cos(latitude) * sin(obliquity) * sin(longitude))
        return (ra, dec)
    }

    private static func normalized(_ degrees: Double) -> Double {
        let r = degrees.truncatingRemainder(dividingBy: 360)
        return r < 0 ? r + 360 : r
    }

    private static func rad(_ degrees: Double) -> Double { degrees * .pi / 180 }
    private static func deg(_ radians: Double) -> Double { radians * 180 / .pi }
}
