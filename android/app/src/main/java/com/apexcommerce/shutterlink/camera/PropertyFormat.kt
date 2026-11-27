package com.apexcommerce.shutterlink.camera

/**
 * Names the connected camera gives its own settings and values. LUMIX menus carry an English name for
 * every option; these are checked before the built-in tables.
 */
data class CameraText(
    val titles: Map<String, String> = emptyMap(),
    val values: Map<String, Map<String, String>> = emptyMap(),
)

/** Human-readable labels for the camera's raw property values (port of PropertyFormat.swift). */
object PropertyFormat {
    @Volatile private var cameraText = CameraText()

    /** Replaces the connected camera's own names (empty when it disconnects). */
    fun setCameraText(text: CameraText) {
        cameraText = text
    }

    val featured: List<Pair<String, String>> = listOf(
        "takemode" to "Mode",
        "focalvalue" to "Aperture",
        "shutspeedvalue" to "Shutter",
        "isospeedvalue" to "ISO",
        "expcomp" to "EV",
        "wbvalue" to "WB",
        "drivemode" to "Drive",
        "artfilter" to "Art filter",
        "colortone" to "Picture",
        "colorphase" to "Hue (CRT)",
    )

    fun title(name: String): String = cameraText.titles[name] ?: featured.firstOrNull { it.first == name }?.second ?: name

    /** Exposure time in seconds for a shutter value: `60"` → 60, `250` → 1/250, `1.3` → 1/1.3. */
    fun seconds(fromShutter: String): Double? {
        if (fromShutter.endsWith("\"")) return fromShutter.dropLast(1).toDoubleOrNull()
        val d = fromShutter.toDoubleOrNull()
        return if (d != null && d > 0) 1 / d else null
    }

    /** Live Composite, Live Time, Live Bulb and Bulb run until stopped. */
    fun isOpenEnded(shutter: String): Boolean = shutter.lowercase().let { it.startsWith("live") || it == "bulb" || it == "time" }

    fun display(name: String, value: String): String = cameraText.values[name]?.get(value) ?: when (name) {
        "takemode" -> when (value.lowercase()) {
            "iauto" -> "iAUTO"
            "movie" -> "Movie"
            else -> value.uppercase()
        }
        "focalvalue" -> if (value.toDoubleOrNull() != null) "F$value" else value
        "shutspeedvalue" -> when {
            value.endsWith("\"") -> value
            value.toDoubleOrNull() != null -> "1/$value"
            else -> when (value.lowercase()) {
                "livecomp" -> "Live Comp"
                "livetime" -> "Live Time"
                "livebulb" -> "Live Bulb"
                "bulb" -> "Bulb"
                else -> words(value)
            }
        }
        "expcomp" -> if (value.toDoubleOrNull() == 0.0) "±0.0" else value
        "isospeedvalue" -> when (value.lowercase()) {
            "auto" -> "Auto"
            "i_iso" -> "iAuto"
            else -> value
        }
        "wbvalue" -> whiteBalance[value] ?: if (value.toIntOrNull() != null) "WB $value" else words(value)
        "drivemode" -> drive(value)
        "artfilter", "colortone" -> words(value)
        "colorphase" -> value.replace("step", "Hue ")
        else -> value
    }

    /** Best guess from the order the camera lists them (matches the WB menu order). */
    val whiteBalance: Map<String, String> = mapOf(
        "0" to "Auto", "18" to "Sunny", "16" to "Shade", "17" to "Cloudy", "20" to "Incandescent",
        "35" to "Fluorescent", "64" to "Underwater", "23" to "Flash",
        "256" to "One-touch 1", "257" to "One-touch 2", "258" to "One-touch 3", "259" to "One-touch 4",
        "512" to "Custom K",
        // Canon's two auto modes
        "awb_white" to "Auto (white priority)", "awb_ambience" to "Auto (ambience priority)",
    )

    private fun drive(value: String): String {
        val names = mapOf(
            "normal" to "Single", "lowvib" to "Anti-shock", "silent" to "Silent",
            "continuous" to "Cont.", "selftimer" to "Self-timer", "customselftimer" to "Custom timer",
        )
        return value.split("-").joinToString(" ") { names[it] ?: it }
    }

    private fun words(value: String): String =
        value.replace("_", " ").split(" ").joinToString(" ") { w -> w.lowercase().replaceFirstChar { it.uppercase() } }
}
