package com.apexcommerce.shutterlink.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.horizontalScroll
import androidx.compose.ui.draw.clip
import androidx.compose.material.icons.filled.Lock
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.border
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

/** Whether a locked value is one the camera picks itself (shown as "· Auto"). */
fun isAutoValue(name: String, locked: Boolean, mode: String): Boolean =
    locked && name in setOf("focalvalue", "shutspeedvalue", "isospeedvalue") && mode.isNotEmpty()

/**
 * The options for one setting (port of SettingsDock.swift's OptionPanel): the big readout over the
 * curved dial, or a grid of buttons for drive, quality and the like. Locked settings explain why and
 * offer the way out. `fill` = the panel has the height under the values to itself (portrait).
 */
@Composable
fun OptionPanel(camera: CameraModel, spec: SettingSpec, onClose: () -> Unit, fill: Boolean = false, onTick: (Boolean) -> Unit = {}) {
    val raw = camera.properties[spec.name] ?: return
    val property = camera.dialOptions(raw)
    val scope = rememberCoroutineScope()
    val label = if (spec.name == "expcomp") "EV" else spec.title
    val mode = camera.properties["takemode"]?.value ?: ""
    val auto = isAutoValue(spec.name, !property.settable, mode)
    Column(
        Modifier.fillMaxWidth().then(if (fill) Modifier.fillMaxHeight() else Modifier)
            .then(if (spec.dial) Modifier else Modifier.padding(14.dp)),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        if (!spec.dial) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(spec.title, style = Theme.num(26.sp), color = Theme.text)
                Spacer(Modifier.weight(1f))
                Text(PropertyFormat.display(spec.name, property.value), style = Theme.num(22.sp, medium = true), color = Theme.accent)
                SurfaceButton(onClick = onClose, circle = true) {
                    Icon(Icons.Filled.Close, "Close ${spec.title}", Modifier.size(16.dp))
                }
            }
        }
        when {
            !property.settable -> {
                if (spec.name == "expcomp" && mode.uppercase() == "M") {
                    // 205: EV means nothing in M, so no readout: a lock, why, and the way out.
                    Icon(Icons.Filled.Lock, null, Modifier.padding(top = 20.dp).size(16.dp), tint = Theme.tertiary)
                } else {
                    DialReadout(label + if (auto) " · Auto" else "", stripText(spec.name, camera).removePrefix("ISO "),
                        Modifier.padding(top = 10.dp), locked = true)
                }
                LockedExplanation(camera, spec)
            }
            spec.name == "shutspeedvalue" -> ShutterOptions(camera, property, fill, onTick)
            spec.dial -> Box(if (fill) Modifier.weight(1f) else Modifier) {
                ValueDial(property, label, fill, onTick) { value -> scope.launch { camera.setProperty(spec.name, value) } }
                // A camera that lets EV be set in M (LUMIX) only uses it with ISO on Auto.
                val iso = camera.properties["isospeedvalue"]?.value
                if (spec.name == "expcomp" && mode.uppercase() == "M" && iso != null && !iso.lowercase().contains("auto")) {
                    Text("In M the camera applies EV only with ISO on Auto.", color = Theme.secondary, fontSize = 13.sp,
                        modifier = Modifier.align(Alignment.TopCenter).padding(top = 104.dp))
                }
            }
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
    val exposure = spec.name in setOf("focalvalue", "shutspeedvalue", "isospeedvalue", "wbvalue")
    val modeSettable = camera.properties["takemode"]?.settable == true
    val why = when {
        spec.name == "takemode" -> MODE_DIAL_HINT
        spec.name == "expcomp" && mode.uppercase() == "M" ->
            "Exposure compensation has no effect in M, where you set the exposure yourself. It works in P, A and S."
        mode.isEmpty() || !(exposure || spec.name == "expcomp") -> "Set this on the camera: this body doesn't let the phone change it right now."
        else -> "The camera sets this itself in ${PropertyFormat.display("takemode", mode)} mode."
    }
    val modes = camera.properties["takemode"]?.options ?: emptyList()
    Column(Modifier.padding(horizontal = 24.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text(why, color = Theme.text, fontSize = 15.sp, lineHeight = 20.sp, textAlign = TextAlign.Center)
        when {
            spec.name == "expcomp" && mode.uppercase() == "M" && ("A" in modes || "S" in modes) ->
                listOf("Switch to A (aperture priority)" to "A", "Switch to S (shutter priority)" to "S").filter { it.second in modes }.forEach { item ->
                    UnlockButton(item.first) { scope.launch { camera.setProperty("takemode", item.second) } }
                }
            unlock != null && unlock.second in modes -> UnlockButton(unlock.first) { scope.launch { camera.setProperty("takemode", unlock.second) } }
            unlock != null && !modeSettable && mode.isNotEmpty() && mode.uppercase() != unlock.second ->
                // The mode is on a physical dial (LUMIX): say which way to turn it.
                Text("Turn the camera's mode dial to ${unlock.second} to set this from the phone.", color = Theme.secondary,
                    fontSize = 13.sp, textAlign = TextAlign.Center)
        }
    }
}

/** The way out of a locked value (205): a light-outlined capsule with a lock, 44 dp. */
@Composable
private fun UnlockButton(title: String, onClick: () -> Unit) {
    Row(Modifier.heightIn(min = Theme.target).clip(Pill).border(1.5.dp, Theme.text, Pill).clickable(onClick = onClick)
        .padding(horizontal = 20.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Icon(Icons.Filled.LockOpen, null, Modifier.size(16.dp), tint = Theme.text)
        Text(title, color = Theme.text, fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
    }
}

/** Tappable grid for settings with a handful of named values: three across, text only, the chosen one in the accent (208, 209). */
@Composable
fun OptionGrid(property: CameraProperty, onSelect: (String) -> Unit) {
    val view = androidx.compose.ui.platform.LocalView.current
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        property.options.chunked(3).forEach { row ->
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                row.forEach { option ->
                    val selected = option == property.value
                    val shape = RoundedCornerShape(14.dp)
                    Box(
                        Modifier.weight(1f).heightIn(min = 62.dp).clip(shape)
                            .background(if (selected) Theme.accent else Color.Transparent, shape)
                            .then(if (selected) Modifier else Modifier.border(1.dp, Theme.outline, shape))
                            .clickable {
                                Feedback.play(Feedback.Moment.SELECT, view)
                                onSelect(option)
                            }
                            .padding(horizontal = 6.dp),
                        contentAlignment = Alignment.Center,
                    ) {
                        Text(PropertyFormat.display(property.name, option), color = if (selected) Theme.onAccent else Theme.text,
                            fontSize = 15.sp, fontWeight = FontWeight.SemiBold, textAlign = TextAlign.Center, maxLines = 2)
                    }
                }
                repeat(3 - row.size) { Spacer(Modifier.weight(1f)) }
            }
        }
    }
}

/**
 * Shutter: timed speeds on the dial, which runs on past the slowest one into the camera's own Live
 * Comp / Live Time / Bulb. Once one of those is chosen, the kinds show as chips, with Stop after (210).
 */
@Composable
fun ShutterOptions(camera: CameraModel, property: CameraProperty, fill: Boolean = false, onTick: (Boolean) -> Unit = {}) {
    val scope = rememberCoroutineScope()
    var lastTimed by remember { mutableStateOf(camera.prefs.getString("lastTimedShutter", "250") ?: "250") }
    val liveModes = property.options.filter { PropertyFormat.isOpenEnded(it) }
    val timedOptions = property.options.filter { !PropertyFormat.isOpenEnded(it) }
    val timedValue = when {
        property.value in timedOptions -> property.value
        lastTimed in timedOptions -> lastTimed
        else -> timedOptions.firstOrNull() ?: property.value
    }
    val current = if (PropertyFormat.isOpenEnded(property.value)) property.value else "timed"
    Column(Modifier.fillMaxWidth().then(if (fill) Modifier.fillMaxHeight() else Modifier),
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
        if (liveModes.isNotEmpty() && current != "timed") {
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                (listOf("timed") + liveModes).forEach { choice ->
                    val on = choice == current
                    Box(Modifier.heightIn(min = 34.dp).clip(Pill)
                        .background(if (on) Theme.text else Color.Black.copy(alpha = 0.25f), Pill)
                        .then(if (on) Modifier else Modifier.border(1.dp, Theme.text.copy(alpha = 0.35f), Pill))
                        .clickable {
                            val value = if (choice == "timed") timedValue else choice
                            scope.launch { camera.setProperty("shutspeedvalue", value) }
                        }
                        .padding(horizontal = 12.dp), contentAlignment = Alignment.Center) {
                        Text(if (choice == "timed") "Timed" else PropertyFormat.display("shutspeedvalue", choice),
                            color = if (on) Theme.background else Theme.text, fontSize = 13.sp,
                            fontWeight = if (on) FontWeight.SemiBold else FontWeight.Normal, maxLines = 1)
                    }
                }
            }
        }
        if (current == "timed") {
            Box(if (fill) Modifier.weight(1f) else Modifier) {
                ValueDial(property, "Shutter", fill, onTick) { value ->
                    if (!PropertyFormat.isOpenEnded(value)) {
                        lastTimed = value
                        camera.prefs.edit().putString("lastTimedShutter", value).apply()
                    }
                    scope.launch { camera.setProperty("shutspeedvalue", value) }
                }
            }
        } else {
            Spacer(Modifier.height(14.dp))
            BulbTimerControl(camera)
            Text(
                when {
                    current == "livecomp" -> "Live Composite stacks only new light: star trails without over-exposing the sky. " +
                        if (camera.bulbTimer > 0) "It stops by itself after ${CameraModel.durationLabel(camera.bulbTimer)}." else "Tap the shutter to start, again to stop."
                    camera.bulbTimer > 0 -> "The exposure stops by itself after ${CameraModel.durationLabel(camera.bulbTimer)}, or when you tap the shutter."
                    else -> "The exposure runs until you tap the shutter again."
                },
                color = Theme.secondary, fontSize = 13.sp, textAlign = TextAlign.Center, modifier = Modifier.padding(horizontal = 24.dp),
            )
        }
    }
}

