package com.apexcommerce.shutterlink.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material3.Icon
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.layout
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.compose.ui.window.DialogWindowProvider
import com.apexcommerce.shutterlink.camera.Astronomy
import com.apexcommerce.shutterlink.camera.CameraModel
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.util.Calendar
import kotlin.math.abs
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

// Pieces the tool screens share (port of the parts of ExtrasViews.swift and Instruments.swift the
// "big number panels" use): the tool screen itself, the wheel (211) and the row that opens it, the
// switch row, the frame bars (303), the fanned focus stack (306) and the sun over the interval (301).

/**
 * A tool's screen (301–312): full screen, the title on the left and Done on the right, then the
 * content scrolling under it. The content is at least the screen's height, so a tool's main button
 * sits at the bottom behind the weighted space `PinnedBottom` puts before it; longer content scrolls.
 * `camera` puts the blurred live view behind it (Presets); the other tools sit on black. `action` is
 * the header button's title ("Close" on a preset's own screen, 314).
 */
@Composable
fun ToolScreen(title: String, onDismiss: () -> Unit, camera: CameraModel? = null, action: String = "Done",
               content: @Composable ColumnScope.() -> Unit) {
    FullScreenPage(onDismiss, camera) {
        Column(Modifier.fillMaxSize()) {
            ScreenHeader(title, Modifier.padding(top = 6.dp), trailing = { HeaderButton(action, onClick = onDismiss) })
            BoxWithConstraints(Modifier.weight(1f).fillMaxWidth()) {
                val viewport = maxHeight
                Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState())) {
                    Column(Modifier.fillMaxWidth().heightIn(min = viewport).padding(horizontal = 20.dp).padding(top = 4.dp, bottom = 20.dp),
                        content = content)
                }
            }
        }
    }
}

/** The screen's main button(s), at the bottom of a `ToolScreen` when the content is short (at least 20 dp under it). */
@Composable
fun ColumnScope.PinnedBottom(content: @Composable ColumnScope.() -> Unit) {
    Spacer(Modifier.height(20.dp))
    Spacer(Modifier.weight(1f))
    Column(Modifier.fillMaxWidth().padding(bottom = 14.dp), verticalArrangement = Arrangement.spacedBy(10.dp), content = content)
}

/** A hairline along the top (the first of a group of hairline rows). */
fun Modifier.hairlineAbove(): Modifier = drawBehind {
    drawRect(Theme.stroke, size = Size(size.width, 1.dp.toPx()))
}

/** Lets a full-width graphic run out to the screen's edges through the content's side margins. */
fun Modifier.bleed(horizontal: Dp): Modifier = layout { measurable, constraints ->
    val extra = horizontal.roundToPx() * 2
    val width = constraints.maxWidth + extra
    val placeable = measurable.measure(constraints.copy(minWidth = width, maxWidth = width))
    layout(constraints.maxWidth, placeable.height) { placeable.place(-extra / 2, 0) }
}

/** A switch on a hairline row: a title and a line under it (Follow the light, Pin-sharp stars). */
@Composable
fun ToggleRow(title: String, subtitle: String?, checked: Boolean, onChange: (Boolean) -> Unit, enabled: Boolean = true,
              accent: Color = Theme.accent, textColor: Color = Theme.text) {
    Row(Modifier.fillMaxWidth().hairRow(62.dp)
        .toggleable(checked, enabled = enabled, role = Role.Switch, onValueChange = onChange)
        .padding(vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(title, color = textColor, fontSize = 16.sp, fontWeight = FontWeight.Medium)
            if (subtitle != null) Text(subtitle, color = Theme.secondary, fontSize = 13.sp, lineHeight = 17.sp)
        }
        Switch(checked, null, enabled = enabled, colors = SwitchDefaults.colors(
            checkedTrackColor = accent, checkedThumbColor = Theme.background, checkedBorderColor = accent,
            uncheckedTrackColor = Theme.surfaceRaised, uncheckedBorderColor = Theme.outline, uncheckedThumbColor = Theme.secondary,
            disabledUncheckedTrackColor = Theme.surface, disabledUncheckedBorderColor = Theme.stroke,
            disabledUncheckedThumbColor = Theme.tertiary.copy(alpha = 0.5f)))
    }
}

