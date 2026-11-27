package com.apexcommerce.shutterlink.ui

import androidx.compose.animation.core.animateDpAsState
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.snapping.rememberSnapFlingBehavior
import androidx.compose.foundation.gestures.waitForUpOrCancellation
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Battery1Bar
import androidx.compose.material.icons.filled.Battery3Bar
import androidx.compose.material.icons.filled.Battery5Bar
import androidx.compose.material.icons.filled.BatteryAlert
import androidx.compose.material.icons.filled.BatteryFull
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Collections
import androidx.compose.material.icons.filled.GridView
import androidx.compose.material.icons.filled.NorthEast
import androidx.compose.material.icons.filled.PhotoLibrary
import androidx.compose.material.icons.filled.Thermostat
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.material.icons.filled.Tune
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.apexcommerce.shutterlink.R
import com.apexcommerce.shutterlink.camera.CameraMode
import com.apexcommerce.shutterlink.camera.CameraModel
import com.apexcommerce.shutterlink.camera.PropertyFormat
import com.apexcommerce.shutterlink.camera.cancelBracket
import com.apexcommerce.shutterlink.camera.stripValue
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.filter
import kotlinx.coroutines.launch
import kotlin.math.ceil
import kotlin.math.max
import kotlin.math.min

// Camera-app style controls (port of HomeControls.swift / Instruments.swift / RemoteView.swift parts).

/** Battery, shots left and warnings. */
@Composable
fun CameraStatusRow(camera: CameraModel, color: Color = Theme.secondary) {
    val info = camera.liveInfo
    Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
        info.battery?.let { battery ->
            val icon = when {
                battery < 13 -> Icons.Filled.BatteryAlert
                battery < 38 -> Icons.Filled.Battery1Bar
                battery < 63 -> Icons.Filled.Battery3Bar
                battery < 88 -> Icons.Filled.Battery5Bar
                else -> Icons.Filled.BatteryFull
            }
            val tint = if (battery <= 15) Theme.red else color
            Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.semantics { contentDescription = "Camera battery $battery percent" }) {
                Icon(icon, null, Modifier.size(16.dp).rotate(90f), tint = tint)
                Text("$battery%", color = tint, style = monoStyle(13.sp))
            }
        }
        info.shotsRemaining?.let { shots ->
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp),
                modifier = Modifier.semantics { contentDescription = "$shots shots left on the card" }) {
                Icon(Icons.Filled.Collections, null, Modifier.size(15.dp), tint = color)
                Text("$shots", color = color, style = monoStyle(13.sp))
            }
        }
        if (info.temperatureWarning) Icon(Icons.Filled.Thermostat, "Camera is hot", Modifier.size(16.dp), tint = Theme.orange)
    }
}

