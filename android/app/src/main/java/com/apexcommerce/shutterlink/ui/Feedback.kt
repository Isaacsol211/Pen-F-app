package com.apexcommerce.shutterlink.ui

import android.Manifest
import android.content.ContentResolver
import android.content.Context
import android.content.SharedPreferences
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.SoundPool
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.os.VibrationAttributes
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.provider.Settings
import android.view.HapticFeedbackConstants
import android.view.View
import androidx.annotation.RequiresApi
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.ProcessLifecycleOwner
import com.apexcommerce.shutterlink.R
import com.apexcommerce.shutterlink.camera.CameraModel
import com.apexcommerce.shutterlink.camera.ConnectionPhase
import com.apexcommerce.shutterlink.ui.Feedback.Moment
import kotlinx.coroutines.launch
import java.lang.ref.WeakReference
import kotlin.random.Random

/**
 * One entry point for haptics and sound (port of Feedback.swift; docs/design/04-motion-sound-haptics.md §4).
 * Screens never call a vibrator or a sound player: they say what happened, `Feedback.play(Moment.SHUTTER)`,
 * and this looks up the haptic and the sound, checks More ▸ Haptics, Sounds and Quiet on tripod, and
 * plays them. Every moment also shows on screen; sound is never the only signal.
 *
 * From Compose: `val feedback = rememberFeedback(); feedback(Moment.SHUTTER)`, or
 * `FeedbackOnChange(Moment.SELECT, trigger = value)` (the iOS `.feedback(_:trigger:)`). From other code:
 * `Feedback.play(Moment.X)`, once `init` has run (`FeedbackObserver` at the root does it).
 */
object Feedback {
    enum class Moment {
        /** The dial passed a third stop (or any value of a dial without stops). */
        DIAL_TICK,
        /** The dial entered a full stop, or 0 EV: a firmer click. */
        DIAL_STOP,
        /** A chip, toggle or segment changed. */
        SELECT,
        /** The shutter half press, on touch: the hand gets its answer before the camera's. */
        PRESS,
        /** The camera locked focus (AF confirmed, or the loupe's focus peak reached). */
        FOCUS_LOCK,
        /** The shutter released, on touch. */
        SHUTTER,
        /** The camera refused or failed a request. */
        REFUSED,
        /** A Bulb / Live exposure, a long exposure, a movie or a series started. */
        EXPOSURE_START,
        /** It stopped. */
        EXPOSURE_STOP,
        /** An interval series, bracket or focus stack finished all its frames. */
        SERIES_COMPLETE,
        /** Connected to the camera. */
        CONNECTED,
        /** Lost contact with the camera. */
        LOST_CONTACT,
    }

    /** Settings keys (More ▸ Feedback) in the app's "shutterlink" preferences; the same names and defaults as iOS. */
    const val KEY_HAPTICS = "feedback.haptics"
    const val KEY_SOUNDS = "feedback.sounds"
    const val KEY_QUIET_ON_TRIPOD = "feedback.quietOnTripod"

    /** The note under the three switches in More. */
    const val SETTINGS_NOTE = "No vibration or sound from this phone while the shutter is open: Bulb, long " +
        "exposures and each frame of a series. Sounds are off while the phone is on silent or vibrate."

    private var app: Context? = null
    private var prefs: SharedPreferences? = null
    private val main = Handler(Looper.getMainLooper())
    private var host: WeakReference<View>? = null

    // Compose state, so the More panel's switches follow them.
    private var hapticsOn by mutableStateOf(true)
    private var soundsOn by mutableStateOf(false)
    private var quietOn by mutableStateOf(true)

    /** More ▸ Haptics (on by default). */
    var haptics: Boolean
        get() = hapticsOn
        set(value) {
            hapticsOn = value
            prefs?.edit()?.putBoolean(KEY_HAPTICS, value)?.apply()
        }

