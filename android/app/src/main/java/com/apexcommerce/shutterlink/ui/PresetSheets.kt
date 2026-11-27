package com.apexcommerce.shutterlink.ui

import android.content.res.Configuration
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Bookmark
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.NorthEast
import androidx.compose.material.icons.filled.WbSunny
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.apexcommerce.shutterlink.camera.CameraMode
import com.apexcommerce.shutterlink.camera.CameraModel
import com.apexcommerce.shutterlink.camera.NDMeter
import com.apexcommerce.shutterlink.camera.PresetRecipe
import com.apexcommerce.shutterlink.camera.PresetStep
import com.apexcommerce.shutterlink.camera.PropertyFormat
import com.apexcommerce.shutterlink.camera.SavedPreset
import com.apexcommerce.shutterlink.camera.apply
import com.apexcommerce.shutterlink.camera.armMotion
import com.apexcommerce.shutterlink.camera.deleteSavedPreset
import com.apexcommerce.shutterlink.camera.exposeToTheRight
import com.apexcommerce.shutterlink.camera.isPresetOn
import com.apexcommerce.shutterlink.camera.meteredExposure
import com.apexcommerce.shutterlink.camera.ndSeconds
import com.apexcommerce.shutterlink.camera.ndShutter
import com.apexcommerce.shutterlink.camera.ndSteps
import com.apexcommerce.shutterlink.camera.presetOrder
import com.apexcommerce.shutterlink.camera.runPreset
import com.apexcommerce.shutterlink.camera.saveCurrentSettings
import com.apexcommerce.shutterlink.camera.savedPresetsForCamera
import com.apexcommerce.shutterlink.camera.shootNd
import com.apexcommerce.shutterlink.camera.shutterLabel
import com.apexcommerce.shutterlink.camera.steps
import com.apexcommerce.shutterlink.camera.undoPreset
import kotlinx.coroutines.launch
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow

// Presets, the ND filter calculator and the motion trigger (port of the redesign's PresetsViews.swift,
// design screens 310, 311 and 313–315).

// MARK: - Presets (313–315)

