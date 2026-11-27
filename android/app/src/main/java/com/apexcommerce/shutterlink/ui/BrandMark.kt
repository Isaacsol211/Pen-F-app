package com.apexcommerce.shutterlink.ui

import android.provider.Settings
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.LinearOutSlowInEasing
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.wrapContentWidth
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.FilterQuality
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.CanvasDrawScope
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

// The redesigned mark (port of BrandMark.swift): the "Finder" mark, the lockup at the top of the
// Connect screen, the launch hand-off, and the design's dusk picture for screens with no live view.

/**
 * The Shutterlink "Finder" mark: four frame corners round an accent focus point, the same drawing as
 * the iOS app icon and launch screen, drawn live so it stays sharp at any size. `monochrome` draws it
 * in one colour (for faint backgrounds).
 */
@Composable
fun FinderMark(modifier: Modifier = Modifier, monochrome: Color? = null) {
    Canvas(modifier) { drawFinderMark(monochrome) }
}

/** The Finder mark in a 120 box, centred in `box`. */
fun DrawScope.drawFinderMark(monochrome: Color? = null, box: Size = size) {
    val side = min(box.width, box.height)
    val k = side / 120f
    translate((box.width - side) / 2, (box.height - side) / 2) {
        scale(k, k, pivot = Offset.Zero) {
            val corners = Path().apply {
                moveTo(22f, 46f); lineTo(22f, 22f); lineTo(46f, 22f)
                moveTo(74f, 22f); lineTo(98f, 22f); lineTo(98f, 46f)
                moveTo(98f, 74f); lineTo(98f, 98f); lineTo(74f, 98f)
                moveTo(46f, 98f); lineTo(22f, 98f); lineTo(22f, 74f)
            }
            drawPath(corners, monochrome ?: Theme.text, style = Stroke(8f, cap = StrokeCap.Round, join = StrokeJoin.Round))
            drawCircle(monochrome ?: Theme.accent, 11f, Offset(60f, 60f))
        }
    }
}

/**
 * Mark + name, as at the top of the Connect screen (the design's lockup: the mark at 28 dp and the
 * name in 18 sp semibold, a little larger from a 44 dp `markSize` up).
 */
@Composable
fun FinderLockup(markSize: Dp, modifier: Modifier = Modifier) {
    val scale = max(1f, markSize.value / 44f)
    Row(
        modifier.heightIn(min = Theme.target).clearAndSetSemantics { contentDescription = "Shutterlink"; heading() },
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        FinderMark(Modifier.size((28 * scale).dp))
        Text("Shutterlink", color = Theme.text, fontSize = (18 * scale).sp, fontWeight = FontWeight.SemiBold, maxLines = 1)
    }
}

/** True when the system's animations are off (Settings ▸ Accessibility ▸ Remove animations). */
@Composable
fun rememberReduceMotion(): Boolean {
    val context = LocalContext.current
    return remember {
        runCatching { Settings.Global.getFloat(context.contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f) == 0f }
            .getOrDefault(false)
    }
}

/** Shown once per launch (per process). */
private var launchHandoffShown = false

/**
 * Continues the launch (101): the dusk picture fades in behind the mark and the name, then it all
 * fades away so the app appears without the mark jumping. Put it over everything at the app's root;
 * it shows once per process and then removes itself.
 */
