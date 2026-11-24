package com.apexcommerce.shutterlink.camera

import kotlin.math.PI
import kotlin.math.acos
import kotlin.math.asin
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.sin
import kotlin.math.tan

/**
 * Where the sun and moon are, to about a degree: enough to tell golden hour, blue hour, night and whether
 * the moon is up. Low-precision formulas (Astronomical Almanac / Meeus), no network. Port of Astronomy.swift.
 */
object Astronomy {
    data class Sky(
        /** Degrees above the horizon (negative below). */
        val sunAltitude: Double,
        val moonAltitude: Double,
        /** 0 = new moon, 1 = full. */
        val moonIllumination: Double,
    )

    fun sky(timeMillis: Long, latitude: Double, longitude: Double): Sky {
        val d = timeMillis / 86_400_000.0 + 2440587.5 - 2451545.0   // days since J2000.0
        val obliquity = rad(23.439 - 0.0000004 * d)

        // Sun: mean anomaly and longitude, then the equation of centre.
        val g = rad(normalized(357.529 + 0.98560028 * d))
        val q = normalized(280.459 + 0.98564736 * d)
        val sunLongitude = rad(q + 1.915 * sin(g) + 0.020 * sin(2 * g))
        val sun = equatorial(sunLongitude, 0.0, obliquity)

        // Moon: mean longitude, anomaly and argument of latitude with the largest terms.
        val l = normalized(218.316 + 13.176396 * d)
        val m = rad(normalized(134.963 + 13.064993 * d))
        val f = rad(normalized(93.272 + 13.229350 * d))
        val moonLongitude = rad(l + 6.289 * sin(m))
        val moonLatitude = rad(5.128 * sin(f))
        val moon = equatorial(moonLongitude, moonLatitude, obliquity)

        val siderealTime = rad(normalized(280.46061837 + 360.98564736629 * d + longitude))
        val lat = rad(latitude)
        fun altitude(body: Pair<Double, Double>): Double {
            val hourAngle = siderealTime - body.first
            return deg(asin(sin(lat) * sin(body.second) + cos(lat) * cos(body.second) * cos(hourAngle)))
        }
        // The sunlit fraction follows from the angle between them as seen from Earth.
        val elongation = acos(cos(moonLatitude) * cos(moonLongitude - sunLongitude))
        return Sky(altitude(sun), altitude(moon), (1 - cos(elongation)) / 2)
    }

    /** (right ascension, declination) in radians. */
    private fun equatorial(longitude: Double, latitude: Double, obliquity: Double): Pair<Double, Double> {
        val ra = atan2(sin(longitude) * cos(obliquity) - tan(latitude) * sin(obliquity), cos(longitude))
        val dec = asin(sin(latitude) * cos(obliquity) + cos(latitude) * sin(obliquity) * sin(longitude))
        return ra to dec
    }

    private fun normalized(degrees: Double) = degrees.mod(360.0)

    private fun rad(degrees: Double) = degrees * PI / 180
    private fun deg(radians: Double) = radians * 180 / PI
}
