package com.apexcommerce.shutterlink.camera

import java.util.Calendar
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
data class AfRect(val x: Double = 0.0, val y: Double = 0.0, val w: Double = 0.0, val h: Double = 0.0) {
    val midX get() = x + w / 2
    val midY get() = y + h / 2
}

/** What the camera reports with each live-view frame (Olympus) or polls (others). */
data class LiveInfo(
    /** 0 = no AF, 1 = focused, 2 = failed. */
    val afState: Int = 0,
    val afRect: AfRect = AfRect(),
    val rotation: Int = 1,
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
    val id: String = UUID.randomUUID().toString(),
) {
    val ok: Boolean get() = status != null && status in 200..204

    val line: String
        get() {
            val c = Calendar.getInstance().apply { timeInMillis = date }
            val time = fmt("%02d:%02d:%02d", c.get(Calendar.HOUR_OF_DAY), c.get(Calendar.MINUTE), c.get(Calendar.SECOND))
            return "$time $method $path → ${status?.toString() ?: "ERR"} ($millis ms) $summary"
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
)

data class IntervalState(
    val running: Boolean = false,
    val done: Int = 0,
    val total: Int = 0,
    val nextShotAt: Long? = null,
    val startedAt: Long? = null,
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
    val state: State = State.Pending,
    val id: String = UUID.randomUUID().toString(),
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
    /** Star trails with Live Composite instead of single exposures. */
    val trails: Boolean = false,
) {
    /** Longest exposure before stars visibly streak: rule ÷ (focal length × 2× crop). */
    val maxSeconds: Double get() = (if (strict) 300.0 else 500.0) / (focalLength * 2)
}