@Composable
fun LaunchHandoff() {
    var visible by remember { mutableStateOf(!launchHandoffShown) }
    if (!visible) return
    val reduceMotion = rememberReduceMotion()
    val sceneIn = remember { Animatable(0f) }
    val leaving = remember { Animatable(0f) }
    LaunchedEffect(Unit) {
        launchHandoffShown = true
        launch { sceneIn.animateTo(1f, tween(300, easing = LinearOutSlowInEasing)) }
        delay(900)
        leaving.animateTo(1f, tween(if (reduceMotion) 200 else 450, easing = LinearOutSlowInEasing))
        delay(50)
        visible = false
    }
    Box(
        Modifier.fillMaxSize()
            .graphicsLayer { alpha = 1f - leaving.value }
            .background(Theme.background)
            // Nothing behind it reacts while it's showing.
            .clickable(remember { MutableInteractionSource() }, null) {}
            .clearAndSetSemantics {},
        contentAlignment = Alignment.Center,
    ) {
        Box(Modifier.fillMaxSize().graphicsLayer { alpha = sceneIn.value }) {
            DuskScene(Modifier.fillMaxSize())
            Box(Modifier.fillMaxSize().background(Brush.verticalGradient(listOf(Wash.copy(alpha = 0.25f), Wash.copy(alpha = 0.55f)))))
        }
        Box(Modifier.size(180.dp)) {
            FinderMark(Modifier.fillMaxSize().graphicsLayer {
                val s = if (reduceMotion) 1f else 1f - 0.18f * leaving.value
                scaleX = s
                scaleY = s
            })
            Text("Shutterlink", color = Theme.text, maxLines = 1, softWrap = false,
                style = Theme.num(40.sp).copy(letterSpacing = 0.8.sp),
                modifier = Modifier.align(Alignment.BottomCenter).offset(y = 46.dp).wrapContentWidth(unbounded = true)
                    .graphicsLayer { alpha = sceneIn.value })
        }
    }
}

/**
 * The design's sample picture, dusk over a lake (dkit.py `scene`), for screens with no live view: the
 * first-run cover, and blurred behind the camera list and the connecting screen. Cropped to fill.
 */
@Composable
fun DuskScene(modifier: Modifier = Modifier, night: Boolean = false) {
    Canvas(modifier.clipToBounds()) { drawDusk(night) }
}

/** Draws the dusk picture in the design's 390 × 292 space, scaled to fill this scope and centred (the SVG's `slice`). */
fun DrawScope.drawDusk(night: Boolean = false) {
    val w = 390f
    val h = 292f
    val k = max(size.width / w, size.height / h)
    translate((size.width - w * k) / 2, (size.height - h * k) / 2) {
        scale(k, k, pivot = Offset.Zero) {
            val sky = if (night) arrayOf(0f to Color(0xFF04060F), 0.7f to Color(0xFF0F1530), 1f to Color(0xFF1D2347))
            else arrayOf(0f to Color(0xFF0E1430), 0.42f to Color(0xFF4B4470), 0.7f to Color(0xFFC77F6E), 0.82f to Color(0xFFF3B36F))
            drawRect(Brush.verticalGradient(*sky, startY = 0f, endY = 226f), size = Size(w, 226f))
            val stars = if (night) listOf(
                Triple(22f, 30f, 1.1f), Triple(60f, 70f, 0.8f), Triple(96f, 22f, 1.4f), Triple(130f, 96f, 0.8f), Triple(168f, 48f, 1.1f),
                Triple(204f, 120f, 0.9f), Triple(236f, 30f, 1.3f), Triple(270f, 84f, 0.9f), Triple(306f, 46f, 1.2f), Triple(340f, 110f, 0.8f),
                Triple(368f, 26f, 1f), Triple(44f, 130f, 0.9f), Triple(150f, 150f, 0.7f), Triple(290f, 150f, 0.8f),
            ) else listOf(
                Triple(40f, 30f, 1.1f), Triple(110f, 18f, 1f), Triple(170f, 54f, 1.2f), Triple(250f, 26f, 1f), Triple(330f, 60f, 1.1f),
                Triple(70f, 84f, 0.8f), Triple(300f, 100f, 0.8f),
            )
            stars.forEach { (x, y, r) -> drawCircle(Color.White, r, Offset(x, y)) }
            if (night) {
                drawCircle(Color(0xFFC9D3E8), 9f, Offset(300f, 60f))
                drawCircle(Color(0xFF0A0E20), 8f, Offset(296f, 57f))
            } else {
                drawCircle(Color(0xFFFFE2A6).copy(alpha = 0.22f), 46f, Offset(262f, 190f))
                drawCircle(Color(0xFFFFE2A6), 17f, Offset(262f, 190f))
            }
            fun poly(vararg points: Float) = Path().apply {
                moveTo(points[0], points[1])
                for (i in 2 until points.size step 2) lineTo(points[i], points[i + 1])
                close()
            }
            drawPath(poly(0f, 206f, 50f, 168f, 92f, 192f, 150f, 140f, 204f, 188f, 256f, 160f, 310f, 196f, 390f, 170f, 390f, 226f, 0f, 226f),
                if (night) Color(0xFF141A36) else Color(0xFF3A3460))
            drawPath(poly(0f, 222f, 70f, 200f, 140f, 216f, 210f, 194f, 290f, 218f, 390f, 204f, 390f, 226f, 0f, 226f),
                if (night) Color(0xFF0A0D1C) else Color(0xFF1B1C33))
            drawRect(
                Brush.verticalGradient(if (night) listOf(Color(0xFF141A36), Color(0xFF05070D)) else listOf(Color(0xFFB97C66), Color(0xFF14172B)),
                    startY = 224f, endY = 292f),
                topLeft = Offset(0f, 224f), size = Size(w, 68f),
            )
            if (!night) {
                val glint = Color(0xFFFFE2A6).copy(alpha = 0.6f)
                drawLine(glint, Offset(240f, 234f), Offset(284f, 234f), strokeWidth = 3f, cap = StrokeCap.Round)
                drawLine(glint, Offset(230f, 247f), Offset(294f, 247f), strokeWidth = 3f, cap = StrokeCap.Round)
                drawLine(glint, Offset(246f, 262f), Offset(278f, 262f), strokeWidth = 3f, cap = StrokeCap.Round)
            }
        }
    }
}

