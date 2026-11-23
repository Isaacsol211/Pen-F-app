package com.apexcommerce.shutterlink.ui

import android.graphics.RectF
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.gestures.detectTransformGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Videocam
import androidx.compose.material.icons.filled.VideocamOff
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.FilterQuality
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.apexcommerce.shutterlink.camera.CameraMode
import com.apexcommerce.shutterlink.camera.CameraModel
import kotlinx.coroutines.launch
import kotlin.math.min
import kotlin.math.roundToInt

/** The image's rectangle inside `bounds` (aspect fit). */
private fun fitRect(contentW: Double, contentH: Double, bounds: Size): Rect {
    if (contentW <= 0 || contentH <= 0 || bounds.width <= 0 || bounds.height <= 0) return Rect(Offset.Zero, bounds)
    val scale = min(bounds.width / contentW, bounds.height / contentH).toFloat()
    val w = (contentW * scale).toFloat()
    val h = (contentH * scale).toFloat()
    return Rect(Offset((bounds.width - w) / 2, (bounds.height - h) / 2), Size(w, h))
}

/**
 * Live view with its overlays (port of LiveViewPane.swift): composition grid, AF box, histogram,
 * focus peaking, a focus loupe (pan, pinch, sharpness meter), the shot flash and the status card.
 */
