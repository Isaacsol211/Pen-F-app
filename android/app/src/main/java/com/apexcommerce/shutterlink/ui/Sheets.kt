package com.apexcommerce.shutterlink.ui

import android.app.Activity
import android.view.WindowManager
import androidx.activity.compose.BackHandler
import androidx.compose.animation.Crossfade
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Cancel
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Remove
import androidx.compose.material.icons.outlined.Circle
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.LocalTextStyle
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import com.apexcommerce.shutterlink.camera.AstroPlan
import com.apexcommerce.shutterlink.camera.BracketPlan
import com.apexcommerce.shutterlink.camera.BracketTarget
import com.apexcommerce.shutterlink.camera.CameraMode
import com.apexcommerce.shutterlink.camera.CameraModel
import com.apexcommerce.shutterlink.camera.ConnectionPhase
import com.apexcommerce.shutterlink.camera.FocusStepSize
import com.apexcommerce.shutterlink.camera.IntervalPlan
import com.apexcommerce.shutterlink.camera.PresetRecipe
import com.apexcommerce.shutterlink.camera.PresetStep
import com.apexcommerce.shutterlink.camera.PropertyFormat
import com.apexcommerce.shutterlink.camera.applyAstro
import com.apexcommerce.shutterlink.camera.astroSteps
import com.apexcommerce.shutterlink.camera.bracketSet
import com.apexcommerce.shutterlink.camera.canBracket
import com.apexcommerce.shutterlink.camera.canFocusStack
import com.apexcommerce.shutterlink.camera.canRampExposure
import com.apexcommerce.shutterlink.camera.cancelBracket
import com.apexcommerce.shutterlink.camera.cropFactor
import com.apexcommerce.shutterlink.camera.focusStackSetup
import com.apexcommerce.shutterlink.camera.focusStackUnavailable
import com.apexcommerce.shutterlink.camera.hasLiveComposite
import com.apexcommerce.shutterlink.camera.isPresetOn
import com.apexcommerce.shutterlink.camera.lastKnownLocation
import com.apexcommerce.shutterlink.camera.offsetLabel
import com.apexcommerce.shutterlink.camera.startBracket
import com.apexcommerce.shutterlink.camera.startFocusStack
import com.apexcommerce.shutterlink.camera.startInterval
import com.apexcommerce.shutterlink.camera.startTrailsSeries
import com.apexcommerce.shutterlink.camera.stopInterval
import com.apexcommerce.shutterlink.camera.trailsSeries
import com.apexcommerce.shutterlink.camera.undoPreset
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlin.math.ceil
import kotlin.math.max
import kotlin.math.roundToInt

// The tool screens (port of the redesign's "big number panels": Instruments.swift's IntervalPanel,
// ExtrasViews.swift, AstroView.swift and HighResView.swift, design screens 301–312 and 316). Every tool
// opens on one very large Barlow number that states the result, then a few hairline rows, then one
// primary button; running states show a progress ring and the same big number. On a phone they're
// full-screen pages (ToolScreen in ToolKit.kt).

/** A dark bottom sheet with a title row and a Done button. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun Sheet(title: String, onDismiss: () -> Unit, footer: (@Composable () -> Unit)? = null, content: @Composable ColumnScope.() -> Unit) {
    val state = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = state, containerColor = Theme.background,
        contentColor = Color.White, dragHandle = null, shape = RoundedCornerShape(topStart = 26.dp, topEnd = 26.dp)) {
        Column(Modifier.fillMaxWidth().navigationBarsPadding()) {
            Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 10.dp), verticalAlignment = Alignment.CenterVertically) {
                Text(title, fontSize = 17.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f))
                SurfaceButton(onClick = onDismiss, circle = true) { Icon(Icons.Filled.Check, "Done", Modifier.size(20.dp)) }
            }
            Column(Modifier.weight(1f, fill = false).verticalScroll(rememberScrollState()).padding(horizontal = 16.dp).padding(bottom = 16.dp),
                verticalArrangement = Arrangement.spacedBy(16.dp), content = content)
            footer?.let { Box(Modifier.padding(horizontal = 16.dp, vertical = 8.dp)) { it() } }
        }
    }
}

/** A selectable chip: text-on-light when chosen, outlined when not (the design's chip). */
@Composable
fun Chip(text: String, on: Boolean, enabled: Boolean = true, onClick: () -> Unit) {
    ChipButton(text, on, enabled = enabled, onClick = onClick)
}