/**
 * The design's backdrop with no live view (103, 104): the dusk picture blurred and dimmed, fading to
 * near-black at the bottom.
 */
@Composable
fun DuskBackdrop(modifier: Modifier = Modifier, dim: Float = 0.35f) {
    Box(modifier.fillMaxSize().background(Theme.background).clearAndSetSemantics {}) {
        BlurredDusk(Modifier.fillMaxSize().graphicsLayer { alpha = dim })
        Box(Modifier.fillMaxSize().background(Brush.verticalGradient(0.44f to Wash.copy(alpha = 0f), 0.81f to Wash.copy(alpha = 0.96f))))
    }
}

/**
 * The dusk picture, 1.2× and heavily blurred. The blur is a tiny copy (about one pixel per 30 dp)
 * scaled back up with filtering, like LiveBackdrop: it works on every Android version, unlike Modifier.blur.
 */
@Composable
private fun BlurredDusk(modifier: Modifier) {
    val density = LocalDensity.current
    var area by remember { mutableStateOf(IntSize.Zero) }
    val image = remember(area) {
        if (area.width == 0 || area.height == 0) return@remember null
        val cell = with(density) { 30.dp.toPx() }
        val w = (area.width / cell).roundToInt().coerceAtLeast(2)
        val h = (area.height / cell).roundToInt().coerceAtLeast(2)
        runCatching {
            val bitmap = ImageBitmap(w, h)
            CanvasDrawScope().draw(Density(1f), LayoutDirection.Ltr, androidx.compose.ui.graphics.Canvas(bitmap), Size(w.toFloat(), h.toFloat())) {
                drawRect(Theme.background)
                scale(1.2f) { drawDusk() }
            }
            bitmap
        }.getOrNull()
    }
    Box(modifier.onSizeChanged { area = it }) {
        image?.let {
            Image(it, null, Modifier.fillMaxSize(), contentScale = ContentScale.FillBounds, filterQuality = FilterQuality.High)
        }
    }
}
