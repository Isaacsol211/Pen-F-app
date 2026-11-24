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

/** The top of the live screen: what's connected and how it's doing; the menu sits at the end. */
@Composable
fun InfoBar(camera: CameraModel, trailing: @Composable () -> Unit) {
    Row(Modifier.fillMaxWidth().heightIn(min = 52.dp).padding(start = 18.dp, end = 10.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        LiveDot(camera.liveViewRunning)
        Text((camera.cameraName ?: camera.brand.shortTitle).uppercase(), color = Color.White, fontSize = 15.sp,
            fontWeight = FontWeight.Black, letterSpacing = 1.2.sp, maxLines = 1, modifier = Modifier.weight(1f, fill = false))
        Spacer(Modifier.weight(1f))
        CameraStatusRow(camera)
        trailing()
    }
}

@Composable
fun LiveDot(live: Boolean) {
    Box(Modifier.size(8.dp).background(if (live) Theme.green else Theme.orange, CircleShape))
}

/** Live dot, battery and shots left, as a pill over the image (landscape). */
@Composable
fun StatusPill(camera: CameraModel) {
    Row(Modifier.heightIn(min = 36.dp).surface(Pill).padding(horizontal = 14.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        LiveDot(camera.liveViewRunning)
        CameraStatusRow(camera, Color.White)
    }
}

// MARK: - Exposure strip

private fun stripLabel(name: String) = when (name) {
    "focalvalue" -> "F-stop"
    "shutspeedvalue" -> "Shutter"
    "isospeedvalue" -> "ISO"
    "expcomp" -> "EV"
    "wbvalue" -> "WB"
    "drivemode" -> "Drive"
    "exposemovie" -> "Video"
    else -> name
}

/**
 * The readouts: one cell per value that matters, a small-caps label over a big monospaced value,
 * showing what the camera is actually using (AUTO when the camera chooses it). Tap a cell for its dial.
 */
@Composable
fun ExposureStrip(camera: CameraModel, active: String?, onSelect: (String?) -> Unit, compact: Boolean = false) {
    val haptics = LocalHapticFeedback.current
    val names = buildList {
        addAll(listOf("focalvalue", "shutspeedvalue", "isospeedvalue", "expcomp", "wbvalue", "drivemode"))
        if (camera.isMovieMode) add("exposemovie")
    }.filter { camera.properties[it] != null }
    if (names.isEmpty()) {
        Box(Modifier.fillMaxWidth().heightIn(min = if (compact) 50.dp else 58.dp).surface(RoundedCornerShape(18.dp), overImage = compact),
            contentAlignment = Alignment.Center) {
            Text(if (camera.mode == CameraMode.REC && !camera.isSwitchingMode) "Reading camera settings…" else "–",
                color = Theme.tertiary, fontSize = 13.sp)
        }
        return
    }
    Row(Modifier.fillMaxWidth().surface(RoundedCornerShape(18.dp), overImage = compact).padding(4.dp),
        verticalAlignment = Alignment.CenterVertically) {
        names.forEachIndexed { index, name ->
            if (index > 0) Hairline(Modifier.width(1.dp).height(26.dp))
            val property = camera.properties[name]?.let { camera.dialOptions(it) }
            val locked = property?.settable != true
            val selected = active == name
            val auto = locked && name != "drivemode"
            Column(
                Modifier.weight(1f).heightIn(min = if (compact) 50.dp else 58.dp)
                    .clip(RoundedCornerShape(14.dp))
                    .background(if (selected) Theme.accent.copy(alpha = 0.16f) else Color.Transparent)
                    .clickable(enabled = !camera.isBusyExposing) {
                        haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                        onSelect(if (selected) null else name)
                    }
                    .padding(horizontal = 4.dp)
                    .semantics { contentDescription = "${SettingSpec.spec(name)?.title ?: name}: ${camera.stripValue(name, property)}${if (auto) ", automatic" else ""}" },
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.Center,
            ) {
                CapsLabel(if (auto) "Auto" else stripLabel(name),
                    color = if (selected) Theme.accent else if (auto) Theme.accent.copy(alpha = 0.85f) else Theme.tertiary, size = 10.sp)
                val tint = if (selected) Theme.accent else if (auto) Theme.secondary else Color.White
                if (name == "drivemode") {
                    Icon(SettingSpec.optionIcon(name, property?.value ?: "") ?: Icons.Filled.GridView, null, Modifier.size(18.dp), tint = tint)
                } else {
                    AutoSizeText(camera.stripValue(name, property), tint, if (compact) 16 else 18)
                }
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

private fun modeTitle(mode: String) = when (mode.lowercase()) {
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

@Composable
fun ToolButton(item: ToolItem) {
    val haptics = LocalHapticFeedback.current
    val shape = RoundedCornerShape(14.dp)
    Box(
        Modifier.fillMaxWidth().heightIn(min = 66.dp).clip(shape)
            .background(if (item.on) Theme.accent.copy(alpha = 0.14f) else Theme.surfaceRaised, shape)
            .border(if (item.on) 1.5.dp else 1.dp, if (item.on) Theme.accent.copy(alpha = 0.85f) else Theme.stroke, shape)
            .clickable {
                haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                item.action()
            }
            .semantics { contentDescription = item.title + if (item.opens) "" else if (item.on) ", on" else ", off" },
        contentAlignment = Alignment.Center,
    ) {
        val tint = if (item.on) Theme.accent else Color.White
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Icon(item.icon, null, Modifier.size(22.dp), tint = tint)
            Text(item.title, color = tint, fontSize = 12.sp, fontWeight = FontWeight.SemiBold, maxLines = 1)
        }
        if (item.opens) {
            Icon(Icons.Filled.NorthEast, null, Modifier.align(Alignment.TopEnd).padding(7.dp).size(10.dp),
                tint = if (item.on) Theme.accent else Theme.tertiary)
        }
    }
}

/** Every tool, in two groups: shooting tools that open their own screen, and switches. */
@Composable
fun ToolsTray(tools: List<ToolItem>, columns: Int = 4) {
    Column(Modifier.fillMaxWidth().surface(RoundedCornerShape(24.dp)).padding(14.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        for ((title, items) in listOf("Shooting" to tools.filter { it.opens }, "Switches" to tools.filter { !it.opens })) {
            if (items.isEmpty()) continue
            CapsLabel(title, color = Theme.tertiary, modifier = Modifier.padding(start = 2.dp))
            items.chunked(columns).forEach { row ->
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    row.forEach { Box(Modifier.weight(1f)) { ToolButton(it) } }
                    repeat(columns - row.size) { Spacer(Modifier.weight(1f)) }
                }
            }
        }
    }
}

/** The aids you toggle most (grid, histogram, peaking, loupe, night), one tap away under the readouts. */
@Composable
fun QuickAidStrip(tools: List<ToolItem>) {
    Row(Modifier.fillMaxWidth().surface(RoundedCornerShape(18.dp)).padding(horizontal = 4.dp), verticalAlignment = Alignment.CenterVertically) {
        tools.forEachIndexed { index, item ->
            if (index > 0) Hairline(Modifier.width(1.dp).height(22.dp))
            val tint = if (item.on) Theme.accent else Color.White
            Column(
                Modifier.weight(1f).heightIn(min = 52.dp).clickable { item.action() }
                    .semantics { contentDescription = item.title + if (item.on) ", on" else ", off" },
                horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center,
            ) {
                Icon(item.icon, null, Modifier.size(19.dp), tint = tint)
                CapsLabel(if (item.id == "histogram") "Histo" else item.title, color = if (item.on) Theme.accent else Theme.tertiary, size = 10.sp)
                Box(Modifier.padding(top = 2.dp).width(18.dp).height(3.dp).background(if (item.on) Theme.accent else Color.Transparent, Pill))
            }
        }
    }
}

/** Round button next to the shutter that opens the tools tray (and shows interval progress). */
@Composable
fun ToolsButton(camera: CameraModel, open: Boolean, onToggle: () -> Unit) {
    Box(
        Modifier.size(58.dp).surface(CircleShape, tint = if (open) Theme.accent.copy(alpha = 0.22f) else null).clickable(onClick = onToggle)
            .semantics { contentDescription = if (open) "Close tools" else "Tools" },
        contentAlignment = Alignment.Center,
    ) {
        if (camera.interval.running) {
            Text(if (camera.interval.total == 0) "${camera.interval.done}" else "${camera.interval.done}/${camera.interval.total}",
                color = Theme.accent, style = monoStyle(11.sp, FontWeight.Bold))
        } else {
            Icon(if (open) Icons.Filled.Close else Icons.Filled.GridView, null, Modifier.size(22.dp))
        }
    }
}

/** The latest capture as a thumbnail (opens the card browser); a card icon before the first shot. */
@Composable
fun LastShotButton(camera: CameraModel, onClick: () -> Unit) {
    val enabled = !camera.isBusyExposing && !camera.interval.running && camera.capabilities.cardBrowser
    Box(
        Modifier.size(58.dp).surface(RoundedCornerShape(17.dp)).clickable(enabled = enabled, onClick = onClick)
            .alpha(if (enabled) 1f else 0.4f).padding(3.dp)
            .semantics { contentDescription = if (camera.lastShot == null) "Card" else "Last photo. Opens the card." },
        contentAlignment = Alignment.Center,
    ) {
        val shot = camera.lastShot
        if (shot != null) {
            Image(shot, null, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize().clip(RoundedCornerShape(14.dp)))
        } else {
            Icon(Icons.Filled.PhotoLibrary, null, Modifier.size(24.dp))
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
    val innerSize by animateDpAsState(if (pressed) 58.dp else 68.dp, label = "shutter")
    LaunchedEffect(camera.shotCounter) {
        if (camera.shotCounter > 0) haptics.performHapticFeedback(HapticFeedbackType.LongPress)
    }

    val progress: Float? = when {
        camera.interval.running && camera.interval.total > 0 -> camera.interval.done / camera.interval.total.toFloat()
        camera.bracket.running && camera.bracket.total > 0 -> camera.bracket.done / camera.bracket.total.toFloat()
        else -> null
    }

    Box(Modifier.size(104.dp), contentAlignment = Alignment.Center) {
        Canvas(Modifier.size(102.dp)) {
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
            Modifier.size(90.dp).border(4.dp, Color.White.copy(alpha = 0.9f), CircleShape)
                .alpha(if (enabled) 1f else 0.4f)
                .semantics { contentDescription = if (movie) (if (camera.isRecordingMovie) "Stop recording" else "Record movie") else "Shutter" }
                .pointerInput(enabled, movie, camera.isOpenEndedShutter) {
                    awaitEachGesture {
                        awaitFirstDown()
                        if (!enabled) return@awaitEachGesture
                        pressed = true
                        val openEnded = camera.isOpenEndedShutter
                        val isMovie = camera.isMovieMode
                        if (!openEnded && !isMovie) scope.launch { camera.shutterPressed() }
                        waitForUpOrCancellation()
                        pressed = false
                        when {
                            isMovie -> scope.launch { camera.toggleMovie() }
                            openEnded -> scope.launch { camera.toggleOpenExposure() }
                            else -> scope.launch { camera.shutterReleased() }
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
                    if (movie) Theme.red else if (camera.isShooting) Theme.accent else Color.White, CircleShape))
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