/** One-tap recipes, Undo, My presets and Expose to the right, on the blurred live view (313). */
@Composable
fun PresetsSheet(camera: CameraModel, openAstro: () -> Unit, openFocusStack: () -> Unit, onDismiss: () -> Unit) {
    val scope = rememberCoroutineScope()
    var expanded by remember { mutableStateOf<String?>(null) }
    var naming by remember { mutableStateOf(false) }
    var newName by remember { mutableStateOf("") }
    FullScreenPage(onDismiss, camera) {
        Column(Modifier.fillMaxSize()) {
            ScreenHeader("Presets", Modifier.padding(top = 6.dp), trailing = { HeaderButton("Done", onClick = onDismiss) })
            Column(Modifier.weight(1f).fillMaxWidth().verticalScroll(rememberScrollState())
                .padding(horizontal = 20.dp).padding(top = 4.dp, bottom = 20.dp),
                verticalArrangement = Arrangement.spacedBy(16.dp)) {
                SolidHeadline("One tap.\nCamera set.", 60.sp, Modifier.padding(top = 4.dp))
                camera.presetUndo?.let { undo ->
                    // The one thing to undo, outlined in green, with a white Undo button.
                    val shape = RoundedCornerShape(16.dp)
                    Row(Modifier.fillMaxWidth().clip(shape).background(Theme.surface.copy(alpha = 0.85f), shape)
                        .border(1.5.dp, Theme.green.copy(alpha = 0.8f), shape).padding(start = 14.dp, end = 6.dp, top = 6.dp, bottom = 6.dp),
                        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                            Text("Undo ${undo.title}", color = Theme.text, fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
                            Text("Puts back the settings from before it.", color = Theme.secondary, fontSize = 13.sp)
                        }
                        Box(Modifier.heightIn(min = Theme.target).clip(Pill).background(Theme.text)
                            .clickable(enabled = !camera.presetRunning, role = Role.Button) { scope.launch { camera.undoPreset() } }
                            .alpha(if (camera.presetRunning) 0.45f else 1f).padding(horizontal = 20.dp),
                            contentAlignment = Alignment.Center) {
                            Text("Undo", color = Theme.background, fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
                        }
                    }
                }
                HairCard(spacing = 0.dp) {
                    CapsLabel("One tap", modifier = Modifier.padding(bottom = 4.dp))
                    PresetRecipe.entries.forEach { recipe ->
                        PresetRow({ RecipeArt(recipe) }, recipe.title, recipe.summary, on = camera.isPresetOn(recipe.id),
                            opens = recipe == PresetRecipe.ASTRO) {
                            if (recipe == PresetRecipe.ASTRO) openAstro() else expanded = recipe.id
                        }
                    }
                }
                HairCard {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        CapsLabel("My presets", modifier = Modifier.weight(1f))
                        SurfaceButton(onClick = { newName = ""; naming = true }, enabled = camera.properties.isNotEmpty()) {
                            Icon(Icons.Filled.Add, null, Modifier.size(16.dp))
                            Text("Save current", fontSize = 14.sp)
                        }
                    }
                    val saved = camera.savedPresetsForCamera
                    if (saved.isEmpty()) {
                        Text("Set the camera the way you like it, then Save current. Presets are kept for each camera brand.",
                            color = Theme.secondary, fontSize = 13.sp)
                    }
                    saved.forEach { preset ->
                        PresetRow({ SavedTile() }, preset.name, summary(preset), on = camera.isPresetOn(preset.id), opens = false) {
                            expanded = preset.id
                        }
                    }
                }
                HairCard {
                    CapsLabel("Exposure")
                    Text("Expose to the right raises the exposure until the brightest parts are about to clip, then stops a step short: the cleanest RAW files.",
                        color = Theme.secondary, fontSize = 13.sp)
                    SurfaceButton(onClick = { scope.launch { camera.exposeToTheRight() } }, modifier = Modifier.fillMaxWidth(),
                        enabled = !camera.ettrRunning && camera.mode == CameraMode.REC && !camera.isShooting) {
                        if (camera.ettrRunning) CircularProgressIndicator(color = Theme.accent, strokeWidth = 2.dp, modifier = Modifier.size(16.dp))
                        else Icon(Icons.Filled.WbSunny, null, Modifier.size(18.dp))
                        Text(if (camera.ettrRunning) "Measuring…" else "Expose to the right", fontWeight = FontWeight.SemiBold)
                    }
                }
            }
        }
        // 315: the name in the design's dialog card.
        if (naming) {
            SaveNameDialog(newName, { newName = it },
                save = { naming = false; camera.saveCurrentSettings(newName) },
                cancel = { naming = false })
        }
    }
    // 314: a recipe (or a saved preset) on a screen of its own.
    expanded?.let { id -> PresetDetail(camera, id, close = { expanded = null }, openFocusStack = openFocusStack) }
}

/** A section of the presets screen: rows over a hairline (the D replacement for a card). */
@Composable
private fun HairCard(spacing: Dp = 12.dp, content: @Composable ColumnScope.() -> Unit) {
    Column(Modifier.fillMaxWidth().hairRow().padding(vertical = 14.dp), verticalArrangement = Arrangement.spacedBy(spacing), content = content)
}

/** A preset's row: its tile (ringed in green when it's on), the name in Barlow, what it does, ↗ or ›. */
@Composable
private fun PresetRow(tile: @Composable () -> Unit, title: String, subtitle: String, on: Boolean, opens: Boolean, onClick: () -> Unit) {
    Row(Modifier.fillMaxWidth().hairRow().clickable(role = Role.Button, onClick = onClick).padding(vertical = 8.dp)
        .heightIn(min = Theme.target).semantics(mergeDescendants = true) {},
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
        Box(Modifier.drawWithContent {
            drawContent()
            if (on) {
                val out = 4.dp.toPx()
                drawRoundRect(Theme.green, Offset(-out, -out), Size(size.width + 2 * out, size.height + 2 * out),
                    CornerRadius(18.dp.toPx()), style = Stroke(2.5.dp.toPx()))
            }
        }) { tile() }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(title, style = Theme.num(28.sp), color = Theme.text)
            Text(subtitle, color = Theme.secondary, fontSize = 13.sp, lineHeight = 17.sp, maxLines = 2)
        }
        if (on) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                Icon(Icons.Filled.CheckCircle, null, Modifier.size(14.dp), tint = Theme.green)
                Text("On", color = Theme.green, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
            }
        }
        if (opens) Icon(Icons.Filled.NorthEast, null, Modifier.size(16.dp), tint = Theme.tertiary)
        else Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, null, Modifier.size(20.dp), tint = Theme.tertiary)
    }
}

