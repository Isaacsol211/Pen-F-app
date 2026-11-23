package com.apexcommerce.shutterlink.ui

import android.app.Activity
import android.view.WindowManager
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Lightbulb
import androidx.compose.material.icons.filled.Remove
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Stop
import androidx.compose.material.icons.filled.Timer
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.apexcommerce.shutterlink.camera.AstroPlan
import com.apexcommerce.shutterlink.camera.BracketPlan
import com.apexcommerce.shutterlink.camera.BracketTarget
import com.apexcommerce.shutterlink.camera.CameraMode
import com.apexcommerce.shutterlink.camera.CameraModel
import com.apexcommerce.shutterlink.camera.IntervalPlan
import com.apexcommerce.shutterlink.camera.PresetStep
import com.apexcommerce.shutterlink.camera.PropertyFormat
import com.apexcommerce.shutterlink.camera.applyAstro
import com.apexcommerce.shutterlink.camera.astroSteps
import com.apexcommerce.shutterlink.camera.bracketSet
import com.apexcommerce.shutterlink.camera.canBracket
import com.apexcommerce.shutterlink.camera.offsetLabel
import com.apexcommerce.shutterlink.camera.startBracket
import com.apexcommerce.shutterlink.camera.startInterval
import com.apexcommerce.shutterlink.camera.stopInterval
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

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

@Composable
private fun Chip(text: String, on: Boolean, enabled: Boolean = true, onClick: () -> Unit) {
    Text(text, color = if (on) Color.Black else Color.White, fontSize = 14.sp, fontWeight = FontWeight.SemiBold,
        modifier = Modifier.background(if (on) Theme.accent else Theme.surfaceRaised, Pill)
            .clickable(enabled = enabled, onClick = onClick).padding(horizontal = 14.dp, vertical = 9.dp))
}

@Composable
private fun Stepper(label: String, value: String, onMinus: () -> Unit, onPlus: () -> Unit) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        Text(label, fontSize = 16.sp, modifier = Modifier.weight(1f))
        Text(value, style = monoStyle(16.sp), color = Theme.secondary)
        SurfaceButton(onClick = onMinus, circle = true) { Icon(Icons.Filled.Remove, "Less", Modifier.size(18.dp)) }
        SurfaceButton(onClick = onPlus, circle = true) { Icon(Icons.Filled.Add, "More", Modifier.size(18.dp)) }
    }
}

// MARK: - Interval timer

