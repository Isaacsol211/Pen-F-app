package com.apexcommerce.shutterlink.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.snapping.rememberSnapFlingBehavior
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.BurstMode
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.CropSquare
import androidx.compose.material.icons.filled.FlashOn
import androidx.compose.material.icons.filled.LockOpen
import androidx.compose.material.icons.filled.PanTool
import androidx.compose.material.icons.filled.Timer
import androidx.compose.material.icons.filled.Tune
import androidx.compose.material.icons.automirrored.filled.VolumeOff
import androidx.compose.material.icons.filled.WaterDrop
import androidx.compose.material.icons.filled.WbAuto
import androidx.compose.material.icons.filled.WbCloudy
import androidx.compose.material.icons.filled.WbIncandescent
import androidx.compose.material.icons.filled.WbIridescent
import androidx.compose.material.icons.filled.WbShade
import androidx.compose.material.icons.filled.WbSunny
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.layout.layout
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.apexcommerce.shutterlink.camera.CameraModel
import com.apexcommerce.shutterlink.camera.CameraProperty
import com.apexcommerce.shutterlink.camera.PropertyFormat
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.filter
import kotlinx.coroutines.launch
import kotlin.math.abs
import kotlin.math.ln
import kotlin.math.roundToInt

/** How a setting is presented on the main screen (port of SettingSpec). */
data class SettingSpec(val name: String, val title: String, val dial: Boolean) {
    companion object {
        /** Everything the PEN-F lets an app change over Wi-Fi, in shooting order. */
        val all = listOf(
            SettingSpec("takemode", "Mode", false),
            SettingSpec("focalvalue", "Aperture", true),
            SettingSpec("shutspeedvalue", "Shutter", true),
            SettingSpec("isospeedvalue", "ISO", true),
            SettingSpec("expcomp", "EV", true),
            SettingSpec("wbvalue", "White balance", true),
            SettingSpec("drivemode", "Drive", false),
            SettingSpec("colorphase", "Hue", true),
            SettingSpec("exposemovie", "Movie", false),
        )

        fun spec(name: String) = all.firstOrNull { it.name == name }

        /** Icon for an individual option in a grid or on the WB dial. */
        fun optionIcon(name: String, value: String): ImageVector? = when (name) {
            "wbvalue" -> when (value) {
                "0" -> Icons.Filled.WbAuto
                "18" -> Icons.Filled.WbSunny
                "16" -> Icons.Filled.WbShade
                "17" -> Icons.Filled.WbCloudy
                "20" -> Icons.Filled.WbIncandescent
                "35" -> Icons.Filled.WbIridescent
                "64" -> Icons.Filled.WaterDrop
                "23" -> Icons.Filled.FlashOn
                "256", "257", "258", "259" -> Icons.Filled.PanTool
                "512" -> Icons.Filled.Tune
                else -> null
            }
            "drivemode" -> when {
                value.contains("selftimer") -> Icons.Filled.Timer
                value.contains("continuous") -> Icons.Filled.BurstMode
                value.startsWith("silent") -> Icons.AutoMirrored.Filled.VolumeOff
                else -> Icons.Filled.CropSquare
            }
            else -> null
        }
    }
}

/** The options for one setting: a swipe dial or a grid of buttons. Locked settings explain why. */
@Composable
fun OptionPanel(camera: CameraModel, spec: SettingSpec, onClose: () -> Unit) {
    val raw = camera.properties[spec.name] ?: return
    val property = camera.dialOptions(raw)
    val scope = rememberCoroutineScope()
    val ruler = property.settable && spec.dial
    Column(
        Modifier.fillMaxWidth().surface(RoundedCornerShape(26.dp))
            .padding(horizontal = 14.dp, vertical = if (ruler) 8.dp else 14.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        if (!ruler) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                CapsLabel(spec.title, color = Theme.accent)
                Spacer(Modifier.weight(1f))
                Text(PropertyFormat.display(spec.name, property.value), style = monoStyle(15.sp))
                SurfaceButton(onClick = onClose, circle = true) {
                    Icon(Icons.Filled.Close, "Close ${spec.title}", Modifier.size(16.dp))
                }
            }
        }
        when {
            !property.settable -> LockedExplanation(camera, spec)
            spec.name == "shutspeedvalue" -> ShutterOptions(camera, property)
            spec.dial -> ValueDial(property) { value -> scope.launch { camera.setProperty(spec.name, value) } }
            else -> OptionGrid(property) { value -> scope.launch { camera.setProperty(spec.name, value) } }
        }
    }
}