/** A value on a hairline row with − and + buttons. */
@Composable
fun Stepper(label: String, value: String, onMinus: () -> Unit, onPlus: () -> Unit, less: String = "Less", more: String = "More") {
    Row(Modifier.fillMaxWidth().hairRow(58.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        Text(label, color = Theme.text, fontSize = 16.sp, fontWeight = FontWeight.Medium, modifier = Modifier.weight(1f))
        Text(value, style = Theme.num(22.sp), color = Theme.text, maxLines = 1)
        SurfaceButton(onClick = onMinus, circle = true) { Icon(Icons.Filled.Remove, less, Modifier.size(18.dp)) }
        SurfaceButton(onClick = onPlus, circle = true) { Icon(Icons.Filled.Add, more, Modifier.size(18.dp)) }
    }
}

// MARK: - Interval timer (301–303)

private enum class IntervalField { SECONDS, COUNT }

private val intervalSeconds: List<Int> = (1..9).toList() + (10..600 step 5).toList()
private val intervalCounts: List<Int> = listOf(0) + (2..19).toList() + (20..9990 step 10).toList()

/** Interval timer (time-lapse / star stacking) setup and progress. */
@Composable
fun IntervalSheet(camera: CameraModel, onDismiss: () -> Unit) {
    var count by remember { mutableIntStateOf(camera.prefs.getInt("interval.count", 60)) }
    var seconds by remember { mutableDoubleStateOf(camera.prefs.getFloat("interval.seconds", 20f).toDouble()) }
    var ramp by remember { mutableStateOf(camera.prefs.getBoolean("interval.ramp", false)) }
    var maxIso by remember { mutableIntStateOf(camera.prefs.getInt("interval.maxISO", 3200)) }
    var editing by remember { mutableStateOf<IntervalField?>(null) }
    fun save() = camera.prefs.edit().putInt("interval.count", count).putFloat("interval.seconds", seconds.toFloat())
        .putBoolean("interval.ramp", ramp).putInt("interval.maxISO", maxIso).apply()
    val plan = IntervalPlan(count, seconds, ramp = ramp && camera.canRampExposure, maxISO = maxIso)
    val location = remember { camera.lastKnownLocation() }
    ToolScreen("Interval timer", onDismiss) {
        if (camera.interval.running) {
            IntervalRunning(camera)
        } else {
            // 301: where the sun is today, when the phone knows where it is.
            location?.let { SunArc(it.latitude, it.longitude, Modifier.bleed(20.dp).padding(bottom = 14.dp)) }
            Row(Modifier.padding(bottom = 14.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                for ((title, c, s) in listOf(Triple("Star stack", 30, 22.0), Triple("Time-lapse", 240, 5.0), Triple("Trails", 120, 32.0))) {
                    ChipButton(title, count == c && seconds == s) { count = c; seconds = s; save() }
                }
            }
            // Every and Frames side by side; tap one to change it on a wheel.
            Column(Modifier.fillMaxWidth().hairlineAbove()) {
                PairRow(listOf(
                    PairCell("Every", "${seconds.toInt()} s") { editing = IntervalField.SECONDS },
                    PairCell("Frames", if (count == 0) "Until stopped" else "$count") { editing = IntervalField.COUNT },
                ))
                IntervalNote(intervalSummary(count, seconds))
                val shutter = PropertyFormat.seconds(camera.properties["shutspeedvalue"]?.value ?: "")
                if (shutter != null && shutter + 1 > seconds) {
                    NoteRow("The interval is shorter than the exposure (${shutter.toInt()} s). Shots will run back to back.", warning = true)
                }
                ToggleRow("Follow the light", "Day to night (or night to day)", ramp && camera.canRampExposure,
                    { ramp = it; save() }, enabled = camera.canRampExposure)
                if (ramp && camera.canRampExposure) {
                    SegRow("Highest ISO", listOf(1600, 3200, 6400, 12800), maxIso, { maxIso = it; save() }, { "$it" })
                }
                IntervalNote(if (camera.canRampExposure)
                    "Keeps live view as bright as when you start: as it gets dark the shutter gets longer (up to what the interval leaves room for), then the ISO goes up, a third of a stop at a time, and back at sunrise. Needs live view to show the exposure (Live View Boost off)."
                else "Switch the camera to M so the app can change the shutter speed.")
                if (camera.isOpenEndedShutter) {
                    NoteRow("Interval shooting needs a timed shutter speed, not Live Composite/Time/Bulb.", warning = true)
                }
            }
            PinnedBottom {
                AccentButton(onClick = { camera.startInterval(plan) }, modifier = Modifier.fillMaxWidth(),
                    enabled = camera.mode == CameraMode.REC && !camera.isOpenEndedShutter) { Text("Start") }
            }
        }
    }
    // 301: Every or Frames on a wheel in the bottom panel.
    val field = editing
    PanelCover(field != null, { editing = null }, title = if (field == IntervalField.COUNT) "Frames" else "Every") { dismiss ->
        if (field == IntervalField.COUNT) {
            WheelPicker(intervalCounts, count, "Frames", onSet = { count = it; save() }, dismiss = dismiss, zeroText = "Until stopped")
        } else {
            WheelPicker(intervalSeconds, seconds.toInt(), "Every", onSet = { seconds = it.toDouble(); save() }, dismiss = dismiss, unit = "s")
        }
    }
}

@Composable
private fun IntervalNote(text: String) {
    Text(text, color = Theme.secondary, fontSize = 13.sp, lineHeight = 18.sp,
        modifier = Modifier.fillMaxWidth().hairRow().padding(vertical = 12.dp))
}

private fun intervalSummary(count: Int, seconds: Double): String {
    if (count == 0) return "Shoots every ${seconds.toInt()} s until you tap Stop."
    val total = (count * seconds).toLong()
    val duration = if (total >= 3600) "${total / 3600} h ${total % 3600 / 60} min" else if (total >= 60) "${total / 60} min ${total % 60} s" else "$total s"
    return "$count frames over about $duration. At 25 fps that's a ${String.format(java.util.Locale.US, "%.1f", count / 25.0)} s clip."
}

/** 303: the ring with the frames taken, the time to the next shot, the frame bars, Stop at the bottom. */
@Composable
private fun ColumnScope.IntervalRunning(camera: CameraModel) {
    val now = rememberNow(true, 500)
    val state = camera.interval
    Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(18.dp)) {
        ProgressRing("${state.done}", if (state.total > 0) state.done.toDouble() / state.total else 0.0,
            sub = if (state.total == 0) "shooting until stopped" else "of ${state.total}")
        val next = state.nextShotAt
        if (next != null) {
            val left = ((next - now + 999) / 1000).coerceAtLeast(0)
            BigNumber(String.format(java.util.Locale.US, "%d:%02d", left / 60, left % 60), caption = "Next shot in $left s", size = 80.sp)
        } else {
            BigNumber("…", caption = "Exposing…", size = 72.sp)
        }
        if (state.total > 0) FrameBars(state.done, state.total)
        state.rampNote?.let { NoteRow(it, color = Theme.accent) }
    }
    PinnedBottom {
        OutlineButton(onClick = { camera.stopInterval() }, modifier = Modifier.fillMaxWidth()) { Text("Stop") }
    }
}

// MARK: - Bracketing and focus stacking (304–307)

/** "⅓" … "2": a bracket's step, in thirds of a stop. */
private fun stepLabel(thirds: Int): String = when (thirds) {
    1 -> "⅓"
    2 -> "⅔"
    3 -> "1"
    4 -> "1⅓"
    5 -> "1⅔"
    else -> "2"
}

@Composable
fun BracketSheet(camera: CameraModel, onDismiss: () -> Unit) {
    var frames by remember { mutableIntStateOf(camera.prefs.getInt("bracket.frames", 3)) }
    var thirds by remember { mutableIntStateOf(camera.prefs.getInt("bracket.thirds", 3)) }
    var target by remember { mutableStateOf(BracketTarget.entries.getOrElse(camera.prefs.getInt("bracket.target", 0)) { BracketTarget.AUTO }) }
    fun save() = camera.prefs.edit().putInt("bracket.frames", frames).putInt("bracket.thirds", thirds).putInt("bracket.target", target.ordinal).apply()
    var focusMode by remember { mutableStateOf(camera.prefs.getBoolean("bracket.focus", false)) }
    var focusFrames by remember { mutableIntStateOf(camera.prefs.getInt("focusStack.frames", 10)) }
    var focusStep by remember { mutableStateOf(FocusStepSize.of(camera.prefs.getInt("focusStack.step", 1))) }
    fun saveFocus() = camera.prefs.edit().putBoolean("bracket.focus", focusMode).putInt("focusStack.frames", focusFrames)
        .putInt("focusStack.step", focusStep.raw).apply()
    val plan = BracketPlan(frames, thirds, target)
    val running = camera.bracket.running
    val title = when {
        running -> if (camera.bracket.isFocusStack) "Focus stack" else "Bracketing"
        focusMode -> "Focus stack"
        else -> "Bracketing"
    }
    FeedbackOnChange(Feedback.Moment.SELECT, focusMode)
    ToolScreen(title, onDismiss) {
        if (running) {
            BracketRunning(camera)
        } else {
            // 304/305: Exposure and Focus as two chips, white when chosen.
            Row(Modifier.padding(bottom = 14.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                ChipButton("Exposure", !focusMode) { focusMode = false; saveFocus() }
                ChipButton("Focus", focusMode) { focusMode = true; saveFocus() }
            }
            if (focusMode) {
                FocusStackCards(camera, focusFrames, focusStep, { focusFrames = it; saveFocus() }, { focusStep = it; saveFocus() }, onDismiss)
            } else {
                ExposureBracketCards(camera, plan, { frames = it; save() }, { thirds = it; save() }, { target = it; save() })
            }
        }
    }
}

/** 304: "3 × 1" large, Frames, Step and Vary, the frames it will shoot, Shoot at the bottom. */
@Composable
private fun ColumnScope.ExposureBracketCards(
    camera: CameraModel, plan: BracketPlan, setFrames: (Int) -> Unit, setThirds: (Int) -> Unit, setTarget: (BracketTarget) -> Unit,
) {
    val frames = plan.frames
    val thirds = plan.thirds
    BigNumber("$frames × ${stepLabel(thirds)}", Modifier.padding(bottom = 14.dp),
        caption = "$frames frames, ${stepLabel(thirds)} stop${if (thirds == 3) "" else "s"} apart", size = 104.sp)
    Column(Modifier.fillMaxWidth().hairlineAbove()) {
        SegRow("Frames", listOf(3, 5, 7, 9), frames, setFrames, { "$it" })
        SegRow("Step", (1..6).toList(), thirds, setThirds, { stepLabel(it) })
        SegRow("Vary", BracketTarget.entries.toList(), plan.target, setTarget, { it.title })
        NoteRow(if (camera.properties["takemode"] == null)
            "Auto varies EV. In M, choose Shutter: the app can't read this camera's mode dial."
        else "Auto varies the shutter speed in M and exposure compensation in P, A and S.")
    }
    SectionLabel("Will shoot")
    val set = camera.bracketSet(plan)
    set.onSuccess { s ->
        // One box per frame: the offset over the value, the metered one outlined in the accent.
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            s.values.forEachIndexed { i, value ->
                val offset = s.offsets[i]
                Column(Modifier.weight(1f).heightIn(min = 54.dp).outlinedBox(if (offset == 0) Theme.accent else Theme.outline)
                    .padding(horizontal = 2.dp, vertical = 6.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(2.dp, Alignment.CenterVertically)) {
                    Text(offsetLabel(offset), color = Theme.secondary, fontSize = 11.sp, maxLines = 1)
                    AutoFitText(PropertyFormat.display(s.property, value), Theme.num(18.sp), Theme.text, Modifier.fillMaxWidth())
                }
            }
        }
        val current = PropertyFormat.display(s.property, camera.properties[s.property]?.value ?: "")
        NoteRow(if (s.clamped)
            "The setting goes back to $current afterwards. Some frames reach the end of the camera's range and repeat a value."
        else "The setting goes back to $current afterwards.")
    }.onFailure { NoteRow(it.message ?: "Can't bracket now.", warning = true) }
    if (camera.isOpenEndedShutter) {
        NoteRow("Bracketing needs a timed shutter speed, not Bulb or Live modes.")
    }
    PinnedBottom {
        AccentButton(onClick = { camera.startBracket(plan) }, modifier = Modifier.fillMaxWidth(),
            enabled = set.isSuccess && camera.canBracket) { Text("Shoot ${set.getOrNull()?.values?.size ?: frames} frames") }
    }
}

private val focusFrameValues: List<Int> = (2..200).toList()

/** 305: the frame count large, Frames on a wheel, Step, what to do first; 307 when the camera does it itself. */
@Composable
private fun ColumnScope.FocusStackCards(
    camera: CameraModel, frames: Int, step: FocusStepSize, setFrames: (Int) -> Unit, setStep: (FocusStepSize) -> Unit, onDone: () -> Unit,
) {
    if (!camera.capabilities.focusDrive) {
        // 307: the camera does it itself.
        SolidHeadline("Use the camera's own\nfocus bracketing", 44.sp, Modifier.padding(vertical = 12.dp))
        Text(camera.focusStackUnavailable, color = Theme.secondary, fontSize = 15.sp, lineHeight = 21.sp)
        PinnedBottom {
            OutlineButton(onClick = onDone, modifier = Modifier.fillMaxWidth()) { Text("Done") }
        }
        return
    }
    BigNumber("$frames", Modifier.padding(bottom = 14.dp), caption = "frames, from where you focused towards infinity", size = 104.sp)
    Column(Modifier.fillMaxWidth().hairlineAbove()) {
        WheelValueRow("Frames", "2 to 200", focusFrameValues, frames, setFrames) { "$it" }
        SegRow("Step", FocusStepSize.entries.toList(), step, setStep, { it.title })
        NoteRow("Fine for macro and wide apertures, coarser for landscapes and stopped-down lenses. The stack stops early if the lens reaches infinity.")
    }
    SectionLabel("Before you start")
    NoteRow(camera.focusStackSetup)
    NoteRow("Not yet tried on a real camera of this brand: shoot a short stack first.", warning = true)
    if (camera.isOpenEndedShutter) {
        NoteRow("Focus stacking needs a timed shutter speed, not Bulb or Live modes.")
    }
    PinnedBottom {
        AccentButton(onClick = { camera.startFocusStack(frames, step) }, modifier = Modifier.fillMaxWidth(),
            enabled = camera.canFocusStack) { Text("Shoot $frames-frame focus stack") }
    }
}

/** 306: the frames as a fanned stack (focus) or a ring (exposure), "3 of 10", the bars, Cancel at the bottom. */
@Composable
private fun ColumnScope.BracketRunning(camera: CameraModel) {
    val b = camera.bracket
    Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) {
        if (b.isFocusStack) {
            FocusStackArt(b.done, max(1, b.total), Modifier.fillMaxWidth().height(230.dp))
        } else {
            ProgressRing("${b.done}", if (b.total > 0) b.done.toDouble() / b.total else 0.0, Modifier.padding(vertical = 10.dp),
                sub = "of ${b.total}")
        }
        BigNumber("${b.done} of ${b.total}", Modifier.padding(top = 8.dp),
            caption = b.label ?: if (b.isFocusStack) "Focus stack" else "Bracketing", size = 72.sp)
        FrameBars(b.done, b.total, Modifier.padding(vertical = 18.dp))
    }
    PinnedBottom {
        OutlineButton(onClick = { camera.cancelBracket() }, modifier = Modifier.fillMaxWidth()) { Text("Cancel") }
    }
}

// MARK: - Astro (308, 309)

private val astroLenses = listOf(8, 12, 17, 25)

/** One-tap night-sky setup: a night screen of its own, stars and the moon behind, the night palette throughout. */
@Composable
fun AstroSheet(camera: CameraModel, onDismiss: () -> Unit) {
    val scope = rememberCoroutineScope()
    var trails by remember { mutableStateOf(false) }
    // Starts from the mounted lens when it reports its focal length.
    var focal by remember {
        mutableDoubleStateOf(camera.liveInfo.focalLength?.toDouble() ?: camera.prefs.getFloat("astro.focalLength", 17f).toDouble())
    }
    var strict by remember { mutableStateOf(camera.prefs.getBoolean("astro.strict", true)) }
    var iso by remember { mutableIntStateOf(camera.prefs.getInt("astro.iso", 1600)) }
    fun save() = camera.prefs.edit().putFloat("astro.focalLength", focal.toFloat()).putBoolean("astro.strict", strict)
        .putInt("astro.iso", iso).apply()
    val plan = AstroPlan(focal, strict, iso, trails, cropFactor = camera.cropFactor)
    // A new plan (or opening the screen) clears the results of the last Apply.
    LaunchedEffect(trails, focal, strict, iso) {
        if (!camera.presetRunning && camera.presetResultsFor == PresetRecipe.ASTRO.id) camera.presetSteps = emptyList()
    }
    FeedbackOnChange(Feedback.Moment.SELECT, trails)
    val steps = if (camera.presetResultsFor == PresetRecipe.ASTRO.id && (camera.presetRunning || camera.presetSteps.isNotEmpty()))
        camera.presetSteps else camera.astroSteps(plan)
    val series = camera.trailsSeries(plan)
    val astroOn = camera.isPresetOn(PresetRecipe.ASTRO.id)

    FullScreenPage(onDismiss, background = Theme.astroBackground) {
        AstroSky(Modifier.fillMaxSize())
        Column(Modifier.fillMaxSize()) {
            Row(Modifier.fillMaxWidth().padding(start = 20.dp, end = 6.dp, top = 6.dp), verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                Text("Astro", color = Theme.astroText, fontSize = 15.sp, fontWeight = FontWeight.SemiBold,
                    modifier = Modifier.semantics { heading() })
                Spacer(Modifier.weight(1f))
                Row(Modifier.border(1.dp, Theme.astroText.copy(alpha = 0.3f), Pill)) {
                    AstroPill("Stars", !trails) { trails = false }
                    AstroPill("Star trails", trails) { trails = true }
                }
                CloseButton(onDismiss, Theme.astroText)
            }
            Column(Modifier.weight(1f).fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal = 20.dp).padding(bottom = 20.dp)) {
                AstroBigNumber(camera, plan, trails, series, Modifier.padding(top = 8.dp, bottom = 18.dp))
                FocalRuler(camera, focal) { focal = it; save() }
                if (!trails) {
                    Row(Modifier.padding(vertical = 12.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        astroLenses.forEach { mm -> AstroChip("$mm mm", focal.toInt() == mm) { focal = mm.toDouble(); save() } }
                    }
                    Column(Modifier.fillMaxWidth().hairlineAbove()) {
                        ToggleRow("Pin-sharp stars",
                            if (strict) "300 rule: stars stay round even at 100%." else "500 rule: longer exposures, slight streaks when zoomed in.",
                            strict, { strict = it; save() }, accent = Theme.astroAccent, textColor = Theme.astroText)
                        NoteRow(String.format(java.util.Locale.US, "Longest exposure before stars streak: %.1f s (crop factor %s)", plan.maxSeconds,
                            if (plan.cropFactor == Math.rint(plan.cropFactor)) plan.cropFactor.toInt().toString() else plan.cropFactor.toString()))
                    }
                }
                SegRow("ISO", listOf(800, 1600, 3200, 6400), iso, { iso = it; save() }, { "$it" }, accent = Theme.astroAccent)
                SectionLabel("Will set")
                steps.forEach { step -> StepResultRow(step, Modifier.fillMaxWidth().hairRow().padding(vertical = 10.dp)) }
                SectionLabel("Before you shoot")
                val tips = listOf(
                    "Put the camera on a tripod and turn image stabilisation off on the camera.",
                    "Focus manually on a bright star: switch the lens to MF and use the loupe.",
                    "Shoot from the phone so nothing touches the camera.",
                ) + when {
                    trails && camera.hasLiveComposite -> listOf("Set the base exposure for Live Composite on the camera (Shooting menu ▸ Composite Settings). Tap the shutter to start and again to stop.")
                    trails -> listOf("This camera has no Live Composite, so the app shoots a series of 30 s frames with the interval timer. Stack them afterwards (StarStaX, Sequator or Photoshop) for the trails.")
                    else -> emptyList()
                }
                tips.forEach { NoteRow(it, color = Theme.astroText.copy(alpha = 0.85f)) }
            }
            // Apply stays at the bottom without scrolling. It stays on after it's applied; tapping again
            // turns it off and puts the old settings back.
            Column(Modifier.fillMaxWidth()
                .background(Brush.verticalGradient(0f to Theme.astroBackground.copy(alpha = 0f), 0.3f to Theme.astroBackground))
                .padding(horizontal = 20.dp).padding(top = 10.dp, bottom = 8.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp)) {
                val ready = !camera.presetRunning && camera.mode == CameraMode.REC
                if (astroOn && series != null && !camera.interval.running) {
                    val minutes = (series.count * series.seconds / 60).roundToInt()
                    AstroButton(Theme.astroAccent, ready, onClick = {
                        camera.startTrailsSeries(series)
                        onDismiss()
                    }) {
                        AutoFitText("Start the series: ${series.count} frames, about $minutes min",
                            TextStyle(fontSize = 16.sp, fontWeight = FontWeight.SemiBold), Theme.astroBackground, Modifier.weight(1f, fill = false))
                    }
                }
                AstroButton(if (astroOn) Theme.green else Theme.astroText, ready, onClick = {
                    scope.launch {
                        if (astroOn) {
                            camera.undoPreset()
                            return@launch
                        }
                        camera.applyAstro(plan)
                        val allGood = camera.presetSteps.none { it.state is PresetStep.State.Failed }
                        // Trails without Live Composite stay open for Start the series.
                        if (allGood && camera.trailsSeries(plan) == null) {
                            camera.showToast("Astro is on")
                            delay(1100)
                            onDismiss()
                        }
                    }
                }) {
                    if (camera.presetRunning) CircularProgressIndicator(color = Theme.astroBackground, strokeWidth = 2.dp, modifier = Modifier.size(18.dp))
                    Text(if (camera.presetRunning) "Applying…" else if (astroOn) "Astro is on · Tap to turn off" else "Apply astro settings",
                        maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
            }
        }
    }
}

/** 308: the longest exposure; 309: the series (frames × seconds) or Live Composite. */
@Composable
private fun AstroBigNumber(camera: CameraModel, plan: AstroPlan, trails: Boolean, series: IntervalPlan?, modifier: Modifier) {
    if (trails) {
        if (series != null) {
            BigNumber("${series.count} × ${series.seconds.toInt()} s", modifier,
                caption = "A series for star trails, about ${(series.count * series.seconds / 60).roundToInt()} min",
                size = 64.sp, color = Theme.astroText, accent = Theme.astroAccent)
        } else {
            BigNumber(if (camera.hasLiveComposite) "Live Composite" else "30 s series", modifier.padding(horizontal = 24.dp),
                caption = "Star trails", size = 64.sp, color = Theme.astroText, accent = Theme.astroAccent)
        }
    } else {
        BigNumber("${plan.maxSeconds.roundToInt()} s", modifier, caption = "The longest exposure that keeps stars round",
            size = 132.sp, color = Theme.astroText, accent = Theme.astroAccent)
    }
}

private val rulerMarks = listOf(7, 17, 25, 35, 45)

/** 308: a ruler from 7 to 45 mm with a marker at the lens; drag or tap along it. */
@Composable
private fun FocalRuler(camera: CameraModel, focal: Double, onChange: (Double) -> Unit) {
    val lens = camera.liveInfo.focalLength
    val measurer = rememberTextMeasurer()
    val latestChange by rememberUpdatedState(onChange)
    FeedbackOnChange(Feedback.Moment.SELECT, focal.toInt())
    fun pick(x: Float, width: Int) {
        val mm = (7 + x / max(1, width) * 38).roundToInt().coerceIn(7, 45).toDouble()
        latestChange(mm)
    }
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text("Lens focal length", color = Theme.secondary, fontSize = 12.sp, modifier = Modifier.weight(1f))
            if (lens != null) {
                val fromLens = focal.toInt() == lens
                Text(if (fromLens) "From your lens ($lens mm)" else "Your lens reports $lens mm", fontSize = 12.sp,
                    color = if (fromLens) Theme.green else Theme.secondary,
                    modifier = Modifier.clickable(role = Role.Button) { latestChange(lens.toDouble()) })
            }
        }
        Canvas(Modifier.fillMaxWidth().height(52.dp)
            .pointerInput(Unit) { detectTapGestures { pick(it.x, size.width) } }
            .pointerInput(Unit) {
                detectHorizontalDragGestures(onDragStart = { pick(it.x, size.width) }) { change, _ ->
                    pick(change.position.x, size.width)
                    change.consume()
                }
            }
            .semantics {
                contentDescription = "Lens focal length"
                stateDescription = "${focal.toInt()} millimetres"
                customActions = listOf(
                    CustomAccessibilityAction("Increase") { latestChange((focal + 1).coerceAtMost(45.0)); true },
                    CustomAccessibilityAction("Decrease") { latestChange((focal - 1).coerceAtLeast(7.0)); true },
                )
            }) {
            val w = size.width
            fun x(mm: Double) = ((mm - 7) / 38).toFloat().coerceIn(0f, 1f) * w
            for (mm in 7..45) {
                val major = mm in rulerMarks
                drawLine(Theme.astroText.copy(alpha = if (major) 0.7f else 0.35f),
                    Offset(x(mm.toDouble()), if (major) 0f else 6.dp.toPx()), Offset(x(mm.toDouble()), 16.dp.toPx()), strokeWidth = 1.dp.toPx())
            }
            drawLine(Theme.astroAccent, Offset(x(focal), -4.dp.toPx()), Offset(x(focal), 22.dp.toPx()), strokeWidth = 2.5.dp.toPx())
            for (mm in rulerMarks) {
                val on = focal.toInt() == mm
                val layout = measurer.measure(if (mm == 17 || on) "$mm mm" else "$mm",
                    TextStyle(fontFamily = Theme.barlow, fontSize = if (on) 18.sp else 16.sp,
                        fontWeight = if (on) FontWeight.SemiBold else FontWeight.Medium, color = if (on) Theme.astroText else Theme.secondary))
                val cx = x(mm.toDouble()).coerceIn(12.dp.toPx(), w - 12.dp.toPx())
                drawText(layout, topLeft = Offset(cx - layout.size.width / 2f, 40.dp.toPx() - layout.size.height / 2f))
            }
        }
    }
}

/** Stars or Star trails, in the joined pill of the astro header. */
@Composable
private fun AstroPill(title: String, on: Boolean, onClick: () -> Unit) {
    Box(Modifier.heightIn(min = Theme.target).clickable(role = Role.RadioButton, onClick = onClick), contentAlignment = Alignment.Center) {
        Box(Modifier.height(36.dp).clip(Pill).background(if (on) Theme.astroText else Color.Transparent).padding(horizontal = 14.dp),
            contentAlignment = Alignment.Center) {
            Text(title, color = if (on) Theme.astroBackground else Theme.astroText, fontSize = 14.sp,
                fontWeight = if (on) FontWeight.SemiBold else FontWeight.Normal, maxLines = 1)
        }
    }
}

/** Astro's lens chips: light when chosen. */
@Composable
private fun AstroChip(title: String, on: Boolean, onClick: () -> Unit) {
    Box(Modifier.heightIn(min = Theme.target).clip(Pill)
        .background(if (on) Theme.astroText else Color.Transparent)
        .then(if (on) Modifier else Modifier.border(1.dp, Theme.astroText.copy(alpha = 0.3f), Pill))
        .clickable(role = Role.RadioButton, onClick = onClick).padding(horizontal = 16.dp), contentAlignment = Alignment.Center) {
        Text(title, color = if (on) Theme.astroBackground else Theme.astroText.copy(alpha = 0.8f), fontSize = 14.sp,
            fontWeight = if (on) FontWeight.SemiBold else FontWeight.Normal, maxLines = 1)
    }
}

/** Astro's main button: a 54 dp capsule in the night palette. */
@Composable
private fun AstroButton(fill: Color, enabled: Boolean, onClick: () -> Unit, content: @Composable RowScope.() -> Unit) {
    Row(Modifier.fillMaxWidth().heightIn(min = 54.dp).clip(Pill).background(fill.copy(alpha = if (enabled) 1f else 0.4f))
        .clickable(enabled = enabled, role = Role.Button, onClick = onClick).padding(horizontal = 20.dp),
        horizontalArrangement = Arrangement.spacedBy(10.dp, Alignment.CenterHorizontally), verticalAlignment = Alignment.CenterVertically) {
        CompositionLocalProvider(LocalContentColor provides Theme.astroBackground,
            LocalTextStyle provides TextStyle(fontSize = 16.sp, fontWeight = FontWeight.SemiBold)) { content() }
    }
}

/** The night sky behind Astro (308): near-black blue, scattered stars in the band at the top, a crescent moon top right. */
@Composable
private fun AstroSky(modifier: Modifier) {
    Canvas(modifier.clearAndSetSemantics {}) {
        drawRect(Theme.astroBackground)
        val rng = SeededRandom(7)
        repeat(38) {
            val x = (rng.next() * size.width).toFloat()
            val y = (40.dp.toPx() + rng.next() * size.height * 0.2).toFloat()
            val r = (0.5 + rng.next() * 1.1).toFloat().dp.toPx()
            drawCircle(Color.White.copy(alpha = (0.35 + rng.next() * 0.5).toFloat().coerceAtMost(1f)), r, Offset(x + r, y + r))
        }
        val moon = Offset(size.width - 46.dp.toPx(), 124.dp.toPx())
        drawCircle(Color(0xFFEEF1F7), 12.dp.toPx(), moon)
        drawCircle(Theme.astroBackground, 12.dp.toPx(), moon + Offset(-7.dp.toPx(), -4.dp.toPx()))
    }
}

/** A fixed sequence of pseudo-random numbers in 0 until 1, so the stars stay put between frames. */
private class SeededRandom(seed: Long) {
    private var state: Long = seed * 6364136223846793005L + 1442695040888963407L
    fun next(): Double {
        state = state * 6364136223846793005L + 1442695040888963407L
        return (state ushr 11).toDouble() / (1L shl 53).toDouble()
    }
}

/** One preset step and what happened: skipped steps read as notes (what to do on the camera), not errors. */
@Composable
fun StepResultRow(step: PresetStep, modifier: Modifier = Modifier) {
    Row(modifier, verticalAlignment = Alignment.Top, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        Box(Modifier.width(20.dp).padding(top = 2.dp), contentAlignment = Alignment.Center) {
            when (step.state) {
                PresetStep.State.Pending -> Icon(if (step.value == null) Icons.Outlined.Info else Icons.Outlined.Circle, null,
                    Modifier.size(18.dp), tint = if (step.value == null) Theme.tertiary else Theme.secondary)
                PresetStep.State.Running -> CircularProgressIndicator(Modifier.size(16.dp), color = Theme.accent, strokeWidth = 2.dp)
                PresetStep.State.Done -> Icon(Icons.Filled.CheckCircle, "Done", Modifier.size(18.dp), tint = Theme.green)
                is PresetStep.State.Failed -> Icon(Icons.Filled.Cancel, "Failed", Modifier.size(18.dp), tint = Theme.red)
                // Not an error: the caption says what to do on the camera instead.
                is PresetStep.State.Skipped -> Icon(Icons.Outlined.Info, null, Modifier.size(18.dp), tint = Theme.secondary)
            }
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(step.title, color = Theme.text, fontSize = 16.sp, fontWeight = FontWeight.Medium, modifier = Modifier.weight(1f))
                Text(step.value?.let { PropertyFormat.display(step.property, it) } ?: "–", style = Theme.num(18.sp, medium = true),
                    color = if (step.value == null) Theme.tertiary else Theme.secondary, maxLines = 1)
            }
            val caption = when (val st = step.state) {
                is PresetStep.State.Failed -> st.reason
                is PresetStep.State.Skipped -> st.reason
                else -> if (step.value == null) step.unavailable else step.detail
            }
            Text(caption, color = if (step.state is PresetStep.State.Failed) Theme.red else Theme.secondary, fontSize = 13.sp, lineHeight = 17.sp)
        }
    }
}