/** Interval timer (time-lapse / star stacking) setup and progress. */
@Composable
fun IntervalSheet(camera: CameraModel, onDismiss: () -> Unit) {
    var count by remember { mutableIntStateOf(camera.prefs.getInt("interval.count", 60)) }
    var seconds by remember { mutableDoubleStateOf(camera.prefs.getFloat("interval.seconds", 20f).toDouble()) }
    fun save() = camera.prefs.edit().putInt("interval.count", count).putFloat("interval.seconds", seconds.toFloat()).apply()
    Sheet("Interval timer", onDismiss) {
        if (camera.interval.running) {
            val now = rememberNow(true, 500)
            Card {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(18.dp)) {
                    Box(Modifier.size(86.dp), contentAlignment = Alignment.Center) {
                        CircularProgressIndicator(
                            progress = { if (camera.interval.total > 0) camera.interval.done / camera.interval.total.toFloat() else 0f },
                            modifier = Modifier.size(86.dp), color = Theme.accent, strokeWidth = 8.dp, trackColor = Color.White.copy(alpha = 0.15f))
                        Text("${camera.interval.done}", style = monoStyle(22.sp))
                    }
                    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        Text(if (camera.interval.total == 0) "Shooting until stopped" else "${camera.interval.done} of ${camera.interval.total}",
                            fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
                        val next = camera.interval.nextShotAt
                        Text(if (next != null) "Next shot in ${((next - now + 999) / 1000).coerceAtLeast(0)} s" else "Exposing…",
                            color = Theme.secondary, style = monoStyle(15.sp, FontWeight.Normal))
                    }
                }
                SurfaceButton(onClick = { camera.stopInterval() }, modifier = Modifier.fillMaxWidth()) {
                    Icon(Icons.Filled.Stop, null, tint = Theme.red)
                    Text("Stop", color = Theme.red, fontWeight = FontWeight.SemiBold)
                }
            }
        } else {
            Card {
                Text("Presets", fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    for ((title, c, s) in listOf(Triple("Star stack", 30, 22.0), Triple("Time-lapse", 240, 5.0), Triple("Trails", 120, 32.0))) {
                        Chip(title, count == c && seconds == s) { count = c; seconds = s; save() }
                    }
                }
            }
            Card {
                Stepper("Every", "${seconds.toInt()} s",
                    { seconds = (seconds - if (seconds <= 10) 1 else 5).coerceAtLeast(1.0); save() },
                    { seconds = (seconds + if (seconds < 10) 1 else 5).coerceAtMost(600.0); save() })
                Stepper("Frames", if (count == 0) "Until stopped" else "$count",
                    { count = (count - if (count <= 20) 1 else 10).coerceAtLeast(0); save() },
                    { count = (count + if (count < 20) 1 else 10).coerceAtMost(9999); save() })
                val summary = if (count == 0) "Shoots every ${seconds.toInt()} s until you tap Stop." else {
                    val total = (count * seconds).toLong()
                    val duration = if (total >= 3600) "${total / 3600} h ${total % 3600 / 60} min" else if (total >= 60) "${total / 60} min ${total % 60} s" else "$total s"
                    "$count frames over about $duration. At 25 fps that's a ${String.format(java.util.Locale.US, "%.1f", count / 25.0)} s clip."
                }
                Text(summary, color = Theme.secondary, fontSize = 13.sp)
                val shutter = PropertyFormat.seconds(camera.properties["shutspeedvalue"]?.value ?: "")
                if (shutter != null && shutter + 1 > seconds) {
                    Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        Icon(Icons.Filled.Warning, null, Modifier.size(16.dp), tint = Theme.orange)
                        Text("The interval is shorter than the exposure (${shutter.toInt()} s). Shots will run back to back.", color = Theme.orange, fontSize = 13.sp)
                    }
                }
            }
            AccentButton(onClick = { camera.startInterval(IntervalPlan(count, seconds)) }, modifier = Modifier.fillMaxWidth(),
                enabled = camera.mode == CameraMode.REC && !camera.isOpenEndedShutter) {
                Icon(Icons.Filled.Timer, null)
                Text("Start")
            }
            if (camera.isOpenEndedShutter) {
                Text("Interval shooting needs a timed shutter speed, not Live Composite/Time/Bulb.", color = Theme.secondary, fontSize = 13.sp)
            }
        }
    }
}

// MARK: - Bracketing

