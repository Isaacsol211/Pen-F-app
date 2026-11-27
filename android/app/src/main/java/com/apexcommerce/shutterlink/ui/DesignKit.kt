package com.apexcommerce.shutterlink.ui

import android.graphics.Bitmap
import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.scaleOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectVerticalDragGestures
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
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
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.WarningAmber
import androidx.compose.material3.Icon
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.graphics.ColorMatrix
import androidx.compose.ui.graphics.FilterQuality
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.apexcommerce.shutterlink.camera.CameraModel
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlin.math.roundToInt

// The pieces every redesigned screen is built from (port of Design.swift's panels, screens, dialogs
// and rows): the bottom panel, the full-screen page, the header, the dialog card, the big number, the
// progress ring, and the hairline rows of the tool screens.

/** The design's dark wash, a hair warmer than the background. */
val Wash = Color(red = 6, green = 6, blue = 8)

/** A hairline under a row (the D replacement for cards). */
fun Modifier.hairRow(minHeight: Dp = 0.dp): Modifier = this
    .heightIn(min = minHeight)
    .drawBehind {
        drawRect(Theme.stroke, topLeft = androidx.compose.ui.geometry.Offset(0f, size.height - 1.dp.toPx()),
            size = androidx.compose.ui.geometry.Size(size.width, 1.dp.toPx()))
    }

/** The big number that opens a tool panel: a label in the accent, a very large Barlow value, a caption. */
@Composable
fun BigNumber(value: String, modifier: Modifier = Modifier, label: String? = null, caption: String? = null,
              size: TextUnit = 104.sp, color: Color = Theme.text, accent: Color = Theme.accent) {
    Column(modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(4.dp)) {
        if (label != null) CapsLabel(label, accent)
        AutoFitText(value, Theme.num(size), color, Modifier.fillMaxWidth())
        if (caption != null) Text(caption, color = Theme.secondary, fontSize = 13.sp, textAlign = TextAlign.Center)
    }
}

