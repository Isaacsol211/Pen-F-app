package com.apexcommerce.shutterlink.camera

// What the app knows about each Wi-Fi Olympus / OM System and Panasonic LUMIX body, beyond what the
// camera reports about itself (port of ModelProfiles.swift; keep the two in step). Most differences
// come from the camera at connect time; this table only holds what the camera doesn't say.

enum class SupportLevel(val text: String) {
    HARDWARE("Tested on this camera"),
    MOCK("Tested against a mock camera only"),
    RESEARCHED("Researched, not yet tried on this camera"),
    UNSUPPORTED("Not supported"),
}

/** How a LUMIX body lets a phone in. */
enum class LumixPairing {
    /** No pairing request (GH3, GH4): just start sending commands. */
    NONE,
    /** `accctrl req_acc`, with a Yes/No prompt on the camera the first time. */
    STANDARD,
    /** `req_acc_g` / `req_acc_e` and an `X-SESSION_ID` header (S5IIX, G9 II…). Unverified. */
    NEWER,
}

data class ModelProfile(
    val brand: CameraBrand,
    /** As people know it, e.g. "E-M10 Mark III", "LUMIX GX80 / GX85". */
    val name: String,
    /** What the camera may report (Olympus `get_caminfo` model, LUMIX UPnP modelNumber), any spelling. */
    val aliases: List<String>,
    val year: Int,
    val support: SupportLevel = SupportLevel.RESEARCHED,
    /** Shown once after connecting. */
    val notes: List<String> = emptyList(),
    /** Remote shooting isn't possible; the reason, shown instead of connecting. */
    val unsupportedReason: String? = null,
    // Olympus
    val highResShot: Boolean = false,
    // LUMIX
    val pairing: LumixPairing = LumixPairing.STANDARD,
    /** Aperture and shutter can't be set over Wi-Fi (compacts with fixed controls). */
    val fixedExposure: Boolean = false,
    val noExposureComp: Boolean = false,
    val noISO: Boolean = false,
    val noVideo: Boolean = false,
) {
    companion object {
        /** "E-M10 Mark III", "E-M10MarkIII", "DC-GX80", "DMC-GX80 (mock)" → comparable keys. */
        fun key(text: String): String {
            var s = text.uppercase()
            val paren = s.indexOf('(')
            if (paren >= 0) s = s.substring(0, paren)
            for (prefix in listOf("OLYMPUS ", "OM SYSTEM ", "OMSYSTEM ", "PANASONIC ", "LUMIX ", "DMC-", "DC-")) s = s.removePrefix(prefix)
            return s.replace("MARK", "").filter { it.isLetterOrDigit() }
        }
    }
}

object ModelProfiles {
    /** The profile for what the camera reported, if this body is in the table. */
    fun find(brand: CameraBrand, reported: String?): ModelProfile? {
        if (reported.isNullOrEmpty()) return null
        val key = ModelProfile.key(reported)
        return all.firstOrNull { p -> p.brand == brand && p.aliases.any { ModelProfile.key(it) == key } }
    }

    private const val OM = "OM System bodies: start Device Connection on the camera (Bluetooth can stay off). OM System says remote shooting is partly limited, and its app may speak a newer protocol: this body hasn't been tried with Shutterlink yet."
    private const val PRO_REMOTE = "Olympus may restrict remote shooting from other apps on this body (other apps only offer downloads). If controls are refused, use OI.Share."
    private const val NEWER_PAIRING = "This body may use the newer LUMIX pairing, which is experimental in Shutterlink. Since the 2025 firmware the camera's Wi-Fi always has a password, shown on the camera."

    private fun o(name: String, aliases: List<String>, year: Int, notes: List<String> = emptyList(),
                  highRes: Boolean = false, support: SupportLevel = SupportLevel.RESEARCHED,
                  unsupported: String? = null) =
        ModelProfile(CameraBrand.OLYMPUS, name, aliases, year, support = support, notes = notes,
            unsupportedReason = unsupported, highResShot = highRes)

