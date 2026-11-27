package com.apexcommerce.shutterlink.camera

import java.util.UUID

enum class ConnectionPhase { DISCONNECTED, CONNECTING, CONNECTED }

/** The camera's operating mode. Shooting, live view and settings need REC; the card needs PLAY. */
enum class CameraMode { UNKNOWN, REC, PLAY }

data class CameraProperty(
    val name: String,
    val settable: Boolean,
    val value: String,
    val options: List<String>,
)

data class CardFolder(
    val path: String,
    val name: String,
    val count: Int,
    /** A folder made by a different camera brand, which this camera may not list. */
    val isForeign: Boolean = !name.uppercase().endsWith("OLYMP"),
)

/** Where a photo can be fetched when the camera serves files by URL (Panasonic UPnP, Sony). */
data class MediaUrls(
    val thumbnail: String?,
    val preview: String?,
    val original: String,
)

data class CameraImage(
    val directory: String,
    val name: String,
    val size: Long,
    val attributes: Int,
    /** Capture time in ms since 1970; 0 when unknown. */
    val date: Long,
    val urls: MediaUrls? = null,
) {
    val path: String get() = "$directory/$name"
    val isDirectory: Boolean get() = attributes and 16 != 0
    val fileExtension: String get() = name.substringAfterLast('.', "").uppercase()
    val isVideo: Boolean get() = fileExtension in setOf("MOV", "MP4", "AVI")
    val baseName: String get() = name.substringBeforeLast('.')
}

/** AF frame in live-view pixels; signed (the box can hang off the frame edge). */
data class AfRect(val x: Double = 0.0, val y: Double = 0.0, val w: Double = 0.0, val h: Double = 0.0)

/** What the camera reports with each live-view frame (Olympus) or polls (others). */
data class LiveInfo(
    /** 0 = no AF, 1 = focused, 2 = failed. */
    val afState: Int = 0,
    val afRect: AfRect = AfRect(),
    val shutter: String? = null,
    val aperture: String? = null,
    /** Lens aperture limits (e.g. 1.8…22), null if the lens reports none (manual lens). */
    val apertureRange: ClosedFloatingPointRange<Double>? = null,
    val expComp: String? = null,
    val iso: String? = null,
    val shotsRemaining: Int? = null,
    /** Battery level 0–100. */
    val battery: Int? = null,
    val temperatureWarning: Boolean = false,
    /** Lens focal length in mm, when the lens reports it. */
    val focalLength: Int? = null,
    val aspectRatio: String? = null,
)

data class LogEntry(
    val date: Long,
    val method: String,
    val path: String,
    val status: Int?,
    val millis: Long,
    val summary: String,
    /** A line from the app itself (e.g. live view's frame rate), not a request: `method` is its kind, `path` its text. */
    val note: Boolean = false,
) {
    val ok: Boolean get() = status != null && status in 200..204

    /** `%tT`: the local time as HH:MM:SS. */
    val line: String
        get() = if (note) "${fmt("%tT", date)} $method $path"
        else "${fmt("%tT", date)} $method $path → ${status?.toString() ?: "ERR"} ($millis ms) $summary"

    companion object {
        /** A note in the Request log, e.g. `note("LIVE", "320×240 · 24.1 frames/s…")`. */
        fun note(kind: String, text: String) = LogEntry(System.currentTimeMillis(), kind, text, 200, 0, "", note = true)
    }
}

/** An error the app explains in its own words. */
class CameraException(message: String) : Exception(message)

/** Interval timer (time-lapse / star stacking). */
data class IntervalPlan(
    /** Number of frames; 0 = keep going until stopped. */
    val count: Int = 60,
    /** Seconds from the start of one shot to the start of the next. */
    val seconds: Double = 20.0,
    /** Day-to-night: keep live view as bright as at the start by lengthening the shutter, then raising ISO. */
    val ramp: Boolean = false,
    /** The highest ISO ramping may go to. */
    val maxISO: Int = 3200,
)

data class IntervalState(
    val running: Boolean = false,
    val done: Int = 0,
    val total: Int = 0,
    val nextShotAt: Long? = null,
    /** The last exposure change ramping made. */
    val rampNote: String? = null,
)

enum class BracketTarget(val title: String) { AUTO("Auto"), EV("EV"), SHUTTER("Shutter") }

data class BracketPlan(
    val frames: Int = 3,
    /** Step between frames, in thirds of a stop (1 = ⅓ EV … 6 = 2 EV). */
    val thirds: Int = 3,
    val target: BracketTarget = BracketTarget.AUTO,
)

data class BracketState(
    val running: Boolean = false,
    val done: Int = 0,
    val total: Int = 0,
    /** What the frame being shot is set to, e.g. "−1 EV · 1/500". */
    val label: String? = null,
    /** The run is a focus stack (which shares this state), not an exposure bracket. */
    val isFocusStack: Boolean = false,
)

/** The settings a bracket will shoot, worked out before it starts. */
data class BracketSet(
    val property: String,
    val values: List<String>,
    val offsets: List<Int>,
    /** Some frames hit the end of the camera's range and repeat a value. */
    val clamped: Boolean,
)

data class RawImportProgress(
    val done: Int = 0,
    val total: Int = 0,
    val current: String? = null,
    /** Set when finished: what happened, for the card browser to show. */
    val message: String? = null,
)

