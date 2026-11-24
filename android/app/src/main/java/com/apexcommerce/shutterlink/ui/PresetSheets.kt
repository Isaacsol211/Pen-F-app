package com.apexcommerce.shutterlink.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.automirrored.filled.Undo
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Bookmark
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.DarkMode
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.DirectionsRun
import androidx.compose.material.icons.filled.Filter
import androidx.compose.material.icons.filled.Landscape
import androidx.compose.material.icons.filled.Lightbulb
import androidx.compose.material.icons.filled.LocalFlorist
import androidx.compose.material.icons.filled.NightsStay
import androidx.compose.material.icons.filled.NorthEast
import androidx.compose.material.icons.filled.Remove
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.Waves
import androidx.compose.material.icons.filled.WbSunny
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.apexcommerce.shutterlink.camera.CameraMode
import com.apexcommerce.shutterlink.camera.CameraModel
import com.apexcommerce.shutterlink.camera.NDMeter
import com.apexcommerce.shutterlink.camera.PresetRecipe
import com.apexcommerce.shutterlink.camera.PropertyFormat
import com.apexcommerce.shutterlink.camera.SavedPreset
import com.apexcommerce.shutterlink.camera.apply
import com.apexcommerce.shutterlink.camera.armMotion
import com.apexcommerce.shutterlink.camera.deleteSavedPreset
import com.apexcommerce.shutterlink.camera.exposeToTheRight
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

// Presets, ND filter calculator and motion trigger (port of PresetsViews.swift).

private fun recipeIcon(recipe: PresetRecipe): ImageVector = when (recipe) {
    PresetRecipe.ASTRO -> Icons.Filled.NightsStay
    PresetRecipe.MOON -> Icons.Filled.DarkMode
    PresetRecipe.FIREWORKS -> Icons.Filled.AutoAwesome
    PresetRecipe.LANDSCAPE -> Icons.Filled.Landscape
    PresetRecipe.ACTION -> Icons.Filled.DirectionsRun
    PresetRecipe.MACRO -> Icons.Filled.LocalFlorist
    PresetRecipe.TRAILS -> Icons.Filled.Waves
}

@Composable
private fun RowHeader(icon: ImageVector, title: String, subtitle: String, open: Boolean, opens: Boolean, onClick: () -> Unit) {
    Row(Modifier.fillMaxWidth().heightIn(min = Theme.target).clickable(onClick = onClick), verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Box(Modifier.size(36.dp).background(Theme.accent, RoundedCornerShape(10.dp)), contentAlignment = Alignment.Center) {
            Icon(icon, null, Modifier.size(19.dp), tint = Theme.onAccent)
        }
        Column(Modifier.weight(1f)) {
            Text(title, fontSize = 16.sp, fontWeight = FontWeight.SemiBold)
            Text(subtitle, color = Theme.secondary, fontSize = 13.sp, maxLines = 2)
        }
        if (opens) Icon(Icons.Filled.NorthEast, null, Modifier.size(14.dp), tint = Theme.tertiary)
        else Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, null, Modifier.rotate(if (open) 90f else 0f), tint = Theme.tertiary)
    }
}

@Composable
private fun ApplyButton(camera: CameraModel, title: String, action: suspend () -> Unit) {
    val scope = rememberCoroutineScope()
    AccentButton(onClick = { scope.launch { action() } }, modifier = Modifier.fillMaxWidth(),
        enabled = !camera.presetRunning && camera.mode == CameraMode.REC) {
        if (camera.presetRunning) CircularProgressIndicator(color = Theme.onAccent, strokeWidth = 2.dp, modifier = Modifier.size(18.dp))
        Text(if (camera.presetRunning) "Applying…" else title)
    }
}