@Composable
fun LiveViewPane(
    camera: CameraModel,
    showGrid: Boolean,
    showHistogram: Boolean,
    showLoupe: Boolean,
    modifier: Modifier = Modifier,
    hudTopInset: androidx.compose.ui.unit.Dp = 0.dp,
) {
    val scope = rememberCoroutineScope()
    val density = LocalDensity.current
    var loupeZoom by remember { mutableFloatStateOf(camera.prefs.getFloat("loupe.zoom", 4f)) }
    var loupeCenter by remember { mutableStateOf(Offset(0.5f, 0.5f)) }
    val flash = remember { Animatable(0f) }

    LaunchedEffect(camera.shotCounter) {
        if (camera.shotCounter > 0) {
            flash.snapTo(0.85f)
            flash.animateTo(0f, tween(350))
        }
    }

    fun clamped(p: Offset): Offset {
        val half = 0.5f / loupeZoom
        return Offset(p.x.coerceIn(half, 1 - half), p.y.coerceIn(half, 1 - half))
    }

    LaunchedEffect(showLoupe) {
        if (showLoupe) loupeCenter = clamped(camera.focusPoint?.let { Offset(it.first.toFloat(), it.second.toFloat()) } ?: Offset(0.5f, 0.5f))
    }
    LaunchedEffect(showLoupe, loupeCenter, loupeZoom) {
        if (showLoupe) {
            val half = 0.5f / loupeZoom
            camera.setFocusMeterRegion(RectF(loupeCenter.x - half, loupeCenter.y - half, loupeCenter.x + half, loupeCenter.y + half))
        } else {
            camera.setFocusMeterRegion(null)
        }
    }

    BoxWithConstraints(modifier.background(Color(0.05f, 0.05f, 0.05f)).clipToBounds()) {
        val bounds = with(density) { Size(maxWidth.toPx(), maxHeight.toPx()) }
        val (fw, fh) = camera.frameSpace
        val imageRect = fitRect(fw, fh, bounds)
        val frame = camera.liveFrame

        // The picture (magnified in the loupe), peaking and grid.
        Canvas(Modifier.fillMaxSize()
            .pointerInput(showLoupe, imageRect) {
                detectTapGestures { location ->
                    if (imageRect.width <= 0) return@detectTapGestures
                    val nx = (location.x - imageRect.left) / imageRect.width
                    val ny = (location.y - imageRect.top) / imageRect.height
                    if (showLoupe) {
                        // In the loupe, a tap re-centres the magnified area on that spot.
                        val half = 0.5f / loupeZoom
                        loupeCenter = clamped(Offset(loupeCenter.x - half + nx / loupeZoom, loupeCenter.y - half + ny / loupeZoom))
                        return@detectTapGestures
                    }
                    if (nx !in 0f..1f || ny !in 0f..1f) return@detectTapGestures
                    scope.launch { camera.tapFocus(nx.toDouble(), ny.toDouble()) }
                }
            }
            .pointerInput(showLoupe, imageRect) {
                if (!showLoupe) return@pointerInput
                detectTransformGestures { _, pan, zoom, _ ->
                    val newZoom = (loupeZoom * zoom).coerceIn(2f, 10f)
                    if (newZoom != loupeZoom) {
                        loupeZoom = newZoom
                        camera.prefs.edit().putFloat("loupe.zoom", newZoom).apply()
                    }
                    loupeCenter = clamped(Offset(loupeCenter.x - pan.x / (imageRect.width * loupeZoom),
                        loupeCenter.y - pan.y / (imageRect.height * loupeZoom)))
                }
            }) {
            val dst = IntOffset(imageRect.left.roundToInt(), imageRect.top.roundToInt())
            val dstSize = IntSize(imageRect.width.roundToInt(), imageRect.height.roundToInt())
            if (frame != null) {
                if (showLoupe) {
                    val half = 0.5f / loupeZoom
                    val src = IntOffset(((loupeCenter.x - half) * frame.width).roundToInt().coerceAtLeast(0),
                        ((loupeCenter.y - half) * frame.height).roundToInt().coerceAtLeast(0))
                    val srcSize = IntSize((frame.width / loupeZoom).roundToInt().coerceAtLeast(1).coerceAtMost(frame.width - src.x),
                        (frame.height / loupeZoom).roundToInt().coerceAtLeast(1).coerceAtMost(frame.height - src.y))
                    drawImage(frame, src, srcSize, dst, dstSize, filterQuality = FilterQuality.Low)
                } else {
                    drawImage(frame, IntOffset.Zero, IntSize(frame.width, frame.height), dst, dstSize, filterQuality = FilterQuality.Low)
                    camera.peakingOverlay?.let { overlay ->
                        drawImage(overlay, IntOffset.Zero, IntSize(overlay.width, overlay.height), dst, dstSize, filterQuality = FilterQuality.None)
                    }
                }
            }
            if (showGrid && !showLoupe) {
                val line = Color.White.copy(alpha = 0.35f)
                for (i in 1..2) {
                    val x = imageRect.left + imageRect.width * i / 3
                    val y = imageRect.top + imageRect.height * i / 3
                    drawLine(line, Offset(x, imageRect.top), Offset(x, imageRect.bottom), 1f)
                    drawLine(line, Offset(imageRect.left, y), Offset(imageRect.right, y), 1f)
                }
            }
            // AF result box from the camera, or brackets where the user tapped.
            if (!showLoupe && fw > 0) {
                val sx = imageRect.width / fw.toFloat()
                val sy = imageRect.height / fh.toFloat()
                val info = camera.liveInfo
                val point = camera.focusPoint
                if (info.afState > 0 && info.afRect.w > 0) {
                    val r = info.afRect
                    drawRect(if (info.afState == 1) Theme.green else Theme.red,
                        topLeft = Offset(imageRect.left + (r.x * sx).toFloat(), imageRect.top + (r.y * sy).toFloat()),
                        size = Size((r.w * sx).toFloat(), (r.h * sy).toFloat()), style = Stroke(2.dp.toPx()))
                } else if (point != null) {
                    val c = Offset(imageRect.left + point.first.toFloat() * imageRect.width, imageRect.top + point.second.toFloat() * imageRect.height)
                    val s = 28.dp.toPx()
                    val arm = 10.dp.toPx()
                    val w = 2.dp.toPx()
                    for ((dx, dy) in listOf(-1f to -1f, 1f to -1f, -1f to 1f, 1f to 1f)) {
                        val corner = Offset(c.x + dx * s, c.y + dy * s)
                        drawLine(Color.White, corner, Offset(corner.x - dx * arm, corner.y), w)
                        drawLine(Color.White, corner, Offset(corner.x, corner.y - dy * arm), w)
                    }
                }
            }
            if (flash.value > 0) drawRect(Color.White.copy(alpha = flash.value))
        }

        val hist = camera.histogram
        if (showHistogram && !showLoupe && hist != null) {
            HistogramView(hist, Modifier.align(Alignment.TopEnd)
                .padding(top = hudTopInset + 10.dp + if (camera.focusPoint != null) 48.dp else 0.dp, end = 10.dp)
                .surface(RoundedCornerShape(12.dp), overImage = true).padding(horizontal = 8.dp, vertical = 6.dp)
                .width(100.dp).height(36.dp))
        }

        if (camera.focusPoint != null && !showLoupe) {
            SurfaceButton(onClick = { scope.launch { camera.clearFocus() } },
                modifier = Modifier.align(Alignment.TopEnd).padding(top = hudTopInset + 10.dp, end = 10.dp)) {
                Text("AF", fontSize = 12.sp, fontWeight = FontWeight.SemiBold)
                Icon(Icons.Filled.Close, "Clear focus point", Modifier.size(14.dp))
            }
        }

        if (showLoupe) LoupeHud(camera, loupeZoom, loupeCenter, Modifier.align(Alignment.BottomCenter))

        StatusOverlay(camera)
    }
}