/** The top of the live screen: what's connected and how it's doing, like the info line on a camera's rear screen. */
@Composable
fun InfoBar(camera: CameraModel, trailing: @Composable () -> Unit) {
    Row(Modifier.fillMaxWidth().heightIn(min = Theme.target).padding(start = 20.dp, end = 6.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Row(Modifier.weight(1f, fill = false).semantics(mergeDescendants = true) {
            contentDescription = "${camera.cameraName ?: "Camera"}, ${if (camera.liveViewRunning) "live" else "live view off"}"
        }, verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            LiveDot(camera.liveViewRunning)
            Text(camera.cameraName ?: camera.brand.shortTitle, color = Theme.text, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, maxLines = 1)
        }
        Spacer(Modifier.weight(1f))
        CameraStatusRow(camera)
        trailing()
    }
}

@Composable
fun LiveDot(live: Boolean) {
    Box(Modifier.size(7.dp).background(if (live) Theme.green else Theme.accent, CircleShape))
}

/** Live dot, the camera's name (landscape) and the status, as a pill over the image. */
@Composable
fun StatusPill(camera: CameraModel, showsName: Boolean = false) {
    Row(Modifier.heightIn(min = 36.dp).surface(Pill).padding(horizontal = 14.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        LiveDot(camera.liveViewRunning)
        if (showsName) Text(camera.cameraName ?: camera.brand.shortTitle, color = Theme.text, fontSize = 13.sp, fontWeight = FontWeight.SemiBold, maxLines = 1)
        CameraStatusRow(camera)
    }
}

// MARK: - Exposure strip

/** Where to change the mode on a body whose mode dial the phone can't turn. */
const val MODE_DIAL_HINT = "Turn the mode dial on the camera to change the mode."

/** The values that get a place in the row under the picture; white balance, drive and quality are the small line. */
fun stripItems(camera: CameraModel): List<String> = buildList {
    addAll(listOf("takemode", "focalvalue", "shutspeedvalue", "isospeedvalue", "expcomp"))
    if (camera.isMovieMode) add("exposemovie")
}.filter { camera.properties[it] != null }

/** What the row shows for a value: f/5.6, ISO 400, the mode's short name… */
fun stripText(name: String, camera: CameraModel): String {
    val property = camera.properties[name]?.let { camera.dialOptions(it) }
    val raw = camera.stripValue(name, property)
    return when (name) {
        "focalvalue" -> when {
            raw.firstOrNull()?.isDigit() == true -> "f/$raw"
            // Live view reports "F1.8": written the design's way, f/1.8.
            raw.startsWith("F") && raw.drop(1).firstOrNull()?.isDigit() == true -> "f/" + raw.drop(1)
            else -> raw
        }
        "isospeedvalue" -> if (raw.firstOrNull()?.isDigit() == true) "ISO $raw" else raw
        "takemode" -> modeTitle(property?.value ?: raw)
        else -> raw
    }
}

private val valueGrey = Color(0xFFC9C5BA)

/**
 * The row of values under the picture (mode, aperture, shutter, ISO, EV): what the camera is actually
 * using, in Barlow, the selected one in the accent. Tap one and the dial below becomes its dial.
 * Centred with even gaps, as designed; it only narrows when the values don't fit.
 */
@Composable
fun ExposureStrip(camera: CameraModel, selected: String?, onSelect: (String) -> Unit, modifier: Modifier = Modifier) {
    val view = androidx.compose.ui.platform.LocalView.current
    val names = stripItems(camera)
    val measurer = androidx.compose.ui.text.rememberTextMeasurer()
    val style = Theme.num(20.sp)
    BoxWithConstraints(modifier.fillMaxWidth().padding(horizontal = 8.dp)) {
        val texts = names.map { stripText(it, camera) }
        val density = androidx.compose.ui.platform.LocalDensity.current
        val natural = with(density) {
            texts.sumOf { measurer.measure(it, style).size.width + 8.dp.roundToPx() } + (22.dp * (names.size - 1).coerceAtLeast(0)).roundToPx()
        }
        val fits = natural <= constraints.maxWidth
        Row(Modifier.fillMaxWidth(), horizontalArrangement = if (fits) Arrangement.spacedBy(22.dp, Alignment.CenterHorizontally) else Arrangement.Start,
            verticalAlignment = Alignment.CenterVertically) {
            names.forEachIndexed { i, name ->
                val property = camera.properties[name]?.let { camera.dialOptions(it) }
                val locked = property?.settable != true
                val isSelected = selected == name
                val cell = (if (fits) Modifier else Modifier.weight(1f)).heightIn(min = Theme.target)
                val color = if (isSelected) Theme.accent else if (locked) Theme.secondary else valueGrey
                val textStyle = Theme.num(20.sp, medium = !isSelected).copy(letterSpacing = 0.6.sp)
                if (name == "takemode" && locked) {
                    // A body with a physical mode dial the phone can't turn (LUMIX): a plain label; a tap says where to change it.
                    Box(cell.clickable { camera.showToast(MODE_DIAL_HINT) }.padding(horizontal = 4.dp)
                        .semantics { contentDescription = "Mode: ${texts[i]}. $MODE_DIAL_HINT" }, contentAlignment = Alignment.Center) {
                        AutoFitText(texts[i], textStyle, Theme.secondary)
                    }
                } else {
                    Box(cell.clickable(enabled = !camera.isBusyExposing) {
                        Feedback.play(Feedback.Moment.SELECT, view)
                        onSelect(name)
                    }.padding(horizontal = 4.dp)
                        .semantics { contentDescription = "${SettingSpec.spec(name)?.title ?: name}: ${texts[i]}" },
                        contentAlignment = Alignment.Center) {
                        AutoFitText(texts[i], textStyle, color)
                    }
                }
            }
        }
    }
}

/**
 * The small line under the picture: white balance, drive and quality. White balance picks its dial;
 * drive and quality open a panel of options. Above it, the aids that are on ("Grid on"…), tap to turn off (212).
 */
@Composable
fun SettingLine(camera: CameraModel, active: String?, aids: List<ToolItem>, onSelect: (String) -> Unit, openSheet: (String) -> Unit) {
    Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) {
        val on = aids.filter { it.on }
        if (on.isNotEmpty()) {
            Row(Modifier.height(22.dp), horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
                if (on.size <= 3) on.forEach { item ->
                    Text("${item.title} on", color = Theme.text.copy(alpha = 0.85f), fontSize = 12.sp, maxLines = 1,
                        modifier = Modifier.clickable(onClick = item.action).semantics { contentDescription = "${item.title} on. Turns it off" })
                } else Text("${on.size} aids on", color = Theme.secondary, fontSize = 13.sp)
            }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
            listOf("wbvalue", "drivemode", "quality").filter { camera.properties[it] != null }.forEach { name ->
                val property = camera.properties[name]?.let { camera.dialOptions(it) }
                val isOn = active == name
                val value = camera.stripValue(name, property)
                Text((if (name == "wbvalue") "WB " else "") + value, color = if (isOn) Theme.accent else Theme.secondary, fontSize = 13.sp,
                    fontWeight = if (isOn) FontWeight.SemiBold else FontWeight.Normal, maxLines = 1,
                    modifier = Modifier.heightIn(min = 30.dp).clickable(enabled = !camera.isBusyExposing) {
                        if (name == "wbvalue") onSelect(name) else openSheet(name)
                    }.padding(horizontal = 10.dp, vertical = 6.dp)
                        .semantics { contentDescription = "${SettingSpec.spec(name)?.title ?: name}: $value" })
            }
        }
    }
}

/** A one-line monospaced value that shrinks to fit (1/4000 in a narrow cell). */
@Composable
fun AutoSizeText(text: String, color: Color, maxSp: Int) {
    BoxWithConstraints(contentAlignment = Alignment.Center) {
        // Roughly 0.62 em per monospaced character.
        val fit = (maxWidth.value / (text.length.coerceAtLeast(1) * 0.62f)).coerceAtMost(maxSp.toFloat()).coerceAtLeast(9f)
        Text(text, color = color, style = monoStyle(fit.sp), maxLines = 1, softWrap = false)
    }
}

// MARK: - Mode carousel

fun modeTitle(mode: String) = when (mode.lowercase()) {
    "iauto" -> "AUTO"
    "movie" -> "VIDEO"
    else -> mode.uppercase()
}

/** Swipe or tap AUTO · P · A · S · M · VIDEO; the mode under the index mark is the one set. */
@Composable
fun ModeCarousel(camera: CameraModel, vertical: Boolean = false) {
    val property = camera.properties["takemode"] ?: return
    val options = property.options
    val current = property.value
    val enabled = !camera.isBusyExposing && property.settable
    val state = rememberLazyListState(initialFirstVisibleItemIndex = options.indexOf(current).coerceAtLeast(0))
    val fling = rememberSnapFlingBehavior(state)
    val scope = rememberCoroutineScope()
    val haptics = LocalHapticFeedback.current
    var committed by remember { mutableStateOf(current) }
    val itemSize = if (vertical) Theme.target else 70.dp
    val centered by remember(options) { derivedStateOf { state.itemAtCenter() } }
    // Every mode is a hard detent, like the mode dial on the camera.
    FeedbackOnChange(Feedback.Moment.DIAL_STOP, centered)
    fun commit(mode: String) {
        if (mode == committed || mode == current) return
        committed = mode
        scope.launch { camera.setProperty("takemode", mode) }
    }
    LaunchedEffect(options) {
        snapshotFlow { centered }.distinctUntilChanged().collect {
            if (state.isScrollInProgress) haptics.performHapticFeedback(HapticFeedbackType.LongPress)
        }
    }
    LaunchedEffect(options) {
        snapshotFlow { state.isScrollInProgress }.distinctUntilChanged().filter { !it }.collect {
            centered?.let { options.getOrNull(it) }?.let(::commit)
        }
    }
    LaunchedEffect(current, options) {
        committed = current
        val i = options.indexOf(current)
        if (i >= 0 && i != centered && !state.isScrollInProgress) state.animateScrollToItem(i)
    }
    BoxWithConstraints(
        if (vertical) Modifier.width(84.dp).heightIn(max = 140.dp) else Modifier.fillMaxWidth().height(Theme.target),
        contentAlignment = Alignment.Center,
    ) {
        val pad = (((if (vertical) maxHeight else maxWidth) - itemSize) / 2).coerceAtLeast(0.dp)
        val item: @Composable (Int, String) -> Unit = { index, mode ->
            val isCurrent = index == (centered ?: options.indexOf(current))
            Box(
                (if (vertical) Modifier.height(itemSize).width(80.dp) else Modifier.width(itemSize).height(Theme.target))
                    .clickable(enabled = enabled) {
                        scope.launch { state.animateScrollToItem(index) }
                        commit(mode)
                    },
                contentAlignment = Alignment.Center,
            ) {
                Text(modeTitle(mode), color = if (isCurrent) Theme.accent else Theme.tertiary, fontSize = 15.sp,
                    fontWeight = FontWeight.Black, letterSpacing = 1.6.sp, modifier = Modifier.scale(if (isCurrent) 1.1f else 1f))
            }
        }
        if (vertical) {
            LazyColumn(state = state, flingBehavior = fling, userScrollEnabled = enabled,
                contentPadding = PaddingValues(vertical = pad), modifier = Modifier.fillMaxSize()) {
                itemsIndexed(options) { i, m -> item(i, m) }
            }
            Text("▶", color = Theme.accent, fontSize = 7.sp, modifier = Modifier.align(Alignment.CenterStart))
        } else {
            LazyRow(state = state, flingBehavior = fling, userScrollEnabled = enabled,
                contentPadding = PaddingValues(horizontal = pad), modifier = Modifier.fillMaxSize()) {
                itemsIndexed(options) { i, m -> item(i, m) }
            }
            Text("▲", color = Theme.accent, fontSize = 7.sp, modifier = Modifier.align(Alignment.BottomCenter).offset(y = 4.dp))
        }
    }
}

// MARK: - Tools

data class ToolItem(
    val id: String,
    val icon: ImageVector,
    val title: String,
    val on: Boolean,
    /** Opens its own screen (Astro, Interval…) rather than switching something on and off. */
    val opens: Boolean = false,
    val action: () -> Unit,
)

/** The design's drawn line icon for a tool (converted from the iOS asset catalog), or null. */
fun toolIcon(id: String): Int? = when (id) {
    "presets" -> R.drawable.tool_presets
    "astro" -> R.drawable.tool_astro
    "interval" -> R.drawable.tool_interval
    "bracket" -> R.drawable.tool_bracket
    "focusstack" -> R.drawable.tool_focusstack
    "nd" -> R.drawable.tool_nd
    "motion" -> R.drawable.tool_motion
    "highres" -> R.drawable.tool_highres
    "pocket" -> R.drawable.tool_pocket
    "video" -> R.drawable.tool_video
    "loupe" -> R.drawable.tool_loupe
    "night" -> R.drawable.tool_night
    "histogram" -> R.drawable.tool_histogram
    "grid" -> R.drawable.tool_grid
    "peaking" -> R.drawable.tool_peaking
    "geotag" -> R.drawable.tool_geotag
    "tap", "touchshutter" -> R.drawable.tool_tap
    else -> null
}

/** A tool in the Tools panel: a rounded tile, filled with the accent when on; ↗ on tools that open a screen. */
@Composable
fun ToolButton(item: ToolItem) {
    val view = androidx.compose.ui.platform.LocalView.current
    val shape = RoundedCornerShape(18.dp)
    val tint = if (item.on) Theme.onAccent else Theme.text
    Box(
        Modifier.fillMaxWidth().heightIn(min = 78.dp).clip(shape)
            .background(if (item.on) Theme.accent else Theme.surface.copy(alpha = 0.9f), shape)
            .then(if (item.on) Modifier else Modifier.border(1.dp, Theme.outline, shape))
            .clickable {
                Feedback.play(Feedback.Moment.SELECT, view)
                item.action()
            }
            .semantics { contentDescription = item.title + if (item.opens) ". Opens ${item.title}" else if (item.on) ", on" else ", off" },
        contentAlignment = Alignment.Center,
    ) {
        Column(Modifier.padding(vertical = 6.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)) {
            val drawn = toolIcon(item.id)
            if (drawn != null) Icon(androidx.compose.ui.res.painterResource(drawn), null, Modifier.size(26.dp), tint = tint)
            else Icon(item.icon, null, Modifier.size(24.dp), tint = tint)
            Text(item.title, color = tint, fontSize = 12.sp, fontWeight = FontWeight.SemiBold, maxLines = 1)
        }
        if (item.opens) {
            Text("↗", color = if (item.on) Theme.onAccent else Theme.secondary, fontSize = 12.sp,
                modifier = Modifier.align(Alignment.TopEnd).padding(top = 4.dp, end = 8.dp))
        }
    }
}

/** Every tool, in two groups: shooting tools that open their own screen, and switches. */
@Composable
fun ToolsTray(tools: List<ToolItem>, columns: Int = 4) {
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        for ((title, items) in listOf("Shooting" to tools.filter { it.opens }, "Switches" to tools.filter { !it.opens })) {
            if (items.isEmpty()) continue
            CapsLabel(title, color = Theme.secondary, modifier = Modifier.padding(start = 4.dp, top = 14.dp))
            items.chunked(columns).forEach { row ->
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    row.forEach { Box(Modifier.weight(1f)) { ToolButton(it) } }
                    repeat(columns - row.size) { Spacer(Modifier.weight(1f)) }
                }
            }
        }
    }
}

