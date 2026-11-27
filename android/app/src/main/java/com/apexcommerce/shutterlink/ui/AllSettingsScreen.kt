package com.apexcommerce.shutterlink.ui

import androidx.compose.animation.Crossfade
import androidx.compose.animation.core.animate
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectVerticalDragGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.wrapContentHeight
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.text.BasicText
import androidx.compose.foundation.text.TextAutoSize
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.outlined.Lock
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.em
import androidx.compose.ui.unit.sp
import com.apexcommerce.shutterlink.camera.CameraModel
import com.apexcommerce.shutterlink.camera.CameraProperty
import com.apexcommerce.shutterlink.camera.PropertyFormat
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

// Every setting the camera reports, direction D (port of AllSettingsView and PropertyOptionsList in
// PropertyViews.swift; design 405 and 406): the exposure at a glance in Barlow, hairline rows, and for
// one setting a wheel with the chosen value very large between two accent rules.

private fun settingsText(size: TextUnit, weight: FontWeight = FontWeight.Normal) =
    TextStyle(fontSize = size, fontWeight = weight, lineHeight = size * 1.35f)

/** Every property the camera reports, for poking at things the main screen doesn't show. */
@Composable
fun AllSettingsScreen(camera: CameraModel, onDismiss: () -> Unit) {
    // The setting whose wheel is open; Back from the wheel returns to the list.
    var open by remember { mutableStateOf<String?>(null) }
    FullScreenPage(onDismiss = { if (open != null) open = null else onDismiss() }, camera = camera) {
        Crossfade(open, label = "settings") { name ->
            val property = name?.let { camera.properties[it] }
            if (property != null) OptionWheel(camera, property) { open = null }
            else SettingsList(camera, onDismiss) { open = it }
        }
    }
}

@Composable
private fun SettingsList(camera: CameraModel, onDismiss: () -> Unit, onOpen: (String) -> Unit) {
    val scope = rememberCoroutineScope()
    Column(Modifier.fillMaxSize()) {
        ScreenHeader("Camera settings", centred = true,
            leading = {
                HeaderButton("Reload") {
                    scope.launch {
                        try {
                            camera.refreshProperties()
                        } catch (e: CancellationException) {
                            throw e
                        } catch (e: Exception) {
                            camera.report(e)
                        }
                    }
                }
            },
            trailing = { HeaderButton("Done", onClick = onDismiss) })
        val sorted = camera.properties.values.sortedWith(compareBy(String.CASE_INSENSITIVE_ORDER) { propertyTitle(it.name) })
        LazyColumn(Modifier.fillMaxSize().padding(horizontal = 20.dp)) {
            if (sorted.isEmpty()) {
                item(key = "none") {
                    Text("No settings read yet.", style = settingsText(15.sp), color = Theme.secondary,
                        modifier = Modifier.padding(vertical = 16.dp))
                }
            } else {
                item(key = "glance") { ExposureGlance(camera) }
            }
            itemsIndexed(sorted, key = { _, p -> "p:" + p.name }) { index, p -> SettingRow(camera, p, first = index == 0, onOpen) }
            item(key = "footer") {
                Text("Everything the camera lets the app read or change over Wi-Fi. Locked rows can't be changed in the current mode.",
                    style = settingsText(13.sp), color = Theme.secondary, modifier = Modifier.padding(top = 10.dp, bottom = 24.dp))
            }
        }
    }
}

/** The exposure at a glance (405): the mode large in the accent, then aperture, shutter and ISO. */
@Composable
private fun ExposureGlance(camera: CameraModel) {
    val parts = buildList {
        if (camera.properties["takemode"] != null) add(stripText("takemode", camera) to true)
        listOf("focalvalue", "shutspeedvalue", "isospeedvalue").filter { camera.properties[it] != null }
            .forEach { add(stripText(it, camera).replace("ISO ", "") to false) }
    }
    if (parts.isEmpty()) return
    val text = buildAnnotatedString {
        parts.forEachIndexed { index, (value, mode) ->
            if (index > 0) append("\u2004")   // a third of an em: the 12 pt gap of the design
            if (mode) withStyle(SpanStyle(color = Theme.accent, fontSize = (60f / 36f).em)) { append(value) } else append(value)
        }
    }
    // One line; it shrinks (to 60 %) rather than wrap when the values are long.
    BasicText(text, Modifier.fillMaxWidth().padding(top = 8.dp, bottom = 14.dp)
        .semantics(mergeDescendants = true) { contentDescription = parts.joinToString(", ") { it.first } },
        style = Theme.num(36.sp).copy(color = Theme.text), maxLines = 1,
        autoSize = TextAutoSize.StepBased(minFontSize = 22.sp, maxFontSize = 36.sp, stepSize = 1.sp))
}