/** Progress ring with the running number inside, for tools that run. */
@Composable
fun ProgressRing(text: String, fraction: Double, modifier: Modifier = Modifier, sub: String? = null,
                 color: Color = Theme.accent, size: Dp = 220.dp) {
    val shown by animateFloatAsState(fraction.coerceIn(0.001, 1.0).toFloat(), label = "ring")
    Box(modifier.size(size), contentAlignment = Alignment.Center) {
        Canvas(Modifier.fillMaxSize()) {
            val w = 6.dp.toPx()
            val inset = w / 2
            val arcSize = androidx.compose.ui.geometry.Size(this.size.width - w, this.size.height - w)
            val topLeft = androidx.compose.ui.geometry.Offset(inset, inset)
            drawArc(Theme.stroke, 0f, 360f, false, topLeft, arcSize, style = Stroke(w))
            drawArc(color, -90f, 360f * shown, false, topLeft, arcSize, style = Stroke(w, cap = StrokeCap.Round))
        }
        Column(Modifier.padding(horizontal = 20.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            AutoFitText(text, Theme.num((size.value * 0.345f).sp), Theme.text, Modifier.fillMaxWidth())
            if (sub != null) Text(sub, color = Theme.text, fontSize = 13.sp)
        }
    }
}

/**
 * The blurred, dimmed live frame that fills the screen behind the remote. Refreshed a couple of times a
 * second: it's only a colour wash. The blur is a tiny copy of the frame scaled back up (works on every
 * Android version, unlike Modifier.blur).
 */
@Composable
fun LiveBackdrop(camera: CameraModel, modifier: Modifier = Modifier, page: Boolean = false) {
    var image by remember { mutableStateOf<ImageBitmap?>(null) }
    LaunchedEffect(Unit) {
        while (true) {
            camera.latestBitmap?.let { frame ->
                image = runCatching { Bitmap.createScaledBitmap(frame, 24, 18, true).asImageBitmap() }.getOrNull() ?: image
            }
            delay(600)
        }
    }
    // A touch more colour than the frame (the wash should glow, not look muddy), toned down like the design's dusk.
    val matrix = remember {
        ColorMatrix().apply { setToSaturation(1.35f) }.also { m ->
            val dim = ColorMatrix(floatArrayOf(0.9f, 0f, 0f, 0f, -8f, 0f, 0.9f, 0f, 0f, -8f, 0f, 0f, 0.9f, 0f, -8f, 0f, 0f, 0f, 1f, 0f))
            m.timesAssign(dim)
        }
    }
    Box(modifier.fillMaxSize().background(Theme.background)) {
        image?.let {
            Image(it, null, Modifier.fillMaxSize().alpha(if (page) 0.7f else 0.85f), contentScale = ContentScale.Crop,
                filterQuality = FilterQuality.High, colorFilter = ColorFilter.colorMatrix(matrix))
        }
        val stops = if (page) arrayOf(0f to Wash.copy(alpha = 0.25f), 0.45f to Wash.copy(alpha = 0.55f), 1f to Wash.copy(alpha = 0.94f))
        else arrayOf(0f to Wash.copy(alpha = 0.72f), 0.1f to Wash.copy(alpha = 0.35f), 0.4f to Wash.copy(alpha = 0.3f),
            0.5f to Wash.copy(alpha = 0.82f), 0.66f to Wash.copy(alpha = 0.96f))
        Box(Modifier.fillMaxSize().background(Brush.verticalGradient(*stops)))
    }
}

/**
 * The design's bottom panel (Tools, Drive, Quality, More): rounded top with a grabber, a Barlow title
 * and a close button, the live view still visible above it. Drag the top down or tap outside to close.
 */
@Composable
fun BottomPanel(visible: Boolean, onClose: () -> Unit, title: String? = null, dimsBehind: Boolean = true,
                content: @Composable ColumnScope.() -> Unit) {
    BackHandler(enabled = visible, onBack = onClose)
    Box(Modifier.fillMaxSize()) {
        AnimatedVisibility(visible && dimsBehind, enter = fadeIn(), exit = fadeOut()) {
            Box(Modifier.fillMaxSize().background(Wash.copy(alpha = 0.3f))
                .clickable(remember { MutableInteractionSource() }, null, onClick = onClose))
        }
        AnimatedVisibility(visible, Modifier.align(Alignment.BottomCenter),
            enter = slideInVertically(spring(dampingRatio = 0.9f, stiffness = 500f)) { it },
            exit = slideOutVertically { it }) {
            var drag by remember { mutableStateOf(0f) }
            val scope = rememberCoroutineScope()
            val shape = RoundedCornerShape(topStart = 28.dp, topEnd = 28.dp)
            Column(
                Modifier.padding(top = 120.dp).widthIn(max = 640.dp).fillMaxWidth()
                    .offset { IntOffset(0, drag.roundToInt()) }
                    .clip(shape).background(Theme.background, shape).border(1.dp, Theme.outline, shape)
                    .clickable(remember { MutableInteractionSource() }, null) {}
                    .navigationBarsPadding(),
            ) {
                Column(Modifier.fillMaxWidth().pointerInput(Unit) {
                    var total = 0f
                    detectVerticalDragGestures(
                        onDragStart = { total = 0f },
                        onDragEnd = {
                            if (total > 90.dp.toPx()) onClose()
                            val from = drag
                            scope.launch { Animatable(from).animateTo(0f, spring(dampingRatio = 0.68f)) { drag = value } }
                        },
                    ) { change, amount ->
                        total += amount
                        drag = maxOf(0f, total)
                        change.consume()
                    }
                }, horizontalAlignment = Alignment.CenterHorizontally) {
                    Box(Modifier.padding(top = 8.dp).size(40.dp, 5.dp).background(Color(0xFF4A4946), RoundedCornerShape(50)))
                    if (title != null) {
                        Row(Modifier.fillMaxWidth().heightIn(min = 48.dp).padding(start = 20.dp, end = 8.dp),
                            verticalAlignment = Alignment.CenterVertically) {
                            Text(title, style = Theme.num(26.sp), color = Theme.text, modifier = Modifier.weight(1f).semantics { heading() })
                            CloseButton(onClose)
                        }
                    }
                }
                Column(Modifier.verticalScroll(rememberScrollState()), content = content)
            }
        }
    }
}

@Composable
fun CloseButton(onClose: () -> Unit, color: Color = Theme.text) {
    Box(Modifier.size(Theme.target).clickable(role = Role.Button, onClick = onClose), contentAlignment = Alignment.Center) {
        Icon(Icons.Filled.Close, "Close", tint = color, modifier = Modifier.size(20.dp))
    }
}

/**
 * A full-screen page (the design's tool screens, settings, log, report): over everything, its own
 * background, closed with Back. `ambient` puts the blurred live view behind it instead of flat black.
 */
@Composable
fun FullScreenPage(onDismiss: () -> Unit, camera: CameraModel? = null, background: Color = Theme.background,
                   content: @Composable BoxScope.() -> Unit) {
    Dialog(onDismissRequest = onDismiss,
        properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false)) {
        Box(Modifier.fillMaxSize().background(background)) {
            if (camera != null) LiveBackdrop(camera, page = true)
            CompositionLocalProvider(LocalContentColor provides Theme.text) {
                Box(Modifier.fillMaxSize().safeDrawingPadding(), content = content)
            }
        }
    }
}