/** Timed Bulb: Off, 30 s, 1–10 min. */
@Composable
fun BulbTimerControl(camera: CameraModel) {
    val choices = listOf(0.0, 30.0, 60.0, 120.0, 300.0)
    var picking by remember { mutableStateOf(false) }
    val custom = camera.bulbTimer > 0 && camera.bulbTimer !in choices
    Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
        CapsLabel("Stop after", color = Theme.secondary)
        Row(Modifier.horizontalScroll(androidx.compose.foundation.rememberScrollState()).padding(horizontal = 16.dp),
            horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            choices.forEach { seconds ->
                ChipButton(if (seconds == 0.0) "Off" else CameraModel.durationLabel(seconds), camera.bulbTimer == seconds,
                    enabled = !camera.isShooting) { camera.changeBulbTimer(seconds) }
            }
            // 211: any other length, on a wheel.
            ChipButton(if (custom) CameraModel.durationLabel(camera.bulbTimer) else "Other…", custom, enabled = !camera.isShooting) { picking = true }
        }
    }
    PanelCover(picking, { picking = false }, title = "Stop the exposure after") { dismiss ->
        StopAfterPicker(camera.bulbTimer, { camera.changeBulbTimer(it) }, dismiss)
    }
}

/**
 * A setting's dial (port of PropertyViews.swift's ValueDial): the big readout under the values, the
 * curved dial low over the shutter row; the gap between them is what's left over (201). The value is
 * sent to the camera once the dial settles, and follows the camera if it adjusts or rejects it.
 */