/** A hairline along the top, for the first row. */
private fun Modifier.settingsTopRule(): Modifier = this.drawBehind {
    drawRect(Theme.stroke, size = Size(size.width, 1.dp.toPx()))
}

/** 405: the setting and how many options it has, its value in Barlow on the right; a lock when it can't be changed. */
@Composable
private fun SettingRow(camera: CameraModel, property: CameraProperty, first: Boolean, onOpen: (String) -> Unit) {
    val shown = camera.dialOptions(property)
    val opens = property.settable && shown.options.isNotEmpty()
    Row(Modifier.fillMaxWidth().then(if (first) Modifier.settingsTopRule() else Modifier).hairRow(58.dp)
        .then(if (opens) Modifier.clickable(role = Role.Button) { onOpen(property.name) } else Modifier)
        .padding(vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(propertyTitle(property.name), style = settingsText(16.sp, FontWeight.Medium), color = Theme.text)
            Text(
                when (shown.options.size) {
                    0 -> property.name
                    1 -> "1 option"
                    else -> "${shown.options.size} options"
                },
                style = settingsText(13.sp), color = Theme.secondary,
            )
        }
        Text(PropertyFormat.display(property.name, shown.value), style = Theme.num(22.sp, medium = true),
            color = if (property.settable) Theme.text else Theme.secondary, textAlign = TextAlign.End, maxLines = 2,
            modifier = Modifier.widthIn(max = 200.dp))
        if (!property.settable) Icon(Icons.Outlined.Lock, "Locked", Modifier.size(16.dp), tint = Theme.tertiary)
        else if (opens) Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, null, Modifier.size(20.dp), tint = Theme.tertiary)
    }
}

// MARK: - The option wheel (406)

/** Size and distance from the centre (by how many values away), interpolated between whole steps. */
private val wheelSizes = floatArrayOf(150f, 38f, 26f, 20f, 14f)
private val wheelOffsets = floatArrayOf(0f, 128f, 176f, 212f, 240f)

private fun wheelLerp(table: FloatArray, d: Float): Float {
    val a = min(abs(d), (table.size - 1).toFloat())
    val i = a.toInt()
    val f = a - i
    return table[i] + (table[min(i + 1, table.size - 1)] - table[i]) * f
}

/**
 * One setting's options as a wheel: the chosen value very large between two accent rules, the
 * neighbours shrinking and fading away above and below. Drag to turn it; tap a value to set it; Done
 * sets the value between the rules.
 */
