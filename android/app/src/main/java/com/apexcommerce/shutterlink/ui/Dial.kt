package com.apexcommerce.shutterlink.ui

import android.provider.Settings
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.input.pointer.util.VelocityTracker
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.em
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import kotlin.math.sin

/**
 * The one dial for every setting (port of Design.swift's CurvedDial): a ruler bent along a big arc
 * across the bottom of the screen, the centre value under an accent pointer.
 *
 * Feel (docs/design/04-motion-sound-haptics.md, item 1): the ruler follows the finger 1:1, coasts on
 * after a flick with the momentum projected from the release speed, and settles on a value with a
 * critically damped spring (no bounce). `onTick(firm)` fires on entering a value: firm on full stops
 * and on 0 EV. With animations turned off it goes straight to the nearest value. The value is
 * committed once the dial has settled. Tap a label to go to it.
 */
@Composable
fun CurvedDial(
    options: List<String>,
    selection: String,
    label: (String) -> String,
    onSelectionChange: (String) -> Unit,
    onCommit: (String) -> Unit,
    modifier: Modifier = Modifier,
    isMajor: (String) -> Boolean = { false },
    isAnchor: (String) -> Boolean = { false },
    onTick: (firm: Boolean) -> Unit = {},
) {
    val context = LocalContext.current
    val density = LocalDensity.current
    val scope = rememberCoroutineScope()
    val measurer = rememberTextMeasurer()
    val reduceMotion = remember {
        runCatching { Settings.Global.getFloat(context.contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f) == 0f }.getOrDefault(false)
    }
    val latestOptions by rememberUpdatedState(options)
    val latestSelection by rememberUpdatedState(selection)
    val latestChange by rememberUpdatedState(onSelectionChange)
    val latestCommit by rememberUpdatedState(onCommit)
    val latestTick by rememberUpdatedState(onTick)

    // Where the ruler is, in values (0 = first); null when it rests on the selection.
    var position by remember { mutableStateOf<Double?>(null) }
    var dragStart by remember { mutableStateOf<Double?>(null) }
    var coast by remember { mutableStateOf<Job?>(null) }
    // The value the ruler last landed on: committed at the end (the selection parameter only catches up on recomposition).
    val landed = remember { arrayOf<String?>(null) }
    DisposableEffect(Unit) { onDispose { coast?.cancel() } }

    val radiusPx = with(density) { 420.dp.toPx() }
    val topPx = with(density) { 26.dp.toPx() }

    // Degrees between values: wider for named values (white balance, mode…) so their labels fit. Full
    // stops among third stops (shutter, aperture, ISO, EV): full stops 10° apart and labelled, thirds as
    // ticks between.
    val stopScale = options.any(isMajor) && options.any { !isMajor(it) }
    val step: Double = when {
        stopScale -> 10.0 / 3
        options.all { o -> label(o).any { it.isDigit() } } -> 8.0
        else -> {
            val lengths = options.map { label(it).length }.sorted()
            val typical = if (lengths.isEmpty()) 4 else lengths[lengths.size / 2]
            min(12.0, max(10.0, (typical * 8.5 + 14) / 6.7))
        }
    }
    val pxPerValue = (radiusPx * step * PI / 180).toFloat()

    fun index() = latestOptions.indexOf(latestSelection).coerceAtLeast(0)
    fun current() = position ?: index().toDouble()
    fun maxIndex() = max(0, latestOptions.size - 1).toDouble()
    fun firm(value: String) = isAnchor(value) || (isMajor(value) && latestOptions.any { !isMajor(it) })
    fun rubber(over: Double) = 0.6 * (1 - 1 / (over * 0.8 + 1))

    /** Moves the ruler, with a tick for each value it passes and the selection following. */
    fun move(to: Double) {
        val before = current().roundToInt()
        position = to
        val now = min(maxIndex(), max(0.0, to)).roundToInt()
        if (now == before || now !in latestOptions.indices) return
        val passed = if (now > before) (before + 1)..now else now..(before - 1)
        latestTick(passed.any { it in latestOptions.indices && firm(latestOptions[it]) })
        landed[0] = latestOptions[now]
        latestChange(latestOptions[now])
    }

    /** After a release: coast on the projected momentum, then spring onto a value and commit it. */
    fun settle(start: Double, velocity: Double, fixed: Double? = null) {
        coast?.cancel()
        val flick = abs(velocity) > 6
        val projected = if (reduceMotion) start else start + velocity * 0.35
        val target = fixed ?: min(maxIndex(), max(0.0, projected)).roundToInt().toDouble()
        if (reduceMotion) {
            move(target)
            position = null
            latestCommit(landed[0] ?: latestSelection)
            landed[0] = null
            return
        }
        coast = scope.launch {
            // Motion.mirror's response (longer after a flick), critically damped: settles without a bounce.
            val response = if (flick) 0.35 * 1.5 else 0.35
            val omega = 2 * PI / response
            var x = start
            var v = velocity
            val dt = 1.0 / 120
            for (i in 0 until 480) {
                val a = -omega * omega * (x - target) - 2 * omega * v
                v += a * dt
                x += v * dt
                move(x)
                if (abs(x - target) < 0.002 && abs(v) < 0.02) break
                delay(8)
                if (!isActive) return@launch
            }
            move(target)
            position = null
            latestCommit(landed[0] ?: latestSelection)
            landed[0] = null
        }
    }

    val labelColor = Color(0xFFC9C5BA)
    Canvas(
        modifier
            .fillMaxWidth()
            .height(112.dp)
            .semantics {
                contentDescription = "Dial"
                stateDescription = label(selection)
            }
            .pointerInput(pxPerValue) {
                val tracker = VelocityTracker()
                var travelled = 0f
                detectHorizontalDragGestures(
                    onDragStart = {
                        coast?.cancel()
                        dragStart = current()
                        travelled = 0f
                        tracker.resetTracking()
                    },
                    onDragEnd = {
                        dragStart = null
                        val vx = tracker.calculateVelocity().x
                        settle(current(), -(vx / pxPerValue).toDouble())
                    },
                    onDragCancel = {
                        dragStart = null
                        settle(current(), 0.0)
                    },
                ) { change, dragAmount ->
                    tracker.addPosition(change.uptimeMillis, change.position)
                    travelled += dragAmount
                    var p = (dragStart ?: current()) - travelled / pxPerValue
                    // Past either end the ruler gives a little, with resistance.
                    if (p < 0) p = -rubber(-p) else if (p > maxIndex()) p = maxIndex() + rubber(p - maxIndex())
                    move(p)
                    change.consume()
                }
            }
            .pointerInput(pxPerValue, step) {
                detectTapGestures { tap ->
                    if (dragStart != null || tap.y < 30.dp.toPx()) return@detectTapGestures
                    val dx = (tap.x - size.width / 2).toDouble()
                    val dy = (topPx + radiusPx - tap.y).toDouble()
                    val angle = atan2(dx, dy) * 180 / PI
                    val target = min(maxIndex(), max(0.0, (current() + angle / step).roundToInt().toDouble()))
                    if (target != current().roundToInt().toDouble()) settle(current(), 0.0, target)
                }
            },
    ) {
        val total = options.size
        if (total == 0) return@Canvas
        val cur = current()
        val cx = size.width / 2
        val centre = Offset(cx, topPx + radiusPx)
        val minor = max(0, (step / 2).roundToInt() - 1)   // ticks about 2° apart, as designed
        fun at(angle: Double, r: Float): Offset {
            val rad = (angle - 90) * PI / 180
            return Offset(centre.x + r * cos(rad).toFloat(), centre.y + r * sin(rad).toFloat())
        }
        val span = (62 / step).toInt() + 2
        val first = max(0, cur.toInt() - span)
        val last = min(total - 1, cur.toInt() + span)
        for (i in first..last) {
            for (m in 0..minor) {
                val value = i + m.toDouble() / (minor + 1)
                if (value > total - 1) continue
                val angle = (value - cur) * step
                if (abs(angle) > 62) continue
                val major = m == 0 && isMajor(options[i])
                val len = (if (m == 0) (if (major) 16 else 13) else 9).dp.toPx()
                val fade = max(0.2, 1 - max(0.0, abs(angle) - 22) / 40).toFloat()
                drawLine(Theme.text.copy(alpha = (if (m == 0) 0.8f else 0.5f) * fade), at(angle, radiusPx - len), at(angle, radiusPx),
                    strokeWidth = (if (m == 0) 1.8f else 1.4f).dp.toPx())
            }
        }
        // Labels, nearest the pointer first; one that would touch a label already drawn is left out, so
        // long names never run into each other. The value under the pointer is always drawn.
        val taken = mutableListOf<ClosedFloatingPointRange<Double>>()
        val labelRadius = radiusPx - 40.dp.toPx()
        for (i in (first..last).sortedBy { abs(it - cur) }) {
            val angle = (i - cur) * step
            if (abs(angle) > 25) continue
            val near = abs(i - cur) < 0.5
            if (stopScale && !near && !isMajor(options[i])) continue
            val style = TextStyle(
                fontFamily = Theme.barlow, fontSize = if (near) 22.sp else 19.sp,
                fontWeight = if (near) FontWeight.SemiBold else FontWeight.Medium,
                color = if (near) Theme.text else labelColor.copy(alpha = max(0.5, 1 - abs(angle) / 50).toFloat()),
            )
            val layout = measurer.measure(label(options[i]), style, maxLines = 1, overflow = TextOverflow.Clip)
            val half = (layout.size.width / 2 + 7.dp.toPx()) / (labelRadius * PI / 180)
            val range = (angle - half)..(angle + half)
            if (!near && taken.any { it.start <= range.endInclusive && range.start <= it.endInclusive }) continue
            taken.add(range)
            val pt = at(angle, labelRadius)
            rotate(angle.toFloat(), pivot = pt) {
                drawText(layout, topLeft = Offset(pt.x - layout.size.width / 2, pt.y - layout.size.height / 2))
            }
        }
        val tri = Path().apply {
            moveTo(cx, 24.dp.toPx())
            lineTo(cx - 8.dp.toPx(), 2.dp.toPx())
            lineTo(cx + 8.dp.toPx(), 2.dp.toPx())
            close()
        }
        drawPath(tri, Theme.accent)
    }
}

/** The big readout above the dial: the selected value's label in the accent and the value at 68 sp. */
@Composable
fun DialReadout(label: String, value: String, modifier: Modifier = Modifier, locked: Boolean = false) {
    Column(modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) {
        Text(label.uppercase(), color = Theme.accent, maxLines = 1,
            style = TextStyle(fontSize = 12.sp, fontWeight = FontWeight.Medium, letterSpacing = 0.14.em))
        AutoFitText(value, Theme.num(68.sp), if (locked) Theme.secondary else Theme.text, Modifier.fillMaxWidth().height(76.dp))
    }
}

/** One line of big text that shrinks to fit its width (down to a third), never wraps. */
@Composable
fun AutoFitText(text: String, style: TextStyle, color: Color, modifier: Modifier = Modifier, textAlign: androidx.compose.ui.text.style.TextAlign = androidx.compose.ui.text.style.TextAlign.Center) {
    androidx.compose.foundation.text.BasicText(
        text, modifier, style = style.copy(color = color, textAlign = textAlign), maxLines = 1,
        autoSize = androidx.compose.foundation.text.TextAutoSize.StepBased(
            minFontSize = style.fontSize * 0.33f, maxFontSize = style.fontSize, stepSize = 1.sp),
    )
}