// MARK: - The wheel (211)

/**
 * One wheel of values: the chosen one large in Barlow in the middle, its neighbours smaller and dim.
 * Scrolls and settles on the value in the middle; tap a value to go to it.
 */
@Composable
fun WheelColumn(values: List<Int>, selection: Int?, onSelect: (Int) -> Unit, modifier: Modifier = Modifier,
                unit: String = "", zeroText: String? = null, label: String = "") {
    if (values.isEmpty()) return
    val row = 34.dp
    val rowPx = with(LocalDensity.current) { row.toPx() }
    val feedback = rememberFeedback()
    val scope = rememberCoroutineScope()
    val start = remember { values.indexOf(selection).coerceAtLeast(0) }
    val state = rememberLazyListState(initialFirstVisibleItemIndex = start)
    val latestSelect by rememberUpdatedState(onSelect)
    val latestSelection by rememberUpdatedState(selection)
    // The value in the middle: with the padding below, item i is centred when the list is scrolled i rows.
    val centred by remember(values) {
        derivedStateOf {
            (state.firstVisibleItemIndex + if (state.firstVisibleItemScrollOffset > rowPx / 2) 1 else 0).coerceIn(0, values.size - 1)
        }
    }
    LaunchedEffect(centred) {
        val value = values[centred]
        if (value != latestSelection) {
            if (latestSelection != null) feedback(Feedback.Moment.SELECT)
            latestSelect(value)
        }
    }
    // Settles on a value once the scroll stops.
    LaunchedEffect(state.isScrollInProgress) {
        if (!state.isScrollInProgress && state.firstVisibleItemScrollOffset != 0) state.animateScrollToItem(centred)
    }
    fun text(value: Int) = if (value == 0 && zeroText != null) zeroText else if (unit.isEmpty()) "$value" else "$value $unit"
    BoxWithConstraints(modifier
        .semantics {
            if (label.isNotEmpty()) contentDescription = label
            stateDescription = text(values[centred])
            customActions = listOf(
                CustomAccessibilityAction("Increase") {
                    if (centred < values.size - 1) scope.launch { state.animateScrollToItem(centred + 1) }
                    true
                },
                CustomAccessibilityAction("Decrease") {
                    if (centred > 0) scope.launch { state.animateScrollToItem(centred - 1) }
                    true
                },
            )
        }
        .graphicsLayer { compositingStrategy = CompositingStrategy.Offscreen }
        .drawWithContent {
            drawContent()
            drawRect(Brush.verticalGradient(0f to Color.Transparent, 0.25f to Color.Black, 0.75f to Color.Black, 1f to Color.Transparent),
                blendMode = BlendMode.DstIn)
        }) {
        val pad = ((maxHeight - row) / 2).coerceAtLeast(0.dp)
        LazyColumn(Modifier.fillMaxSize(), state = state, contentPadding = PaddingValues(vertical = pad)) {
            itemsIndexed(values) { index, value ->
                val on = index == centred
                Box(Modifier.fillMaxWidth().height(row)
                    .clickable(role = Role.Button) { scope.launch { state.animateScrollToItem(index) } },
                    contentAlignment = Alignment.Center) {
                    Text(text(value), style = Theme.num(if (on) 34.sp else 20.sp, medium = !on).copy(lineHeight = 34.sp),
                        color = if (on) Theme.text else Theme.secondary, maxLines = 1)
                }
            }
        }
    }
}

/** Wheels between two hairlines (211): `content` lays out one wheel or several side by side, 170 dp tall. */
@Composable
fun WheelFrame(modifier: Modifier = Modifier, content: @Composable () -> Unit) {
    Box(modifier.fillMaxWidth().height(170.dp).drawWithContent {
        drawContent()
        val band = 46.dp.toPx()
        val top = (size.height - band) / 2
        drawRect(Theme.stroke, Offset(0f, top), Size(size.width, 1.dp.toPx()))
        drawRect(Theme.stroke, Offset(0f, top + band), Size(size.width, 1.dp.toPx()))
    }) { content() }
}