/** A saved preset's tile: a bookmark on a surface. */
@Composable
private fun SavedTile() {
    val shape = RoundedCornerShape(16.dp)
    Box(Modifier.size(68.dp).clip(shape).background(Theme.surface, shape).border(1.dp, Theme.outline, shape), contentAlignment = Alignment.Center) {
        Icon(Icons.Filled.Bookmark, null, Modifier.size(26.dp), tint = Theme.accent)
    }
}

/**
 * A preset on its own screen (314): Close top right, the exposure it sets large ("f/8 · 1/250"), what
 * it will set, a tip, and its buttons at the bottom.
 */
@Composable
private fun PresetDetail(camera: CameraModel, id: String, close: () -> Unit, openFocusStack: () -> Unit) {
    val recipe = PresetRecipe.entries.firstOrNull { it.id == id }
    val saved = if (recipe == null) camera.savedPresetsForCamera.firstOrNull { it.id == id } else null
    if (recipe == null && saved == null) {
        LaunchedEffect(Unit) { close() }
        return
    }
    val title = recipe?.title ?: saved!!.name
    val caption = recipe?.summary ?: summary(saved!!)
    val steps = if (camera.presetResultsFor == id && camera.presetSteps.isNotEmpty()) camera.presetSteps
    else recipe?.let { camera.steps(it) } ?: camera.steps(saved!!)
    val tip = recipe?.tip ?: ""
    val headline = listOf("focalvalue", "shutspeedvalue").mapNotNull { name ->
        steps.firstOrNull { it.property == name }?.value?.let { value ->
            if (name == "focalvalue") "f/" + shortLabel(name, value) else PropertyFormat.display(name, value)
        }
    }.let { if (it.isEmpty()) title else it.joinToString(" · ") }
    ToolScreen(title, close, action = "Close") {
        BigNumber(headline, Modifier.padding(vertical = 12.dp), caption = caption, size = 60.sp)
        SectionLabel("Will set")
        steps.forEach { StepResultRow(it, Modifier.fillMaxWidth().hairRow().padding(vertical = 10.dp)) }
        if (tip.isNotEmpty()) {
            SectionLabel("Tip")
            NoteRow(tip)
        }
        PinnedBottom {
            if (recipe != null) {
                ApplyButton(camera, "Apply ${recipe.title}", recipe.id) { camera.apply(recipe) }
                if (recipe == PresetRecipe.MACRO && camera.capabilities.focusDrive) {
                    OutlineButton(onClick = { close(); openFocusStack() }, modifier = Modifier.fillMaxWidth()) { Text("Focus stack next") }
                }
            } else if (saved != null) {
                ApplyButton(camera, "Apply ${saved.name}", saved.id) { camera.apply(saved) }
                OutlineButton(onClick = { close(); camera.deleteSavedPreset(saved) }, modifier = Modifier.fillMaxWidth(), color = Theme.red) {
                    Text("Delete")
                }
            }
        }
    }
}

/** Applies the setup; once it's on, turns it off again (the settings from before come back). */
@Composable
private fun ApplyButton(camera: CameraModel, title: String, id: String, action: suspend () -> Unit) {
    val scope = rememberCoroutineScope()
    val on = camera.isPresetOn(id)
    AccentButton(onClick = { scope.launch { if (on) camera.undoPreset() else action() } }, modifier = Modifier.fillMaxWidth(),
        enabled = !camera.presetRunning && camera.mode == CameraMode.REC) {
        if (camera.presetRunning) CircularProgressIndicator(color = Theme.onAccent, strokeWidth = 2.dp, modifier = Modifier.size(18.dp))
        AutoFitText(if (camera.presetRunning) "Applying…" else if (on) "Turn off · put back the settings from before" else title,
            TextStyle(fontSize = 16.sp, fontWeight = FontWeight.SemiBold), Theme.onAccent, Modifier.weight(1f, fill = false))
    }
}