@Composable
fun ValueDial(property: CameraProperty, readoutLabel: String?, fill: Boolean = false, onTick: (Boolean) -> Unit = {}, onCommit: (String) -> Unit) {
    var selection by remember(property.name) { mutableStateOf(property.value) }
    LaunchedEffect(property.value) { selection = property.value }
    Column(Modifier.fillMaxWidth().then(if (fill) Modifier.fillMaxHeight() else Modifier)) {
        if (readoutLabel != null) DialReadout(readoutLabel, readoutText(property.name, selection), Modifier.padding(top = 10.dp))
        if (fill) Spacer(Modifier.weight(1f)) else Spacer(Modifier.height(6.dp))
        CurvedDial(
            options = property.options, selection = selection,
            label = { shortLabel(property.name, it) },
            onSelectionChange = { selection = it },
            onCommit = { if (it != property.value) onCommit(it) },
            isMajor = { isMajor(property.name, it) },
            isAnchor = { property.name == "expcomp" && it.toDoubleOrNull() == 0.0 },
            onTick = onTick,
        )
    }
}

/** The selected value as the big readout shows it. */
fun readoutText(name: String, value: String): String = when (name) {
    "focalvalue" -> "f/" + shortLabel(name, value)
    "takemode" -> modeTitle(value)
    else -> PropertyFormat.display(name, value)
}

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
    "takemode" -> modeTitle(value)
    "focalvalue" -> if (value.endsWith(".0")) value.dropLast(2) else value
    "wbvalue" -> {
        // Short on the dial so five fit (206: "Fluor."); the readout above says it in full.
        val full = PropertyFormat.display(name, value)
        val short = listOf("Fluorescent" to "Fluor.", "Incandescent" to "Incand.", "Underwater" to "Water", "One-touch" to "1-touch",
            "Auto (white priority)" to "Auto W", "Auto (ambience priority)" to "Auto A", "Daylight" to "Day", "Halogen" to "Halog.",
            "Colour temperature" to "K", "White set" to "Set")
        short.firstOrNull { full.startsWith(it.first) }?.let { it.second + full.drop(it.first.length) } ?: full
    }
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