/**
 * The bottom panel from anywhere (iOS dPanelCover): a see-through full-screen window over the page
 * hosting the app's bottom panel, for controls nested deep in a screen (a wheel row, Stop after's
 * custom time). `content` gets a `dismiss` that slides the panel away before it closes.
 */
@Composable
fun PanelCover(visible: Boolean, onClose: () -> Unit, title: String? = null, content: @Composable ColumnScope.(dismiss: () -> Unit) -> Unit) {
    if (visible) PanelCoverHost(onClose, title, content)
}

@Composable
private fun PanelCoverHost(onClose: () -> Unit, title: String?, content: @Composable ColumnScope.(dismiss: () -> Unit) -> Unit) {
    var shown by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    val latestClose by rememberUpdatedState(onClose)
    val dismiss: () -> Unit = {
        if (shown) {
            shown = false
            scope.launch {
                delay(300)
                latestClose()
            }
        }
    }
    LaunchedEffect(Unit) { shown = true }
    Dialog(onDismissRequest = dismiss,
        properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false)) {
        // The panel dims what's behind it itself; no window dim on top of that.
        val window = (LocalView.current.parent as? DialogWindowProvider)?.window
        SideEffect { window?.setDimAmount(0f) }
        BottomPanel(shown, dismiss, title = title) { content(this, dismiss) }
    }
}

/** A wheel of whole numbers and Set, in the bottom panel (the pickers behind WheelValueRow and the interval). */
@Composable
fun WheelPicker(values: List<Int>, start: Int, label: String, onSet: (Int) -> Unit, dismiss: () -> Unit,
                unit: String = "", zeroText: String? = null) {
    val initial = remember { values.minByOrNull { abs(it - start) } ?: start }
    var picked by remember { mutableStateOf<Int?>(initial) }
    Column(Modifier.fillMaxWidth().padding(horizontal = 20.dp).padding(bottom = 16.dp), verticalArrangement = Arrangement.spacedBy(18.dp)) {
        WheelFrame {
            WheelColumn(values, picked, { picked = it }, Modifier.fillMaxSize(), unit = unit, zeroText = zeroText, label = label)
        }
        AccentButton({ picked?.let(onSet); dismiss() }, Modifier.fillMaxWidth()) { Text("Set") }
    }
}

private val stopAfterMinutes: List<Int> = (0..120).toList()
private val stopAfterSeconds: List<Int> = (0..55 step 5).toList()

/**
 * 211: Stop after's own length on two Barlow wheels (minutes, seconds) between hairlines, then Set and
 * Cancel (iOS BulbTimerSheet). Host it in `PanelCover(…, title = "Stop the exposure after")` behind an
 * "Other…" chip; `onSet` gets the seconds.
 */
@Composable
fun StopAfterPicker(seconds: Double, onSet: (Double) -> Unit, dismiss: () -> Unit) {
    val total = seconds.roundToInt()
    var minutes by remember { mutableStateOf<Int?>(total / 60) }
    var secs by remember { mutableStateOf<Int?>((total % 60) / 5 * 5) }
    Column(Modifier.fillMaxWidth().padding(horizontal = 20.dp).padding(bottom = 16.dp), verticalArrangement = Arrangement.spacedBy(18.dp)) {
        WheelFrame(Modifier.padding(top = 6.dp)) {
            Row(Modifier.fillMaxSize()) {
                WheelColumn(stopAfterMinutes, minutes, { minutes = it }, Modifier.weight(1f).fillMaxHeight(), unit = "min", label = "Minutes")
                WheelColumn(stopAfterSeconds, secs, { secs = it }, Modifier.weight(1f).fillMaxHeight(), unit = "s", label = "Seconds")
            }
        }
        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            AccentButton({ onSet(((minutes ?: 0) * 60 + (secs ?: 0)).toDouble()); dismiss() }, Modifier.fillMaxWidth()) { Text("Set") }
            OutlineButton(onClick = dismiss, modifier = Modifier.fillMaxWidth()) { Text("Cancel") }
        }
    }
}