/** A screen's top bar: a title (centred, or after `leading`) and buttons at either end. */
@Composable
fun ScreenHeader(title: String, modifier: Modifier = Modifier, centred: Boolean = false, titleSize: TextUnit = 15.sp,
                 leading: @Composable RowScope.() -> Unit = {}, trailing: @Composable RowScope.() -> Unit = {}) {
    Box(modifier.fillMaxWidth().heightIn(min = Theme.target).padding(horizontal = 20.dp), contentAlignment = Alignment.Center) {
        if (centred) Text(title, color = Theme.text, fontSize = titleSize, fontWeight = FontWeight.SemiBold, maxLines = 1,
            modifier = Modifier.semantics { heading() })
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            leading()
            if (!centred) Text(title, color = Theme.text, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, maxLines = 1,
                modifier = Modifier.semantics { heading() })
            Spacer(Modifier.weight(1f))
            trailing()
        }
    }
}

/** A text button in a screen header ("Done", "Cancel"). */
@Composable
fun HeaderButton(title: String, color: Color = Theme.text, enabled: Boolean = true, onClick: () -> Unit) {
    Box(Modifier.heightIn(min = Theme.target).widthIn(min = Theme.target)
        .clickable(enabled = enabled, role = Role.Button, onClick = onClick).alpha(if (enabled) 1f else 0.4f),
        contentAlignment = Alignment.Center) {
        Text(title, color = color, fontSize = 15.sp)
    }
}

/**
 * A question before something that can't be taken back (226). The compact card (one line and the
 * action, near the top) has no Cancel: a tap outside or Back cancels. The full one has a message, the
 * action as a filled capsule and Cancel under it.
 */