    private fun p(name: String, aliases: List<String>, year: Int, notes: List<String> = emptyList(),
                  pairing: LumixPairing = LumixPairing.STANDARD, fixed: Boolean = false, noEv: Boolean = false,
                  noIso: Boolean = false, noVideo: Boolean = false, support: SupportLevel = SupportLevel.RESEARCHED) =
        ModelProfile(CameraBrand.PANASONIC, name, aliases, year, support = support, notes = notes, pairing = pairing,
            fixedExposure = fixed, noExposureComp = noEv, noISO = noIso, noVideo = noVideo)

    val olympus: List<ModelProfile> = listOf(
        o("PEN E-P5", listOf("E-P5"), 2013),
        o("OM-D E-M1", listOf("E-M1"), 2013,
            notes = listOf("Remote control only works with the camera's Wi-Fi set to Private, not One-Time. Movie mode isn't available over Wi-Fi.")),
        o("Stylus 1 / 1s", listOf("STYLUS1", "STYLUS1S", "STYLUS1,1s"), 2013),
        o("OM-D E-M10", listOf("E-M10"), 2014),
        o("Stylus SH-1", listOf("SH-1"), 2014),
        o("Tough TG-3", listOf("TG-3"), 2014),
        o("PEN E-PL7", listOf("E-PL7"), 2014),
        o("OM-D E-M5 Mark II", listOf("E-M5MarkII", "E-M5 II"), 2015, highRes = true),
        o("Stylus SH-2", listOf("SH-2"), 2015),
        o("Tough TG-4", listOf("TG-4"), 2015),
        o("Tough TG-860 / TG-870", listOf("TG-860", "TG-870"), 2015),
        o("OM-D E-M10 Mark II", listOf("E-M10MarkII", "E-M10 II"), 2015),
        o("AIR A01", listOf("AIR-A01", "A01", "AIR A01"), 2015, support = SupportLevel.UNSUPPORTED,
            unsupported = "The AIR A01 speaks Olympus's Open Platform API (switch_cameramode, newstarttake), which Shutterlink doesn't support yet."),
        o("PEN-F", listOf("PEN-F"), 2016, highRes = true, support = SupportLevel.HARDWARE),
        o("Stylus SH-3", listOf("SH-3"), 2016),
        o("PEN E-PL8", listOf("E-PL8"), 2016),
        o("OM-D E-M1 Mark II", listOf("E-M1MarkII", "E-M1 II"), 2016, highRes = true),
        o("TG-Tracker", listOf("TG-Tracker"), 2016, support = SupportLevel.UNSUPPORTED,
            unsupported = "The TG-Tracker works with OI.Track, not remote shooting."),
        o("Tough TG-5", listOf("TG-5"), 2017),
        o("OM-D E-M10 Mark III", listOf("E-M10MarkIII", "E-M10 III"), 2017),
        o("PEN E-PL9", listOf("E-PL9"), 2018),
        o("OM-D E-M1X", listOf("E-M1X"), 2019, notes = listOf(PRO_REMOTE), highRes = true),
        o("Tough TG-6", listOf("TG-6"), 2019),
        o("OM-D E-M5 Mark III", listOf("E-M5MarkIII", "E-M5 III"), 2019, highRes = true),
        o("PEN E-PL10", listOf("E-PL10"), 2019),
        o("OM-D E-M1 Mark III", listOf("E-M1MarkIII", "E-M1 III"), 2020, notes = listOf(PRO_REMOTE), highRes = true),
        o("OM-D E-M10 Mark IV", listOf("E-M10MarkIV", "E-M10 IV"), 2020,
            notes = listOf("Over Wi-Fi the E-M10 IV only changes mode, aperture, shutter, EV, ISO, white balance, drive, art filter and hue.")),
        o("PEN E-P7", listOf("E-P7"), 2021),
        o("OM System OM-1", listOf("OM-1"), 2022, notes = listOf(OM), highRes = true),
        o("OM System OM-5", listOf("OM-5"), 2022, notes = listOf(OM), highRes = true),
        o("OM System TG-7", listOf("TG-7"), 2023, notes = listOf(OM)),
        o("OM System OM-1 Mark II", listOf("OM-1MarkII", "OM-1 II"), 2024, notes = listOf(OM), highRes = true),
        o("OM System OM-3", listOf("OM-3"), 2025, notes = listOf(OM), highRes = true),
        o("OM System OM-5 Mark II", listOf("OM-5MarkII", "OM-5 II"), 2025, notes = listOf(OM), highRes = true),
    )