@Composable
fun BracketSheet(camera: CameraModel, onDismiss: () -> Unit) {
    var frames by remember { mutableIntStateOf(camera.prefs.getInt("bracket.frames", 3)) }
    var thirds by remember { mutableIntStateOf(camera.prefs.getInt("bracket.thirds", 3)) }
    var target by remember { mutableStateOf(BracketTarget.entries.getOrElse(camera.prefs.getInt("bracket.target", 0)) { BracketTarget.AUTO }) }
    fun save() = camera.prefs.edit().putInt("bracket.frames", frames).putInt("bracket.thirds", thirds).putInt("bracket.target", target.ordinal).apply()
    val plan = BracketPlan(frames, thirds, target)
    val set = camera.bracketSet(plan)
    Sheet("Exposure bracketing", onDismiss, footer = {
        AccentButton(onClick = { camera.startBracket(plan); onDismiss() }, modifier = Modifier.fillMaxWidth(),
            enabled = set.isSuccess && camera.canBracket) { Text("Shoot ${set.getOrNull()?.values?.size ?: frames} frames") }
    }) {
        Card {
            CapsLabel("Frames")
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) { listOf(3, 5, 7, 9).forEach { n -> Chip("$n", frames == n) { frames = n; save() } } }
            CapsLabel("Step")
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                listOf(1 to "⅓", 2 to "⅔", 3 to "1", 6 to "2").forEach { (t, label) -> Chip("$label EV", thirds == t) { thirds = t; save() } }
            }
            CapsLabel("Varies")
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) { BracketTarget.entries.forEach { t -> Chip(t.title, target == t) { target = t; save() } } }
        }
        Card {
            set.onSuccess { s ->
                Text("Will shoot", fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
                s.values.forEachIndexed { i, v ->
                    Row {
                        Text("${offsetLabel(s.offsets[i])} EV", style = monoStyle(14.sp), modifier = Modifier.weight(1f))
                        Text(PropertyFormat.display(s.property, v), style = monoStyle(14.sp), color = Theme.secondary)
                    }
                }
                if (s.clamped) Text("Some frames hit the end of the camera's range and repeat a value.", color = Theme.orange, fontSize = 13.sp)
                Text("The setting goes back to where it was afterwards. No focus bracketing: there's no Wi-Fi command to step the focus.",
                    color = Theme.secondary, fontSize = 13.sp)
            }.onFailure { Text(it.message ?: "Can't bracket now.", color = Theme.orange, fontSize = 14.sp) }
        }
    }
}

// MARK: - Astro

@Composable
fun AstroSheet(camera: CameraModel, onDismiss: () -> Unit) {
    val scope = rememberCoroutineScope()
    var trails by remember { mutableStateOf(false) }
    var focal by remember { mutableDoubleStateOf((camera.liveInfo.focalLength ?: 17).toDouble()) }
    var strict by remember { mutableStateOf(true) }
    var iso by remember { mutableIntStateOf(1600) }
    val plan = AstroPlan(focal, strict, iso, trails)
    val steps = if (camera.presetSteps.isNotEmpty() && camera.presetRunning) camera.presetSteps else camera.astroSteps(plan)
    val canTrails = camera.properties["shutspeedvalue"]?.options?.any { it.lowercase() == "livecomp" } == true
    Sheet("Astro preset", onDismiss, footer = {
        AccentButton(onClick = {
            scope.launch {
                camera.applyAstro(plan)
                if (camera.presetSteps.none { it.state is PresetStep.State.Failed }) {
                    camera.showToast("Astro settings applied")
                    delay(1100)
                    onDismiss()
                }
            }
        }, modifier = Modifier.fillMaxWidth(), enabled = !camera.presetRunning && camera.mode == CameraMode.REC) {
            Text(if (camera.presetRunning) "Applying…" else "Apply to camera")
        }
    }) {
        if (canTrails) {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Chip("Stars", !trails) { trails = false }
                Chip("Star trails", trails) { trails = true }
            }
        }
        Card {
            Stepper("Lens focal length", "${focal.toInt()} mm", { focal = (focal - 1).coerceAtLeast(7.0) }, { focal = (focal + 1).coerceAtMost(300.0) })
            if (camera.liveInfo.focalLength != null) Text("Read from the lens.", color = Theme.tertiary, fontSize = 12.sp)
            if (!trails) {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Chip("300 rule (sharp)", strict) { strict = true }
                    Chip("500 rule", !strict) { strict = false }
                }
                Text(String.format(java.util.Locale.US, "Longest exposure before stars streak: %.1f s", plan.maxSeconds), color = Theme.secondary, fontSize = 13.sp)
            }
            CapsLabel("ISO")
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) { listOf(800, 1600, 3200, 6400).forEach { v -> Chip("$v", iso == v) { iso = v } } }
        }
        Card {
            Text("Will set", fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
            steps.forEach { step -> StepLine(step) }
        }
        Card {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Filled.Lightbulb, null, Modifier.size(18.dp), tint = Theme.accent)
                Text("Before you shoot", fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
            }
            listOf(
                "Put the camera on a tripod and turn image stabilisation off on the camera.",
                "Focus manually on a bright star: switch the lens to MF and use the loupe.",
                "Shoot from the phone so nothing touches the camera.",
            ).plus(if (trails) listOf("Set the base exposure for Live Composite on the camera (Shooting menu ▸ Composite Settings). Tap the shutter to start and again to stop.") else emptyList())
                .forEach { Text("• $it", color = Theme.secondary, fontSize = 14.sp) }
        }
    }
}