// MARK: - High Res (All settings and the log are AllSettingsScreen.kt and LogScreen.kt)


/**
 * High Res Shot can't be switched on over Wi-Fi, so this walks through it (312): the big number, caps
 * sections, numbered steps between hairlines, Done at the bottom.
 */
@Composable
fun HighResSheet(camera: CameraModel, onDismiss: () -> Unit) {
    ToolScreen("High Res Shot", onDismiss) {
        BigNumber("50 MP", Modifier.padding(bottom = 8.dp), caption = "8 sensor-shifted frames → 50 MP JPEG, 80 MP RAW", size = 120.sp)
        SectionLabel("Turn it on at the camera")
        NoteRow("Olympus cameras don't accept this setting over Wi-Fi. On the camera, open MENU ▸ Shooting Menu 2 ▸ High Res Shot ▸ On (or press the button you've assigned to it). A 0 s delay is fine when you shoot from the phone.")
        SectionLabel("Then")
        HighResStep(1, "Tripod, and nothing moving in the scene: wind, water and people smear.")
        HighResStep(2, "The camera limits High Res to slower ISOs and shorter exposures; check its screen.")
        HighResStep(3, "Tap the shutter here. The camera takes about a second to capture, then a few more to merge. The app waits for it.")
        HighResStep(4, "Open Card: High Res files show a 50 MP badge.")
        SectionLabel("For the night sky")
        NoteRow("Stars move between the 8 frames, so High Res suits landscapes and still subjects, not long star exposures. For astro, use the Astro preset and the interval timer to stack instead.")
        Text("Shown for ${camera.cameraName ?: "this camera"}.", color = Theme.tertiary, fontSize = 12.sp, modifier = Modifier.padding(top = 12.dp))
        PinnedBottom {
            OutlineButton(onClick = onDismiss, modifier = Modifier.fillMaxWidth()) { Text("Done") }
        }
    }
}