@Composable
private fun LockedExplanation(camera: CameraModel, spec: SettingSpec) {
    val scope = rememberCoroutineScope()
    val mode = camera.properties["takemode"]?.value ?: ""
    val unlock = when (spec.name) {
        "focalvalue" -> "Switch to A (aperture priority)" to "A"
        "shutspeedvalue" -> "Switch to S (shutter priority)" to "S"
        "expcomp" -> "Switch to A" to "A"
        else -> null
    }
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(
            if (mode.isEmpty()) "This can't be changed from the phone on this camera."
            else "The camera sets this itself in ${PropertyFormat.display("takemode", mode)} mode.",
            color = Theme.secondary, fontSize = 15.sp,
        )
        if (unlock != null && camera.properties["takemode"]?.options?.contains(unlock.second) == true) {
            SurfaceButton(onClick = { scope.launch { camera.setProperty("takemode", unlock.second) } }) {
                Icon(Icons.Filled.LockOpen, null, Modifier.size(18.dp))
                Text(unlock.first, fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
            }
        }
    }
}

/** Tappable grid for settings with a handful of named values (mode, drive, movie exposure…). */
@Composable
fun OptionGrid(property: CameraProperty, onSelect: (String) -> Unit) {
    val haptics = LocalHapticFeedback.current
    LazyVerticalGrid(
        columns = GridCells.Adaptive(92.dp),
        modifier = Modifier.heightIn(max = 190.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        items(property.options) { option ->
            val selected = option == property.value
            Column(
                Modifier.heightIn(min = 52.dp)
                    .surface(RoundedCornerShape(14.dp), tint = if (selected) Theme.accent else null)
                    .clickable {
                        haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                        onSelect(option)
                    }
                    .padding(6.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.Center,
            ) {
                val color = if (selected) Color.Black else Color.White
                SettingSpec.optionIcon(property.name, option)?.let { Icon(it, null, Modifier.size(18.dp), tint = color) }
                Text(PropertyFormat.display(property.name, option), color = color, fontSize = 12.sp,
                    fontWeight = FontWeight.SemiBold, textAlign = TextAlign.Center, maxLines = 2)
            }
        }
    }
}

/** Shutter: Live Composite / Live Time / Live Bulb / Bulb as chips, timed speeds on the dial. */
@Composable
fun ShutterOptions(camera: CameraModel, property: CameraProperty) {
    val scope = rememberCoroutineScope()
    var lastTimed by remember { mutableStateOf(camera.prefs.getString("lastTimedShutter", "250") ?: "250") }
    val liveModes = property.options.filter { PropertyFormat.isOpenEnded(it) }
    val timedOptions = property.options.filter { !PropertyFormat.isOpenEnded(it) }
    val timedValue = when {
        property.value in timedOptions -> property.value
        lastTimed in timedOptions -> lastTimed
        else -> timedOptions.firstOrNull() ?: property.value
    }
    val timed = property.copy(options = timedOptions, value = timedValue)
    val current = if (PropertyFormat.isOpenEnded(property.value)) property.value else "timed"
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        if (liveModes.isNotEmpty()) {
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                (listOf("timed") + liveModes).forEach { choice ->
                    val on = choice == current
                    Text(
                        if (choice == "timed") "Timed" else PropertyFormat.display("shutspeedvalue", choice),
                        color = if (on) Color.Black else Color.White.copy(alpha = 0.8f), fontSize = 12.sp, fontWeight = FontWeight.SemiBold,
                        modifier = Modifier.background(if (on) Theme.accent else Color.White.copy(alpha = 0.1f), Pill)
                            .clickable {
                                val value = if (choice == "timed") timed.value else choice
                                scope.launch { camera.setProperty("shutspeedvalue", value) }
                            }
                            .padding(horizontal = 10.dp, vertical = 5.dp),
                    )
                }
            }
        }
        if (current == "timed") {
            ValueDial(timed) { value ->
                lastTimed = value
                camera.prefs.edit().putString("lastTimedShutter", value).apply()
                scope.launch { camera.setProperty("shutspeedvalue", value) }
            }
        } else {
            BulbTimerControl(camera)
            Text(
                when {
                    current == "livecomp" -> "Live Composite stacks only new light: star trails without over-exposing the sky. " +
                        if (camera.bulbTimer > 0) "It stops by itself after ${CameraModel.durationLabel(camera.bulbTimer)}." else "Tap the shutter to start, again to stop."
                    camera.bulbTimer > 0 -> "The exposure stops by itself after ${CameraModel.durationLabel(camera.bulbTimer)}, or when you tap the shutter."
                    else -> "The exposure runs until you tap the shutter again."
                },
                color = Theme.secondary, fontSize = 13.sp,
            )
        }
    }
}