/** "Save current settings" (315): the dialog card with a name field, Save and Cancel. */
@Composable
private fun SaveNameDialog(name: String, onName: (String) -> Unit, save: () -> Unit, cancel: () -> Unit) {
    val focus = remember { FocusRequester() }
    BackHandler(onBack = cancel)
    Box(Modifier.fillMaxSize().background(Wash.copy(alpha = 0.7f))
        .clickable(remember { MutableInteractionSource() }, null, onClick = cancel),
        contentAlignment = Alignment.Center) {
        val shape = RoundedCornerShape(24.dp)
        Column(Modifier.padding(horizontal = 28.dp).widthIn(max = 420.dp).fillMaxWidth()
            .background(Theme.surface, shape).border(1.dp, Theme.outline, shape)
            .clickable(remember { MutableInteractionSource() }, null) {}
            .padding(24.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Text("Save current settings", style = Theme.num(28.sp), color = Theme.text)
            Text("Mode, aperture, shutter, ISO, exposure, white balance and drive: whatever the camera lets the app set.",
                color = Theme.secondary, fontSize = 15.sp, lineHeight = 21.sp)
            Column(Modifier.fillMaxWidth().hairRow().padding(vertical = 4.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text("Name", color = Theme.secondary, fontSize = 12.sp)
                BasicTextField(name, onName, Modifier.fillMaxWidth().focusRequester(focus).semantics { contentDescription = "Name" },
                    singleLine = true, textStyle = TextStyle(fontSize = 17.sp, color = Theme.text), cursorBrush = SolidColor(Theme.accent),
                    keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Sentences, imeAction = ImeAction.Done),
                    keyboardActions = KeyboardActions(onDone = { save() }),
                    decorationBox = { field ->
                        Box(Modifier.heightIn(min = Theme.target), contentAlignment = Alignment.CenterStart) { field() }
                    })
            }
            AccentButton(onClick = save, modifier = Modifier.fillMaxWidth().padding(top = 6.dp)) { Text("Save") }
            Box(Modifier.fillMaxWidth().heightIn(min = 48.dp).clickable(role = Role.Button, onClick = cancel), contentAlignment = Alignment.Center) {
                Text("Cancel", color = Theme.text, fontSize = 16.sp)
            }
        }
    }
    LaunchedEffect(Unit) { runCatching { focus.requestFocus() } }
}

private fun summary(saved: SavedPreset): String = presetOrder.mapNotNull { name ->
    saved.values[name]?.let { value -> if (name == "isospeedvalue") "ISO ${PropertyFormat.display(name, value)}" else PropertyFormat.display(name, value) }
}.joinToString(" · ")

/** The 68 dp illustrated tile for a one-tap recipe (313), drawn on a 64-unit grid. */
@Composable
private fun RecipeArt(recipe: PresetRecipe) {
    val shape = RoundedCornerShape(16.dp)
    Canvas(Modifier.size(68.dp).clip(shape).border(1.dp, Theme.stroke, shape).clearAndSetSemantics {}) {
        val k = size.width / 64f
        scale(k, k, pivot = Offset.Zero) {
            fun rect(x: Float, y: Float, w: Float, h: Float, c: Color) = drawRect(c, Offset(x, y), Size(w, h))
            fun dot(x: Float, y: Float, r: Float, c: Color) = drawCircle(c, r, Offset(x, y))
            fun path(points: List<Pair<Float, Float>>, closed: Boolean) = Path().also { p ->
                p.moveTo(points[0].first, points[0].second)
                points.drop(1).forEach { p.lineTo(it.first, it.second) }
                if (closed) p.close()
            }
            fun poly(points: List<Pair<Float, Float>>, c: Color) = drawPath(path(points, true), c)
            fun line(points: List<Pair<Float, Float>>, c: Color, w: Float) =
                drawPath(path(points, false), c, style = Stroke(w, cap = StrokeCap.Round, join = StrokeJoin.Round))
            val cream = Color(0xFFF4F1EA)
            when (recipe) {
                PresetRecipe.ASTRO -> {
                    rect(0f, 0f, 64f, 64f, Color(0xFF070A18))
                    listOf(Triple(12f, 14f, 1.2f), Triple(30f, 8f, 1.0f), Triple(50f, 18f, 1.4f), Triple(22f, 30f, 1.0f),
                        Triple(44f, 36f, 1.1f), Triple(56f, 8f, 0.9f)).forEach { (x, y, r) -> dot(x, y, r, Color(0xFFEEF1F7)) }
                    val arc = Path().also {
                        it.moveTo(6f, 44f)
                        it.quadraticTo(14f, 12f, 58f, 18f)
                    }
                    drawPath(arc, Theme.astroAccent, style = Stroke(1.4f, cap = StrokeCap.Round,
                        pathEffect = PathEffect.dashPathEffect(floatArrayOf(14f, 60f))))
                    poly(listOf(0f to 52f, 14f to 44f, 26f to 50f, 42f to 40f, 64f to 52f, 64f to 64f, 0f to 64f), Color(0xFF141A36))
                }
                PresetRecipe.MOON -> {
                    rect(0f, 0f, 64f, 64f, Color(0xFF070A18))
                    dot(32f, 30f, 17f, Color(0xFFE8E4D8))
                    dot(26f, 25f, 4f, Color(0xFFC9C5BA))
                    dot(38f, 36f, 3f, Color(0xFFC9C5BA))
                    dot(37f, 23f, 2f, Color(0xFFC9C5BA))
                }
                PresetRecipe.FIREWORKS -> {
                    rect(0f, 0f, 64f, 64f, Color(0xFF0A0A0A))
                    listOf(32f to 10f, 45f to 16f, 49f to 30f, 43f to 41f, 21f to 41f, 15f to 30f, 19f to 16f)
                        .forEach { end -> line(listOf(32f to 28f, end), Theme.accent, 2f) }
                    listOf(46f to 39f, 51f to 42f, 51f to 49f, 41f to 49f, 41f to 42f)
                        .forEach { end -> line(listOf(46f to 46f, end), Color(0xFFFF6A45), 2f) }
                    dot(32f, 28f, 2.4f, Color(0xFFFFE2A6))
                }
                PresetRecipe.LANDSCAPE -> {
                    rect(0f, 0f, 64f, 64f, Color(0xFF4B4470))
                    rect(0f, 34f, 64f, 30f, Color(0xFFC77F6E))
                    dot(44f, 38f, 7f, Color(0xFFFFE2A6))
                    poly(listOf(0f to 46f, 14f to 32f, 24f to 40f, 38f to 24f, 64f to 48f, 64f to 64f, 0f to 64f), Color(0xFF1B1C33))
                }
                PresetRecipe.ACTION -> {
                    rect(0f, 0f, 64f, 64f, Color(0xFF16233A))
                    line(listOf(6f to 22f, 28f to 22f), Color(0xFF8FB8FF), 2.4f)
                    line(listOf(4f to 32f, 22f to 32f), Color(0xFF8FB8FF), 2.4f)
                    line(listOf(10f to 42f, 24f to 42f), Color(0xFF8FB8FF), 2.4f)
                    dot(42f, 32f, 12f, cream)
                    line(listOf(34f to 32f, 50f to 32f), Color(0xFF16233A), 2f)
                }
                PresetRecipe.MACRO -> {
                    rect(0f, 0f, 64f, 64f, Color(0xFF16281F))
                    listOf(32f to 18f, 45f to 28f, 40f to 43f, 24f to 43f, 19f to 28f).forEach { (x, y) -> dot(x, y, 8f, Color(0xFFF3B36F)) }
                    dot(32f, 32f, 7f, Color(0xFFFFE2A6))
                }
                PresetRecipe.TRAILS -> {
                    rect(0f, 0f, 64f, 64f, Color(0xFF0E1430))
                    fun curve(y0: Float, c1x: Float, c1y: Float, c2x: Float, c2y: Float, y1: Float, c: Color) =
                        drawPath(Path().also { it.moveTo(-2f, y0); it.cubicTo(c1x, c1y, c2x, c2y, 66f, y1) }, c,
                            style = Stroke(2.4f, cap = StrokeCap.Round))
                    curve(56f, 20f, 44f, 30f, 30f, 24f, Theme.red)
                    curve(62f, 24f, 50f, 36f, 38f, 34f, Theme.red.copy(alpha = 0.6f))
                    curve(46f, 16f, 38f, 26f, 22f, 14f, Color(0xFFFFE2A6))
                }
            }
        }
    }
}

// MARK: - ND filter (310)

/**
 * Meter without the filter, pick its strength, and the app sets M, works out the exposure and times
 * Bulb when it's longer than the camera's own speeds.
 */
@Composable
fun NDSheet(camera: CameraModel, onDismiss: () -> Unit) {
    val scope = rememberCoroutineScope()
    var stops by remember { mutableIntStateOf(camera.prefs.getInt("nd.stops", 10)) }
    var meter by remember { mutableStateOf<NDMeter?>(null) }
    fun setStops(v: Int) {
        stops = v.coerceIn(1, 20)
        camera.prefs.edit().putInt("nd.stops", stops).apply()
    }
    val seconds = meter?.let { ndSeconds(it.seconds, stops) }
    FeedbackOnChange(Feedback.Moment.SELECT, stops)
    ToolScreen("ND filter", onDismiss) {
        val m = meter
        if (m != null && seconds != null) {
            BigNumber(shutterLabel(seconds), label = "With the filter on, expose for",
                caption = "${shutterLabel(m.seconds)} → ${shutterLabel(seconds)}", size = 104.sp, color = Theme.accent)
            StopScale(m.seconds, seconds, stops, Modifier.padding(vertical = 10.dp))
        } else {
            BigNumber("$stops stops", Modifier.padding(bottom = 14.dp), label = "ND filter", caption = "Meter without the filter first", size = 88.sp)
        }
        // 1: the reading on the right of its row, "Meter again" under it in the accent.
        val live = camera.meteredExposure
        Row(Modifier.fillMaxWidth().hairlineAbove().padding(vertical = 12.dp), verticalAlignment = Alignment.Top,
            horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text("1. Meter without the filter", color = Theme.text, fontSize = 16.sp, fontWeight = FontWeight.Medium)
                Text("Let the camera meter in A or P (or set the exposure yourself in M), with a fixed ISO.",
                    color = Theme.secondary, fontSize = 13.sp, lineHeight = 17.sp)
            }
            Text(live?.let(::describe) ?: "Waiting…", style = Theme.num(20.sp), maxLines = 1,
                color = if (live == null) Theme.secondary else Theme.text, modifier = Modifier.widthIn(max = 200.dp))
        }
        Box(Modifier.heightIn(min = Theme.target).clickable(enabled = live != null, role = Role.Button) { meter = camera.meteredExposure }
            .alpha(if (live != null) 1f else 0.4f), contentAlignment = Alignment.CenterStart) {
            Text(if (meter == null) "Use this exposure" else "Meter again", color = Theme.accent, fontSize = 15.sp, fontWeight = FontWeight.Medium)
        }
        SectionLabel("2. The filter")
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            listOf(3 to "ND8", 6 to "ND64", 10 to "ND1000", 15 to "ND32k").forEach { (value, name) ->
                val on = stops == value
                Column(Modifier.weight(1f).heightIn(min = 66.dp)
                    .outlinedBox(if (on) Color.Transparent else Theme.outline, 14.dp, if (on) Theme.accent else Color.Transparent)
                    .clip(RoundedCornerShape(14.dp)).clickable(role = Role.RadioButton) { setStops(value) },
                    horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(1.dp, Alignment.CenterVertically)) {
                    Text("$value stops", color = if (on) Theme.onAccent else Theme.text, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, maxLines = 1)
                    Text(name, color = if (on) Theme.onAccent else Theme.secondary, fontSize = 12.sp, maxLines = 1)
                }
            }
        }
        WheelValueRow("Strength", "1 to 20", ndStopValues, stops, { setStops(it) }) { "$it stops" }
        if (seconds != null && camera.ndShutter(seconds).second) {
            NoteRow("Longer than the camera's own speeds: the app runs Bulb and stops it. Keep Shutterlink open.")
        }
        if (m != null) {
            AccentButton(onClick = { scope.launch { camera.runPreset("nd", "ND filter") { camera.ndSteps(m, stops) } } },
                modifier = Modifier.fillMaxWidth().padding(top = 14.dp), enabled = !camera.presetRunning && camera.mode == CameraMode.REC) {
                if (camera.presetRunning) CircularProgressIndicator(color = Theme.onAccent, strokeWidth = 2.dp, modifier = Modifier.size(18.dp))
                Text(if (camera.presetRunning) "Applying…" else "Set up the camera")
            }
            if (camera.presetResultsFor == "nd" && camera.presetSteps.isNotEmpty()) {
                camera.presetSteps.forEach { StepResultRow(it, Modifier.fillMaxWidth().hairRow().padding(vertical = 10.dp)) }
            }
            if (seconds != null) {
                SectionLabel("3. Fit the filter and shoot")
                NoteRow("Focus first: with a dark filter on, autofocus may not find anything. Then switch the lens to MF.")
                OutlineButton(onClick = { scope.launch { camera.shootNd(seconds) } }, modifier = Modifier.fillMaxWidth().padding(top = 12.dp),
                    enabled = !camera.isShooting && camera.mode == CameraMode.REC && !camera.presetRunning) {
                    Text("Shoot ${shutterLabel(seconds)}")
                }
            }
        }
        Spacer(Modifier.height(14.dp))
    }
}