@Composable
private fun StepLine(step: PresetStep) {
    Row(verticalAlignment = Alignment.Top, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        val (mark, color) = when (step.state) {
            PresetStep.State.Done -> "✓" to Theme.green
            PresetStep.State.Running -> "…" to Theme.accent
            is PresetStep.State.Failed -> "✕" to Theme.red
            is PresetStep.State.Skipped -> "–" to Theme.tertiary
            PresetStep.State.Pending -> "•" to Theme.tertiary
        }
        Text(mark, color = color, style = monoStyle(15.sp))
        Column(Modifier.weight(1f)) {
            Text(step.title, fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
            val reason = (step.state as? PresetStep.State.Failed)?.reason ?: (step.state as? PresetStep.State.Skipped)?.reason
            Text(reason ?: step.detail, color = if (step.state is PresetStep.State.Failed) Theme.red else Theme.secondary, fontSize = 13.sp)
        }
        Text(step.value?.let { PropertyFormat.display(step.property, it) } ?: "–", style = monoStyle(14.sp), color = Theme.accent)
    }
}

// MARK: - All settings, log, High Res

@Composable
fun AllSettingsSheet(camera: CameraModel, onDismiss: () -> Unit) {
    var open by remember { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()
    Sheet("All camera settings", onDismiss) {
        if (camera.properties.isEmpty()) Text("No settings read yet.", color = Theme.secondary)
        camera.properties.values.sortedBy { it.name }.forEach { p ->
            val shown = camera.dialOptions(p)
            Column(Modifier.fillMaxWidth().surface(RoundedCornerShape(16.dp))
                .clickable(enabled = p.settable && p.options.size > 1) { open = if (open == p.name) null else p.name }
                .padding(14.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) {
                        Text(propertyTitle(p.name), fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
                        Text(p.name, color = Theme.tertiary, fontSize = 11.sp)
                    }
                    Text(PropertyFormat.display(p.name, shown.value), style = monoStyle(14.sp), color = if (p.settable) Theme.accent else Theme.secondary)
                }
                if (open == p.name) {
                    shown.options.chunked(4).forEach { row ->
                        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                            row.forEach { o ->
                                Box(Modifier.weight(1f)) {
                                    Chip(PropertyFormat.display(p.name, o), o == shown.value) { scope.launch { camera.setProperty(p.name, o) } }
                                }
                            }
                            repeat(4 - row.size) { Spacer(Modifier.weight(1f)) }
                        }
                    }
                }
            }
        }
    }
}

@Composable
fun LogSheet(camera: CameraModel, onDismiss: () -> Unit) {
    val clipboard = LocalClipboardManager.current
    Sheet("Request log", onDismiss) {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            SurfaceButton(onClick = {
                val text = buildString {
                    appendLine("Shutterlink Android · ${camera.cameraName ?: camera.brand.title} · ${camera.connectionHost}")
                    camera.log.forEach { appendLine(it.line) }
                    if (camera.rawCommandList.isNotEmpty()) appendLine("\n${camera.rawCommandList.take(20_000)}")
                }
                clipboard.setText(AnnotatedString(text))
                camera.showToast("Log copied")
            }) { Text("Copy all") }
            SurfaceButton(onClick = { camera.clearLog() }) { Text("Clear") }
        }
        if (camera.log.isEmpty()) Text("No requests yet.", color = Theme.secondary)
        SelectionContainer {
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                camera.log.asReversed().take(300).forEach { entry ->
                    Text(entry.line, style = monoStyle(11.sp, FontWeight.Normal), color = if (entry.ok || entry.method == "PTP") Theme.secondary else Theme.red)
                }
            }
        }
    }
}