    /** More ▸ Sounds (off by default). */
    var sounds: Boolean
        get() = soundsOn
        set(value) {
            soundsOn = value
            prefs?.edit()?.putBoolean(KEY_SOUNDS, value)?.apply()
            if (value) app?.let { Sounds.load(it) }
        }

    /** More ▸ Quiet on tripod (on by default): nothing plays while the shutter is open. */
    var quietOnTripod: Boolean
        get() = quietOn
        set(value) {
            quietOn = value
            prefs?.edit()?.putBoolean(KEY_QUIET_ON_TRIPOD, value)?.apply()
        }

    /**
     * Whether the shutter is open now (Bulb, a long exposure, a series frame), read at each play: with
     * Quiet on tripod nothing plays then, so the phone on the tripod doesn't shake the picture.
     * `FeedbackObserver` points it at the camera.
     */
    var exposureOpen: () -> Boolean = { false }

    /** Reads the switches and gets the vibrator and sounds ready. Safe to call more than once. Main thread. */
    fun init(context: Context) {
        if (app != null) return
        val c = context.applicationContext
        app = c
        val p = c.getSharedPreferences("shutterlink", Context.MODE_PRIVATE)
        prefs = p
        hapticsOn = p.getBoolean(KEY_HAPTICS, true)
        soundsOn = p.getBoolean(KEY_SOUNDS, false)
        quietOn = p.getBoolean(KEY_QUIET_ON_TRIPOD, true)
        Haptics.setUp(c)
        Sounds.setUp(c)
        if (soundsOn) Sounds.load(c)
    }

    /**
     * Plays a moment. `view` is used for the system haptic constants where the vibrator can't be (no
     * VIBRATE permission, or a motor without haptic primitives); without one, the root view
     * `FeedbackObserver` registered is used. Any thread.
     */
    fun play(moment: Moment, view: View? = null) {
        if (Looper.myLooper() != Looper.getMainLooper()) {
            main.post { play(moment, view) }
            return
        }
        if (app == null) view?.context?.let { init(it) }
        if (quietOn && exposureOpen()) return
        if (hapticsOn) Haptics.play(moment, view?.takeIf { it.isAttachedToWindow } ?: host?.get())
        if (soundsOn) Sounds.play(moment, app)
    }

    /** The dial entered a value: a firm click on full stops and 0 EV, a tick otherwise (`CurvedDial`'s `onTick`). */
    fun dial(firm: Boolean, view: View? = null) = play(if (firm) Moment.DIAL_STOP else Moment.DIAL_TICK, view)

    internal fun attach(view: View) {
        host = WeakReference(view)
    }

    internal fun detach(view: View) {
        if (host?.get() === view) host = null
    }
}

// MARK: - Haptics

/**
 * On Android 11+ with the VIBRATE permission and a motor that has haptic primitives, the iOS patterns are
 * composed from clicks and ticks at the same intensities and timings (touch usage, so the system's
 * Touch feedback setting applies). Elsewhere the closest system constants play on a view.
 */
private object Haptics {
    private val main = Handler(Looper.getMainLooper())
    private var vibrator: Vibrator? = null
    private var resolver: ContentResolver? = null
    private var clickMs = 12
    private var tickMs = 8
    private var lastDial = 0L
    private val effects = HashMap<Moment, VibrationEffect>()
    private val touchAudio = AudioAttributes.Builder()
        .setUsage(AudioAttributes.USAGE_ASSISTANCE_SONIFICATION)
        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
        .build()

    fun setUp(context: Context) {
        resolver = context.contentResolver
        if (Build.VERSION.SDK_INT >= 30) setUpComposed(context)
    }

