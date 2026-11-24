package com.apexcommerce.shutterlink.ui

import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
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
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.List
import androidx.compose.material.icons.filled.Apps
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.Download
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import com.apexcommerce.shutterlink.camera.SceneSuggestion
import com.apexcommerce.shutterlink.camera.applySceneSuggestion
import com.apexcommerce.shutterlink.camera.runSceneAssistant
import androidx.compose.material.icons.filled.AutoFixHigh
import androidx.compose.material.icons.filled.DirectionsWalk
import androidx.compose.material.icons.filled.Filter
import androidx.compose.material.icons.filled.AspectRatio
import androidx.compose.material.icons.filled.BarChart
import androidx.compose.material.icons.filled.Bedtime
import androidx.compose.material.icons.filled.CenterFocusStrong
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.GridOn
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.Layers
import androidx.compose.material.icons.filled.MoreHoriz
import androidx.compose.material.icons.filled.NightsStay
import androidx.compose.material.icons.filled.PowerSettingsNew
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material.icons.filled.Timer
import androidx.compose.material.icons.filled.TouchApp
import androidx.compose.material.icons.filled.Videocam
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material.icons.filled.WifiOff
import androidx.compose.material.icons.filled.ZoomIn
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
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
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.layout
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.zIndex
import com.apexcommerce.shutterlink.camera.CameraModel
import com.apexcommerce.shutterlink.camera.changeAutoSave
import kotlinx.coroutines.launch

/** Which sheet or full-screen page is open over the remote. */
enum class RemotePage { NONE, GALLERY, ASTRO, INTERVAL, BRACKET, ALL_SETTINGS, LOG, HIGH_RES, POCKET, PRESETS, ND, MOTION }

@Composable
fun RemoteScreen(camera: CameraModel) {
    val scope = rememberCoroutineScope()
    var page by rememberSaveable { mutableStateOf(RemotePage.NONE) }
    var toolsOpen by remember { mutableStateOf(false) }
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

    BackHandler(enabled = activeSetting != null || toolsOpen || showLoupe) {
        when {
            activeSetting != null -> activeSetting = null
            toolsOpen -> toolsOpen = false
            else -> showLoupe = false
        }
    }

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
    val quickAids = listOf("grid", "histogram", "peaking", "loupe", "night").mapNotNull { id -> tools.firstOrNull { it.id == id } }

    val menu: @Composable () -> Unit = {
        CameraMenu(camera,
            open = { page = it },
            disconnect = { confirmDisconnect = true },
            powerOff = { confirmPowerOff = true })
    }
    val selectSetting: (String?) -> Unit = { name ->
        activeSetting = name
        if (name != null) toolsOpen = false
    }
    // Recipes and settings run straight away; ND and Motion open their panel, ready to go.
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

    NightVision(nightMode) {
        BoxWithConstraints(Modifier.fillMaxSize().safeDrawingPadding()) {
            val landscape = maxWidth > maxHeight
            if (landscape) {
                LandscapeLayout(camera, menu, tools, toolsOpen, toggleTools, activeSetting, selectSetting,
                    showGrid, showHistogram, showLoupe, maxWidth, maxHeight, motionOpen = page == RemotePage.MOTION,
                    closeMotion = { page = RemotePage.NONE }, applySuggestion = applySuggestion) { page = RemotePage.GALLERY }
            } else {
                PortraitLayout(camera, menu, tools, quickAids, toolsOpen, toggleTools, activeSetting, selectSetting,
                    showGrid, showHistogram, showLoupe, showAids = maxHeight >= 700.dp, motionOpen = page == RemotePage.MOTION,
                    closeMotion = { page = RemotePage.NONE }, applySuggestion = applySuggestion) { page = RemotePage.GALLERY }
            }
            Toast(camera, Modifier.align(Alignment.TopCenter))
        }
    }

    when (page) {
        RemotePage.ASTRO -> AstroSheet(camera) { page = RemotePage.NONE }
        RemotePage.INTERVAL -> IntervalSheet(camera) { page = RemotePage.NONE }
        RemotePage.BRACKET -> BracketSheet(camera) { page = RemotePage.NONE }
        RemotePage.ALL_SETTINGS -> AllSettingsSheet(camera) { page = RemotePage.NONE }
        RemotePage.LOG -> LogSheet(camera) { page = RemotePage.NONE }
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

    if (confirmPowerOff) {
        AlertDialog(
            onDismissRequest = { confirmPowerOff = false },
            title = { Text("Turn the camera off?") },
            text = { Text("You'll need to switch it on and start Wi-Fi on the camera again to reconnect.") },
            confirmButton = { TextButton({ confirmPowerOff = false; scope.launch { camera.powerOff() } }) { Text("Turn off", color = Theme.red) } },
            dismissButton = { TextButton({ confirmPowerOff = false }) { Text("Cancel") } },
            containerColor = Theme.surfaceRaised,
        )
    }
    if (confirmDisconnect) {
        AlertDialog(
            onDismissRequest = { confirmDisconnect = false },
            title = { Text("Disconnect from the camera?") },
            confirmButton = { TextButton({ confirmDisconnect = false; scope.launch { camera.disconnect() } }) { Text("Disconnect", color = Theme.red) } },
            dismissButton = { TextButton({ confirmDisconnect = false }) { Text("Cancel") } },
            containerColor = Theme.surfaceRaised,
        )
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
            drawRect(Color(1f, 0.22f, 0.18f), blendMode = BlendMode.Multiply)
        }) { content() }
}