private val ndStopValues: List<Int> = (1..20).toList()

/** The stops from the metered time to the filtered one as a row of dots (310), a few labelled. */
@Composable
private fun StopScale(start: Double, end: Double, stops: Int, modifier: Modifier) {
    val count = min(16, max(2, stops + 1))
    Column(modifier.fillMaxWidth().clearAndSetSemantics {}, verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Canvas(Modifier.fillMaxWidth().height(12.dp)) {
            val cy = size.height / 2
            drawLine(Theme.outline, Offset(0f, cy), Offset(size.width, cy), strokeWidth = 1.dp.toPx())
            val inset = 5.dp.toPx()
            for (i in 0 until count) {
                val ends = i == 0 || i == count - 1
                val x = inset + (size.width - 2 * inset) * i / (count - 1)
                drawCircle(if (i == count - 1) Theme.accent else Theme.text, (if (ends) 5 else 3).dp.toPx(), Offset(x, cy))
            }
        }
        Row(Modifier.fillMaxWidth()) {
            val style = Theme.num(16.sp, medium = true)
            Text(shutterLabel(start), style = style, color = Theme.text)
            Spacer(Modifier.weight(1f))
            Text(shutterLabel(start * 2.0.pow(stops / 2.0)), style = style, color = Theme.secondary)
            Spacer(Modifier.weight(1f))
            Text(shutterLabel(end), style = style, color = Theme.accent)
        }
    }
}