    @RequiresApi(30)
    private fun setUpComposed(context: Context) {
        if (context.checkSelfPermission(Manifest.permission.VIBRATE) != PackageManager.PERMISSION_GRANTED) return
        val v = if (Build.VERSION.SDK_INT >= 31) context.getSystemService(VibratorManager::class.java)?.defaultVibrator
            else context.getSystemService(Vibrator::class.java)
        if (v == null || !v.hasVibrator()) return
        val click = VibrationEffect.Composition.PRIMITIVE_CLICK
        val tick = VibrationEffect.Composition.PRIMITIVE_TICK
        if (!v.areAllPrimitivesSupported(click, tick)) return
        if (Build.VERSION.SDK_INT >= 31) {
            val d = v.getPrimitiveDurations(click, tick)
            if (d[0] > 0) clickMs = d[0]
            if (d[1] > 0) tickMs = d[1]
        }
        vibrator = v
    }

    fun play(m: Moment, view: View?) {
        if (m == Moment.DIAL_TICK || m == Moment.DIAL_STOP) {
            // At most one per 60 ms, so a fast drag doesn't buzz.
            val now = SystemClock.uptimeMillis()
            if (now - lastDial <= 60) return
            lastDial = now
        }
        if (Build.VERSION.SDK_INT >= 30 && vibrator != null) {
            if (!touchFeedbackOn()) return
            if (vibrate(m)) return
        }
        if (view != null) playOnView(m, view)
    }

    /** Android 13+ applies the Touch feedback setting to touch vibrations itself; before that, it's read here. */
    @Suppress("DEPRECATION")
    private fun touchFeedbackOn(): Boolean {
        if (Build.VERSION.SDK_INT >= 33) return true
        val r = resolver ?: return true
        return Settings.System.getInt(r, Settings.System.HAPTIC_FEEDBACK_ENABLED, 1) != 0
    }

    @RequiresApi(30)
    private fun vibrate(m: Moment): Boolean {
        val v = vibrator ?: return false
        val effect = effects.getOrPut(m) { composed(m) }
        return try {
            if (Build.VERSION.SDK_INT >= 33) v.vibrate(effect, VibrationAttributes.createForUsage(VibrationAttributes.USAGE_TOUCH))
            else vibrateLegacy(v, effect)
            true
        } catch (e: RuntimeException) {
            // SecurityException and the like: use the view constants from now on.
            vibrator = null
            false
        }
    }

    @Suppress("DEPRECATION")
    private fun vibrateLegacy(v: Vibrator, effect: VibrationEffect) = v.vibrate(effect, touchAudio)

    /** iOS's (time, intensity) transients as clicks (sharp) and ticks (soft). */
    @RequiresApi(30)
    private fun composed(m: Moment): VibrationEffect {
        val click = VibrationEffect.Composition.PRIMITIVE_CLICK
        val tick = VibrationEffect.Composition.PRIMITIVE_TICK
        return when (m) {
            Moment.DIAL_TICK, Moment.SELECT -> hits(Hit(0, tick, 0.6f))
            Moment.DIAL_STOP -> hits(Hit(0, click, 0.85f))
            Moment.PRESS -> hits(Hit(0, click, 0.45f))
            Moment.FOCUS_LOCK -> hits(Hit(0, click, 0.7f))
            // The curtain closes and opens again 45 ms later.
            Moment.SHUTTER -> hits(Hit(0, click, 1f), Hit(45, click, 0.6f))
            // Rising: soft then firm. Falling: firm then soft.
            Moment.EXPOSURE_START -> hits(Hit(0, tick, 0.6f), Hit(80, click, 0.9f))
            Moment.EXPOSURE_STOP -> hits(Hit(0, click, 0.9f), Hit(80, tick, 0.6f))
            // iOS's notification patterns: success, warning, error.
            Moment.SERIES_COMPLETE, Moment.CONNECTED -> hits(Hit(0, click, 0.5f), Hit(110, click, 1f))
            Moment.LOST_CONTACT -> hits(Hit(0, click, 1f), Hit(150, click, 0.5f))
            Moment.REFUSED -> hits(Hit(0, click, 0.8f), Hit(70, click, 0.8f), Hit(140, click, 1f))
        }
    }