/** Portrait, like a phone camera app: status on top, a clean viewfinder, everything you touch at the bottom. */
@Composable
private fun PortraitLayout(
    camera: CameraModel, menu: @Composable () -> Unit, tools: List<ToolItem>, quickAids: List<ToolItem>,
    toolsOpen: Boolean, toggleTools: () -> Unit, activeSetting: String?, selectSetting: (String?) -> Unit,
    showGrid: Boolean, showHistogram: Boolean, showLoupe: Boolean, showAids: Boolean,
    motionOpen: Boolean, closeMotion: () -> Unit, applySuggestion: (SceneSuggestion) -> Unit, openGallery: () -> Unit,
) {
    Column(Modifier.fillMaxSize(), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        InfoBar(camera) { menu() }
        HorizontalDivider(color = Theme.stroke, thickness = 1.dp)
        Spacer(Modifier.weight(1f))
        Box {
            LiveViewPane(camera, showGrid, showHistogram, showLoupe, Modifier.fillMaxWidth().aspectRatio(4f / 3f))
            Banners(camera, Modifier.align(Alignment.TopCenter).padding(top = 8.dp))
            SuggestionOverlay(camera, showLoupe, applySuggestion, Modifier.align(Alignment.BottomCenter).padding(10.dp))
        }
        Box(Modifier.padding(horizontal = 12.dp).zIndex(1f)) {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                if (motionOpen) {
                    // Docked, not a sheet: the box on live view stays draggable while it's open.
                    MotionPanel(camera, closeMotion, maxHeight = 250.dp)
                } else {
                    OptionPanelFor(camera, activeSetting) { selectSetting(null) }
                    ExposureStrip(camera, activeSetting, selectSetting)
                    // While a setting panel is open (Drive, ISO…) it gets the aids' room; they come back when it closes.
                    if (showAids && activeSetting == null) QuickAidStrip(quickAids)
                }
            }
            // The tools float over the picture rather than squeezing it.
            androidx.compose.animation.AnimatedVisibility(toolsOpen, Modifier.align(Alignment.BottomCenter).floatUp(),
                enter = slideInVertically { it / 2 } + fadeIn(), exit = slideOutVertically { it / 2 } + fadeOut()) {
                ToolsTray(tools)
            }
        }
        Spacer(Modifier.weight(1f))
        if (camera.properties["takemode"] != null) ModeCarousel(camera)
        Row(Modifier.fillMaxWidth().padding(horizontal = 24.dp).padding(bottom = 4.dp), verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.width(84.dp), contentAlignment = Alignment.Center) {
                LastShotButton(camera, enabled = !camera.isBusyExposing && !camera.interval.running && camera.capabilities.cardBrowser, onClick = openGallery)
            }
            Spacer(Modifier.weight(1f))
            ShutterButton(camera)
            Spacer(Modifier.weight(1f))
            Box(Modifier.width(84.dp), contentAlignment = Alignment.Center) { ToolsButton(camera, toolsOpen, toggleTools) }
        }
    }
}