/** Timed Bulb: Off, 30 s, 1–10 min. */
@Composable
fun BulbTimerControl(camera: CameraModel) {
    val choices = listOf(0.0, 30.0, 60.0, 120.0, 300.0, 600.0)
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        CapsLabel("Stop after", color = Theme.tertiary)
        choices.forEach { seconds ->
            val on = camera.bulbTimer == seconds
            Text(
                if (seconds == 0.0) "Off" else CameraModel.durationLabel(seconds),
                color = if (on) Color.Black else Color.White.copy(alpha = 0.85f), fontSize = 12.sp, fontWeight = FontWeight.SemiBold,
                modifier = Modifier.background(if (on) Theme.accent else Color.White.copy(alpha = 0.1f), Pill)
                    .clickable(enabled = !camera.isShooting) { camera.changeBulbTimer(seconds) }
                    .padding(horizontal = 8.dp, vertical = 5.dp),
            )
        }
    }
}

/**
 * iPhone Camera–style exposure ruler (port of ValueDial): fine ticks for every step, taller
 * labelled ticks on full stops, a fixed centre marker, the live value above, and a haptic tick for
 * every step crossed. The value is sent to the camera when scrolling stops.
 */
@Composable
fun ValueDial(property: CameraProperty, onCommit: (String) -> Unit) {
    val usesIcons = property.name == "wbvalue"
    val spacing: Dp = if (usesIcons) 46.dp else if (property.name == "shutspeedvalue") 13.dp else 11.dp
    val options = property.options
    val startIndex = options.indexOf(property.value).coerceAtLeast(0)
    val state = rememberLazyListState(initialFirstVisibleItemIndex = startIndex)
    val fling = rememberSnapFlingBehavior(state)
    val haptics = LocalHapticFeedback.current
    var committed by remember(property.name) { mutableStateOf(property.value) }
    val scope = rememberCoroutineScope()

    // The item under the centre marker.
    val centeredIndex by remember(options) { derivedStateOf { state.itemAtCenter() ?: startIndex } }
    val current = options.getOrNull(centeredIndex) ?: property.value

    // Haptic per step, firmer on full stops.
    LaunchedEffect(options) {
        snapshotFlow { centeredIndex }.distinctUntilChanged().collect { i ->
            if (state.isScrollInProgress) {
                haptics.performHapticFeedback(
                    if (isMajor(property.name, options.getOrNull(i) ?: "")) HapticFeedbackType.LongPress else HapticFeedbackType.TextHandleMove,
                )
            }
        }
    }
    // Commit when scrolling stops.
    LaunchedEffect(options) {
        snapshotFlow { state.isScrollInProgress }.distinctUntilChanged().filter { !it }.collect {
            val value = options.getOrNull(centeredIndex) ?: return@collect
            if (value != committed) {
                committed = value
                onCommit(value)
            }
        }
    }
    // The camera may adjust or reject a value (or a preset changed it): follow it.
    LaunchedEffect(property.value) {
        committed = property.value
        val i = options.indexOf(property.value)
        if (i >= 0 && i != centeredIndex && !state.isScrollInProgress) state.animateScrollToItem(i)
    }

    Column(Modifier.fillMaxWidth().padding(vertical = 4.dp), verticalArrangement = Arrangement.spacedBy(8.dp),
        horizontalAlignment = Alignment.CenterHorizontally) {
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
            CapsLabel(PropertyFormat.title(property.name), color = Theme.secondary, size = 10.sp)
            Text(PropertyFormat.display(property.name, current), color = Theme.accent, style = monoStyle(14.sp))
        }
        BoxWithConstraints(Modifier.fillMaxWidth().height(if (usesIcons) 40.dp else 30.dp)) {
            val side = (maxWidth - spacing) / 2
            LazyRow(
                state = state,
                flingBehavior = fling,
                contentPadding = PaddingValues(horizontal = side.coerceAtLeast(0.dp)),
                modifier = Modifier.fillMaxWidth()
                    .graphicsLayer { compositingStrategy = CompositingStrategy.Offscreen }
                    .drawWithContent {
                        drawContent()
                        drawRect(
                            Brush.horizontalGradient(0f to Color.Transparent, 0.22f to Color.Black, 0.78f to Color.Black, 1f to Color.Transparent),
                            blendMode = BlendMode.DstIn,
                        )
                    },
            ) {
                itemsIndexed(options) { index, option ->
                    Tick(property.name, option, option == current, usesIcons, Modifier.width(spacing).clickable {
                        scope.launch { state.animateScrollToItem(index) }
                        committed = option
                        onCommit(option)
                    })
                }
            }
            // Centre marker.
            Box(Modifier.align(Alignment.TopCenter).width(2.dp).height(if (usesIcons) 20.dp else 22.dp)
                .background(Theme.accent, Pill))
        }
    }
}