/** Round button next to the shutter that opens the tools (and shows interval progress). */
@Composable
fun ToolsButton(camera: CameraModel, open: Boolean, onToggle: () -> Unit) {
    Box(Modifier.size(58.dp).clickable(onClick = onToggle).semantics { contentDescription = if (open) "Close tools" else "Tools" },
        contentAlignment = Alignment.Center) {
        Box(Modifier.size(48.dp).border(1.dp, if (camera.interval.running) Theme.accent else Theme.text.copy(alpha = 0.4f), CircleShape),
            contentAlignment = Alignment.Center) {
            if (camera.interval.running) {
                Text(if (camera.interval.total == 0) "${camera.interval.done}" else "${camera.interval.done}/${camera.interval.total}",
                    color = Theme.accent, style = Theme.num(16.sp), maxLines = 1)
            } else {
                Icon(if (open) Icons.Filled.Close else Icons.Filled.Tune, null, Modifier.size(22.dp), tint = Theme.text)
            }
        }
    }
}

/** The latest capture as a thumbnail (opens the card browser); a card icon before the first shot. */
@Composable
fun LastShotButton(camera: CameraModel, onClick: () -> Unit) {
    val enabled = !camera.isBusyExposing && !camera.interval.running && camera.capabilities.cardBrowser
    val shape = RoundedCornerShape(12.dp)
    Box(
        Modifier.size(58.dp).clickable(enabled = enabled, onClick = onClick).alpha(if (enabled) 1f else 0.4f)
            .semantics { contentDescription = if (camera.lastShot == null) "Card" else "Last photo. Opens the card." },
        contentAlignment = Alignment.Center,
    ) {
        Box(Modifier.size(48.dp).clip(shape).border(1.dp, Theme.text.copy(alpha = 0.4f), shape), contentAlignment = Alignment.Center) {
            val shot = camera.lastShot
            if (shot != null) Image(shot, null, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize())
            else Icon(Icons.Filled.PhotoLibrary, null, Modifier.size(22.dp), tint = Theme.text)
        }
    }
}