@Composable
fun DialogCard(visible: Boolean, title: String, action: String, onAction: () -> Unit, onCancel: () -> Unit,
               message: String? = null, actionColor: Color = Theme.red, compact: Boolean = false) {
    BackHandler(enabled = visible, onBack = onCancel)
    Box(Modifier.fillMaxSize()) {
        AnimatedVisibility(visible, enter = fadeIn(), exit = fadeOut()) {
            Box(Modifier.fillMaxSize().background(Wash.copy(alpha = 0.7f))
                .clickable(remember { MutableInteractionSource() }, null, onClick = onCancel))
        }
        AnimatedVisibility(visible,
            Modifier.align(if (compact) Alignment.TopCenter else Alignment.Center)
                .padding(top = if (compact) 66.dp else 0.dp, bottom = if (compact) 0.dp else 60.dp),
            enter = scaleIn(initialScale = 0.94f) + fadeIn(), exit = scaleOut(targetScale = 0.94f) + fadeOut()) {
            val shape = RoundedCornerShape(24.dp)
            Box(Modifier.padding(horizontal = 28.dp).widthIn(max = 420.dp).fillMaxWidth()
                .background(Theme.surface, shape).border(1.dp, Theme.outline, shape)
                .clickable(remember { MutableInteractionSource() }, null) {}) {
                if (compact) {
                    Row(Modifier.padding(horizontal = 24.dp, vertical = 20.dp), verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        Text(title, style = Theme.num(24.sp), color = Theme.text, modifier = Modifier.weight(1f))
                        Box(Modifier.heightIn(min = Theme.target).clip(RoundedCornerShape(50)).background(Theme.text)
                            .clickable(role = Role.Button, onClick = onAction).padding(horizontal = 18.dp),
                            contentAlignment = Alignment.Center) {
                            Text(action, color = Theme.background, fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
                        }
                    }
                } else {
                    Column(Modifier.padding(24.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        Text(title, style = Theme.num(28.sp), color = Theme.text)
                        if (message != null) Text(message, color = Theme.secondary, fontSize = 15.sp, lineHeight = 21.sp)
                        Spacer(Modifier.height(6.dp))
                        Box(Modifier.fillMaxWidth().heightIn(min = 50.dp).clip(RoundedCornerShape(50)).background(actionColor)
                            .clickable(role = Role.Button, onClick = onAction), contentAlignment = Alignment.Center) {
                            Text(action, color = Theme.background, fontSize = 16.sp, fontWeight = FontWeight.SemiBold)
                        }
                        Box(Modifier.fillMaxWidth().heightIn(min = 48.dp).clickable(role = Role.Button, onClick = onCancel),
                            contentAlignment = Alignment.Center) {
                            Text("Cancel", color = Theme.text, fontSize = 16.sp)
                        }
                    }
                }
            }
        }
    }
}

/** A big Barlow headline, one line per "\n", tight leading (Presets, Pro, the connect screen). */
@Composable
fun SolidHeadline(text: String, size: TextUnit, modifier: Modifier = Modifier, color: Color = Theme.text, leading: Float = 0.9f) {
    Column(modifier.semantics { heading() }) {
        text.split("\n").forEach { line ->
            Box(Modifier.height((size.value * leading).dp), contentAlignment = Alignment.CenterStart) {
                AutoFitText(line, Theme.num(size), color, textAlign = TextAlign.Start)
            }
        }
    }
}

/** The alternative to the primary: a 54 dp capsule with a 1.5 dp outline. */
@Composable
fun OutlineButton(onClick: () -> Unit, modifier: Modifier = Modifier, color: Color = Theme.text, enabled: Boolean = true,
                  content: @Composable RowScope.() -> Unit) {
    Row(modifier.heightIn(min = 54.dp).clip(RoundedCornerShape(50)).border(1.5.dp, color, RoundedCornerShape(50))
        .clickable(enabled = enabled, role = Role.Button, onClick = onClick).alpha(if (enabled) 1f else 0.4f)
        .padding(horizontal = 24.dp),
        horizontalArrangement = Arrangement.spacedBy(10.dp, Alignment.CenterHorizontally), verticalAlignment = Alignment.CenterVertically) {
        CompositionLocalProvider(LocalContentColor provides color,
            androidx.compose.material3.LocalTextStyle provides TextStyle(fontSize = 16.sp, fontWeight = FontWeight.SemiBold)) { content() }
    }
}

/** A selectable chip: text-on-light when chosen, outlined when not. */
@Composable
fun ChipButton(text: String, selected: Boolean, modifier: Modifier = Modifier, enabled: Boolean = true, outlined: Boolean = true, onClick: () -> Unit) {
    val shape = RoundedCornerShape(50)
    val view = androidx.compose.ui.platform.LocalView.current
    Box(modifier.heightIn(min = Theme.target).clip(shape)
        .background(if (selected) Theme.text else Color.Transparent, shape)
        .then(if (!selected && outlined) Modifier.border(1.dp, Theme.outline, shape) else Modifier)
        .clickable(enabled = enabled, role = Role.Button) { Feedback.play(Feedback.Moment.SELECT, view); onClick() }.alpha(if (enabled) 1f else 0.4f)
        .padding(horizontal = 16.dp), contentAlignment = Alignment.Center) {
        Text(text, color = if (selected) Theme.background else Theme.secondary, fontSize = 14.sp,
            fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Normal, maxLines = 1)
    }
}

/** A label and segmented Barlow choices, the chosen one underlined in the accent (dkit "seg"). */
@Composable
fun <T> SegRow(label: String, options: List<T>, selection: T, onSelect: (T) -> Unit, title: (T) -> String, accent: Color = Theme.accent) {
    FeedbackOnChange(Feedback.Moment.SELECT, selection)
    Row(Modifier.fillMaxWidth().hairRow(54.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(label, color = Theme.secondary, fontSize = 13.sp, modifier = Modifier.weight(1f))
        Row(horizontalArrangement = Arrangement.spacedBy(2.dp)) {
            options.forEach { option ->
                val on = option == selection
                Box(Modifier.heightIn(min = Theme.target).clickable(role = Role.RadioButton) { onSelect(option) }.padding(horizontal = 9.dp),
                    contentAlignment = Alignment.Center) {
                    Text(title(option), style = Theme.num(18.sp, medium = !on), color = if (on) accent else Theme.secondary)
                    if (on) Box(Modifier.align(Alignment.BottomCenter).fillMaxWidth().height(2.dp).background(accent))
                }
            }
        }
    }
}

/** One cell of a PairRow: a small label over a Barlow value; tappable when it has an action. */
data class PairCell(val label: String, val value: String, val action: (() -> Unit)? = null)

/** Two or three values side by side over a hairline (dkit "pair"). */
@Composable
fun PairRow(cells: List<PairCell>) {
    Row(Modifier.fillMaxWidth().hairRow(78.dp), verticalAlignment = Alignment.CenterVertically) {
        cells.forEachIndexed { index, cell ->
            val align = when (index) {
                0 -> Alignment.Start
                cells.size - 1 -> Alignment.End
                else -> Alignment.CenterHorizontally
            }
            Column(Modifier.weight(1f).then(if (cell.action != null) Modifier.clickable(role = Role.Button, onClick = cell.action) else Modifier),
                horizontalAlignment = align, verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(cell.label, color = Theme.secondary, fontSize = 12.sp)
                Text(cell.value, style = Theme.num(30.sp), color = Theme.text, maxLines = 1)
            }
        }
    }
}

/** A note between rows: small secondary text, or a warning in the accent with a triangle. */
@Composable
fun NoteRow(text: String, color: Color = Theme.secondary, warning: Boolean = false) {
    Row(Modifier.fillMaxWidth().hairRow().padding(vertical = 12.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        if (warning) Icon(Icons.Filled.WarningAmber, null, tint = Theme.accent, modifier = Modifier.size(16.dp))
        Text(text, color = if (warning) Theme.accent else color, fontSize = 13.sp, lineHeight = 18.sp)
    }
}

/** A section's caps label, with room above it. */
@Composable
fun SectionLabel(text: String) {
    CapsLabel(text, modifier = Modifier.fillMaxWidth().padding(top = 18.dp, bottom = 6.dp))
}
