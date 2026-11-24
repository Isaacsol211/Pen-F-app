package com.apexcommerce.shutterlink.camera

/**
 * Which camera family the app is talking to. Each speaks its own Wi-Fi protocol; the driver for
 * each lives in its own file (OlympusDriver, PanasonicDriver, NikonDriver, CanonDriver, SonyDriver).
 * Port of CameraBrand.swift.
 */
enum class CameraBrand(val id: String) {
    OLYMPUS("olympus"),
    PANASONIC("panasonic"),
    NIKON("nikon"),
    CANON("canon"),
    SONY("sony");

    val title: String
        get() = when (this) {
            OLYMPUS -> "Olympus / OM"
            PANASONIC -> "Panasonic LUMIX"
            NIKON -> "Nikon"
            CANON -> "Canon"
            SONY -> "Sony"
        }

    val shortTitle: String
        get() = when (this) {
            OLYMPUS -> "Olympus"
            PANASONIC -> "LUMIX"
            NIKON -> "Nikon"
            CANON -> "Canon"
            SONY -> "Sony"
        }

    /** The camera's own address on its Wi-Fi network (with the port when it isn't 80). */
    val defaultHost: String
        get() = when (this) {
            OLYMPUS -> "192.168.0.10"
            PANASONIC -> "192.168.54.1"
            NIKON -> "192.168.1.1"
            CANON -> "192.168.1.2:8080"
            SONY -> "192.168.122.1:8080"
        }

    /** Addresses to try when auto-detecting: the default, then others seen in the wild. */
    val likelyHosts: List<String>
        get() = when (this) {
            CANON -> listOf("192.168.1.2:8080", "192.168.1.1:8080")
            SONY -> listOf("192.168.122.1:8080", "192.168.122.1:10000")
            else -> listOf(defaultHost)
        }

    /** What the camera's Wi-Fi network is called, for instructions and errors. */
    val ssidHint: String
        get() = when (this) {
            OLYMPUS -> "the camera's network (E-M10-P-…, PEN-F-P-…, OM-1-P-…)"
            PANASONIC -> "the camera's network (GH5-…, G9-…, the camera's name)"
            NIKON -> "the camera's network (Nikon_WU2_…, Z_50_…, the camera's name)"
            CANON -> "the camera's network (EOSR6-…, the camera's name)"
            SONY -> "the camera's network (DIRECT-xxxx:ILCE-…)"
        }

    /** Live-view sizes to offer before connecting (the camera's own list replaces these). */
    val defaultLiveViewSizes: List<String>
        get() = when (this) {
            OLYMPUS -> listOf("0320x0240", "0640x0480", "0800x0600", "1024x0768", "1280x0960")
            PANASONIC -> listOf("0320x0240", "0640x0480")
            else -> emptyList()
        }

    /** What to expect before connecting; the driver's own list replaces it once connected. */
    val defaultCapabilities: CameraCapabilities
        get() = when (this) {
            OLYMPUS -> CameraCapabilities(
                liveViewSizes = defaultLiveViewSizes, movie = true, lastShotReview = true, clockSync = true,
                highResShot = true, powerOff = true,
            )
            PANASONIC -> CameraCapabilities(liveViewSizes = defaultLiveViewSizes, movie = true, videoSwitch = true, powerOff = true)
            NIKON -> CameraCapabilities()
            CANON, SONY -> CameraCapabilities(movie = true, videoSwitch = true)
        }

    /** Drivers tried only against mock cameras so far. */
    val isBeta: Boolean get() = this == NIKON || this == CANON || this == SONY

    /** Which bodies this covers, under the brand's name when adding a camera. */
    val coverage: String
        get() = when (this) {
            OLYMPUS -> "OM-D, PEN, Tough and OM System bodies with Wi-Fi"
            PANASONIC -> "G, GH, GX, GF, S and compact bodies with Wi-Fi"
            NIKON -> "Z bodies and DSLRs with Wi-Fi"
            CANON -> "EOS bodies with Canon's CCAPI unlocked"
            SONY -> "Alpha and RX bodies with Smart Remote, up to about 2019"
        }

    /** How far the app gets with this brand, shown on the Connect screen. */
    val supportNote: String?
        get() = when (this) {
            OLYMPUS -> null
            PANASONIC -> "Tested against a mock GH5; not yet on a real LUMIX."
            NIKON -> "Experimental: tested against a mock camera only."
            CANON -> "Experimental: needs Canon's CCAPI unlocked on the camera first. Tested against a mock only."
            SONY -> "Experimental: older bodies with Smart Remote Control only. Tested against a mock only."
        }

    /** A new driver for this brand, talking to `camera` at `camera.connectionHost`. */
    fun makeDriver(camera: CameraModel): CameraDriver = when (this) {
        OLYMPUS -> OlympusDriver(camera)
        PANASONIC -> PanasonicDriver(camera)
        NIKON -> NikonDriver(camera)
        CANON -> CanonDriver(camera)
        SONY -> SonyDriver(camera)
    }

    companion object {
        fun fromId(id: String?): CameraBrand? = entries.firstOrNull { it.id == id }
    }
}