/**
 * A hairline row with a whole-number value on the right in Barlow (305, 310, 311); tap it to change
 * the value on a wheel in the bottom panel. TalkBack can also step it with its actions.
 */
@Composable
fun WheelValueRow(title: String, subtitle: String?, values: List<Int>, value: Int, onChange: (Int) -> Unit, format: (Int) -> String) {
    var editing by remember { mutableStateOf(false) }
    Row(Modifier.fillMaxWidth().hairRow(58.dp)
        .clickable(role = Role.Button) { editing = true }
        .padding(vertical = 8.dp)
        .clearAndSetSemantics {
            contentDescription = title
            stateDescription = format(value)
            role = Role.Button
            onClick { editing = true; true }
            customActions = listOf(
                CustomAccessibilityAction("Increase") {
                    val i = values.indexOf(value)
                    if (i in 0 until values.size - 1) onChange(values[i + 1])
                    true
                },
                CustomAccessibilityAction("Decrease") {
                    val i = values.indexOf(value)
                    if (i > 0) onChange(values[i - 1])
                    true
                },
            )
        },
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(title, color = Theme.text, fontSize = 16.sp, fontWeight = FontWeight.Medium)
            if (subtitle != null) Text(subtitle, color = Theme.secondary, fontSize = 13.sp)
        }
        Text(format(value), style = Theme.num(22.sp), color = Theme.text, maxLines = 1)
        Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, null, Modifier.size(18.dp), tint = Theme.tertiary)
    }
    PanelCover(editing, { editing = false }, title = title) { dismiss ->
        WheelPicker(values, value, title, onSet = onChange, dismiss = dismiss)
    }
}

// MARK: - Running sequences

/** A row of short bars for a running sequence (303): done in white, the next one in the accent. At most 24 bars. */
@Composable
fun FrameBars(done: Int, total: Int, modifier: Modifier = Modifier) {
    val count = min(24, max(1, total))
    val filled = floor(done.toDouble() / max(1, total) * count).toInt()
    Row(modifier.fillMaxWidth().clearAndSetSemantics {}, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
        repeat(count) { i ->
            Box(Modifier.weight(1f).height(6.dp).background(
                when {
                    i < filled -> Theme.text
                    i == filled -> Theme.accent
                    else -> Theme.stroke
                }, Pill))
        }
    }
}

/** The frames of a focus stack fanned from near to far (306), the done ones in the accent. */
@Composable
fun FocusStackArt(done: Int, total: Int, modifier: Modifier = Modifier) {
    val measurer = rememberTextMeasurer()
    val labelStyle = TextStyle(fontSize = 11.sp, color = Theme.secondary)
    Canvas(modifier.clearAndSetSemantics {}) {
        val count = min(total, 10)
        if (count <= 0) return@Canvas
        val w = size.width * 0.42f
        val h = w * 0.62f
        val lit = floor(done.toDouble() / max(1, total) * count).toInt()
        val corner = CornerRadius(8.dp.toPx())
        for (i in (0 until count).reversed()) {
            val t = i.toFloat() / max(1, count - 1)
            val topLeft = Offset(size.width * 0.18f + t * size.width * 0.34f, size.height * 0.62f - t * size.height * 0.5f - h / 2)
            drawRoundRect(Theme.background, topLeft, Size(w, h), corner)
            drawRoundRect(if (i < lit) Theme.accent else Theme.text.copy(alpha = (0.45f - t * 0.2f).coerceIn(0f, 1f)), topLeft, Size(w, h), corner,
                style = Stroke((if (i < lit) 2f else 1.2f).dp.toPx()))
        }
        fun label(text: String, at: Offset) {
            val layout = measurer.measure(text, labelStyle)
            drawText(layout, topLeft = Offset(at.x - layout.size.width / 2, at.y - layout.size.height / 2))
        }
        label("Near", Offset(size.width * 0.16f, size.height * 0.92f))
        label("Far", Offset(size.width * 0.86f, size.height * 0.06f))
    }
}