/** One-tap recipes, Undo, My presets and Expose to the right. */
@Composable
fun PresetsSheet(camera: CameraModel, openAstro: () -> Unit, openFocusStack: () -> Unit, onDismiss: () -> Unit) {
    val scope = rememberCoroutineScope()
    var expanded by remember { mutableStateOf<String?>(null) }
    var naming by remember { mutableStateOf(false) }
    var newName by remember { mutableStateOf("") }
    Sheet("Presets", onDismiss) {
        camera.presetUndo?.let { undo ->
            Card {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    Icon(Icons.AutoMirrored.Filled.Undo, null, Modifier.size(26.dp), tint = Theme.accent)
                    Column(Modifier.weight(1f)) {
                        Text("Undo ${undo.title}", fontSize = 16.sp, fontWeight = FontWeight.SemiBold)
                        Text("Puts back the settings from before it.", color = Theme.secondary, fontSize = 13.sp)
                    }
                    SurfaceButton(onClick = { scope.launch { camera.undoPreset() } }, enabled = !camera.presetRunning) { Text("Undo") }
                }
            }
        }
        Card {
            CapsLabel("One tap")
            PresetRecipe.entries.forEach { recipe ->
                val open = expanded == recipe.id
                RowHeader(recipeIcon(recipe), recipe.title, recipe.summary, open, opens = recipe == PresetRecipe.ASTRO) {
                    if (recipe == PresetRecipe.ASTRO) openAstro() else expanded = if (open) null else recipe.id
                }
                if (open) {
                    val steps = if (camera.presetResultsFor == recipe.id && camera.presetSteps.isNotEmpty()) camera.presetSteps else camera.steps(recipe)
                    Column(Modifier.padding(start = 6.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                        steps.forEach { StepResultRow(it) }
                        if (recipe.tip.isNotEmpty()) Tip(recipe.tip)
                        ApplyButton(camera, "Apply ${recipe.title}") { camera.apply(recipe) }
                        if (recipe == PresetRecipe.MACRO && camera.capabilities.focusDrive) {
                            SurfaceButton(onClick = openFocusStack, modifier = Modifier.fillMaxWidth()) { Text("Focus stack next") }
                        }
                    }
                }
            }
        }
        Card {
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
                val open = expanded == preset.id
                RowHeader(Icons.Filled.Bookmark, preset.name, summary(preset), open, opens = false) {
                    expanded = if (open) null else preset.id
                }
                if (open) {
                    val steps = if (camera.presetResultsFor == preset.id && camera.presetSteps.isNotEmpty()) camera.presetSteps else camera.steps(preset)
                    Column(Modifier.padding(start = 6.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                        steps.forEach { StepResultRow(it) }
                        ApplyButton(camera, "Apply ${preset.name}") { camera.apply(preset) }
                        SurfaceButton(onClick = { expanded = null; camera.deleteSavedPreset(preset) }, modifier = Modifier.fillMaxWidth()) {
                            Icon(Icons.Filled.Delete, null, Modifier.size(16.dp), tint = Theme.red)
                            Text("Delete", color = Theme.red)
                        }
                    }
                }
            }
        }
        Card {
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
    if (naming) {
        AlertDialog(
            onDismissRequest = { naming = false },
            title = { Text("Save current settings") },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("Mode, aperture, shutter, ISO, exposure, white balance and drive: whatever the camera lets the app set.",
                        color = Theme.secondary, fontSize = 13.sp)
                    OutlinedTextField(newName, { newName = it }, label = { Text("Name") }, singleLine = true,
                        colors = OutlinedTextFieldDefaults.colors(focusedBorderColor = Theme.accent, cursorColor = Theme.accent,
                            focusedLabelColor = Theme.accent))
                }
            },
            confirmButton = { TextButton({ naming = false; camera.saveCurrentSettings(newName) }) { Text("Save", color = Theme.accent) } },
            dismissButton = { TextButton({ naming = false }) { Text("Cancel") } },
            containerColor = Theme.surfaceRaised,
        )
    }
}

@Composable
private fun Tip(text: String) {
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Icon(Icons.Filled.Lightbulb, null, Modifier.size(16.dp), tint = Theme.accent)
        Text(text, color = Theme.secondary, fontSize = 13.sp)
    }
}

private fun summary(saved: SavedPreset): String = presetOrder.mapNotNull { name ->
    saved.values[name]?.let { value -> if (name == "isospeedvalue") "ISO ${PropertyFormat.display(name, value)}" else PropertyFormat.display(name, value) }
}.joinToString(" · ")