@Composable
private fun OptionWheel(camera: CameraModel, property: CameraProperty, onBack: () -> Unit) {
    val current = camera.properties[property.name] ?: property
    val shown = camera.dialOptions(current)
    val options = shown.options
    val last = max(0, options.size - 1)
    val scope = rememberCoroutineScope()
    var centre by remember { mutableFloatStateOf(options.indexOf(shown.value).coerceAtLeast(0).toFloat()) }
    // Once you've turned it, the wheel stays where you left it; until then it follows the camera.
    var touched by remember { mutableStateOf(false) }
    var settling by remember { mutableStateOf<Job?>(null) }
    LaunchedEffect(shown.value, options.size) {
        if (!touched) options.indexOf(shown.value).takeIf { it >= 0 }?.let { centre = it.toFloat() }
    }
    val centreIndex = centre.roundToInt().coerceIn(0, last)
    FeedbackOnChange(Feedback.Moment.DIAL_TICK, centreIndex)
    val value = options.getOrNull(centreIndex) ?: shown.value

    fun set(option: String) {
        if (current.settable && option != current.value) camera.scope.launch { camera.setProperty(property.name, option) }
    }

    /** After a drag: glide onto the nearest value. */
    fun settle() {
        settling?.cancel()
        val target = centre.roundToInt().coerceIn(0, last).toFloat()
        settling = scope.launch { animate(centre, target, animationSpec = tween(200)) { v, _ -> centre = v } }
    }

    BoxWithConstraints(Modifier.fillMaxSize()) {
        // The wheel under the header (406), its notes under it, Done at the bottom.
        val wheelHeight = (maxHeight - 250.dp).coerceIn(240.dp, 380.dp)
        Column(Modifier.fillMaxSize()) {
            ScreenHeader(propertyTitle(property.name), centred = true, leading = { HeaderButton("Back", onClick = onBack) })
            BoxWithConstraints(Modifier.fillMaxWidth().height(wheelHeight).clipToBounds()
                .pointerInput(last) {
                    var start = 0f
                    var moved = 0f
                    detectVerticalDragGestures(
                        onDragStart = {
                            settling?.cancel()
                            touched = true
                            start = centre.roundToInt().toFloat()
                            moved = 0f
                        },
                        onDragEnd = { settle() },
                        onDragCancel = { settle() },
                    ) { change, amount ->
                        change.consume()
                        moved += amount
                        centre = (start - moved / 46.dp.toPx()).coerceIn(0f, last.toFloat())
                    }
                }) {
                // The two accent rules round the chosen value.
                Box(Modifier.align(Alignment.Center).fillMaxWidth().height(168.dp).drawBehind {
                    val line = 1.dp.toPx()
                    drawRect(Theme.accent, size = Size(size.width, line))
                    drawRect(Theme.accent, topLeft = Offset(0f, size.height - line), size = Size(size.width, line))
                })
                options.forEachIndexed { i, option ->
                    val d = i - centre
                    if (abs(d) < 4.5f) key(option) {
                        val isCentre = abs(d) < 0.5f
                        val fontSize = wheelLerp(wheelSizes, d)
                        val y = (if (d < 0) -1 else 1) * wheelLerp(wheelOffsets, d)
                        val label = PropertyFormat.display(property.name, option)
                        Box(Modifier.align(Alignment.Center).offset(y = y.dp)
                            .widthIn(max = maxWidth - 90.dp).height(max(30f, fontSize * 1.05f).dp)
                            .alpha(max(0.15f, 1 - abs(d) * 0.22f))
                            .clickable(enabled = current.settable, role = Role.Button) {
                                set(option)
                                onBack()
                            }
                            .semantics {
                                contentDescription = label
                                selected = option == current.value
                            },
                            contentAlignment = Alignment.Center) {
                            AutoFitText(label, Theme.num(fontSize.sp, medium = !isCentre), if (isCentre) Theme.text else Theme.secondary,
                                Modifier.wrapContentHeight(unbounded = true))
                        }
                    }
                }
                // The pointer, left of the chosen value.
                Canvas(Modifier.align(Alignment.CenterStart).offset(x = 21.dp).size(14.dp, 18.dp)) {
                    val tri = Path().apply {
                        moveTo(0f, 0f)
                        lineTo(size.width, size.height / 2)
                        lineTo(0f, size.height)
                        close()
                    }
                    drawPath(tri, Theme.accent)
                }
            }
            Row(Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 12.dp)) {
                Text("${options.size} option${if (options.size == 1) "" else "s"}", style = settingsText(13.sp), color = Theme.secondary)
                Spacer(Modifier.weight(1f))
                Text("camera code $value", style = settingsText(13.sp), color = Theme.secondary)
            }
            Text(if (current.settable) "Drag to turn, tap a value to set it." else "This setting is locked in the current mode.",
                style = settingsText(13.sp), color = Theme.tertiary, textAlign = TextAlign.Center,
                modifier = Modifier.fillMaxWidth().padding(horizontal = 20.dp))
            Spacer(Modifier.weight(1f))
            // 406: a light Done at the bottom: sets the value between the rules and goes back.
            Box(Modifier.padding(start = 20.dp, end = 20.dp, top = 12.dp, bottom = 16.dp).fillMaxWidth().heightIn(min = 54.dp)
                .clip(Pill).background(Theme.text)
                .clickable(role = Role.Button) {
                    set(value)
                    onBack()
                },
                contentAlignment = Alignment.Center) {
                Text("Done", style = settingsText(16.sp, FontWeight.SemiBold), color = Theme.background)
            }
        }
    }
}