    /** `at` is ms from the start of the pattern; a primitive's delay counts from the end of the one before. */
    private class Hit(val at: Int, val primitive: Int, val scale: Float)

    @RequiresApi(30)
    private fun hits(vararg hits: Hit): VibrationEffect {
        val c = VibrationEffect.startComposition()
        var end = 0
        for (h in hits) {
            val delay = (h.at - end).coerceAtLeast(0)
            c.addPrimitive(h.primitive, h.scale, delay)
            end += delay + if (h.primitive == VibrationEffect.Composition.PRIMITIVE_CLICK) clickMs else tickMs
        }
        return c.compose()
    }

    private fun playOnView(m: Moment, view: View) {
        val frequentTick = if (Build.VERSION.SDK_INT >= 34) HapticFeedbackConstants.SEGMENT_FREQUENT_TICK else HapticFeedbackConstants.CLOCK_TICK
        val tick = if (Build.VERSION.SDK_INT >= 34) HapticFeedbackConstants.SEGMENT_TICK else HapticFeedbackConstants.CONTEXT_CLICK
        val soft = HapticFeedbackConstants.CONTEXT_CLICK
        val click = HapticFeedbackConstants.VIRTUAL_KEY
        when (m) {
            Moment.DIAL_TICK -> view.performHapticFeedback(frequentTick)
            Moment.SELECT -> view.performHapticFeedback(tick)
            Moment.DIAL_STOP, Moment.FOCUS_LOCK -> view.performHapticFeedback(click)
            Moment.PRESS -> view.performHapticFeedback(soft)
            Moment.SHUTTER -> sequence(view, click to 0, soft to 45)
            Moment.EXPOSURE_START -> sequence(view, soft to 0, click to 80)
            Moment.EXPOSURE_STOP -> sequence(view, click to 0, soft to 80)
            Moment.SERIES_COMPLETE, Moment.CONNECTED ->
                view.performHapticFeedback(if (Build.VERSION.SDK_INT >= 30) HapticFeedbackConstants.CONFIRM else click)
            Moment.REFUSED ->
                view.performHapticFeedback(if (Build.VERSION.SDK_INT >= 30) HapticFeedbackConstants.REJECT else HapticFeedbackConstants.LONG_PRESS)
            Moment.LOST_CONTACT -> view.performHapticFeedback(HapticFeedbackConstants.LONG_PRESS)
        }
    }

    /** Haptic constants at ms offsets. */
    private fun sequence(view: View, vararg steps: Pair<Int, Int>) {
        val ref = WeakReference(view)
        for ((constant, at) in steps) {
            if (at == 0) view.performHapticFeedback(constant)
            else main.postDelayed({ ref.get()?.performHapticFeedback(constant) }, at.toLong())
        }
    }
}

// MARK: - Sound

/**
 * Six short sounds (res/raw, converted from the iOS app's Shutterlink/Sounds). Sonification usage, so
 * they follow the phone's ring volume and mix with other audio without taking focus (never ducked or
 * paused). Silent when the phone is on silent or vibrate, during a call, while other audio plays (iOS
 * skips them then too) and while the app is in the background.
 */
private object Sounds {
    private enum class Sfx(val res: Int) {
        TICK(R.raw.sfx_tick), SHUTTER(R.raw.sfx_shutter), START(R.raw.sfx_start),
        STOP(R.raw.sfx_stop), CHIME(R.raw.sfx_chime), CONNECT(R.raw.sfx_connect),
    }

    private var pool: SoundPool? = null
    private var audio: AudioManager? = null
    private val ids = IntArray(Sfx.entries.size)
    private val ready = BooleanArray(Sfx.entries.size)
    private var lastTick = 0L

    fun setUp(context: Context) {
        audio = context.getSystemService(AudioManager::class.java)
    }