// MARK: - ND filter

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
    Sheet("ND filter", onDismiss) {
        Card {
            Text("1. Meter without the filter", fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
            val live = camera.meteredExposure
            Text(live?.let(::describe) ?: "Waiting for the camera's exposure…", style = monoStyle(16.sp),
                color = if (live == null) Theme.secondary else Color.White)
            SurfaceButton(onClick = { meter = camera.meteredExposure }, enabled = live != null) {
                Text(if (meter == null) "Use this exposure" else "Meter again", fontWeight = FontWeight.SemiBold)
            }
            Text("Let the camera meter in A or P (or set the exposure yourself in M), with a fixed ISO.", color = Theme.secondary, fontSize = 13.sp)
        }
        Card {
            Text("2. The filter", fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                listOf(3 to "ND8", 6 to "ND64", 10 to "ND1000", 15 to "ND32k").forEach { (value, name) ->
                    val on = stops == value
                    Column(Modifier.weight(1f).heightIn(min = 44.dp).background(if (on) Theme.accent else Theme.surfaceRaised, RoundedCornerShape(12.dp))
                        .clickable { setStops(value) }.padding(vertical = 6.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                        Text("$value stops", color = if (on) Theme.onAccent else Color.White, fontSize = 12.sp, fontWeight = FontWeight.SemiBold)
                        Text(name, color = if (on) Theme.onAccent else Theme.secondary, fontSize = 11.sp)
                    }
                }
            }
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                Text("Strength", fontSize = 16.sp, modifier = Modifier.weight(1f))
                Text("$stops stops", style = monoStyle(16.sp), color = Theme.secondary)
                SurfaceButton(onClick = { setStops(stops - 1) }, circle = true) { Icon(Icons.Filled.Remove, "Weaker", Modifier.size(18.dp)) }
                SurfaceButton(onClick = { setStops(stops + 1) }, circle = true) { Icon(Icons.Filled.Add, "Stronger", Modifier.size(18.dp)) }
            }
            val m = meter
            if (m != null && seconds != null) {
                Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    Text(shutterLabel(m.seconds), color = Theme.secondary, fontSize = 16.sp)
                    Text("→", color = Theme.tertiary, fontSize = 16.sp)
                    Text(shutterLabel(seconds), color = Theme.accent, style = monoStyle(24.sp))
                }
                if (camera.ndShutter(seconds).second) {
                    Text("Longer than the camera's own speeds: the app runs Bulb and stops it. Keep Shutterlink open.",
                        color = Theme.secondary, fontSize = 13.sp)
                }
            }
        }
        val m = meter
        if (m != null) {
            ApplyButton(camera, "Set up the camera") { camera.runPreset("nd", "ND filter") { camera.ndSteps(m, stops) } }
            if (camera.presetResultsFor == "nd" && camera.presetSteps.isNotEmpty()) {
                Card { camera.presetSteps.forEach { StepResultRow(it) } }
            }
            if (seconds != null) {
                Card {
                    Text("3. Fit the filter and shoot", fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
                    Text("Focus first: with a dark filter on, autofocus may not find anything. Then switch the lens to MF.",
                        color = Theme.secondary, fontSize = 13.sp)
                    SurfaceButton(onClick = { scope.launch { camera.shootNd(seconds) } }, modifier = Modifier.fillMaxWidth(),
                        enabled = !camera.isShooting && camera.mode == CameraMode.REC && !camera.presetRunning) {
                        Icon(Icons.Filled.Filter, null, Modifier.size(18.dp))
                        Text("Shoot ${shutterLabel(seconds)}", fontWeight = FontWeight.SemiBold)
                    }
                }
            }
        }
    }
}

private fun describe(meter: NDMeter): String = buildList {
    add(shutterLabel(meter.seconds))
    meter.aperture?.let { add(PropertyFormat.display("focalvalue", it)) }
    add(meter.iso?.let { "ISO $it" } ?: "ISO Auto")
}.joinToString(" · ")

// MARK: - Motion trigger

/**
 * The motion trigger's controls. Shown docked under live view (not in a sheet) so the box on the
 * picture can be dragged while it's open.
 */
