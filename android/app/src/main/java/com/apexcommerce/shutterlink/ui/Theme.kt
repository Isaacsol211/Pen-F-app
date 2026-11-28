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
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import com.apexcommerce.shutterlink.R
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

// Shutterlink's look, direction D (port of Design.swift): near-black, one warm accent for whatever is
// selected or live, Barlow Condensed for every number, hairlines instead of cards, capsule buttons, and
// nothing to tap smaller than 44 dp. The spec is docs/design/d-full-app/D-SPEC.md in the iOS repo.

object Theme {
    /** The one accent: selected, active, live, the primary button. */
    val accent = Color(0xFFF2C46D)
    /** Text and icons on the accent. */
    val onAccent = Color(0xFF0A0A0A)
    val background = Color(0xFF0A0A0A)
    /** Dialogs, sheets, cards. */
    val surface = Color(0xFF161614)
    val surfaceRaised = Color(0xFF1F1F1D)
    /** Hairline between rows; `outline` for a stronger edge (chips, outline buttons). */
    val stroke = Color(0xFF2C2C2A)
    val outline = Color(0xFF3A3A37)
    val text = Color(0xFFF4F1EA)
    val secondary = Color(0xFFA9A8A2)
    val tertiary = Color(0xFF8F8E88)
    /** Connected, done. */
    val green = Color(0xFF6CD39B)
    /** Recording, destructive, night. */
    val red = Color(0xFFFF5B4F)
    /** Warnings (D has no orange; a warmer accent). */
    val orange = Color(0xFFF0A55A)
    /** Astro screens. */
    val astroBackground = Color(0xFF05070D)
    val astroText = Color(0xFFEEF1F7)
    val astroAccent = Color(0xFF9CC0FF)
    /** Minimum touch target. */
    val target: Dp = 44.dp

    /** Barlow Condensed (bundled, OFL) for numbers, readouts and big headings. */
    val barlow = FontFamily(
        Font(R.font.barlow_condensed_semibold, FontWeight.SemiBold),
        Font(R.font.barlow_condensed_medium, FontWeight.Medium),
    )

    /** Barlow Condensed at `size`: SemiBold (600) by default, or Medium (500). */
    fun num(size: TextUnit, medium: Boolean = false) =
        TextStyle(fontFamily = barlow, fontSize = size, fontWeight = if (medium) FontWeight.Medium else FontWeight.SemiBold)

    val colors: ColorScheme = darkColorScheme(
        primary = accent, onPrimary = onAccent, secondary = accent, onSecondary = onAccent,
        background = background, onBackground = text, surface = surface, onSurface = text,
        surfaceVariant = surfaceRaised, onSurfaceVariant = secondary, outline = outline, outlineVariant = stroke,
        surfaceContainer = surface, surfaceContainerHigh = surfaceRaised, surfaceContainerLow = surface,
        surfaceContainerHighest = surfaceRaised, surfaceContainerLowest = background, error = red,
    )
}

@Composable
fun ShutterlinkTheme(content: @Composable () -> Unit) {
    MaterialTheme(colorScheme = Theme.colors) {
        CompositionLocalProvider(LocalContentColor provides Theme.text, content = content)
    }
}

/** A flat surface with a hairline edge, in `shape`: for dialogs, chips and overlays. Over the live image it's darker and see-through. */
fun Modifier.surface(shape: Shape, overImage: Boolean = false, tint: Color? = null): Modifier =
    this.clip(shape)
        .background(if (overImage) Color.Black.copy(alpha = 0.55f) else Theme.surface, shape)
        .then(if (tint != null) Modifier.background(tint, shape) else Modifier)
        .border(1.dp, Theme.stroke, shape)

val Pill = RoundedCornerShape(percent = 50)

/** Small-caps label above a readout ("SHUTTER", "ISO"): 11 sp, tracked. */
@Composable
fun CapsLabel(text: String, color: Color = Theme.secondary, size: TextUnit = 11.sp, modifier: Modifier = Modifier) {
    Text(
        text.uppercase(), modifier = modifier, color = color, maxLines = 1, overflow = TextOverflow.Clip,
        style = TextStyle(fontSize = size, fontWeight = FontWeight.Medium, letterSpacing = 0.14.em),
    )
}

/** The mark and the wordmark (the redesign's Finder mark, ui/BrandMark.kt). */
@Composable
fun BrandLockup(markSize: Dp) = FinderLockup(markSize)

/** The app's wordmark: tracked capitals, as on a camera's top plate. */
@Composable
fun Wordmark(size: TextUnit = 22.sp) {
    Text("SHUTTERLINK", color = Theme.text, maxLines = 1,
        style = Theme.num(size * 1.15f).copy(letterSpacing = 0.2.em))
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
            .background(if (pressed) Theme.surfaceRaised else Color.Transparent, shape)
            .then(if (tint != null) Modifier.background(tint, shape) else Modifier)
            .border(1.dp, Theme.outline, shape)
            .clickable(interaction, null, enabled = enabled, role = Role.Button, onClick = onClick)
            .padding(horizontal = if (circle) 0.dp else 18.dp)
            .alpha(if (enabled) 1f else 0.45f),
        horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.CenterHorizontally),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        CompositionLocalProvider(
            LocalContentColor provides Theme.text,
            androidx.compose.material3.LocalTextStyle provides TextStyle(fontSize = 15.sp, fontWeight = FontWeight.SemiBold),
        ) { content() }
    }
}

/** The one filled button per screen: accent capsule, 54 dp. */
@Composable
fun AccentButton(onClick: () -> Unit, modifier: Modifier = Modifier, enabled: Boolean = true, content: @Composable RowScope.() -> Unit) {
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    val shape = Pill
    Row(
        modifier
            .heightIn(min = 54.dp)
            .clip(shape)
            .background(if (enabled) Theme.accent else Theme.accent.copy(alpha = 0.45f), shape)
            .clickable(interaction, null, enabled = enabled, role = Role.Button, onClick = onClick)
            .alpha(if (pressed) 0.8f else 1f)
            .padding(horizontal = 24.dp),
        horizontalArrangement = Arrangement.spacedBy(10.dp, Alignment.CenterHorizontally),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        CompositionLocalProvider(
            LocalContentColor provides Theme.onAccent,
            androidx.compose.material3.LocalTextStyle provides TextStyle(fontSize = 16.sp, fontWeight = FontWeight.SemiBold),
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

/** Readout style: Barlow Condensed (it used to be monospaced; every number is Barlow in direction D). */
fun monoStyle(size: TextUnit, weight: FontWeight = FontWeight.SemiBold) =
    TextStyle(fontFamily = Theme.barlow, fontSize = size * 1.15f,
        fontWeight = if (weight == FontWeight.Normal || weight == FontWeight.Medium) FontWeight.Medium else FontWeight.SemiBold)

@Composable
fun Hairline(modifier: Modifier = Modifier) {
    Box(modifier.background(Theme.stroke))
}