// MARK: - The sun (301)

/**
 * Where the sun is today (301): its path as a dotted arc over a horizon, the sun where it is now, and
 * what light that means. From the phone's clock and last known location (the sun position the scene
 * suggestions use); the interval screen leaves it out without a location.
 */
@Composable
fun SunArc(latitude: Double, longitude: Double, modifier: Modifier = Modifier) {
    val now = rememberNow(true, 60_000)
    val start = remember(now / 600_000) {
        Calendar.getInstance().apply {
            timeInMillis = now
            set(Calendar.HOUR_OF_DAY, 0)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }.timeInMillis
    }
    val samples = remember(start, latitude, longitude) {
        (0..96).map { Astronomy.sky(start + it * 900_000L, latitude, longitude).sunAltitude }
    }
    val altitude = Astronomy.sky(now, latitude, longitude).sunAltitude
    val x = ((now - start) / 86_400_000.0).coerceIn(0.0, 1.0)
    val peak = max(10.0, samples.maxOf { abs(it) })
    val up = if (altitude >= 0) "Sun ${altitude.roundToInt()}° up" else "Sun ${(-altitude).roundToInt()}° down"
    Box(modifier.fillMaxWidth().height(150.dp).semantics(mergeDescendants = true) {}) {
        Canvas(Modifier.fillMaxSize()) {
            val horizon = size.height * 0.72f
            val scale = ((horizon - 18.dp.toPx()) / peak).toFloat()
            fun point(fx: Double, alt: Double) = Offset((fx * size.width).toFloat(), horizon - alt.toFloat() * scale)
            // The sky glows warm near the horizon; the ground below it is near-black.
            drawRect(Brush.verticalGradient(listOf(Theme.background, sunGlow(altitude).copy(alpha = 0.55f)), endY = horizon),
                size = Size(size.width, horizon))
            drawRect(Theme.background, Offset(0f, horizon), Size(size.width, size.height - horizon))
            val arc = Path().apply {
                samples.forEachIndexed { i, alt ->
                    val p = point(i.toDouble() / (samples.size - 1), alt)
                    if (i == 0) moveTo(p.x, p.y) else lineTo(p.x, p.y)
                }
            }
            drawPath(arc, Theme.text.copy(alpha = 0.6f), style = Stroke(2.dp.toPx(), cap = StrokeCap.Round,
                pathEffect = PathEffect.dashPathEffect(floatArrayOf(0.1f, 6.dp.toPx()))))
            drawLine(Theme.outline, Offset(0f, horizon), Offset(size.width, horizon), strokeWidth = 1.dp.toPx())
            val sun = point(x, altitude)
            drawCircle(Theme.accent.copy(alpha = if (altitude > -6) 0.25f else 0.1f), 18.dp.toPx(), sun)
            drawCircle(if (altitude > -6) Theme.accent else Theme.tertiary, 9.dp.toPx(), sun)
        }
        Column(Modifier.padding(horizontal = 20.dp).padding(top = 14.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(up, color = Theme.secondary, fontSize = 13.sp)
            Text(sunLight(altitude), style = Theme.num(28.sp), color = Theme.accent)
        }
    }
}

private fun sunLight(altitude: Double): String = when {
    altitude >= 6 -> "Daylight"
    altitude >= -4 -> "Golden hour now"
    altitude >= -6 -> "Blue hour now"
    altitude >= -18 -> "Twilight"
    else -> "Night"
}

private fun sunGlow(altitude: Double): Color = when {
    altitude >= 6 -> Color(0xFF6E8FC4)
    altitude >= -4 -> Color(0xFFC9853F)
    altitude >= -12 -> Color(0xFF3B4A8C)
    else -> Color(0xFF141A36)
}

/** A rounded box with a hairline edge in `edge` (the bracket's frames, ND's filter cards). */
fun Modifier.outlinedBox(edge: Color, radius: Dp = 12.dp, fill: Color = Color.Transparent): Modifier {
    val shape = RoundedCornerShape(radius)
    return this.background(fill, shape).border(1.dp, edge, shape)
}