@Composable
fun HighResSheet(camera: CameraModel, onDismiss: () -> Unit) {
    Sheet("High Res Shot", onDismiss) {
        Card {
            Text("8 sensor-shifted frames → 50 MP JPEG, 80 MP RAW", fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
            Text("Olympus cameras don't accept this setting over Wi-Fi. On the camera, open MENU ▸ Shooting Menu 2 ▸ High Res Shot ▸ On (or press the button you've assigned to it). A 0 s delay is fine when you shoot from the phone.",
                color = Theme.secondary, fontSize = 14.sp)
        }
        Card {
            Text("Stars move between the 8 frames, so High Res suits landscapes and still subjects, not long star exposures. For astro, use the Astro preset and the interval timer to stack instead.",
                color = Theme.secondary, fontSize = 14.sp)
        }
        Text("Shown for ${camera.cameraName ?: "this camera"}.", color = Theme.tertiary, fontSize = 12.sp)
    }
}

// MARK: - Pocket mode

/**
 * A black screen with a dim red countdown for long night sessions. The screen stays on (Android,
 * like iOS, cuts the app's network when it's backgrounded for long). Double-tap to leave.
 */
@Composable
fun PocketMode(camera: CameraModel, onDismiss: () -> Unit) {
    val activity = LocalContext.current as? Activity
    val red = Color(0.75f, 0.05f, 0.05f)
    var showHint by remember { mutableStateOf(true) }
    val now = rememberNow(true, 500)
    BackHandler { onDismiss() }
    DisposableEffect(Unit) {
        val window = activity?.window
        val saved = window?.attributes?.screenBrightness
        window?.let { w -> w.attributes = w.attributes.also { it.screenBrightness = 0.02f } }
        window?.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        onDispose {
            window?.let { w -> w.attributes = w.attributes.also { it.screenBrightness = saved ?: WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_NONE } }
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
            started != null && duration != null -> clock(((duration * 1000) - (now - started)).toLong().coerceAtLeast(0))
            started != null -> clock(now - started)
            camera.isRecordingMovie && camera.movieStartedAt != null -> clock(now - camera.movieStartedAt!!)
            camera.interval.running && next != null -> clock((next - now).coerceAtLeast(0))
            camera.bracket.running -> "${camera.bracket.done}/${camera.bracket.total}"
            else -> "—"
        }
    }
    val detail = when {
        camera.interval.running -> "Interval ${camera.interval.done}${if (camera.interval.total > 0) "/${camera.interval.total}" else ""}"
        camera.exposureStartedAt != null -> "Exposing"
        camera.isRecordingMovie -> "Recording"
        else -> camera.cameraName ?: ""
    }
    Box(Modifier.fillMaxSize().background(Color.Black).pointerInput(Unit) { detectTapGestures(onDoubleTap = { onDismiss() }) },
        contentAlignment = Alignment.Center) {
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(headline, color = red.copy(alpha = 0.55f), style = monoStyle(64.sp, FontWeight.Light))
            Text(detail, color = red.copy(alpha = 0.45f), fontSize = 15.sp)
        }
        Text(
            if (showHint) "Keep the screen on: Android pauses the app's camera connection when the phone locks. For hours-long star trails, use the camera's own Live Composite or interval shooting instead.\n\nDouble-tap to leave."
            else "Double-tap to leave",
            color = red.copy(alpha = if (showHint) 0.45f else 0.25f), fontSize = if (showHint) 13.sp else 11.sp, textAlign = TextAlign.Center,
            modifier = Modifier.align(Alignment.BottomCenter).padding(30.dp),
        )
    }
}
