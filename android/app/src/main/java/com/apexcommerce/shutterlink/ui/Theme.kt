package com.apexcommerce.shutterlink.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ColorScheme
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.em
import androidx.compose.ui.unit.sp
import kotlin.math.PI
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin
import kotlin.math.sqrt

// Shutterlink's look (port of Design.swift): a pro-camera instrument panel. Pure black, solid
// surfaces with a hairline edge, one accent colour (amber) for whatever is selected or live, big
// monospaced readouts, small-caps labels, and nothing to tap smaller than 44 dp.

object Theme {
    /** The one accent: selected, active, live. */
    val accent = Color(1.0f, 0.69f, 0.16f)
    /** Text and icons on the accent. */
    val onAccent = Color.Black
    val background = Color.Black
    /** Panels, cells and buttons. */
    val surface = Color(0.085f, 0.085f, 0.085f)
    val surfaceRaised = Color(0.13f, 0.13f, 0.13f)
    val stroke = Color.White.copy(alpha = 0.13f)
    /** Secondary text: 0.74 white keeps it above 4.5:1 on the surfaces. */
    val secondary = Color.White.copy(alpha = 0.74f)
    val tertiary = Color.White.copy(alpha = 0.55f)
    val red = Color(1f, 0.27f, 0.23f)
    val green = Color(0.2f, 0.84f, 0.29f)
    val orange = Color(1f, 0.62f, 0.04f)
    /** Minimum touch target. */
    val target: Dp = 44.dp

    val colors: ColorScheme = darkColorScheme(
        primary = accent, onPrimary = onAccent, secondary = accent, onSecondary = onAccent,
        background = background, onBackground = Color.White, surface = surface, onSurface = Color.White,
        surfaceVariant = surfaceRaised, onSurfaceVariant = secondary, outline = stroke,
        surfaceContainer = surface, surfaceContainerHigh = surfaceRaised, surfaceContainerLow = surface,
        surfaceContainerHighest = surfaceRaised, surfaceContainerLowest = background, error = red,
    )
}

@Composable
fun ShutterlinkTheme(content: @Composable () -> Unit) {
    MaterialTheme(colorScheme = Theme.colors) {
        CompositionLocalProvider(LocalContentColor provides Color.White, content = content)
    }
}

/** A solid instrument-panel surface with a hairline edge; over the live image it's darker and see-through. */
fun Modifier.surface(shape: Shape, overImage: Boolean = false, tint: Color? = null): Modifier =
    this.clip(shape)
        .background(if (overImage) Color.Black.copy(alpha = 0.62f) else Theme.surface, shape)
        .then(if (tint != null) Modifier.background(tint, shape) else Modifier)
        .border(1.dp, Theme.stroke, shape)

val Pill = RoundedCornerShape(percent = 50)

/** Small-caps label above a readout ("SHUTTER", "ISO"): 11 sp, tracked. */
@Composable
fun CapsLabel(text: String, color: Color = Theme.secondary, size: TextUnit = 11.sp, modifier: Modifier = Modifier) {
    Text(
        text.uppercase(), modifier = modifier, color = color, maxLines = 1, overflow = TextOverflow.Clip,
        style = TextStyle(fontSize = size, fontWeight = FontWeight.SemiBold, letterSpacing = 0.1.em),
    )
}

/** The aperture mark and the wordmark: tracked capitals, as on a camera's top plate. */
@Composable
fun BrandLockup(markSize: Dp) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Canvas(Modifier.size(markSize)) { drawAperture() }
        Text("SHUTTERLINK", color = Color.White,
            style = TextStyle(fontSize = if (markSize < 44.dp) 18.sp else 22.sp, fontWeight = FontWeight.Black, letterSpacing = 0.16.em))
    }
}

/** "Beta" next to brands whose drivers have only been tried against mock cameras. */
@Composable
fun BetaBadge() {
    Text("BETA", color = Theme.accent, style = TextStyle(fontSize = 10.sp, fontWeight = FontWeight.Black, letterSpacing = 0.08.em),
        modifier = Modifier.border(1.dp, Theme.accent.copy(alpha = 0.7f), Pill).padding(horizontal = 5.dp, vertical = 1.dp))
}

/** A dark surface button: capsule, or circle for icon-only buttons. At least 44 × 44 dp. */
@Composable
fun SurfaceButton(
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    circle: Boolean = false,
    enabled: Boolean = true,
    tint: Color? = null,
    content: @Composable RowScope.() -> Unit,
) {
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    val shape = if (circle) CircleShape else Pill
    Row(
        modifier
            .defaultMinSize(Theme.target, Theme.target)
            .clip(shape)
            .background(if (pressed) Theme.surfaceRaised else Theme.surface, shape)
            .then(if (tint != null) Modifier.background(tint, shape) else Modifier)
            .border(1.dp, Theme.stroke, shape)
            .clickable(interaction, null, enabled = enabled, role = Role.Button, onClick = onClick)
            .padding(horizontal = if (circle) 0.dp else 16.dp)
            .alpha(if (enabled) 1f else 0.45f),
        horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.CenterHorizontally),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        CompositionLocalProvider(LocalContentColor provides Color.White) { content() }
    }
}