/** The item nearest the middle of the list: the one under a dial's centre marker. */
fun LazyListState.itemAtCenter(): Int? {
    val info = layoutInfo
    val center = (info.viewportStartOffset + info.viewportEndOffset) / 2
    return info.visibleItemsInfo.minByOrNull { abs(it.offset + it.size / 2 - center) }?.index
}

@Composable
private fun Tick(name: String, option: String, selected: Boolean, usesIcons: Boolean, modifier: Modifier) {
    val major = isMajor(name, option)
    Column(modifier.height(if (usesIcons) 40.dp else 30.dp), horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Box(Modifier.width(if (major) 1.5.dp else 1.dp).height(if (usesIcons) 12.dp else if (major) 14.dp else 8.dp)
            .background(if (selected) Theme.accent else Color.White.copy(alpha = if (major) 0.85f else 0.4f), Pill))
        if (usesIcons) {
            Icon(SettingSpec.optionIcon(name, option) ?: Icons.Filled.Tune, PropertyFormat.display(name, option),
                Modifier.size(16.dp), tint = if (selected) Theme.accent else Color.White.copy(alpha = 0.7f))
        } else if (major) {
            Text(shortLabel(name, option), color = if (selected) Theme.accent else Color.White.copy(alpha = 0.6f),
                style = monoStyle(8.sp, FontWeight.Medium), maxLines = 1, softWrap = false,
                modifier = Modifier.wrapContentWidthUnbounded())
        }
    }
}

/** Lets a label overflow its narrow tick column (like SwiftUI's fixedSize), centred on the tick. */
private fun Modifier.wrapContentWidthUnbounded(): Modifier = this.layout { measurable, constraints ->
    val placeable = measurable.measure(constraints.copy(minWidth = 0, maxWidth = Constraints.Infinity))
    val width = placeable.width.coerceAtMost(constraints.maxWidth).coerceAtLeast(constraints.minWidth)
    layout(width, placeable.height) { placeable.place((width - placeable.width) / 2, 0) }
}

private fun log2(x: Double) = ln(x) / ln(2.0)
private fun nearWhole(x: Double, tolerance: Double) = abs(x - Math.rint(x)) < tolerance

/** Full stops get a tall, labelled tick; third stops a short one. */
fun isMajor(name: String, value: String): Boolean = when (name) {
    "shutspeedvalue" -> PropertyFormat.seconds(value)?.let { nearWhole(log2(it), 0.12) } ?: true
    "isospeedvalue" -> value.toDoubleOrNull()?.let { nearWhole(log2(it / 100), 0.1) } ?: (value.lowercase() == "auto")
    "focalvalue" -> value.toDoubleOrNull()?.let { nearWhole(2 * log2(it), 0.1) } ?: true
    "expcomp" -> value.toDoubleOrNull()?.let { nearWhole(it, 0.05) } ?: true
    else -> true
}

fun shortLabel(name: String, value: String): String = when (name) {
    "focalvalue" -> if (value.endsWith(".0")) value.dropLast(2) else value
    "expcomp" -> value.toDoubleOrNull()?.let { ev -> if (ev == 0.0) "0" else String.format(java.util.Locale.US, "%+d", ev.roundToInt()) } ?: value
    else -> PropertyFormat.display(name, value)
}

/** A canvas-drawn histogram: soft filled curve with clipping warnings at either end. */
@Composable
fun HistogramView(values: FloatArray, modifier: Modifier = Modifier) {
    Canvas(modifier) {
        if (values.size < 2) return@Canvas
        val step = size.width / (values.size - 1)
        val path = androidx.compose.ui.graphics.Path().apply {
            moveTo(0f, size.height)
            values.forEachIndexed { i, v -> lineTo(i * step, size.height * (1 - v.coerceIn(0f, 1f))) }
            lineTo(size.width, size.height)
            close()
        }
        drawPath(path, Brush.verticalGradient(listOf(Color.White.copy(alpha = 0.85f), Color.White.copy(alpha = 0.25f))))
        if (values.first() > 0.6f) drawRect(Color(0f, 0.48f, 1f, 0.8f), size = androidx.compose.ui.geometry.Size(3f, size.height))
        if (values.last() > 0.6f) drawRect(Color.Red.copy(alpha = 0.8f), topLeft = androidx.compose.ui.geometry.Offset(size.width - 3f, 0f),
            size = androidx.compose.ui.geometry.Size(3f, size.height))
    }
}