/** A numbered step: the first in an accent disc, the others in an outlined circle. */
@Composable
private fun HighResStep(n: Int, text: String) {
    Row(Modifier.fillMaxWidth().hairRow().padding(vertical = 10.dp).semantics(mergeDescendants = true) {},
        verticalAlignment = Alignment.Top, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
        Box(Modifier.size(30.dp).clip(CircleShape)
            .background(if (n == 1) Theme.accent else Color.Transparent)
            .then(if (n == 1) Modifier else Modifier.border(1.5.dp, Theme.tertiary, CircleShape)),
            contentAlignment = Alignment.Center) {
            Text("$n", style = Theme.num(18.sp), color = if (n == 1) Theme.onAccent else Theme.secondary)
        }
        Text(text, color = Theme.text, fontSize = 15.sp, fontWeight = FontWeight.Medium, lineHeight = 20.sp, modifier = Modifier.padding(top = 5.dp))
    }
}

// MARK: - Pocket mode (316)

/**
 * A black screen with a dim red read-out for long night sessions, the phone in a pocket or face up on
 * the ground: the time large in Barlow, what it is under it. The screen stays on, as always while
 * connected (Android, like iOS, cuts the app's network when it's backgrounded for long). Double-tap to leave.
 */
@Composable
fun PocketMode(camera: CameraModel, onDismiss: () -> Unit) {
    val activity = LocalContext.current as? Activity
    val view = LocalView.current
    val red = Color(0.75f, 0.05f, 0.05f)
    var showHint by remember { mutableStateOf(true) }
    val now = rememberNow(true, 500)
    BackHandler { onDismiss() }
    DisposableEffect(Unit) {
        val window = activity?.window
        val saved = window?.attributes?.screenBrightness
        window?.let { w -> w.attributes = w.attributes.also { it.screenBrightness = 0.02f } }
        // Nothing else lit: the status and navigation bars go too (a swipe brings them back for a moment).
        val bars = window?.let { WindowCompat.getInsetsController(it, view) }
        bars?.systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
        bars?.hide(WindowInsetsCompat.Type.systemBars())
        onDispose {
            window?.let { w -> w.attributes = w.attributes.also { it.screenBrightness = saved ?: WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_NONE } }
            bars?.show(WindowInsetsCompat.Type.systemBars())
        }
    }
    LaunchedEffect(Unit) {
        delay(8000)
        showHint = false
    }
    val headline = run {
        val started = camera.exposureStartedAt
        val duration = camera.exposureDuration
        val next = camera.interval.nextShotAt
        when {
            started != null && duration != null -> pocketClock((duration * 1000).toLong() - (now - started))
            started != null -> pocketClock(now - started)
            camera.isRecordingMovie && camera.movieStartedAt != null -> pocketClock(now - camera.movieStartedAt!!)
            camera.interval.running && next != null -> pocketClock(next - now)
            camera.bracket.running -> "${camera.bracket.done}/${camera.bracket.total}"
            else -> "—"
        }
    }
    val detail = when {
        camera.phase != ConnectionPhase.CONNECTED -> "Disconnected"
        camera.exposureStartedAt != null -> if (camera.exposureDuration != null) "exposure left" else "exposing · tap the shutter to stop"
        camera.isRecordingMovie -> "recording"
        camera.interval.running ->
            "next frame · ${camera.interval.done}${if (camera.interval.total > 0) " of ${camera.interval.total}" else ""} taken"
        camera.bracket.running -> "bracketing"
        else -> "Ready" + (camera.liveInfo.battery?.let { " · battery $it%" } ?: "")
    }
    Box(Modifier.fillMaxSize().background(Color.Black)
        .pointerInput(Unit) { detectTapGestures(onDoubleTap = { onDismiss() }) }
        .semantics { customActions = listOf(CustomAccessibilityAction("Leave pocket mode") { onDismiss(); true }) },
        contentAlignment = Alignment.Center) {
        Column(Modifier.fillMaxWidth().padding(horizontal = 30.dp), horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(6.dp)) {
            AutoFitText(headline, Theme.num(120.sp), red.copy(alpha = 0.7f), Modifier.fillMaxWidth())
            Text(detail, color = red.copy(alpha = 0.7f), fontSize = 15.sp, textAlign = TextAlign.Center)
        }
        Crossfade(showHint, Modifier.align(Alignment.BottomCenter).padding(horizontal = 30.dp).padding(bottom = 30.dp),
            animationSpec = tween(1500), label = "pocketHint") { hint ->
            Text(
                if (hint) "Keep the screen on: Android pauses the app's camera connection when the phone locks. For hours-long star trails, use the camera's own Live Composite or interval shooting instead.\n\nDouble-tap to leave."
                else "Double-tap to leave",
                color = red.copy(alpha = if (hint) 0.45f else 0.25f), fontSize = if (hint) 13.sp else 11.sp, textAlign = TextAlign.Center,
            )
        }
    }
}

/** "1:42", or "1:02:05" from an hour, rounded up to the second. */
private fun pocketClock(ms: Long): String {
    val total = ceil(max(0L, ms) / 1000.0).toLong()
    return if (total >= 3600) String.format(java.util.Locale.US, "%d:%02d:%02d", total / 3600, total % 3600 / 60, total % 60)
    else String.format(java.util.Locale.US, "%d:%02d", total / 60, total % 60)
}