    val panasonic: List<ModelProfile> = listOf(
        p("LUMIX GH3", listOf("GH3"), 2012, pairing = LumixPairing.NONE),
        p("LUMIX G6", listOf("G6"), 2013),
        p("LUMIX GF6", listOf("GF6"), 2013, noIso = true),
        p("LUMIX LF1", listOf("LF1"), 2013, noIso = true),
        p("LUMIX GX7", listOf("GX7"), 2013),
        p("LUMIX GM1 / GM1S", listOf("GM1", "GM1S"), 2013),
        p("LUMIX TS5 / FT5", listOf("TS5", "FT5"), 2013),
        p("LUMIX TZ40 / ZS30", listOf("TZ40", "ZS30"), 2013),
        p("LUMIX FZ70 / FZ72", listOf("FZ70", "FZ72"), 2013),
        p("LUMIX GH4", listOf("GH4"), 2014, pairing = LumixPairing.NONE),
        p("LUMIX TZ60 / ZS40", listOf("TZ60", "ZS40", "TZ61"), 2014, fixed = true),
        p("LUMIX TZ55 / ZS35", listOf("TZ55", "ZS35"), 2014, fixed = true, noVideo = true),
        p("LUMIX SZ8", listOf("SZ8"), 2014, fixed = true, noVideo = true),
        p("LUMIX LX100", listOf("LX100"), 2014,
            notes = listOf("The LX100's aperture ring, shutter dial and EV dial are physical, so they can't be changed from the phone."),
            fixed = true, noEv = true),
        p("LUMIX FZ1000", listOf("FZ1000"), 2014),
        p("LUMIX GM5", listOf("GM5"), 2014),
        p("LUMIX G7 / G70", listOf("G7", "G70"), 2015, support = SupportLevel.HARDWARE),
        p("LUMIX GF7", listOf("GF7"), 2015),
        p("LUMIX TZ70 / ZS50", listOf("TZ70", "ZS50", "TZ71"), 2015, noIso = true),
        p("LUMIX FZ300 / FZ330", listOf("FZ300", "FZ330"), 2015),
        p("LUMIX TS6 / FT6, TS30", listOf("TS6", "FT6", "TS30"), 2015),
        p("LUMIX TZ57 / ZS45", listOf("TZ57", "ZS45"), 2015, noVideo = true),
        p("LUMIX SZ10", listOf("SZ10"), 2015, fixed = true, noVideo = true),
        p("LUMIX GX8", listOf("GX8"), 2015,
            notes = listOf("The GX8's exposure compensation dial is physical, so EV can't be changed from the phone."), noEv = true),
        p("LUMIX GX80 / GX85 / GX7 II", listOf("GX80", "GX85", "GX7MK2"), 2016),
        p("LUMIX G80 / G85 / G81", listOf("G80", "G85", "G81"), 2016),
        p("LUMIX GF8", listOf("GF8"), 2016),
        p("LUMIX TZ80 / ZS60", listOf("TZ80", "ZS60", "TZ81"), 2016),
        p("LUMIX TZ100 / ZS100", listOf("TZ100", "ZS100", "TZ101"), 2016),
        p("LUMIX LX10 / LX15", listOf("LX10", "LX15"), 2016),
        p("LUMIX FZ2000 / FZ2500", listOf("FZ2000", "FZ2500"), 2016),
        p("LUMIX GH5", listOf("GH5"), 2017, support = SupportLevel.MOCK),
        p("LUMIX GF9 / GX800 / GX850", listOf("GF9", "GX800", "GX850"), 2017),
        p("LUMIX G9", listOf("G9"), 2017, notes = listOf("High Resolution Mode can't be started from Shutterlink; set it on the camera.")),
        p("LUMIX TZ90 / ZS70", listOf("TZ90", "ZS70", "TZ91"), 2017),
        p("LUMIX FZ80 / FZ82", listOf("FZ80", "FZ82"), 2017),
        p("LUMIX GH5S", listOf("GH5S"), 2018),
        p("LUMIX GX9 / GX7 III", listOf("GX9", "GX7MK3"), 2018),
        p("LUMIX TZ200 / ZS200", listOf("TZ200", "ZS200", "TZ202"), 2018),
        p("LUMIX LX100 II", listOf("LX100M2", "LX100II"), 2018),
        p("LUMIX GF10 / GF90", listOf("GF10", "GF90"), 2018),
        p("LUMIX FT7 / TS7", listOf("FT7", "TS7"), 2018, notes = listOf("4K recording is off while the camera's Wi-Fi is on."), fixed = true),
        p("LUMIX G90 / G95 / G91", listOf("G90", "G95", "G91"), 2019),
        p("LUMIX TZ95 / ZS80", listOf("TZ95", "ZS80", "TZ96"), 2019),
        p("LUMIX FZ1000 II", listOf("FZ1000M2", "FZ1000II"), 2019),
        p("LUMIX S1 / S1R / S1H", listOf("S1", "S1R", "S1H"), 2019),
        p("LUMIX G100", listOf("G100", "G110"), 2020),
        p("LUMIX S5", listOf("S5"), 2020, notes = listOf("The S5 sends 16:9 live view (640×360).")),
        p("LUMIX BGH1", listOf("BGH1"), 2020),
        p("LUMIX GH5 II", listOf("GH5M2", "GH5II"), 2021,
            notes = listOf("Since firmware 1.4 the camera's Wi-Fi always has a password, shown on the camera.")),
        p("LUMIX GH6", listOf("GH6"), 2022),
        p("LUMIX BS1H", listOf("BS1H"), 2022),
        p("LUMIX S5 II", listOf("S5M2", "S5II"), 2023, notes = listOf(NEWER_PAIRING)),
        p("LUMIX S5 IIX", listOf("S5M2X", "S5IIX"), 2023, notes = listOf(NEWER_PAIRING), pairing = LumixPairing.NEWER),
        p("LUMIX G9 II", listOf("G9M2", "G9II"), 2023, notes = listOf(NEWER_PAIRING), pairing = LumixPairing.NEWER),
        p("LUMIX TZ99 / ZS99", listOf("TZ99", "ZS99"), 2023),
        p("LUMIX G97", listOf("G97"), 2024),
        p("LUMIX GH7", listOf("GH7"), 2024, notes = listOf(NEWER_PAIRING)),
        p("LUMIX S9", listOf("S9"), 2024, notes = listOf("Remote shooting needs S9 firmware 1.1 or later.", NEWER_PAIRING)),
        p("LUMIX G100D", listOf("G100D"), 2024),
        p("LUMIX S1 II / S1R II / L10", listOf("S1M2", "S1RM2", "S1II", "S1RII", "L10"), 2025,
            notes = listOf("These bodies pair with LUMIX Lab and LUMIX Flow; Panasonic's older Wi-Fi remote protocol may not be there at all.")),
    )

    val all: List<ModelProfile> = olympus + panasonic
}