    /** Loads the sounds (asynchronously; each plays once it has loaded). Main thread. */
    fun load(context: Context) {
        if (pool != null) return
        val p = SoundPool.Builder()
            .setMaxStreams(3)
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ASSISTANCE_SONIFICATION)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build(),
            )
            .build()
        // Called on this (the main) thread's looper, after the ids below are in place.
        p.setOnLoadCompleteListener { _, sampleId, status ->
            val i = ids.indexOf(sampleId)
            if (status == 0 && i >= 0) ready[i] = true
        }
        for (s in Sfx.entries) ids[s.ordinal] = p.load(context, s.res, 1)
        pool = p
    }

    fun play(m: Moment, context: Context?) {
        val sfx = when (m) {
            Moment.DIAL_TICK, Moment.DIAL_STOP -> Sfx.TICK
            Moment.SHUTTER -> Sfx.SHUTTER
            Moment.EXPOSURE_START -> Sfx.START
            Moment.EXPOSURE_STOP -> Sfx.STOP
            Moment.SERIES_COMPLETE -> Sfx.CHIME
            Moment.CONNECTED -> Sfx.CONNECT
            Moment.SELECT, Moment.PRESS, Moment.FOCUS_LOCK, Moment.REFUSED, Moment.LOST_CONTACT -> return
        }
        if (!allowed()) return
        if (pool == null) context?.let { load(it) }
        val p = pool ?: return
        if (sfx == Sfx.TICK) {
            val now = SystemClock.uptimeMillis()
            if (now - lastTick <= 60) return
            lastTick = now
        }
        if (!ready[sfx.ordinal]) return
        // ±3 % pitch on the one repeating sound, so it doesn't machine-gun.
        val rate = if (sfx == Sfx.TICK) Random.nextDouble(0.97, 1.03).toFloat() else 1f
        p.play(ids[sfx.ordinal], 1f, 1f, 1, 0, rate)
    }

    private fun allowed(): Boolean {
        if (!ProcessLifecycleOwner.get().lifecycle.currentState.isAtLeast(Lifecycle.State.STARTED)) return false
        val a = audio ?: return true
        // Silent and vibrate both mean no interface sounds (the Ring/Silent switch on iOS).
        if (a.ringerMode != AudioManager.RINGER_MODE_NORMAL) return false
        if (a.mode == AudioManager.MODE_IN_CALL || a.mode == AudioManager.MODE_IN_COMMUNICATION) return false
        return !a.isMusicActive
    }
}

// MARK: - In Compose

/** More ▸ Haptics, Sounds and Quiet on tripod, and the note under them (iOS MoreSheet). */
@Composable
fun FeedbackSwitches() {
    val view = LocalView.current
    // Normally done already by FeedbackObserver; outside composition, so the switches' state is written globally.
    SideEffect { Feedback.init(view.context) }
    Column(Modifier.fillMaxWidth()) {
        MoreToggle("Haptics", Feedback.haptics) { Feedback.haptics = it }
        MoreToggle("Sounds", Feedback.sounds) { Feedback.sounds = it }
        MoreToggle("Quiet on tripod", Feedback.quietOnTripod) { Feedback.quietOnTripod = it }
        Text(Feedback.SETTINGS_NOTE, color = Theme.secondary, fontSize = 13.sp, lineHeight = 18.sp,
            modifier = Modifier.fillMaxWidth().padding(vertical = 10.dp))
    }
}

/** Plays moments with this composition's view (for the system haptic constants): `feedback(Moment.SHUTTER)`. */
@Composable
fun rememberFeedback(): (Moment) -> Unit {
    val view = LocalView.current
    return remember(view) {
        val play: (Moment) -> Unit = { moment -> Feedback.play(moment, view) }
        play
    }
}

/**
 * Plays `moment` when `trigger` changes (not on first composition), where `condition(old, new)` holds:
 * the iOS `.feedback(_:trigger:condition:)`. Call it inside the composable that shows the value.
 */