/** One setting a preset tries to apply, with what happened. */
data class PresetStep(
    val title: String,
    val detail: String,
    val property: String,
    val value: String?,
    /** Why the step can't run on this camera, shown when `value` is null. */
    val unavailable: String = "Not offered by the camera over Wi-Fi",
    /**
     * What to set on the camera when the phone can't (a dial, the mode): if the camera doesn't take the
     * value, the step says this instead of "refused".
     */
    val onCamera: String? = null,
    val state: State = State.Pending,
) {
    sealed class State {
        data object Pending : State()
        data object Running : State()
        data object Done : State()
        data class Failed(val reason: String) : State()
        data class Skipped(val reason: String) : State()
    }
}

/** Night-sky settings for a tripod-mounted camera. */
data class AstroPlan(
    val focalLength: Double = 17.0,
    /** 300 rule (pin-sharp on a 20 MP sensor) instead of the classic 500 rule. */
    val strict: Boolean = true,
    val iso: Int = 1600,
    /** Star trails: Live Composite where the camera has it, else a series of 30 s frames to stack. */
    val trails: Boolean = false,
    /** The sensor's crop factor: 2 for Micro Four Thirds, about 1.5 for APS-C, 1 for full frame. */
    val cropFactor: Double = 2.0,
) {
    /** Longest exposure before stars visibly streak: rule ÷ (focal length × crop factor). */
    val maxSeconds: Double get() = (if (strict) 300.0 else 500.0) / (focalLength * cropFactor)
}

/** How far one focus-stacking step moves the lens. */
enum class FocusStepSize(val raw: Int, val title: String) {
    FINE(1, "Fine"), MEDIUM(2, "Medium"), COARSE(3, "Coarse");

    companion object {
        fun of(raw: Int) = entries.firstOrNull { it.raw == raw } ?: FINE
    }
}

enum class FocusDriveResult {
    MOVED,
    /** The lens is already at the end of its travel in that direction (infinity or the closest point). */
    END_OF_TRAVEL,
}

/** The settings before a preset changed them, so turning it off (Undo) can put them back. */
data class SettingsSnapshot(
    /** The setup that's on (a recipe's id, or a saved preset's). */
    val id: String,
    val title: String,
    val values: Map<String, String>,
)

/** Settings the user saved under a name, for the camera brand they were saved on. */
data class SavedPreset(
    val id: String = UUID.randomUUID().toString(),
    val name: String,
    val brand: String,
    val values: Map<String, String>,
    val created: Long = System.currentTimeMillis(),
)

/** A rectangle normalised to the live-view frame (0…1). */
data class NRect(val x: Double, val y: Double, val w: Double, val h: Double)

/** The motion trigger: shoots when part of a box on live view changes. */
data class MotionTrigger(
    val armed: Boolean = false,
    /** The box watched for movement, normalised to the frame. */
    val region: NRect = NRect(0.3, 0.3, 0.4, 0.4),
    /** 0…1: higher fires on smaller changes. */
    val sensitivity: Double = 0.6,
    /** Seconds to wait after a shot before firing again. */
    val cooldown: Double = 3.0,
    val shots: Int = 0,
    /** The panel is open: show the box on live view even while disarmed, so it can be placed. */
    val editing: Boolean = false,
) {
    /** Share of the box (0…1) that has to change between frames: 1 % at the most sensitive, 15 % at the least. */
    val threshold: Double get() = 0.01 + (1 - sensitivity) * 0.14

    /** A square box of side `scale` around the same centre. */
    fun resized(scale: Double): MotionTrigger {
        val x = (region.x + region.w / 2 - scale / 2).coerceIn(0.0, 1 - scale)
        val y = (region.y + region.h / 2 - scale / 2).coerceIn(0.0, 1 - scale)
        return copy(region = NRect(x, y, scale, scale))
    }
}

/** The exposure metered without the ND filter on. */
data class NDMeter(
    val seconds: Double,
    /** The camera's aperture value ("8.0"), when known. */
    val aperture: String?,
    /** A fixed ISO ("200"); null when the camera chose it and didn't say. */
    val iso: String?,
)

/** One-tap recipes. Each sets only what the camera lets the app change over Wi-Fi, and says why for anything it can't. */
enum class PresetRecipe(val id: String, val title: String, val summary: String, val tip: String) {
    ASTRO("astro", "Astro", "Stars or star trails, from your lens and sensor", ""),
    MOON("moon", "Moon", "A sharp, properly exposed moon: M, f/8, 1/250 s",
        "Use your longest lens and focus manually on the moon's edge. If the moon still looks too bright, try 1/500 s."),
    FIREWORKS("fireworks", "Fireworks", "Whole bursts on a dark sky",
        "Put the camera on a tripod and focus manually where the bursts are. Start the exposure just before a burst."),
    LANDSCAPE("landscape", "Landscape", "f/8, lowest ISO, nothing shaking the camera",
        "Shoot from the phone so nothing touches the camera. Focus about a third of the way into the scene."),
    ACTION("action", "Action", "1/1000 s to freeze movement, fast bursts",
        "Hold the shutter for a burst. Use the camera's continuous AF (C-AF) for moving subjects: the app can't switch the AF mode."),
    MACRO("macro", "Macro", "f/8 and steady, ready for a focus stack",
        "Use a tripod. For more depth than f/8 gives, shoot a focus stack next."),
    TRAILS("trails", "Light trails & silky water", "Long exposures: car lights, waterfalls, the sea",
        "In daylight this needs an ND filter: use the ND calculator to work out the exposure."),
}