private fun describe(meter: NDMeter): String = buildList {
    add(shutterLabel(meter.seconds))
    meter.aperture?.let { add(PropertyFormat.display("focalvalue", it)) }
    add(meter.iso?.let { "ISO $it" } ?: "ISO Auto")
}.joinToString(" · ")

// MARK: - Motion trigger (311)

private val motionSizes = listOf("Small" to 0.25, "Medium" to 0.4, "Large" to 0.6)
private val motionWaits: List<Int> = (1..60).toList()

/**
 * The motion trigger's controls (311): rows under the picture in place of the remote's controls, so the
 * box on live view can be dragged while it's open, Arm or Disarm at the bottom. The rows scroll when
 * `maxHeight` is short; the button stays in view.
 */
@Composable
fun MotionPanel(camera: CameraModel, onClose: () -> Unit, maxHeight: Dp = 340.dp) {
    DisposableEffect(Unit) {
        camera.motion = camera.motion.copy(editing = true)
        onDispose { camera.motion = camera.motion.copy(editing = false) }
    }
    val motion = camera.motion
    // Over the picture (landscape) it needs a dark backing to be read; under it (portrait) it sits on the wash.
    val overImage = LocalConfiguration.current.orientation == Configuration.ORIENTATION_LANDSCAPE
    Column(Modifier.fillMaxWidth().heightIn(max = maxHeight)
        .then(if (overImage) Modifier.surface(RoundedCornerShape(24.dp), overImage = true).padding(horizontal = 16.dp, vertical = 10.dp) else Modifier)) {
        Column(Modifier.weight(1f, fill = false).verticalScroll(rememberScrollState())) {
            Row(Modifier.padding(bottom = 8.dp), verticalAlignment = Alignment.Top) {
                Text("Shoots when something moves inside the box on live view. Drag the box to move it.",
                    color = Theme.text, fontSize = 15.sp, lineHeight = 20.sp, modifier = Modifier.weight(1f))
                Spacer(Modifier.width(8.dp))
                Box(Modifier.offset(y = (-10).dp)) { HeaderButton("Done", onClick = onClose) }
            }
            val box = motionSizes.minByOrNull { abs(it.second - motion.region.w) }?.second ?: 0.4
            SegRow("Box", motionSizes.map { it.second }, box, { camera.motion = camera.motion.resized(it) },
                { size -> motionSizes.firstOrNull { it.second == size }?.first ?: "" })
            Column(Modifier.fillMaxWidth().hairRow().padding(vertical = 12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Row(Modifier.fillMaxWidth()) {
                    Text("Sensitivity", color = Theme.secondary, fontSize = 13.sp, modifier = Modifier.weight(1f))
                    Text("Movement level", color = Theme.secondary, fontSize = 13.sp)
                }
                Slider(motion.sensitivity.toFloat(), { camera.motion = camera.motion.copy(sensitivity = it.toDouble()) },
                    modifier = Modifier.fillMaxWidth().semantics { contentDescription = "Sensitivity" },
                    colors = SliderDefaults.colors(thumbColor = Theme.text, activeTrackColor = Theme.green, inactiveTrackColor = Theme.stroke))
                MotionMeter(camera.motionLevel, motion.threshold)
            }
            WheelValueRow("Wait between shots", "1 to 60 s", motionWaits, motion.cooldown.toInt().coerceIn(1, 60),
                { camera.motion = camera.motion.copy(cooldown = it.toDouble()) }) { "$it s" }
            if (motion.armed || motion.shots > 0) {
                Text(if (motion.armed) "Armed · ${motion.shots} shots so far" else "${motion.shots} shots",
                    color = if (motion.armed) Theme.green else Theme.secondary, fontSize = 13.sp, fontWeight = FontWeight.SemiBold,
                    modifier = Modifier.padding(vertical = 12.dp))
            }
            if (camera.isOpenEndedShutter && !motion.armed) {
                NoteRow("The motion trigger needs a timed shutter speed, not Bulb or a Live mode.", warning = true)
            }
            NoteRow("Live view over Wi-Fi lags a little, so this suits birds at a feeder and slow subjects, not lightning. Keep Shutterlink open and the phone awake.")
        }
        Spacer(Modifier.height(12.dp))
        val enabled = camera.mode == CameraMode.REC && camera.liveViewRunning && !(camera.isOpenEndedShutter && !motion.armed)
        if (motion.armed) {
            OutlineButton(onClick = { camera.armMotion(false) }, modifier = Modifier.fillMaxWidth(), enabled = enabled) { Text("Disarm") }
        } else {
            AccentButton(onClick = { camera.armMotion(true) }, modifier = Modifier.fillMaxWidth(), enabled = enabled) { Text("Arm") }
        }
    }
}

/** How much the box is changing, against the level that fires. */
@Composable
private fun MotionMeter(level: Double, threshold: Double) {
    val scale = 0.3
    BoxWithConstraints(Modifier.fillMaxWidth().height(8.dp).background(Theme.surfaceRaised, Pill).semantics { contentDescription = "Movement level" }) {
        val fill = (level / scale).coerceIn(0.0, 1.0).toFloat()
        Box(Modifier.fillMaxWidth(fill).height(8.dp).background(if (level > threshold) Theme.accent else Color.White.copy(alpha = 0.6f), Pill))
        Box(Modifier.offset(x = maxWidth * (threshold / scale).coerceIn(0.0, 1.0).toFloat()).width(2.dp).height(8.dp).background(Theme.accent))
    }
}