@Composable
fun <T> FeedbackOnChange(moment: Moment, trigger: T, condition: (old: T, new: T) -> Boolean = { _, _ -> true }) {
    val view = LocalView.current
    val last = remember { LastValue(trigger) }
    SideEffect {
        val old = last.value
        if (old != trigger) {
            last.value = trigger
            if (condition(old, trigger)) Feedback.play(moment, view)
        }
    }
}

private class LastValue<T>(var value: T)

/**
 * Watches the camera for the moments that come from it rather than from a touch: connected, lost
 * contact, refused, focus lock, exposures, movies and series starting, stopping and completing. Also
 * points `Feedback.exposureOpen` at the camera for Quiet on tripod, and registers the root view for
 * calls from outside Compose. Put once at the root (`App` in MainActivity).
 */
@Composable
fun FeedbackObserver(camera: CameraModel) {
    val view = LocalView.current
    DisposableEffect(view, camera) {
        Feedback.init(view.context)
        Feedback.attach(view)
        Feedback.exposureOpen = {
            camera.exposureStartedAt != null || (camera.isShooting && (camera.interval.running || camera.bracket.running))
        }
        onDispose {
            Feedback.detach(view)
            Feedback.exposureOpen = { false }
        }
    }
    LaunchedEffect(camera, view) {
        val play: (Moment) -> Unit = { Feedback.play(it, view) }
        launch {
            onChanges({ camera.phase to camera.lastError }) { (oldPhase, oldError), (phase, error) ->
                val connected = ConnectionPhase.CONNECTED
                when {
                    phase == connected && oldPhase != connected -> play(Moment.CONNECTED)
                    // A drop that came with a new error. (An error reported while connected played already;
                    // a deliberate disconnect leaves the error as it was and plays nothing.)
                    oldPhase == connected && phase != connected -> if (error != null && error != oldError) play(Moment.LOST_CONTACT)
                    phase == connected && error != null && error != oldError ->
                        play(if (error.startsWith("Lost contact")) Moment.LOST_CONTACT else Moment.REFUSED)
                }
            }
        }
        launch {
            onChanges({ camera.liveInfo.afState == 1 }) { _, locked -> if (locked) play(Moment.FOCUS_LOCK) }
        }
        launch {
            onChanges({ camera.exposureStartedAt != null }) { _, open ->
                // Series frames are counted by the series, not one by one. With Quiet on tripod the start is
                // held back (the shutter is open by then); the stop plays once it has closed.
                if (camera.interval.running || camera.bracket.running) return@onChanges
                play(if (open) Moment.EXPOSURE_START else Moment.EXPOSURE_STOP)
            }
        }
        launch {
            onChanges({ camera.isRecordingMovie }) { _, on -> play(if (on) Moment.EXPOSURE_START else Moment.EXPOSURE_STOP) }
        }
        launch {
            onChanges({ camera.interval }) { old, new ->
                series(play, old.running, new.running, maxOf(old.done, new.done), maxOf(old.total, new.total))
            }
        }
        launch {
            onChanges({ camera.bracket }) { old, new ->
                series(play, old.running, new.running, maxOf(old.done, new.done), maxOf(old.total, new.total))
            }
        }
    }
}

/**
 * A series started, or ended: complete when every frame was shot, stopped otherwise. The count is the
 * larger of before and after, since the last frame and the end can arrive together.
 */
private fun series(play: (Moment) -> Unit, was: Boolean, now: Boolean, done: Int, total: Int) {
    if (was == now) return
    if (now) play(Moment.EXPOSURE_START)
    else play(if (total > 0 && done >= total) Moment.SERIES_COMPLETE else Moment.EXPOSURE_STOP)
}

/** Calls `action(old, new)` each time `read()` gives a different value (not for the first one). */
private suspend fun <T> onChanges(read: () -> T, action: (old: T, new: T) -> Unit) {
    var old = read()
    snapshotFlow(read).collect { new ->
        if (new != old) {
            val was = old
            old = new
            action(was, new)
        }
    }
}