@Composable
private fun LoupeHud(camera: CameraModel, zoom: Float, center: Offset, modifier: Modifier) {
    Row(modifier.padding(10.dp).surface(Pill, overImage = true).padding(horizontal = 14.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Text(String.format(java.util.Locale.US, "%.0f×", zoom), color = Theme.accent, style = monoStyle(13.sp))
        // Sharpness meter: where the current reading sits between the worst and best seen.
        val score = camera.focusScore
        val peak = camera.focusPeak
        val floor = camera.focusFloor
        val level = if (score != null && peak > floor) ((score - floor) / (peak - floor)).toFloat().coerceIn(0f, 1f) else 0f
        CapsLabel("Focus", color = Theme.tertiary, size = 10.sp)
        Box(Modifier.width(90.dp).height(6.dp).background(Color.White.copy(alpha = 0.15f), Pill)) {
            Box(Modifier.fillMaxWidth(level).height(6.dp).background(if (level > 0.92f) Theme.green else Theme.accent, Pill))
        }
        // Mini-map: where the magnified area is.
        Canvas(Modifier.size(40.dp, 30.dp)) {
            drawRect(Color.White.copy(alpha = 0.35f), style = Stroke(1f))
            val w = size.width / zoom
            val h = size.height / zoom
            drawRect(Theme.accent, topLeft = Offset(center.x * size.width - w / 2, center.y * size.height - h / 2), size = Size(w, h), style = Stroke(1.5f))
        }
    }
}

@Composable
private fun StatusOverlay(camera: CameraModel) {
    val scope = rememberCoroutineScope()
    val now = rememberNow(camera.liveViewRunning, 1000)
    val stalled = camera.isLiveViewStalled(now)
    val noFrame = camera.frameWidth == 0 || camera.liveFrame == null
    if (!(noFrame || stalled || camera.isSwitchingMode || camera.mode != CameraMode.REC)) return
    Box(Modifier.fillMaxSize().background(if (noFrame) Color.Transparent else Color.Black.copy(alpha = 0.45f)), contentAlignment = Alignment.Center) {
        Column(
            Modifier.padding(20.dp).surface(RoundedCornerShape(22.dp)).padding(24.dp),
            horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            when {
                stalled -> {
                    Icon(Icons.Filled.VideocamOff, null, Modifier.size(30.dp))
                    Text("No live view frames are arriving.", fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
                    Text("The camera sends live view to UDP port ${camera.udpPort} on this phone. Check the phone is still on the camera's Wi-Fi, then restart live view.",
                        color = Theme.secondary, fontSize = 13.sp, textAlign = TextAlign.Center)
                    AccentButton(onClick = { scope.launch { camera.restartLiveView() } }) { Text("Restart live view") }
                }
                camera.isSwitchingMode || camera.liveViewRunning || camera.mode != CameraMode.REC -> {
                    CircularProgressIndicator(color = Theme.accent, strokeWidth = 3.dp, modifier = Modifier.size(28.dp))
                    Text(if (camera.mode == CameraMode.REC) "Starting live view…" else "Switching to shooting mode…",
                        color = Theme.secondary, fontSize = 15.sp)
                }
                else -> {
                    Icon(Icons.Filled.Videocam, null, Modifier.size(30.dp))
                    Text("Live view is off", color = Theme.secondary, fontSize = 15.sp)
                    AccentButton(onClick = { scope.launch { camera.restartLiveView() } }) { Text("Start live view") }
                }
            }
        }
    }
}
