package com.apexcommerce.shutterlink.ui

import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.AutoFixHigh
import androidx.compose.material.icons.filled.BarChart
import androidx.compose.material.icons.filled.Bedtime
import androidx.compose.material.icons.filled.CenterFocusStrong
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.DirectionsWalk
import androidx.compose.material.icons.filled.Filter
import androidx.compose.material.icons.filled.GridOn
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.Layers
import androidx.compose.material.icons.filled.MoreHoriz
import androidx.compose.material.icons.filled.NightsStay
import androidx.compose.material.icons.filled.Apps
import androidx.compose.material.icons.filled.Timer
import androidx.compose.material.icons.filled.TouchApp
import androidx.compose.material.icons.filled.Videocam
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material.icons.filled.ZoomIn
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.layout
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.zIndex
import com.apexcommerce.shutterlink.camera.CameraModel
import com.apexcommerce.shutterlink.camera.PresetRecipe
import com.apexcommerce.shutterlink.camera.PropertyFormat
import com.apexcommerce.shutterlink.camera.isPresetOn
import com.apexcommerce.shutterlink.camera.SceneSuggestion
import com.apexcommerce.shutterlink.camera.applySceneSuggestion
import com.apexcommerce.shutterlink.camera.changeAutoSave
import com.apexcommerce.shutterlink.camera.runSceneAssistant
import com.apexcommerce.shutterlink.camera.stripValue
import com.apexcommerce.shutterlink.camera.undoPreset
import kotlinx.coroutines.launch

/** Which tool screen or page is open over the remote. */
enum class RemotePage { NONE, GALLERY, ASTRO, INTERVAL, BRACKET, ALL_SETTINGS, LOG, REPORT, HIGH_RES, POCKET, PRESETS, ND, MOTION }

/**
 * The remote (port of RemoteView.swift, direction D). Portrait: the whole live view near the top over a
 * blurred copy of itself, a small line (white balance, drive, quality), the row of values, one big
 * readout with the curved dial, then the shutter row. Landscape: the picture fills everything beside a
 * black rail. Tools, Drive, Quality and the ··· menu open as bottom panels with the picture still above.
 */