/** Ticks every `periodMs` while `active`, for countdowns and clocks. */
@Composable
fun rememberNow(active: Boolean, periodMs: Long = 250): Long {
    var now by remember { mutableLongStateOf(System.currentTimeMillis()) }
    LaunchedEffect(active, periodMs) {
        while (active) {
            now = System.currentTimeMillis()
            delay(periodMs)
        }
    }
    return now
}

fun clock(ms: Long): String {
    val s = max(0L, ms / 1000)
    return String.format(java.util.Locale.US, "%d:%02d", s / 60, s % 60)
}

/**
 * The shutter does everything: single, burst (hold), movie record, long exposures with a countdown
 * ring, and Bulb / Live modes with tap-to-stop and an elapsed timer (port of ShutterButton).
 */
@Composable
fun ShutterButton(camera: CameraModel) {
    val scope = rememberCoroutineScope()
    val haptics = LocalHapticFeedback.current
    var pressed by remember { mutableStateOf(false) }
    val enabled = camera.mode == CameraMode.REC && !camera.isSwitchingMode && !camera.bracket.running
    val movie = camera.isMovieMode
    val started = camera.exposureStartedAt
    val duration = camera.exposureDuration
    val openRunning = camera.isShooting && camera.isOpenEndedShutter
    val now = rememberNow(started != null || camera.isRecordingMovie, if (started != null && duration == null) 33 else 250)
    val innerSize by animateDpAsState(if (pressed) 50.dp else 58.dp, label = "shutter")
    val view = androidx.compose.ui.platform.LocalView.current

    val progress: Float? = when {
        camera.interval.running && camera.interval.total > 0 -> camera.interval.done / camera.interval.total.toFloat()
        camera.bracket.running && camera.bracket.total > 0 -> camera.bracket.done / camera.bracket.total.toFloat()
        else -> null
    }

    Box(Modifier.size(104.dp), contentAlignment = Alignment.Center) {
        Canvas(Modifier.size(90.dp)) {
            val stroke = 5.dp.toPx()
            if (progress != null) {
                drawArc(Theme.accent, -90f, 360f * progress, false, style = Stroke(4.dp.toPx(), cap = StrokeCap.Round))
            }
            if (started != null) {
                val elapsed = (now - started) / 1000.0
                if (duration != null) {
                    drawArc(Theme.accent, -90f, 360f * min(1.0, elapsed / duration).toFloat(), false, style = Stroke(stroke, cap = StrokeCap.Round))
                } else {
                    drawArc(Theme.red, (elapsed * 140).toFloat() - 90f, 0.22f * 360f, false, style = Stroke(stroke, cap = StrokeCap.Round))
                }
            }
        }
        Box(
            Modifier.size(74.dp).border(if (pressed) 4.5.dp else 3.dp, Theme.text, CircleShape)
                .alpha(if (enabled) 1f else 0.4f)
                .semantics { contentDescription = if (movie) (if (camera.isRecordingMovie) "Stop recording" else "Record movie") else "Shutter" }
                .pointerInput(enabled, movie, camera.isOpenEndedShutter) {
                    awaitEachGesture {
                        awaitFirstDown()
                        if (!enabled) return@awaitEachGesture
                        pressed = true
                        val openEnded = camera.isOpenEndedShutter
                        val isMovie = camera.isMovieMode
                        if (!openEnded && !isMovie) {
                            Feedback.play(Feedback.Moment.PRESS, view)
                            scope.launch { camera.shutterPressed() }
                        }
                        waitForUpOrCancellation()
                        pressed = false
                        when {
                            isMovie -> scope.launch { camera.toggleMovie() }
                            openEnded -> scope.launch { camera.toggleOpenExposure() }
                            else -> {
                                Feedback.play(Feedback.Moment.SHUTTER, view)
                                scope.launch { camera.shutterReleased() }
                            }
                        }
                    }
                },
            contentAlignment = Alignment.Center,
        ) {
            when {
                started != null && duration != null -> {
                    val left = ceil(duration - (now - started) / 1000.0).toInt().coerceAtLeast(0)
                    Text(
                        if (left >= 60) clock(left * 1000L) else if (left > 0) "$left" else "NR",
                        color = Theme.accent, style = monoStyle(if (left >= 600) 18.sp else if (left >= 60) 22.sp else 28.sp),
                        textAlign = TextAlign.Center,
                    )
                }
                openRunning || camera.isRecordingMovie ->
                    Box(Modifier.size(if (pressed) 26.dp else 30.dp).background(Theme.red, RoundedCornerShape(8.dp)))
                else -> Box(Modifier.size(innerSize).background(
                    if (movie) Theme.red else if (camera.isShooting) Theme.accent else Theme.text, CircleShape))
            }
        }
        val clockStart = if (camera.isRecordingMovie) camera.movieStartedAt else if (openRunning) started else null
        if (clockStart != null) {
            Text(clock(now - clockStart), color = Theme.red, style = monoStyle(11.sp, FontWeight.Bold),
                modifier = Modifier.align(Alignment.TopCenter).offset(y = (-14).dp).surface(Pill).padding(horizontal = 6.dp, vertical = 2.dp))
        } else if (camera.bracket.running) {
            Text("${camera.bracket.done + 1}/${camera.bracket.total}${camera.bracket.label?.let { " · $it" } ?: ""} ✕",
                color = Theme.accent, style = monoStyle(11.sp, FontWeight.Bold),
                modifier = Modifier.align(Alignment.TopCenter).offset(y = (-14).dp).surface(Pill).clickable { camera.cancelBracket() }
                    .padding(horizontal = 6.dp, vertical = 2.dp))
        }
    }
}

/** Readable title for a property in lists. */
fun propertyTitle(name: String) = SettingSpec.spec(name)?.title ?: PropertyFormat.title(name)