/** The one filled button per screen: amber with black text. */
@Composable
fun AccentButton(onClick: () -> Unit, modifier: Modifier = Modifier, enabled: Boolean = true, content: @Composable RowScope.() -> Unit) {
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    val shape = RoundedCornerShape(16.dp)
    Row(
        modifier
            .heightIn(min = 54.dp)
            .clip(shape)
            .background(if (enabled) Theme.accent else Theme.accent.copy(alpha = 0.45f), shape)
            .clickable(interaction, null, enabled = enabled, role = Role.Button, onClick = onClick)
            .alpha(if (pressed) 0.8f else 1f)
            .padding(horizontal = 20.dp),
        horizontalArrangement = Arrangement.spacedBy(10.dp, Alignment.CenterHorizontally),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        CompositionLocalProvider(
            LocalContentColor provides Theme.onAccent,
            androidx.compose.material3.LocalTextStyle provides TextStyle(fontSize = 17.sp, fontWeight = FontWeight.SemiBold),
        ) { content() }
    }
}

/** A titled card: surface, 22 dp corners, 16 dp padding. */
@Composable
fun Card(modifier: Modifier = Modifier, content: @Composable androidx.compose.foundation.layout.ColumnScope.() -> Unit) {
    androidx.compose.foundation.layout.Column(
        modifier.fillMaxWidth().surface(RoundedCornerShape(22.dp)).padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
        content = content,
    )
}

/** A yes/no question before something that can't be taken back: a red confirm button and Cancel. */
@Composable
fun ConfirmDialog(title: String, confirm: String, onDismiss: () -> Unit, text: (@Composable () -> Unit)? = null, onConfirm: () -> Unit) {
    AlertDialog(onDismissRequest = onDismiss, title = { Text(title) }, text = text,
        confirmButton = { TextButton({ onDismiss(); onConfirm() }) { Text(confirm, color = Theme.red) } },
        dismissButton = { TextButton(onDismiss) { Text("Cancel") } })
}

private val lightBlade = Color(0.95f, 0.953f, 0.96f)
private val darkBlade = Color(0.80f, 0.82f, 0.85f)

/**
 * The Shutterlink aperture mark: the same flat drawing as the app icon (tools/make_icon.swift),
 * drawn live so it stays sharp at any size. `monochrome` draws outlines only in one colour, without the link.
 */
fun DrawScope.drawAperture(monochrome: Color? = null, box: Size = size) {
    val side = min(box.width, box.height)
    // Drawn in a 1024 box, mark centred at 45.5 %, y up (flipped below).
    val k = side / 1024f * 1.12f
    translate((box.width - side) / 2, (box.height + side) / 2) {
        scale(1f, -1f, pivot = Offset.Zero) {
            val c = Offset(side * 0.455f, side * 0.455f)
            val accent = monochrome ?: Theme.accent
            if (monochrome == null) drawCircle(Color.Black, 340 * k, c)
            drawCircle(accent, 312 * k, c, style = Stroke((if (monochrome == null) 30 else 10) * k))
            val outer = 276 * k
            val inner = outer * 0.41f
            val rotation = PI / 12
            val vertices = (0 until 6).map { i ->
                val a = rotation + i * PI / 3
                Offset(c.x + inner * cos(a).toFloat(), c.y + inner * sin(a).toFloat())
            }
            fun rim(i: Int): Offset {
                val a = vertices[(i + 5) % 6]
                val b = vertices[i]
                val len = hypot(b.x - a.x, b.y - a.y)
                val d = Offset((b.x - a.x) / len, (b.y - a.y) / len)
                val p = Offset(b.x - c.x, b.y - c.y)
                val dot = p.x * d.x + p.y * d.y
                val t = -dot + sqrt(max(0f, dot * dot - (p.x * p.x + p.y * p.y - outer * outer)))
                return Offset(b.x + t * d.x, b.y + t * d.y)
            }
            for (i in 0 until 6) {
                val p0 = rim(i)
                val p1 = rim((i + 1) % 6)
                val start = Math.toDegrees(atan2((p0.y - c.y).toDouble(), (p0.x - c.x).toDouble())).toFloat()
                var end = Math.toDegrees(atan2((p1.y - c.y).toDouble(), (p1.x - c.x).toDouble())).toFloat()
                while (end < start) end += 360f
                val blade = Path().apply {
                    moveTo(vertices[i].x, vertices[i].y)
                    lineTo(p0.x, p0.y)
                    arcTo(Rect(c, outer), start, end - start, false)
                    lineTo(vertices[(i + 1) % 6].x, vertices[(i + 1) % 6].y)
                    close()
                }
                if (monochrome != null) {
                    drawPath(blade, monochrome, style = Stroke(6 * k))
                    continue
                }
                drawPath(blade, if (i % 2 == 0) lightBlade else darkBlade)
                drawPath(blade, Color.Black, style = Stroke(12 * k, join = StrokeJoin.Round))
            }
            if (monochrome == null) {
                val hole = Path().apply {
                    moveTo(vertices[0].x, vertices[0].y)
                    vertices.drop(1).forEach { lineTo(it.x, it.y) }
                    close()
                }
                drawPath(hole, accent)
                drawPath(hole, Color.Black, style = Stroke(12 * k))
                val origin = Offset(c.x + 250 * k, c.y + 250 * k)
                for (r in listOf(104f, 176f)) {
                    drawArc(accent, (0.06f * 180f), (0.38f * 180f), false,
                        topLeft = Offset(origin.x - r * k, origin.y - r * k), size = Size(2 * r * k, 2 * r * k),
                        style = Stroke(46 * k, cap = StrokeCap.Round))
                }
            }
        }
    }
}

/** Monospaced readout style. */
fun monoStyle(size: TextUnit, weight: FontWeight = FontWeight.SemiBold) =
    TextStyle(fontFamily = FontFamily.Monospace, fontSize = size, fontWeight = weight)

@Composable
fun Hairline(modifier: Modifier = Modifier) {
    Box(modifier.background(Theme.stroke))
}