@Composable
fun RemoteScreen(camera: CameraModel) {
    val scope = rememberCoroutineScope()
    val view = LocalView.current
    var page by rememberSaveable { mutableStateOf(RemotePage.NONE) }
    var toolsOpen by remember { mutableStateOf(false) }
    var showMore by remember { mutableStateOf(false) }
    /** Drive or Quality, whose options open in a panel from the small line under the picture. */
    var settingSheet by remember { mutableStateOf<String?>(null) }
    var activeSetting by remember { mutableStateOf<String?>(null) }
    var showHistogram by remember { mutableStateOf(camera.prefs.getBoolean("ui.histogram", false)) }
    var showGrid by remember { mutableStateOf(camera.prefs.getBoolean("ui.grid", false)) }
    var nightMode by remember { mutableStateOf(camera.prefs.getBoolean("ui.nightMode", false)) }
    var showLoupe by remember { mutableStateOf(false) }
    var confirmPowerOff by remember { mutableStateOf(false) }
    var confirmDisconnect by remember { mutableStateOf(false) }

    LaunchedEffect(showLoupe) { camera.setLoupe(showLoupe) }
    LaunchedEffect(Unit) { camera.runSceneAssistant() }
    LaunchedEffect(camera.isMovieMode) { if (activeSetting == "exposemovie" && !camera.isMovieMode) activeSetting = null }

    BackHandler(enabled = showLoupe && !toolsOpen && !showMore && settingSheet == null) { showLoupe = false }

    if (page == RemotePage.GALLERY) {
        GalleryScreen(camera) {
            page = RemotePage.NONE
            scope.launch { camera.closeGallery() }
        }
        return
    }
    if (page == RemotePage.POCKET) {
        PocketMode(camera) { page = RemotePage.NONE }
        return
    }

    val tools = buildTools(
        camera, showLoupe, nightMode, showHistogram, showGrid,
        open = { toolsOpen = false; page = it },
        toggleLoupe = { showLoupe = !showLoupe; toolsOpen = false },
        toggleNight = { nightMode = !nightMode; camera.prefs.edit().putBoolean("ui.nightMode", nightMode).apply() },
        toggleHistogram = { showHistogram = !showHistogram; camera.prefs.edit().putBoolean("ui.histogram", showHistogram).apply() },
        toggleGrid = { showGrid = !showGrid; camera.prefs.edit().putBoolean("ui.grid", showGrid).apply() },
        closeTools = { toolsOpen = false },
    )
    val lineAids = tools.filter { it.id in setOf("grid", "histogram", "peaking", "tap") }

    val selectSetting: (String?) -> Unit = { name ->
        activeSetting = name
        if (name != null) toolsOpen = false
    }
    // Recipes and settings run straight away; ND and Motion open their screen, ready to go.
    val applySuggestion: (SceneSuggestion) -> Unit = { suggestion ->
        scope.launch { camera.applySceneSuggestion(suggestion) }
        when (suggestion.action) {
            SceneSuggestion.Action.OpenND -> page = RemotePage.ND
            SceneSuggestion.Action.OpenMotion -> page = RemotePage.MOTION
            else -> {}
        }
    }
    val toggleTools: () -> Unit = {
        toolsOpen = !toolsOpen
        if (toolsOpen) activeSetting = null
    }
    // A tick on entering each value of the dial; a firmer one on full stops and 0 EV.
    val dialTick: (Boolean) -> Unit = { firm ->
        Feedback.dial(firm, view)
    }
    val menuButton: @Composable () -> Unit = {
        Box(Modifier.size(Theme.target).clip(RoundedCornerShape(50)).clickable(enabled = !camera.isBusyExposing) { showMore = true }
            .semantics { contentDescription = "More" }, contentAlignment = Alignment.Center) {
            Icon(Icons.Filled.MoreHoriz, null, Modifier.size(20.dp), tint = Theme.secondary)
        }
    }

    NightVision(nightMode) {
        BoxWithConstraints(Modifier.fillMaxSize().background(Theme.background)) {
            val landscape = maxWidth > maxHeight
            if (landscape) {
                LandscapeLayout(camera, menuButton, toolsOpen, toggleTools, activeSetting, selectSetting, showGrid, showHistogram,
                    showLoupe, motionOpen = page == RemotePage.MOTION, closeMotion = { page = RemotePage.NONE },
                    applySuggestion = applySuggestion, dialTick = dialTick) { page = RemotePage.GALLERY }
            } else {
                PortraitLayout(camera, menuButton, lineAids, toolsOpen, toggleTools, activeSetting, selectSetting, showGrid, showHistogram,
                    showLoupe, motionOpen = page == RemotePage.MOTION, closeMotion = { page = RemotePage.NONE },
                    applySuggestion = applySuggestion, openSheet = { settingSheet = it }, dialTick = dialTick) { page = RemotePage.GALLERY }
            }
            Toast(camera, Modifier.align(Alignment.TopCenter).safeDrawingPadding())

            // The design's bottom panels (208, 209, 219–221), drawn by the app, edge to edge.
            BottomPanel(toolsOpen, { toolsOpen = false }, title = "Tools") {
                Column(Modifier.padding(start = 16.dp, end = 16.dp, top = 4.dp, bottom = 12.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
                    ToolsTray(tools, columns = if (landscape) 6 else 4)
                    if (camera.interval.running) {
                        Text("The interval timer is running: the Tools button shows ${camera.interval.done}" +
                            (if (camera.interval.total > 0) "/${camera.interval.total}" else "") + ".", color = Theme.secondary, fontSize = 13.sp)
                    }
                }
            }
            val sheetSpec = settingSheet?.let { SettingSpec.spec(it) }
            BottomPanel(settingSheet != null, { settingSheet = null }, title = sheetSpec?.title) {
                sheetSpec?.let { SettingSheet(camera, it) }
            }
            BottomPanel(showMore, { showMore = false }, title = camera.cameraName ?: "Camera") {
                MoreSheet(camera,
                    openHighRes = { showMore = false; page = RemotePage.HIGH_RES },
                    allSettings = { showMore = false; page = RemotePage.ALL_SETTINGS },
                    log = { showMore = false; page = RemotePage.LOG },
                    report = { showMore = false; page = RemotePage.REPORT },
                    disconnect = { showMore = false; confirmDisconnect = true },
                    powerOff = { showMore = false; confirmPowerOff = true })
            }
            DialogCard(confirmDisconnect, "Disconnect from the camera?", "Disconnect", compact = true,
                onAction = { confirmDisconnect = false; scope.launch { camera.disconnect() } },
                onCancel = { confirmDisconnect = false })
            DialogCard(confirmPowerOff, "Turn the camera off?", "Turn off",
                message = "You'll need to switch it on and start Wi-Fi on the camera again to reconnect.",
                onAction = { confirmPowerOff = false; scope.launch { camera.powerOff() } },
                onCancel = { confirmPowerOff = false })
        }
    }

    when (page) {
        RemotePage.ASTRO -> AstroSheet(camera) { page = RemotePage.NONE }
        RemotePage.INTERVAL -> IntervalSheet(camera) { page = RemotePage.NONE }
        RemotePage.BRACKET -> BracketSheet(camera) { page = RemotePage.NONE }
        RemotePage.ALL_SETTINGS -> AllSettingsScreen(camera) { page = RemotePage.NONE }
        RemotePage.LOG -> LogScreen(camera) { page = RemotePage.NONE }
        RemotePage.REPORT -> ReportProblemPage(camera) { page = RemotePage.NONE }
        RemotePage.HIGH_RES -> HighResSheet(camera) { page = RemotePage.NONE }
        RemotePage.PRESETS -> PresetsSheet(camera,
            openAstro = { page = RemotePage.ASTRO },
            openFocusStack = {
                camera.prefs.edit().putBoolean("bracket.focus", true).apply()
                page = RemotePage.BRACKET
            }) { page = RemotePage.NONE }
        RemotePage.ND -> NDSheet(camera) { page = RemotePage.NONE }
        else -> {}
    }
}

/** Red night-vision mode keeps your eyes dark-adapted under the stars. */
@Composable
private fun NightVision(enabled: Boolean, content: @Composable () -> Unit) {
    if (!enabled) {
        content()
        return
    }
    Box(Modifier.fillMaxSize()
        .graphicsLayer { compositingStrategy = CompositingStrategy.Offscreen }
        .drawWithContent {
            drawContent()
            drawRect(Theme.red, blendMode = BlendMode.Multiply)
        }) { content() }
}

/** The value the portrait dial is on: the one tapped, else the movie exposure in video, else the shutter. */
private fun portraitSelection(camera: CameraModel, active: String?): String {
    val names = stripItems(camera)
    if (active != null && (active in names || active == "wbvalue")) return active
    if (camera.isMovieMode && "exposemovie" in names) return "exposemovie"
    if ("shutspeedvalue" in names) return "shutspeedvalue"
    return names.firstOrNull { it != "takemode" } ?: names.firstOrNull() ?: ""
}

/** Portrait (201): live view near the top, the small line, the values, the readout and dial, the shutter row. */
@Composable
private fun PortraitLayout(
    camera: CameraModel, menuButton: @Composable () -> Unit, lineAids: List<ToolItem>,
    toolsOpen: Boolean, toggleTools: () -> Unit, activeSetting: String?, selectSetting: (String?) -> Unit,
    showGrid: Boolean, showHistogram: Boolean, showLoupe: Boolean,
    motionOpen: Boolean, closeMotion: () -> Unit, applySuggestion: (SceneSuggestion) -> Unit,
    openSheet: (String) -> Unit, dialTick: (Boolean) -> Unit, openGallery: () -> Unit,
) {
    val selected = portraitSelection(camera, activeSetting)
    Box(Modifier.fillMaxSize()) {
        LiveBackdrop(camera)
        Column(Modifier.fillMaxSize().safeDrawingPadding()) {
            InfoBar(camera) { menuButton() }
            Box {
                LiveViewPane(camera, showGrid, showHistogram, showLoupe, Modifier.fillMaxWidth().aspectRatio(4f / 3f), loupeControlsBelow = true)
                Banners(camera, Modifier.align(Alignment.TopCenter).padding(top = 8.dp))
                SuggestionOverlay(camera, showLoupe, applySuggestion, Modifier.align(Alignment.BottomCenter).padding(10.dp))
            }
            if (camera.properties.isEmpty()) {
                Box(Modifier.fillMaxWidth().heightIn(min = 120.dp).weight(1f), contentAlignment = Alignment.Center) {
                    Text("Reading camera settings…", color = Theme.secondary, fontSize = 13.sp)
                }
            } else {
                Column(Modifier.fillMaxWidth().weight(1f), horizontalAlignment = Alignment.CenterHorizontally) {
                    if (!showLoupe && !motionOpen) {
                        SettingLine(camera, selected, lineAids, onSelect = selectSetting, openSheet = openSheet)
                        ExposureStrip(camera, selected, onSelect = { selectSetting(it) }, Modifier.padding(horizontal = 12.dp))
                    }
                    when {
                        // 311: the trigger's controls take the place of the remote's, under the picture with its box.
                        motionOpen -> Box(Modifier.padding(horizontal = 20.dp, vertical = 10.dp)) { MotionPanel(camera, closeMotion, maxHeight = 320.dp) }
                        // 213: the loupe's zoom and focus reading take the dial's place.
                        showLoupe -> {
                            LoupeReadout(camera, Modifier.padding(top = 18.dp))
                            Spacer(Modifier.weight(1f))
                        }
                        // 218: the sequence's progress in place of the dial.
                        camera.bracket.running -> {
                            BigNumber("${camera.bracket.done + 1} of ${camera.bracket.total}", Modifier.padding(top = 16.dp),
                                label = if (camera.bracket.isFocusStack) "Focus stack" else "Bracketing", caption = camera.bracket.label, size = 68.sp)
                            Spacer(Modifier.weight(1f))
                        }
                        // A long or open exposure: one big running time in place of the dial.
                        camera.isBusyExposing && !camera.isRecordingMovie -> {
                            ExposingReadout(camera, Modifier.padding(top = 16.dp))
                            Spacer(Modifier.weight(1f))
                        }
                        else -> {
                            val spec = SettingSpec.spec(selected)
                            if (spec != null && camera.properties[selected] != null) {
                                Box(Modifier.weight(1f).fillMaxWidth()) {
                                    androidx.compose.runtime.key(selected) {
                                        OptionPanel(camera, spec, onClose = { selectSetting(null) }, fill = true, onTick = dialTick)
                                    }
                                }
                            } else Spacer(Modifier.weight(1f))
                        }
                    }
                }
            }
            if (!motionOpen) {
                Row(Modifier.fillMaxWidth().padding(horizontal = 24.dp).padding(bottom = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                    Box(Modifier.width(84.dp), contentAlignment = Alignment.Center) { LastShotButton(camera, openGallery) }
                    Spacer(Modifier.weight(1f))
                    ShutterButton(camera)
                    Spacer(Modifier.weight(1f))
                    Box(Modifier.width(84.dp), contentAlignment = Alignment.Center) { ToolsButton(camera, toolsOpen, toggleTools) }
                }
            }
        }
    }
}

/** Landscape (227): the picture fills everything beside a black rail; status top left, the values along a dark band at its bottom. */
@Composable
private fun LandscapeLayout(
    camera: CameraModel, menuButton: @Composable () -> Unit,
    toolsOpen: Boolean, toggleTools: () -> Unit, activeSetting: String?, selectSetting: (String?) -> Unit,
    showGrid: Boolean, showHistogram: Boolean, showLoupe: Boolean,
    motionOpen: Boolean, closeMotion: () -> Unit, applySuggestion: (SceneSuggestion) -> Unit,
    dialTick: (Boolean) -> Unit, openGallery: () -> Unit,
) {
    Row(Modifier.fillMaxSize()) {
        Box(Modifier.weight(1f).fillMaxHeight()) {
            LiveViewPane(camera, showGrid, showHistogram, showLoupe, Modifier.fillMaxSize(), hudTopInset = 50.dp, fill = true)
            if (!showLoupe) {
                // The dark band behind the values, out to the screen's edges like the picture.
                Box(Modifier.align(Alignment.BottomCenter).fillMaxWidth().height(130.dp)
                    .background(Brush.verticalGradient(listOf(Wash.copy(alpha = 0f), Wash.copy(alpha = 0.85f)))))
            }
            Column(Modifier.fillMaxSize().safeDrawingPadding().padding(horizontal = 16.dp).padding(top = 8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                StatusPill(camera, showsName = true)
                Banners(camera, Modifier.widthIn(max = 460.dp))
                Spacer(Modifier.weight(1f))
                if (motionOpen) {
                    Box(Modifier.align(Alignment.End).widthIn(max = 360.dp).padding(bottom = 8.dp)) { MotionPanel(camera, closeMotion, maxHeight = 300.dp) }
                } else {
                    SuggestionOverlay(camera, showLoupe, applySuggestion, Modifier.align(Alignment.CenterHorizontally))
                    if (!showLoupe) {
                        val spec = activeSetting?.let { SettingSpec.spec(it) }
                        if (spec != null && camera.properties[spec.name] != null) {
                            Box(Modifier.align(Alignment.CenterHorizontally).widthIn(max = 480.dp)
                                .background(Wash.copy(alpha = 0.8f), RoundedCornerShape(24.dp)).padding(vertical = 6.dp)) {
                                androidx.compose.runtime.key(spec.name) { OptionPanel(camera, spec, onClose = { selectSetting(null) }, onTick = dialTick) }
                            }
                        }
                        LandscapeValues(camera, activeSetting, selectSetting)
                    }
                }
            }
        }
        // A black rail: ··· at the top, the mode dial over the shutter, last shot and Tools below.
        Column(Modifier.width(128.dp).fillMaxHeight().background(Theme.background).safeDrawingPadding().padding(vertical = 6.dp),
            horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(10.dp)) {
            menuButton()
            Box(Modifier.weight(1f).fillMaxWidth(), contentAlignment = Alignment.Center) {
                if (camera.properties["takemode"] != null) Box(Modifier.heightIn(max = 110.dp)) { ModeCarousel(camera, vertical = true) }
            }
            ShutterButton(camera)
            Spacer(Modifier.weight(0.4f))
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                LastShotButton(camera, openGallery)
                Box(Modifier.scale(0.85f)) { ToolsButton(camera, toolsOpen, toggleTools) }
            }
        }
    }
}

/**
 * The values along the bottom of the landscape picture (227): the selected one larger with its label
 * over it, the others in Barlow, white balance and drive at the end. Tap one for its dial.
 */
@Composable
private fun LandscapeValues(camera: CameraModel, active: String?, select: (String?) -> Unit) {
    val names = stripItems(camera).filter { it != "takemode" }
    val selected = active ?: if ("shutspeedvalue" in names) "shutspeedvalue" else names.firstOrNull()
    Row(Modifier.fillMaxWidth().padding(start = 22.dp, bottom = 6.dp), verticalAlignment = Alignment.Bottom,
        horizontalArrangement = Arrangement.spacedBy(26.dp)) {
        names.forEach { name ->
            val on = name == selected
            Column(Modifier.heightIn(min = Theme.target).clickable(enabled = !camera.isBusyExposing) { select(if (active == name) null else name) }
                .semantics { contentDescription = "${SettingSpec.spec(name)?.title ?: name}: ${stripText(name, camera)}" },
                verticalArrangement = Arrangement.Bottom, horizontalAlignment = Alignment.CenterHorizontally) {
                if (on) CapsLabel(SettingSpec.spec(name)?.title ?: name, Theme.accent)
                Text(stripText(name, camera), style = Theme.num(if (on) 40.sp else 22.sp, medium = !on),
                    color = if (on) Theme.text else Color(0xFFC9C5BA), maxLines = 1, softWrap = false)
            }
        }
        val extras = listOf("wbvalue", "drivemode").mapNotNull { name -> camera.properties[name]?.let { camera.stripValue(name, camera.dialOptions(it)) } }
        if (extras.isNotEmpty()) {
            Text(extras.joinToString(" · "), style = Theme.num(18.sp, medium = true), color = Color(0xFFC9C5BA), maxLines = 1, softWrap = false)
        }
    }
}

/**
 * While a long (timed) or open-ended exposure runs: what is happening, in the accent (red for an
 * open-ended one), over the running time at 100 sp (216, 217).
 */
@Composable
fun ExposingReadout(camera: CameraModel, modifier: Modifier = Modifier) {
    val open = camera.isOpenEndedShutter
    val started = camera.exposureStartedAt ?: camera.movieStartedAt
    val now = rememberNow(true, 500)
    val elapsed = started?.let { maxOf(0.0, (now - it) / 1000.0) } ?: 0.0
    val shown = camera.exposureDuration?.let { maxOf(0.0, it - elapsed) } ?: elapsed
    val total = shown.toLong()
    val text = if (open) String.format(java.util.Locale.US, "%02d:%02d", total / 60, total % 60)
    else String.format(java.util.Locale.US, "%d:%02d", total / 60, total % 60)
    Column(modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(4.dp)) {
        CapsLabel(if (open) PropertyFormat.display("shutspeedvalue", camera.properties["shutspeedvalue"]?.value ?: "") else "Exposing",
            if (open) Theme.red else Theme.accent)
        Text(text, style = Theme.num(100.sp), color = Theme.text, maxLines = 1)
        val duration = camera.exposureDuration
        Text(
            when {
                duration != null -> "of ${CameraModel.durationLabel(duration)}"
                camera.bulbTimer > 0 -> "The exposure stops by itself after ${CameraModel.durationLabel(camera.bulbTimer)}, or when you tap the shutter."
                else -> "The exposure runs until you tap the shutter again."
            },
            color = Theme.secondary, fontSize = 13.sp, textAlign = TextAlign.Center, modifier = Modifier.padding(horizontal = 24.dp),
        )
    }
}

/** Drive or Quality: the options in a panel, the live view still above it. */
@Composable
private fun SettingSheet(camera: CameraModel, spec: SettingSpec) {
    val scope = rememberCoroutineScope()
    Column(Modifier.padding(start = 20.dp, end = 20.dp, top = 4.dp, bottom = 16.dp)) {
        val raw = camera.properties[spec.name] ?: return@Column
        val property = camera.dialOptions(raw)
        if (property.settable) {
            OptionGrid(property) { value -> scope.launch { camera.setProperty(spec.name, value) } }
        } else {
            Text("Set this on the camera: this body doesn't let the phone change it right now.", color = Theme.secondary, fontSize = 15.sp)
        }
    }
}

/** The ··· menu's rows (221), in the bottom panel. */
@Composable
private fun MoreSheet(
    camera: CameraModel, openHighRes: () -> Unit, allSettings: () -> Unit, log: () -> Unit, report: () -> Unit,
    disconnect: () -> Unit, powerOff: () -> Unit,
) {
    val scope = rememberCoroutineScope()
    Column(Modifier.padding(horizontal = 20.dp).padding(top = 8.dp, bottom = 12.dp)) {
        val sizes = camera.capabilities.liveViewSizes
        if (sizes.isNotEmpty()) {
            var open by remember { mutableStateOf(false) }
            Box {
                MoreRow("Live view size", value = CameraModel.liveViewLabel(camera.liveViewQuality), chevron = true) { open = true }
                DropdownMenu(open, { open = false }, containerColor = Theme.surface) {
                    sizes.forEach { q ->
                        DropdownMenuItem({ Text(CameraModel.liveViewLabel(q), color = if (q == camera.liveViewQuality) Theme.accent else Theme.text) },
                            { open = false; scope.launch { camera.changeLiveViewQuality(q) } })
                    }
                }
            }
        }
        MoreRow("Restart live view") { scope.launch { camera.restartLiveView() } }
        MoreToggle("Scene suggestions", camera.sceneAssistantOn) { camera.changeSceneAssistant(it) }
        MoreToggle("Save new photos to the gallery", camera.autoSaveNewPhotos) { camera.changeAutoSave(it) }
        Spacer(Modifier.height(14.dp))
        FeedbackSwitches()
        Spacer(Modifier.height(14.dp))
        if (camera.capabilities.highResShot) MoreRow("High Res Shot helper", chevron = true, onClick = openHighRes)
        if (camera.capabilities.clockSync) MoreRow("Sync camera clock") {
            scope.launch { if (camera.syncClock()) camera.showToast("Camera clock set to this phone") }
        }
        MoreRow("All camera settings", chevron = true, onClick = allSettings)
        MoreRow("Request log", chevron = true, onClick = log)
        MoreRow("Report a problem", chevron = true, onClick = report)
        Spacer(Modifier.height(14.dp))
        MoreRow("Disconnect", onClick = disconnect)
        if (camera.capabilities.powerOff) MoreRow("Turn camera off", color = Theme.red, onClick = powerOff)
    }
}

@Composable
fun MoreRow(title: String, value: String? = null, valueColor: Color = Theme.secondary, color: Color = Theme.text,
            chevron: Boolean = false, onClick: () -> Unit) {
    Row(Modifier.fillMaxWidth().hairRow(52.dp).clickable(onClick = onClick), verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(title, color = color, fontSize = 16.sp, fontWeight = FontWeight.Medium, modifier = Modifier.weight(1f))
        if (value != null) Text(value, color = valueColor, fontSize = 15.sp, maxLines = 1)
        if (chevron) Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, null, Modifier.size(18.dp), tint = Theme.tertiary)
    }
}

@Composable
fun MoreToggle(title: String, on: Boolean, onChange: (Boolean) -> Unit) {
    Row(Modifier.fillMaxWidth().hairRow(52.dp).clickable { onChange(!on) }, verticalAlignment = Alignment.CenterVertically) {
        Text(title, color = Theme.text, fontSize = 16.sp, fontWeight = FontWeight.Medium, modifier = Modifier.weight(1f))
        Switch(on, onChange, colors = SwitchDefaults.colors(checkedTrackColor = Theme.accent, checkedThumbColor = Theme.onAccent,
            uncheckedTrackColor = Theme.surfaceRaised, uncheckedBorderColor = Theme.outline, uncheckedThumbColor = Theme.secondary))
    }
}

private fun buildTools(
    camera: CameraModel, showLoupe: Boolean, nightMode: Boolean, showHistogram: Boolean, showGrid: Boolean,
    open: (RemotePage) -> Unit, toggleLoupe: () -> Unit, toggleNight: () -> Unit, toggleHistogram: () -> Unit,
    toggleGrid: () -> Unit, closeTools: () -> Unit,
): List<ToolItem> {
    val caps = camera.capabilities
    return listOfNotNull(
        // Video is a switch here when the camera's photo/video mode can't be read.
        ToolItem("video", Icons.Filled.Videocam, "Video", camera.videoMode) {
            if (!camera.isRecordingMovie) {
                camera.videoMode = !camera.videoMode
                closeTools()
            }
        }.takeIf { caps.videoSwitch && caps.movie },
        ToolItem("presets", Icons.Filled.AutoFixHigh, "Presets", false, opens = true) { open(RemotePage.PRESETS) },
        // Stays on once applied; tapping it then turns it off and puts the old settings back.
        ToolItem("astro", Icons.Filled.NightsStay, "Astro", camera.isPresetOn(PresetRecipe.ASTRO.id),
            opens = !camera.isPresetOn(PresetRecipe.ASTRO.id)) {
            if (camera.isPresetOn(PresetRecipe.ASTRO.id)) {
                closeTools()
                camera.scope.launch { camera.undoPreset() }
            } else open(RemotePage.ASTRO)
        },
        ToolItem("interval", Icons.Filled.Timer, "Interval", camera.interval.running, opens = true) { open(RemotePage.INTERVAL) },
        ToolItem("loupe", Icons.Filled.ZoomIn, "Loupe", showLoupe) { toggleLoupe() },
        ToolItem("night", Icons.Filled.Visibility, "Night", nightMode) { toggleNight() },
        ToolItem("histogram", Icons.Filled.BarChart, "Histogram", showHistogram) { toggleHistogram() },
        ToolItem("grid", Icons.Filled.GridOn, "Grid", showGrid) { toggleGrid() },
        ToolItem("peaking", Icons.Filled.CenterFocusStrong, "Peaking", camera.focusPeaking) { camera.setPeaking(!camera.focusPeaking) },
        ToolItem("bracket", Icons.Filled.Layers, "Bracket", camera.bracket.running && !camera.bracket.isFocusStack, opens = true) {
            // Bracket opens on Exposure; Focus stack has its own tile.
            camera.prefs.edit().putBoolean("bracket.focus", false).apply()
            open(RemotePage.BRACKET)
        },
        // Its own tile so it's easy to find; the same screen as Bracket, on its Focus tab (305–307).
        ToolItem("focusstack", Icons.Filled.Layers, "Focus stack", camera.bracket.running && camera.bracket.isFocusStack, opens = true) {
            camera.prefs.edit().putBoolean("bracket.focus", true).apply()
            open(RemotePage.BRACKET)
        },
        ToolItem("nd", Icons.Filled.Filter, "ND filter", false, opens = true) { open(RemotePage.ND) },
        ToolItem("motion", Icons.Filled.DirectionsWalk, "Motion", camera.motion.armed, opens = true) { open(RemotePage.MOTION) },
        ToolItem("pocket", Icons.Filled.Bedtime, "Pocket", false, opens = true) { open(RemotePage.POCKET) },
        ToolItem("tap", Icons.Filled.TouchApp, if (camera.touchShutter) "Tap shoots" else "Tap AF", camera.touchShutter) {
            camera.touchShutter = !camera.touchShutter
        }.takeIf { caps.tapToFocus },
        ToolItem("highres", Icons.Filled.Apps, "High Res", false, opens = true) { open(RemotePage.HIGH_RES) }.takeIf { caps.highResShot },
    )
}

/** The scene assistant's suggestion over the bottom of live view (not while the loupe is open). */
@Composable
private fun SuggestionOverlay(camera: CameraModel, showLoupe: Boolean, apply: (SceneSuggestion) -> Unit, modifier: Modifier) {
    val suggestion = camera.sceneSuggestion
    AnimatedVisibility(suggestion != null && !showLoupe, modifier, enter = slideInVertically { it } + fadeIn(), exit = fadeOut()) {
        suggestion?.let { s -> SceneSuggestionPill(camera, s, onApply = { apply(s) }) }
    }
}

/**
 * Camera errors and model-specific advice over the top of the picture (three lines until tapped), and a
 * one-tap setup that's on, with its way back.
 */
@Composable
fun Banners(camera: CameraModel, modifier: Modifier = Modifier) {
    val scope = rememberCoroutineScope()
    val error = camera.lastError
    val note = camera.cameraNote
    val undo = camera.presetUndo
    var expanded by remember { mutableStateOf(false) }
    Column(modifier, horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)) {
        if (error != null || note != null) {
            val isError = error != null
            Row(
                Modifier.padding(horizontal = 12.dp).fillMaxWidth()
                    .surface(RoundedCornerShape(18.dp), tint = if (isError) Theme.red.copy(alpha = 0.3f) else Theme.accent.copy(alpha = 0.18f))
                    .padding(12.dp),
                horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.Top,
            ) {
                Icon(if (isError) Icons.Filled.Warning else Icons.Filled.Info, null, Modifier.size(18.dp), tint = Theme.accent)
                Text(error ?: note ?: "", fontSize = 13.sp, color = Theme.text, maxLines = if (expanded) Int.MAX_VALUE else 3,
                    modifier = Modifier.weight(1f).clickable { expanded = !expanded })
                Icon(Icons.Filled.Close, "Dismiss", Modifier.size(28.dp).clip(RoundedCornerShape(14.dp))
                    .clickable { if (isError) camera.lastError = null else camera.dismissCameraNote() }
                    .padding(4.dp), tint = Theme.text)
            }
        }
        if (undo != null && !camera.presetRunning) {
            Row(Modifier.surface(Pill, tint = Theme.green.copy(alpha = 0.25f)).clickable { scope.launch { camera.undoPreset() } }
                .padding(horizontal = 12.dp, vertical = 7.dp), verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Icon(Icons.Filled.CheckCircle, null, Modifier.size(15.dp), tint = Theme.text)
                Text("${undo.title} on · Turn off", color = Theme.text, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
            }
        }
    }
}

/** Floating confirmation capsule. */
@Composable
fun Toast(camera: CameraModel, modifier: Modifier = Modifier) {
    val text = camera.toast
    AnimatedVisibility(text != null, modifier.padding(top = 8.dp).zIndex(2f), enter = slideInVertically() + fadeIn(), exit = fadeOut()) {
        Row(Modifier.surface(Pill).padding(horizontal = 16.dp, vertical = 10.dp), horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Filled.CheckCircle, null, Modifier.size(18.dp), tint = Theme.accent)
            Text(text ?: "", fontSize = 15.sp, fontWeight = FontWeight.Medium, color = Theme.text)
        }
    }
}

/**
 * Lays an overlay out at its natural height but reports no height, drawing it upward from where it
 * sits: an overlay floats over the picture instead of pushing the controls down.
 */
fun Modifier.floatUp(): Modifier = this.layout { measurable, constraints ->
    val placeable = measurable.measure(constraints.copy(minHeight = 0, maxHeight = Constraints.Infinity))
    layout(placeable.width, 0) { placeable.place(0, -placeable.height) }
}