@Composable
fun MotionPanel(camera: CameraModel, onClose: () -> Unit, maxHeight: androidx.compose.ui.unit.Dp = 340.dp) {
    DisposableEffect(Unit) {
        camera.motion = camera.motion.copy(editing = true)
        onDispose { camera.motion = camera.motion.copy(editing = false) }
    }
    val motion = camera.motion
    Column(
        Modifier.fillMaxWidth().heightIn(max = maxHeight).surface(RoundedCornerShape(26.dp)).verticalScroll(rememberScrollState()).padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        // Arm stays in the header: the docked panel is short and the rest scrolls.
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            CapsLabel("Motion trigger", color = Theme.accent, modifier = Modifier.weight(1f))
            AccentButton(onClick = { camera.armMotion(!motion.armed) }, modifier = Modifier.heightIn(max = 44.dp),
                enabled = camera.mode == CameraMode.REC && camera.liveViewRunning && !(camera.isOpenEndedShutter && !motion.armed)) {
                Text(if (motion.armed) "Disarm · ${motion.shots}" else "Arm", fontSize = 15.sp)
            }
            SurfaceButton(onClick = onClose, circle = true) { Icon(Icons.Filled.Close, "Close motion trigger", Modifier.size(16.dp)) }
        }
        Text("Shoots when something moves inside the box on live view. Drag the box to move it.", color = Theme.secondary, fontSize = 13.sp)
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            CapsLabel("Box", modifier = Modifier.width(70.dp))
            listOf("Small" to 0.25, "Medium" to 0.4, "Large" to 0.6).forEach { (name, scale) ->
                val on = abs(motion.region.w - scale) < 0.05
                Text(name, color = if (on) Color.Black else Color.White, fontSize = 13.sp, fontWeight = FontWeight.SemiBold,
                    modifier = Modifier.background(if (on) Theme.accent else Theme.surfaceRaised, Pill)
                        .clickable { camera.motion = camera.motion.resized(scale) }.padding(horizontal = 12.dp, vertical = 7.dp))
            }
        }
        Row(verticalAlignment = Alignment.CenterVertically) {
            CapsLabel("Sensitivity", modifier = Modifier.width(96.dp))
            Slider(motion.sensitivity.toFloat(), { camera.motion = camera.motion.copy(sensitivity = it.toDouble()) },
                modifier = Modifier.weight(1f),
                colors = SliderDefaults.colors(thumbColor = Theme.accent, activeTrackColor = Theme.accent, inactiveTrackColor = Theme.surfaceRaised))
        }
        MotionMeter(camera.motionLevel, motion.threshold)
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Text("Wait between shots", fontSize = 15.sp, modifier = Modifier.weight(1f))
            Text("${motion.cooldown.toInt()} s", style = monoStyle(15.sp), color = Theme.secondary)
            SurfaceButton(onClick = { camera.motion = camera.motion.copy(cooldown = (motion.cooldown - 1).coerceAtLeast(1.0)) }, circle = true) {
                Icon(Icons.Filled.Remove, "Shorter", Modifier.size(16.dp))
            }
            SurfaceButton(onClick = { camera.motion = camera.motion.copy(cooldown = (motion.cooldown + 1).coerceAtMost(60.0)) }, circle = true) {
                Icon(Icons.Filled.Add, "Longer", Modifier.size(16.dp))
            }
        }
        if (camera.isOpenEndedShutter && !motion.armed) {
            Text("The motion trigger needs a timed shutter speed, not Bulb or a Live mode.", color = Theme.orange, fontSize = 13.sp)
        }
        if (motion.armed || motion.shots > 0) {
            Text(if (motion.armed) "Armed · ${motion.shots} shots so far" else "${motion.shots} shots", style = monoStyle(14.sp),
                color = if (motion.armed) Theme.accent else Theme.secondary)
        }
        Text("Live view over Wi-Fi lags a little, so this suits birds at a feeder and slow subjects, not lightning. Keep Shutterlink open and the phone awake.",
            color = Theme.secondary, fontSize = 13.sp)
    }
}

@Composable
private fun MotionMeter(level: Double, threshold: Double) {
    val scale = 0.3
    BoxWithConstraints(Modifier.fillMaxWidth().height(8.dp).background(Theme.surfaceRaised, Pill)) {
        val fill = (level / scale).coerceIn(0.0, 1.0).toFloat()
        Box(Modifier.fillMaxWidth(fill).height(8.dp).background(if (level > threshold) Theme.accent else Color.White.copy(alpha = 0.6f), Pill))
        Box(Modifier.offset(x = maxWidth * (threshold / scale).coerceIn(0.0, 1.0).toFloat()).width(2.dp).height(8.dp).background(Theme.accent))
    }
}