/** Landscape: a big viewfinder and a rail with the mode dial and shutter under the thumb. */
@Composable
private fun LandscapeLayout(
    camera: CameraModel, menu: @Composable () -> Unit, tools: List<ToolItem>,
    toolsOpen: Boolean, toggleTools: () -> Unit, activeSetting: String?, selectSetting: (String?) -> Unit,
    showGrid: Boolean, showHistogram: Boolean, showLoupe: Boolean,
    width: androidx.compose.ui.unit.Dp, height: androidx.compose.ui.unit.Dp,
    motionOpen: Boolean, closeMotion: () -> Unit, applySuggestion: (SceneSuggestion) -> Unit, openGallery: () -> Unit,
) {
    val imageWidth = width - 128.dp - 28.dp
    val imageHeight = minOf(height - 8.dp, imageWidth * 3 / 4)
    val readoutsBelow = height - 8.dp - imageHeight >= 74.dp
    Row(Modifier.fillMaxSize().padding(horizontal = 6.dp, vertical = 4.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        Column(Modifier.weight(1f).fillMaxHeight(), verticalArrangement = Arrangement.spacedBy(8.dp, if (readoutsBelow) Alignment.Top else Alignment.CenterVertically),
            horizontalAlignment = Alignment.CenterHorizontally) {
            // The overlays are sized to the picture, not the column around it.
            Box(Modifier.height(imageHeight).aspectRatio(4f / 3f).clip(RoundedCornerShape(18.dp))) {
                LiveViewPane(camera, showGrid, showHistogram, showLoupe, Modifier.fillMaxSize(), hudTopInset = 46.dp)
                Column(Modifier.align(Alignment.TopStart).padding(10.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    StatusPill(camera)
                    Banners(camera, Modifier.widthIn(max = 460.dp))
                }
                if (!motionOpen) {
                    // Above the readouts when they're drawn over the picture.
                    SuggestionOverlay(camera, showLoupe, applySuggestion, Modifier.align(Alignment.BottomCenter)
                        .padding(start = 10.dp, end = 10.dp, bottom = if (!readoutsBelow && !showLoupe) 84.dp else 10.dp))
                }
                if (motionOpen) {
                    Box(Modifier.align(Alignment.BottomEnd).padding(10.dp).widthIn(max = 360.dp)) {
                        MotionPanel(camera, closeMotion, maxHeight = imageHeight - 20.dp)
                    }
                } else if (!readoutsBelow && !showLoupe) {
                    Column(Modifier.align(Alignment.BottomCenter).padding(10.dp).widthIn(max = 620.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        OptionPanelFor(camera, activeSetting) { selectSetting(null) }
                        ExposureStrip(camera, activeSetting, selectSetting, compact = true)
                    }
                }
                androidx.compose.animation.AnimatedVisibility(toolsOpen, Modifier.align(Alignment.BottomCenter).padding(10.dp).widthIn(max = 620.dp).floatUp(),
                    enter = fadeIn(), exit = fadeOut()) { ToolsTray(tools, columns = 6) }
            }
            if (readoutsBelow) {
                Column(Modifier.widthIn(max = 620.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    OptionPanelFor(camera, activeSetting) { selectSetting(null) }
                    ExposureStrip(camera, activeSetting, selectSetting)
                }
            }
        }
        Column(Modifier.width(128.dp).fillMaxHeight().padding(vertical = 6.dp), horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(12.dp)) {
            menu()
            // The mode dial gets whatever height is left, so the buttons below never get squeezed.
            Box(Modifier.weight(1f).fillMaxWidth(), contentAlignment = Alignment.Center) {
                if (camera.properties["takemode"] != null) ModeCarousel(camera, vertical = true)
            }
            ShutterButton(camera)
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                LastShotButton(camera, enabled = !camera.isBusyExposing && !camera.interval.running && camera.capabilities.cardBrowser, onClick = openGallery)
                ToolsButton(camera, toolsOpen, toggleTools)
            }
        }
    }
}

@Composable
private fun OptionPanelFor(camera: CameraModel, name: String?, onClose: () -> Unit) {
    val spec = name?.let { SettingSpec.spec(it) } ?: return
    if (camera.properties[spec.name] == null) return
    androidx.compose.runtime.key(spec.name) { OptionPanel(camera, spec, onClose) }
}

@Composable
private fun CameraMenu(camera: CameraModel, open: (RemotePage) -> Unit, disconnect: () -> Unit, powerOff: () -> Unit) {
    val scope = rememberCoroutineScope()
    var expanded by remember { mutableStateOf(false) }
    var sizes by remember { mutableStateOf(false) }
    Box {
        SurfaceButton(onClick = { expanded = true }, circle = true, enabled = !camera.isBusyExposing) {
            Icon(Icons.Filled.MoreHoriz, "More")
        }
        DropdownMenu(expanded, { expanded = false; sizes = false }, containerColor = Theme.surfaceRaised) {
            Text(camera.cameraName ?: "Camera", color = Theme.tertiary, fontSize = 12.sp, modifier = Modifier.padding(horizontal = 16.dp, vertical = 6.dp))
            if (camera.availableLiveViewSizes.isNotEmpty()) {
                DropdownMenuItem({ Text("Live view size") }, { sizes = !sizes }, leadingIcon = { Icon(Icons.Filled.AspectRatio, null) })
                if (sizes) camera.availableLiveViewSizes.forEach { q ->
                    DropdownMenuItem(
                        { Text(CameraModel.liveViewLabel(q), color = if (q == camera.liveViewQuality) Theme.accent else Color.White, fontSize = 14.sp) },
                        { expanded = false; sizes = false; scope.launch { camera.changeLiveViewQuality(q) } },
                        modifier = Modifier.padding(start = 24.dp),
                    )
                }
            }
            DropdownMenuItem({ Text("Restart live view") }, { expanded = false; scope.launch { camera.restartLiveView() } },
                leadingIcon = { Icon(Icons.Filled.Refresh, null) })
            DropdownMenuItem({ Text("Scene suggestions") }, { camera.changeSceneAssistant(!camera.sceneAssistantOn) },
                leadingIcon = { Icon(Icons.Filled.AutoAwesome, null) },
                trailingIcon = {
                    Switch(camera.sceneAssistantOn, { camera.changeSceneAssistant(it) },
                        colors = SwitchDefaults.colors(checkedTrackColor = Theme.accent, checkedThumbColor = Color.Black))
                })
            DropdownMenuItem({ Text("Save new photos to the gallery") }, { camera.changeAutoSave(!camera.autoSaveNewPhotos) },
                leadingIcon = { Icon(Icons.Filled.Download, null) },
                trailingIcon = {
                    Switch(camera.autoSaveNewPhotos, { camera.changeAutoSave(it) },
                        colors = SwitchDefaults.colors(checkedTrackColor = Theme.accent, checkedThumbColor = Color.Black))
                })
            HorizontalDivider(color = Theme.stroke)
            if (camera.capabilities.highResShot) {
                DropdownMenuItem({ Text("High Res Shot helper") }, { expanded = false; open(RemotePage.HIGH_RES) }, leadingIcon = { Icon(Icons.Filled.Apps, null) })
            }
            if (camera.capabilities.clockSync) {
                DropdownMenuItem({ Text("Sync camera clock") }, {
                    expanded = false
                    scope.launch { if (camera.syncClock()) camera.showToast("Camera clock set to this phone") }
                }, leadingIcon = { Icon(Icons.Filled.Schedule, null) })
            }
            DropdownMenuItem({ Text("All camera settings") }, { expanded = false; open(RemotePage.ALL_SETTINGS) },
                leadingIcon = { Icon(Icons.AutoMirrored.Filled.List, null) })
            DropdownMenuItem({ Text("Request log") }, { expanded = false; open(RemotePage.LOG) }, leadingIcon = { Icon(Icons.Filled.Info, null) })
            HorizontalDivider(color = Theme.stroke)
            DropdownMenuItem({ Text("Disconnect") }, { expanded = false; disconnect() }, leadingIcon = { Icon(Icons.Filled.WifiOff, null) })
            if (camera.capabilities.powerOff) {
                DropdownMenuItem({ Text("Turn camera off", color = Theme.red) }, { expanded = false; powerOff() },
                    leadingIcon = { Icon(Icons.Filled.PowerSettingsNew, null, tint = Theme.red) })
            }
        }
    }
}

private fun buildTools(
    camera: CameraModel, showLoupe: Boolean, nightMode: Boolean, showHistogram: Boolean, showGrid: Boolean,
    open: (RemotePage) -> Unit, toggleLoupe: () -> Unit, toggleNight: () -> Unit, toggleHistogram: () -> Unit,
    toggleGrid: () -> Unit, closeTools: () -> Unit,
): List<ToolItem> {
    val caps = camera.capabilities
    val all = mutableListOf(
        ToolItem("presets", Icons.Filled.AutoFixHigh, "Presets", false, opens = true) { open(RemotePage.PRESETS) },
        ToolItem("astro", Icons.Filled.NightsStay, "Astro", false, opens = true) { open(RemotePage.ASTRO) },
        ToolItem("interval", Icons.Filled.Timer, "Interval", camera.interval.running, opens = true) { open(RemotePage.INTERVAL) },
        ToolItem("loupe", Icons.Filled.ZoomIn, "Loupe", showLoupe) { toggleLoupe() },
        ToolItem("night", Icons.Filled.Visibility, "Night", nightMode) { toggleNight() },
        ToolItem("histogram", Icons.Filled.BarChart, "Histogram", showHistogram) { toggleHistogram() },
        ToolItem("grid", Icons.Filled.GridOn, "Grid", showGrid) { toggleGrid() },
        ToolItem("peaking", Icons.Filled.CenterFocusStrong, "Peaking", camera.focusPeaking) { camera.setPeaking(!camera.focusPeaking) },
        ToolItem("bracket", Icons.Filled.Layers, "Bracket", camera.bracket.running, opens = true) { open(RemotePage.BRACKET) },
        ToolItem("nd", Icons.Filled.Filter, "ND filter", false, opens = true) { open(RemotePage.ND) },
        ToolItem("motion", Icons.Filled.DirectionsWalk, "Motion", camera.motion.armed, opens = true) { open(RemotePage.MOTION) },
        ToolItem("pocket", Icons.Filled.Bedtime, "Pocket", false, opens = true) { open(RemotePage.POCKET) },
        ToolItem("tap", Icons.Filled.TouchApp, if (camera.touchShutter) "Tap shoots" else "Tap AF", camera.touchShutter) {
            camera.touchShutter = !camera.touchShutter
        },
        ToolItem("highres", Icons.Filled.Apps, "High Res", false, opens = true) { open(RemotePage.HIGH_RES) },
    ).filter { item ->
        when (item.id) {
            "highres" -> caps.highResShot
            "tap" -> caps.tapToFocus
            else -> true
        }
    }.toMutableList()
    if (caps.videoSwitch && caps.movie) {
        // Video is a switch here when the camera's photo/video mode can't be read.
        all.add(0, ToolItem("video", Icons.Filled.Videocam, "Video", camera.videoMode) {
            if (!camera.isRecordingMovie) {
                camera.videoMode = !camera.videoMode
                closeTools()
            }
        })
    }
    return all
}

/** The scene assistant's suggestion over the bottom of live view (not while the loupe is open). */
@Composable
private fun SuggestionOverlay(camera: CameraModel, showLoupe: Boolean, apply: (SceneSuggestion) -> Unit, modifier: Modifier) {
    val suggestion = camera.sceneSuggestion
    AnimatedVisibility(suggestion != null && !showLoupe, modifier, enter = slideInVertically { it } + fadeIn(), exit = fadeOut()) {
        suggestion?.let { s -> SceneSuggestionPill(camera, s, onApply = { apply(s) }) }
    }
}

/** Camera errors and model-specific advice, over the top of the picture. */
@Composable
fun Banners(camera: CameraModel, modifier: Modifier = Modifier) {
    val error = camera.lastError
    val note = camera.cameraNote
    if (error == null && note == null) return
    val isError = error != null
    Row(
        modifier.padding(horizontal = 12.dp).fillMaxWidth()
            .surface(RoundedCornerShape(18.dp), tint = if (isError) Theme.red.copy(alpha = 0.35f) else Theme.accent.copy(alpha = 0.18f))
            .padding(12.dp),
        horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.Top,
    ) {
        Icon(if (isError) Icons.Filled.Warning else Icons.Filled.Info, null, Modifier.size(18.dp),
            tint = if (isError) Color(1f, 0.84f, 0.04f) else Theme.accent)
        Text(error ?: note ?: "", fontSize = 13.sp, modifier = Modifier.weight(1f))
        Icon(Icons.Filled.Close, "Dismiss", Modifier.size(28.dp).clip(RoundedCornerShape(14.dp))
            .clickable { if (isError) camera.lastError = null else camera.dismissCameraNote() }
            .padding(4.dp))
    }
}

/** Floating confirmation capsule. */
@Composable
fun Toast(camera: CameraModel, modifier: Modifier = Modifier) {
    val text = camera.toast
    AnimatedVisibility(text != null, modifier.padding(top = 8.dp), enter = slideInVertically() + fadeIn(), exit = fadeOut()) {
        Row(Modifier.surface(Pill).padding(horizontal = 16.dp, vertical = 10.dp), horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Filled.CheckCircle, null, Modifier.size(18.dp), tint = Theme.accent)
            Text(text ?: "", fontSize = 15.sp, fontWeight = FontWeight.Medium)
        }
    }
}

/**
 * Lays an overlay out at its natural height but reports no height, drawing it upward from where it
 * sits: the tools tray floats over the picture instead of pushing the controls down.
 */
fun Modifier.floatUp(): Modifier = this.layout { measurable, constraints ->
    val placeable = measurable.measure(constraints.copy(minHeight = 0, maxHeight = Constraints.Infinity))
    layout(placeable.width, 0) { placeable.place(0, -placeable.height) }
}
