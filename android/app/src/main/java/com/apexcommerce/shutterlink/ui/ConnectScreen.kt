package com.apexcommerce.shutterlink.ui

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.provider.Settings
import android.text.format.DateUtils
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.Crossfade
import androidx.compose.animation.animateContentSize
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.animation.core.animateFloat
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.WindowInsetsSides
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.only
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.Science
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material.icons.filled.Wifi
import androidx.compose.material.icons.filled.WifiOff
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.State
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.em
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import com.apexcommerce.shutterlink.camera.BrandDetector
import com.apexcommerce.shutterlink.camera.CameraBrand
import com.apexcommerce.shutterlink.camera.CameraModel
import com.apexcommerce.shutterlink.camera.CameraNetwork
import com.apexcommerce.shutterlink.camera.ConnectionPhase
import com.apexcommerce.shutterlink.camera.SavedCamera
import com.apexcommerce.shutterlink.camera.applyScannedCode
import com.apexcommerce.shutterlink.camera.connect
import com.apexcommerce.shutterlink.camera.connectFromScannedCode
import com.apexcommerce.shutterlink.camera.forget
import com.apexcommerce.shutterlink.camera.joinAndConnect
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlin.math.PI
import kotlin.math.min
import kotlin.math.sin

/**
 * The home screen while not connected (port of ConnectView.swift, direction D): the cameras this
 * phone knows (the last one as a large card, one tap to reconnect) and "Add a camera" for a new one.
 * First run shows the cover instead (102); while connecting, the whole screen says what's happening (104).
 */
@Composable
fun ConnectScreen(camera: CameraModel) {
    var showAdd by remember { mutableStateOf(false) }
    var connectingId by remember { mutableStateOf<String?>(null) }
    /** Edit on "Your cameras": each camera shows a button to forget it. */
    var editing by remember { mutableStateOf(false) }
    // The camera stays set while the dialog animates away; `forgetShown` opens and closes it.
    var forgetting by remember { mutableStateOf<SavedCamera?>(null) }
    var forgetShown by remember { mutableStateOf(false) }
    var scanNote by remember { mutableStateOf<String?>(null) }
    var showReport by remember { mutableStateOf(false) }
    val empty = camera.savedCameras.isEmpty()
    LaunchedEffect(camera.phase) { if (camera.phase != ConnectionPhase.CONNECTING) connectingId = null }
    LaunchedEffect(empty) { if (empty) editing = false }
    val withWifiPermission = rememberWifiJoinPermission(camera)
    val scan = rememberQrScanner(onCode = { code ->
        withWifiPermission {
            scanNote = if (camera.connectFromScannedCode(code)) null else UNREADABLE_CODE
        }
    }, onError = { scanNote = it })

    if (showAdd) {
        AddCameraScreen(camera) { showAdd = false }
        return
    }

    val connecting = camera.phase == ConnectionPhase.CONNECTING
    BackHandler(enabled = editing) { editing = false }
    var footerHeight by remember { mutableStateOf(0.dp) }
    val density = LocalDensity.current

    BoxWithConstraints(Modifier.fillMaxSize().background(Theme.background)) {
        val compact = maxHeight < 600.dp
        ConnectBackground(firstRun = empty && !connecting)
        Crossfade(connecting, label = "connecting") { showConnecting ->
            Column(
                Modifier.fillMaxSize()
                    .windowInsetsPadding(WindowInsets.safeDrawing.only(WindowInsetsSides.Top + WindowInsetsSides.Horizontal))
                    .verticalScroll(rememberScrollState()),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Column(Modifier.widthIn(max = 560.dp).fillMaxWidth().padding(horizontal = 20.dp)) {
                    if (showConnecting) {
                        // The camera being connected: the card tapped, else the last one of this brand, else
                        // the network being joined, else the brand.
                        val saved = camera.savedCameras.firstOrNull { it.id == connectingId }
                            ?: if (camera.autoDetectBrand) null
                            else camera.savedCameras.filter { it.brand == camera.brand }.maxByOrNull { it.lastUsed }
                        val typedSsid = camera.wifiSsid.trim().ifEmpty { null }
                        ConnectingView(camera,
                            name = saved?.name ?: typedSsid ?: if (camera.autoDetectBrand) "Camera" else camera.brand.shortTitle,
                            ssid = saved?.ssid ?: typedSsid)
                        Spacer(Modifier.windowInsetsPadding(WindowInsets.safeDrawing.only(WindowInsetsSides.Bottom)).height(24.dp))
                    } else {
                        Column(verticalArrangement = Arrangement.spacedBy(24.dp)) {
                            if (empty) {
                                Cover(compact)
                                scan?.let { open ->
                                    ScanToConnect(camera, busy = connecting && connectingId == null, note = scanNote,
                                        onClick = { scanNote = null; open() })
                                }
                                EmptyState()
                            } else {
                                FinderLockup(40.dp, Modifier.padding(top = 20.dp))
                                scan?.let { open ->
                                    ScanToConnect(camera, busy = connecting && connectingId == null, note = scanNote,
                                        onClick = { scanNote = null; open() })
                                }
                                CameraList(camera, editing = editing, canScan = scan != null, connectingId = connectingId,
                                    onToggleEdit = { editing = !editing },
                                    onTap = { saved ->
                                        connectingId = saved.id
                                        // In the camera's own scope: this screen goes away once it's connected,
                                        // and its scope with it, which would cancel the end of the connection.
                                        // A camera saved with its network joins it first, which needs Android's permission.
                                        if (saved.ssid != null) withWifiPermission { camera.scope.launch { camera.connect(saved) } }
                                        else camera.scope.launch { camera.connect(saved) }
                                    },
                                    onForget = { saved -> forgetting = saved; forgetShown = true },
                                    onAdd = { showAdd = true })
                                Text("Long-press a camera to forget it.", color = Theme.tertiary, fontSize = 13.sp)
                            }
                        }
                        // Room to scroll clear of the footer.
                        Spacer(Modifier.height(footerHeight + 56.dp))
                    }
                }
            }
        }
        // While connecting (104) the screen is only the connecting view: no footer.
        if (!connecting) {
            // A short fade, then solid: the list scrolls clear under it.
            Column(
                Modifier.align(Alignment.BottomCenter).fillMaxWidth()
                    .onSizeChanged { footerHeight = with(density) { it.height.toDp() } }
                    .background(Brush.verticalGradient(0f to Theme.background.copy(alpha = 0f), 0.14f to Theme.background))
                    .windowInsetsPadding(WindowInsets.safeDrawing.only(WindowInsetsSides.Bottom + WindowInsetsSides.Horizontal)),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Column(Modifier.widthIn(max = 600.dp).fillMaxWidth().padding(horizontal = 20.dp).padding(top = 20.dp, bottom = 8.dp)
                    .animateContentSize(), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    camera.lastError?.let { error ->
                        ConnectErrorBanner(error, onReport = { showReport = true }, onDismiss = { camera.lastError = null })
                    }
                    WifiStatusRow(camera)
                    if (empty) {
                        OutlineButton(onClick = { showAdd = true }, modifier = Modifier.fillMaxWidth()) { Text("Add your camera") }
                    }
                }
            }
        }
        // 107: forgetting a camera asks in the design's dialog card.
        DialogCard(
            visible = forgetShown,
            title = "Forget ${forgetting?.name ?: "this camera"}?",
            message = "It comes off this list, with the Wi-Fi password Shutterlink saved for it. Connect again to add it back.",
            action = "Forget this camera",
            onAction = {
                forgetting?.let { camera.forget(it) }
                forgetShown = false
            },
            onCancel = { forgetShown = false },
        )
    }

    if (showReport) ReportProblemPage(camera = camera, onDismiss = { showReport = false })
}

// MARK: - Home

/** First run (102): the lockup, the headline and what the app does. */
@Composable
private fun Cover(compact: Boolean) {
    Column(Modifier.padding(top = if (compact) 16.dp else 32.dp), verticalArrangement = Arrangement.spacedBy(if (compact) 10.dp else 16.dp)) {
        FinderLockup(if (compact) 38.dp else 48.dp)
        SolidHeadline("Shoot from\nyour phone.", if (compact) 56.sp else 76.sp, Modifier.padding(top = if (compact) 0.dp else 24.dp))
        Text("Remote control for Olympus, OM System, Panasonic LUMIX, Nikon, Canon and Sony cameras over their own Wi-Fi.",
            color = Color(0xFFD8D4C9), fontSize = 15.sp, lineHeight = 21.sp)
    }
}

@Composable
private fun EmptyState() {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        CapsLabel("Your cameras")
        Text("No cameras yet", color = Theme.text, fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
        Text("Add your camera once. After that it waits here: turn on its Wi-Fi and tap it.", color = Theme.secondary, fontSize = 15.sp)
    }
}

/** "Your cameras": the last one used as the large card, the rest as rows, then Add a camera. */
@Composable
private fun CameraList(
    camera: CameraModel, editing: Boolean, canScan: Boolean, connectingId: String?,
    onToggleEdit: () -> Unit, onTap: (SavedCamera) -> Unit, onForget: (SavedCamera) -> Unit, onAdd: () -> Unit,
) {
    val disconnected = camera.phase == ConnectionPhase.DISCONNECTED
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                CapsLabel("Your cameras", modifier = Modifier.weight(1f))
                HeaderButton(if (editing) "Done" else "Edit", enabled = disconnected, onClick = onToggleEdit)
            }
            Text("Turn on the camera's Wi-Fi and tap it. A camera saved with its Wi-Fi joins it by itself; for others, join it in Settings ▸ Wi-Fi first" +
                if (canScan) ", or scan its code once." else ".",
                color = Theme.secondary, fontSize = 13.sp, lineHeight = 18.sp, modifier = Modifier.padding(bottom = 2.dp))
        }
        camera.savedCameras.forEachIndexed { index, saved ->
            SavedCameraCard(camera, saved, hero = index == 0, editing = editing,
                connecting = camera.phase == ConnectionPhase.CONNECTING && connectingId == saved.id,
                onTap = { onTap(saved) }, onForget = { onForget(saved) })
        }
        Row(
            Modifier.fillMaxWidth().heightIn(min = 60.dp).clickable(enabled = disconnected, role = Role.Button, onClick = onAdd),
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Box(Modifier.size(26.dp).drawBehind {
                val w = 1.5.dp.toPx()
                drawCircle(Theme.tertiary, radius = size.minDimension / 2 - w / 2,
                    style = Stroke(w, pathEffect = PathEffect.dashPathEffect(floatArrayOf(3.dp.toPx(), 3.dp.toPx()))))
            }, contentAlignment = Alignment.Center) {
                Text("+", color = Theme.secondary, fontSize = 16.sp)
            }
            Text("Add a camera", color = Theme.secondary, fontSize = 16.sp)
        }
    }
}

/**
 * A saved camera. The `hero` (the last one used) is a large card: brand and when, the name in big
 * Barlow, "Tap to connect", and the camera in line. The others are hairline rows. Long-press forgets.
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun SavedCameraCard(camera: CameraModel, saved: SavedCamera, hero: Boolean, editing: Boolean, connecting: Boolean,
                            onTap: () -> Unit, onForget: () -> Unit) {
    val lastUsed = DateUtils.getRelativeTimeSpanString(saved.lastUsed, System.currentTimeMillis(), DateUtils.MINUTE_IN_MILLIS).toString()
    val shape = RoundedCornerShape(28.dp)
    Box(Modifier.fillMaxWidth()) {
        Row(
            Modifier.fillMaxWidth()
                .then(if (hero) Modifier.clip(shape).background(if (connecting) Theme.surfaceRaised else Theme.surface, shape)
                    .border(1.dp, if (connecting) Theme.accent.copy(alpha = 0.6f) else Theme.stroke, shape)
                else Modifier.hairRow())
                .combinedClickable(enabled = camera.phase == ConnectionPhase.DISCONNECTED && !editing,
                    onClickLabel = "Connect", onLongClickLabel = "Forget this camera", onClick = onTap, onLongClick = onForget)
                .heightIn(min = if (hero) 120.dp else 64.dp)
                .padding(if (hero) PaddingValues(20.dp) else PaddingValues(vertical = 10.dp))
                .semantics { contentDescription = "${saved.name}, ${saved.brand.title}, last used $lastUsed" },
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(if (hero) 8.dp else 3.dp)) {
                if (hero) CapsLabel("${saved.brand.shortTitle} · $lastUsed")
                AutoFitText(saved.name, Theme.num(if (hero) 60.sp else 28.sp), Theme.text, Modifier.fillMaxWidth(), TextAlign.Start)
                when {
                    connecting -> Text(camera.status ?: "Connecting…", color = Theme.accent, fontSize = 13.sp, maxLines = 1,
                        overflow = TextOverflow.Ellipsis)
                    hero -> Text("Tap to connect", color = Theme.accent, fontSize = 14.sp, fontWeight = FontWeight.SemiBold)
                    else -> CapsLabel("${saved.brand.shortTitle} · $lastUsed", Theme.tertiary)
                }
            }
            if (hero && !connecting && !editing) CameraLineArt(Modifier.size(118.dp, 84.dp))
            if (connecting) CircularProgressIndicator(color = Theme.accent, strokeWidth = 2.dp, modifier = Modifier.size(20.dp))
            else if (!editing && !hero) Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, null, tint = Theme.tertiary)
        }
        if (editing) {
            // Edit's forget button: a red disc with a minus, 44 dp to tap.
            Box(Modifier.align(Alignment.CenterEnd).padding(end = 8.dp).size(Theme.target)
                .clickable(role = Role.Button, onClick = onForget).semantics { contentDescription = "Forget ${saved.name}" },
                contentAlignment = Alignment.Center) {
                Box(Modifier.size(26.dp).background(Theme.red, CircleShape), contentAlignment = Alignment.Center) {
                    Box(Modifier.size(11.dp, 2.5.dp).background(Theme.background, RoundedCornerShape(50)))
                }
            }
        }
    }
}

/** A line drawing of a camera (body, hump, lens, viewfinder) for the large card. */
@Composable
private fun CameraLineArt(modifier: Modifier) {
    Canvas(modifier.clearAndSetSemantics {}) {
        val w = size.width
        val h = size.height
        val ink = Theme.text.copy(alpha = 0.9f)
        val line = Stroke(2.dp.toPx(), cap = StrokeCap.Round, join = StrokeJoin.Round)
        val inset = 2.dp.toPx()
        drawRoundRect(ink, Offset(inset, h * 0.28f), Size(w - 2 * inset, h * 0.68f), CornerRadius(12.dp.toPx()), style = line)
        drawPath(Path().apply {
            moveTo(w * 0.12f, h * 0.28f); lineTo(w * 0.12f, h * 0.14f); lineTo(w * 0.34f, h * 0.14f); lineTo(w * 0.34f, h * 0.28f)
        }, ink, style = line)
        val c = Offset(w * 0.56f, h * 0.62f)
        drawCircle(ink, 26.dp.toPx(), c, style = line)
        drawCircle(Theme.accent, 10.dp.toPx(), c)
        drawCircle(Theme.text.copy(alpha = 0.6f), 3.5.dp.toPx(), Offset(w * 0.82f + 3.5.dp.toPx(), h * 0.4f + 3.5.dp.toPx()))
    }
}

/** First run and the home screen: the design's background (the dusk picture; blurred once there are cameras). */
@Composable
private fun ConnectBackground(firstRun: Boolean) {
    Crossfade(firstRun, label = "background") { first ->
        if (first) {
            // 102: the picture itself across the top, fading to black.
            Box(Modifier.fillMaxSize().background(Theme.background)) {
                DuskScene(Modifier.fillMaxWidth().height(560.dp))
                Box(Modifier.fillMaxSize().background(Brush.verticalGradient(
                    0f to Wash.copy(alpha = 0.3f), 0.3f to Wash.copy(alpha = 0.35f), 0.62f to Theme.background)))
            }
        } else {
            DuskBackdrop()
        }
    }
}

// MARK: - Scan to connect

/** Home screen: scan the QR code on the camera's screen; Shutterlink joins its Wi-Fi, connects and saves it. */
@Composable
private fun ScanToConnect(camera: CameraModel, busy: Boolean, note: String?, onClick: () -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        ScanCard(
            title = if (busy) camera.status ?: "Connecting…" else "Scan the camera's QR code",
            detail = "Joins its Wi-Fi and connects. No trip to Settings.",
            enabled = camera.phase == ConnectionPhase.DISCONNECTED, busy = busy, home = true, onClick = onClick,
        )
        note?.let { Text(it, color = Theme.secondary, fontSize = 13.sp) }
    }
}

/** The accent card (102, 103, 105): the QR glyph, the action, what it does. */
@Composable
private fun ScanCard(title: String, detail: String, enabled: Boolean, busy: Boolean, home: Boolean, onClick: () -> Unit) {
    val shape = RoundedCornerShape(20.dp)
    Row(
        Modifier.fillMaxWidth().heightIn(min = if (home) 84.dp else 76.dp).clip(shape).background(Theme.accent, shape)
            .clickable(enabled = enabled, role = Role.Button, onClickLabel = "Scan", onClick = onClick)
            .alpha(if (enabled || busy) 1f else 0.5f)
            .padding(horizontal = if (home) 16.dp else 18.dp, vertical = if (home) 16.dp else 12.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Box(Modifier.size(if (home) 40.dp else 26.dp, if (home) 50.dp else 26.dp), contentAlignment = Alignment.Center) {
            if (busy) CircularProgressIndicator(color = Theme.onAccent, strokeWidth = 2.dp, modifier = Modifier.size(22.dp))
            else QrGlyph(Modifier.size(if (home) 24.dp else 26.dp))
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(if (home) 3.dp else 2.dp)) {
            Text(title, color = Theme.onAccent, fontSize = 17.sp, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text(detail, color = if (home) Theme.onAccent.copy(alpha = 0.75f) else Theme.onAccent, fontSize = 13.sp, lineHeight = 17.sp)
        }
    }
}

/** The design's QR code glyph, in outline. */
@Composable
private fun QrGlyph(modifier: Modifier) {
    Canvas(modifier.clearAndSetSemantics {}) {
        val k = size.minDimension / 24f
        scale(k, k, pivot = Offset.Zero) {
            val line = Stroke(2f)
            drawRect(Theme.onAccent, Offset(3f, 3f), Size(7f, 7f), style = line)
            drawRect(Theme.onAccent, Offset(14f, 3f), Size(7f, 7f), style = line)
            drawRect(Theme.onAccent, Offset(3f, 14f), Size(7f, 7f), style = line)
            drawRect(Theme.onAccent, Offset(14f, 14f), Size(3f, 3f), style = line)
            drawLine(Theme.onAccent, Offset(20f, 14f), Offset(20f, 21f), strokeWidth = 2f)
            drawLine(Theme.onAccent, Offset(14f, 20f), Offset(17f, 20f), strokeWidth = 2f)
        }
    }
}

// MARK: - Connecting (104)

/** Which of the three steps a status line is on: the camera's Wi-Fi, finding it, reading it. */
private fun connectingStage(status: String): Int = when {
    status.startsWith("Waiting for the camera's Wi-Fi") -> 0
    status.startsWith("Joining") || status.startsWith("Looking") || status.startsWith("Finding") ||
        status.startsWith("Holding") || status.contains("retrying") || status.startsWith("Connecting") -> 1
    else -> 2
}

/**
 * While connecting: the camera drawn in line with signal arcs, its name large, the current status in
 * the accent, and three steps that tick off as the app's own status lines move on.
 */
@Composable
private fun ConnectingView(camera: CameraModel, name: String, ssid: String?) {
    val status = camera.status ?: "Looking for the camera…"
    val stage = connectingStage(status)
    Column(Modifier.fillMaxWidth()) {
        FinderLockup(40.dp, Modifier.padding(top = 20.dp))
        ConnectingArt(Modifier.padding(top = 10.dp).fillMaxWidth().height(300.dp))
        AutoFitText(name, Theme.num(44.sp), Theme.text, Modifier.fillMaxWidth(), TextAlign.Start)
        Text(status, color = Theme.accent, fontSize = 17.sp,
            modifier = Modifier.padding(top = 6.dp).semantics { liveRegion = LiveRegionMode.Polite })
        Column(Modifier.padding(top = 18.dp).fillMaxWidth()) {
            Box(Modifier.fillMaxWidth().height(1.dp).background(Theme.stroke))
            ConnectingStep(1, "Waiting for the camera's Wi-Fi…", stage)
            ConnectingStep(2, if (stage == 1) status else ssid?.let { "Joining $it…" } ?: "Looking for the camera…", stage)
            ConnectingStep(3, if (stage == 2) status else "Reading camera info…", stage)
        }
    }
}

@Composable
private fun ConnectingStep(number: Int, title: String, stage: Int) {
    val done = number - 1 < stage
    val now = number - 1 == stage
    Row(
        Modifier.fillMaxWidth().hairRow().padding(vertical = 12.dp)
            .semantics(mergeDescendants = true) { stateDescription = if (done) "Done" else if (now) "In progress" else "Not yet" },
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Box(
            Modifier.size(30.dp).then(when {
                done -> Modifier.background(Theme.green, CircleShape)
                now -> Modifier.background(Theme.accent, CircleShape)
                else -> Modifier.border(1.5.dp, Theme.tertiary, CircleShape)
            }),
            contentAlignment = Alignment.Center,
        ) {
            if (done) Icon(Icons.Filled.Check, null, tint = Theme.background, modifier = Modifier.size(16.dp))
            else Text("$number", style = Theme.num(18.sp), color = if (now) Theme.background else Theme.secondary)
        }
        Text(title, color = Theme.text, fontSize = 16.sp, fontWeight = FontWeight.Medium, maxLines = 2, overflow = TextOverflow.Ellipsis,
            modifier = Modifier.weight(1f))
    }
}

/** The camera in line (104), with two arcs under it that pulse outward while connecting. */
@Composable
private fun ConnectingArt(modifier: Modifier) {
    val animating = !rememberReduceMotion()
    val phase: State<Float> = if (animating) {
        rememberInfiniteTransition(label = "signal")
            .animateFloat(0f, 1f, infiniteRepeatable(tween(1600, easing = LinearEasing)), label = "phase")
    } else remember { mutableFloatStateOf(0.5f) }
    Canvas(modifier.clearAndSetSemantics {}) {
        val t = phase.value
        // The design's 390 × 300 drawing, centred.
        val k = min(size.width / 390f, size.height / 300f)
        translate((size.width - 390f * k) / 2, (size.height - 300f * k) / 2) {
            scale(k, k, pivot = Offset.Zero) {
                val line = Stroke(2.5f, cap = StrokeCap.Round, join = StrokeJoin.Round)
                drawRoundRect(Theme.text, Offset(95f, 50f), Size(200f, 120f), CornerRadius(16f), style = line)
                drawPath(Path().apply { moveTo(165f, 50f); lineTo(177f, 28f); lineTo(213f, 28f); lineTo(225f, 50f) }, Theme.text, style = line)
                drawRoundRect(Theme.text, Offset(113f, 38f), Size(28f, 12f), CornerRadius(3f), style = line)
                drawRoundRect(Theme.text, Offset(250f, 36f), Size(26f, 14f), CornerRadius(3f), style = line)
                drawCircle(Theme.text, 46f, Offset(195f, 112f), style = line)
                drawCircle(Theme.text, 31f, Offset(195f, 112f), style = line)
                drawCircle(Theme.accent, 13f, Offset(195f, 112f))
                // Two arcs: the near one, then the far one, brightening in turn.
                for (i in 0..1) {
                    val r = if (i == 0) 50f else 90f
                    val cy = if (i == 0) 233f else 268f
                    val p = (t + i * 0.5f) % 1f
                    val base = if (i == 0) 0.4f else 0.7f
                    val alpha = if (animating) 0.25f + 0.75f * (0.5f + 0.5f * sin(p * 2 * PI.toFloat())) * base / 0.7f else base
                    drawArc(Theme.accent.copy(alpha = alpha.coerceIn(0f, 1f)), startAngle = 30f, sweepAngle = 120f, useCenter = false,
                        topLeft = Offset(195f - r, cy - 2 * r), size = Size(2 * r, 2 * r), style = Stroke(3f, cap = StrokeCap.Round))
                }
            }
        }
    }
}

// MARK: - Footer

/**
 * A connection error (107): a red outline on near-black, the message, "More" for a long one, "Report"
 * to send a problem report, × to clear it.
 */
@Composable
private fun ConnectErrorBanner(text: String, onReport: () -> Unit, onDismiss: () -> Unit) {
    // Long explanations open on request, so the banner doesn't cover the form.
    val long = text.length > 140
    var expanded by remember(text) { mutableStateOf(false) }
    val shape = RoundedCornerShape(14.dp)
    Row(
        Modifier.fillMaxWidth().clip(shape).background(Theme.background.copy(alpha = 0.86f), shape).border(1.dp, Theme.red, shape)
            .padding(start = 14.dp, end = 2.dp).animateContentSize(),
        verticalAlignment = Alignment.Top,
    ) {
        Text(text, color = Theme.text, fontSize = 13.sp, lineHeight = 18.sp,
            maxLines = if (expanded || !long) Int.MAX_VALUE else 3, overflow = TextOverflow.Ellipsis,
            modifier = Modifier.weight(1f).padding(vertical = 12.dp))
        if (long) BannerButton(if (expanded) "Less" else "More", Theme.text, if (expanded) "Show less" else "Show the whole message") { expanded = !expanded }
        BannerButton("Report", Theme.accent, "Report a problem", onReport)
        Box(Modifier.size(Theme.target).clickable(role = Role.Button, onClick = onDismiss), contentAlignment = Alignment.Center) {
            Icon(Icons.Filled.Close, "Dismiss", tint = Theme.secondary, modifier = Modifier.size(14.dp))
        }
    }
}

@Composable
private fun BannerButton(title: String, color: Color, label: String, onClick: () -> Unit) {
    Box(Modifier.heightIn(min = Theme.target).clickable(role = Role.Button, onClickLabel = label, onClick = onClick).padding(horizontal = 6.dp),
        contentAlignment = Alignment.Center) {
        Text(title, color = color, fontSize = 13.sp, fontWeight = FontWeight.SemiBold, maxLines = 1)
    }
}

/**
 * This phone's Wi-Fi address (and name, with location permission). It can't prove the phone is on the
 * camera's network: many home routers also use 192.168.0.x, so the network name tells for sure.
 */
@Composable
private fun WifiStatusRow(camera: CameraModel) {
    val context = LocalContext.current
    var address by remember { mutableStateOf(CameraNetwork.wifiAddress()) }
    var ssid by remember { mutableStateOf(CameraNetwork.wifiSsid()) }
    var tick by remember { mutableStateOf(0) }
    val locationGranted = ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED
    val askLocation = rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { tick++ }
    LaunchedEffect(tick) {
        while (true) {
            address = CameraNetwork.wifiAddress()
            ssid = CameraNetwork.wifiSsid()
            delay(2000)
        }
    }
    val host = camera.host
    val (icon, color, text) = run {
        val a = address ?: return@run Triple(Icons.Filled.WifiOff, Theme.orange, "This phone isn't on Wi-Fi")
        val octets = host.substringBefore(':').split(".")
        val name = ssid?.let { "\"$it\" " } ?: ""
        if (octets.size == 4 && octets[0] != "127" && octets[0] != "10" && !a.startsWith(octets.take(3).joinToString(".") + ".")) {
            Triple(Icons.Filled.Warning, Theme.orange, "On another Wi-Fi network $name($a). Join the camera's network first.")
        } else {
            val hint = BrandDetector.hint(a)?.let { " Looks like a $it network." } ?: ""
            Triple(Icons.Filled.Wifi, Theme.secondary, "Wi-Fi $name($a).$hint")
        }
    }
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            Icon(icon, null, Modifier.size(16.dp), tint = color)
            Text(text, color = color, fontSize = 13.sp, maxLines = 2)
        }
        if (address != null && ssid == null && !locationGranted) {
            Text("Show the network's name (needs location permission)", color = Theme.accent, fontSize = 13.sp,
                modifier = Modifier.heightIn(min = Theme.target).clickable(role = Role.Button) {
                    askLocation.launch(arrayOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION))
                }.padding(vertical = 13.dp))
        }
    }
}

// MARK: - Add a camera (105)

/** Setup steps for a brand; null = auto-detect. */
fun steps(brand: CameraBrand?): List<Pair<String, String>> = when (brand) {
    null -> listOf(
        "Start the camera's Wi-Fi" to "Open its smartphone or Wi-Fi connection menu. Pick your brand above for the exact steps.",
        "Join that network" to "Settings ▸ Wi-Fi ▸ the camera's network, with the password the camera shows, or type both below and Shutterlink joins it. If Android says the network has no internet, stay connected.",
        "Connect" to "The app works out which camera it is from the network and by asking it.",
    )
    CameraBrand.OLYMPUS -> listOf(
        "Start Wi-Fi on the camera" to "Open Connection to Smartphone (OM System: Wi-Fi/Bluetooth ▸ Connection to Smartphone) and wait for the screen with the SSID, password and QR code.",
        "Join that network" to "Settings ▸ Wi-Fi ▸ the camera's network (E-M10-P-…, PEN-F-P-…, OM-1-P-…) with the password from the camera. If Android says it has no internet, choose to stay connected.",
        "Connect" to "Live view comes in over the same Wi-Fi.",
    )
    CameraBrand.PANASONIC -> listOf(
        "Start Wi-Fi on the camera" to "MENU ▸ Setup ▸ Wi-Fi ▸ Wi-Fi Function ▸ New Connection ▸ Remote Shooting & View. The camera shows its network name.",
        "Join that network" to "Settings ▸ Wi-Fi ▸ the camera's network (e.g. GH5-…). Enter the password if the camera shows one. Stay connected if Android says there's no internet.",
        "Connect, then approve on the camera" to "The first time, the camera asks whether to connect to this phone: choose Yes.",
    )
    CameraBrand.NIKON -> listOf(
        "Start Wi-Fi on the camera" to "Z bodies: MENU ▸ Network ▸ Connect to smart device ▸ Wi-Fi connection ▸ Establish Wi-Fi connection. Older DSLRs with built-in Wi-Fi: turn Wi-Fi on in the Setup menu.",
        "Join that network" to "Settings ▸ Wi-Fi ▸ the camera's network, with the password the camera shows.",
        "Connect" to "If the camera asks to allow the connection, choose OK.",
    )
    CameraBrand.CANON -> listOf(
        "Unlock CCAPI once" to "Canon locks third-party control until the camera is activated with Canon's free CCAPI tool (developer account, one time per camera). Without it the app can't connect.",
        "Start Wi-Fi on the camera" to "MENU ▸ Wireless ▸ Wi-Fi ▸ the CCAPI connection, as camera access point. Join the camera's network in Settings ▸ Wi-Fi.",
        "Connect" to "If Automatic doesn't find it, type the camera's \"CCAPI top URL\" under Advanced.",
    )
    CameraBrand.SONY -> listOf(
        "Start Smart Remote on the camera" to "Older Alpha / RX bodies: MENU ▸ Application ▸ Smart Remote Control (or Ctrl w/ Smartphone). Bodies from 2020 on (a7 IV, ZV-E10…) don't offer this to other apps.",
        "Join that network" to "Settings ▸ Wi-Fi ▸ DIRECT-xxxx:ILCE-…, with the password the camera shows.",
        "Connect" to "Live view and the card come over the same Wi-Fi.",
    )
}

/** New camera: pick the brand (or Automatic), follow its steps, connect. Saved the first time it connects. */
@Composable
private fun AddCameraScreen(camera: CameraModel, onClose: () -> Unit) {
    val selection: CameraBrand? = if (camera.autoDetectBrand) null else camera.brand
    val connecting = camera.phase == ConnectionPhase.CONNECTING
    val disconnected = camera.phase == ConnectionPhase.DISCONNECTED
    var showAdvanced by remember { mutableStateOf(false) }
    var scanNote by remember { mutableStateOf<String?>(null) }
    var showReport by remember { mutableStateOf(false) }
    val withWifiPermission = rememberWifiJoinPermission(camera)
    val scan = rememberQrScanner(onCode = { code ->
        if (camera.applyScannedCode(code)) {
            scanNote = null
            withWifiPermission { camera.scope.launch { camera.joinAndConnect() } }
        } else {
            scanNote = UNREADABLE_CODE
        }
    }, onError = { scanNote = it })
    val joinsWifi = camera.wifiSsid.isNotBlank()
    val close = {
        camera.lastError = null   // a failed try here shouldn't follow the user home
        onClose()
    }
    BackHandler(enabled = !connecting) { close() }

    Column(Modifier.fillMaxSize().background(Theme.background).safeDrawingPadding().imePadding()) {
        // 105: Cancel on the left, the title centred.
        ScreenHeader("Add a camera", Modifier.padding(top = 4.dp), centred = true, titleSize = 18.sp,
            leading = { HeaderButton("Cancel", enabled = !connecting, onClick = close) })
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()), horizontalAlignment = Alignment.CenterHorizontally) {
            Column(Modifier.widthIn(max = 560.dp).fillMaxWidth().padding(horizontal = 20.dp, vertical = 12.dp),
                verticalArrangement = Arrangement.spacedBy(24.dp)) {
                scan?.let { open ->
                    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        ScanCard(
                            title = "Scan the camera's QR code",
                            detail = "Start the camera's smartphone connection so it shows a QR code. Shutterlink joins its Wi-Fi and connects.",
                            enabled = disconnected, busy = false, home = false, onClick = { scanNote = null; open() },
                        )
                        scanNote?.let { Text(it, color = Theme.secondary, fontSize = 13.sp) }
                    }
                }
                BrandList(selection, enabled = disconnected) { camera.selectBrand(it) }
                Column(Modifier.padding(vertical = 8.dp).animateContentSize()) {
                    CapsLabel("How to connect", modifier = Modifier.padding(bottom = 8.dp))
                    steps(selection).forEachIndexed { index, (title, detail) -> StepRow(index + 1, title, detail) }
                    selection?.supportNote?.let { note ->
                        Row(Modifier.padding(top = 12.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            Icon(Icons.Filled.Science, null, Modifier.size(16.dp), tint = Theme.secondary)
                            Text(note, color = Theme.secondary, fontSize = 13.sp, lineHeight = 18.sp)
                        }
                    }
                }
                WifiCard(camera, typeLabel = if (scan != null) "Or type the camera's Wi-Fi" else "The camera's Wi-Fi")
                Column {
                    Row(Modifier.fillMaxWidth().heightIn(min = Theme.target)
                        .clickable(role = Role.Button, onClickLabel = if (showAdvanced) "Collapse" else "Expand") { showAdvanced = !showAdvanced }
                        .padding(horizontal = 6.dp)
                        .semantics { stateDescription = if (showAdvanced) "Expanded" else "Collapsed" },
                        verticalAlignment = Alignment.CenterVertically) {
                        CapsLabel("Advanced")
                        Spacer(Modifier.weight(1f))
                        Icon(Icons.Filled.KeyboardArrowDown, null, tint = Theme.secondary,
                            modifier = Modifier.rotate(if (showAdvanced) 0f else -90f))
                    }
                    AnimatedVisibility(showAdvanced) {
                        Box(Modifier.padding(top = 24.dp)) { AdvancedCard(camera) }
                    }
                }
            }
        }
        // The connect bar: problems and the Wi-Fi state stay in view above the button.
        Column(Modifier.fillMaxWidth().background(Theme.background), horizontalAlignment = Alignment.CenterHorizontally) {
            Column(Modifier.widthIn(max = 600.dp).fillMaxWidth().padding(horizontal = 20.dp).padding(top = 12.dp, bottom = 8.dp)
                .animateContentSize(), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                camera.lastError?.let { error ->
                    ConnectErrorBanner(error, onReport = { showReport = true }, onDismiss = { camera.lastError = null })
                }
                WifiStatusRow(camera)
                AccentButton(onClick = {
                    // The camera's scope, not this screen's (which closes as soon as it's connected).
                    if (joinsWifi) withWifiPermission { camera.scope.launch { camera.joinAndConnect() } }
                    else camera.scope.launch { camera.connect() }
                }, modifier = Modifier.fillMaxWidth(), enabled = !connecting) {
                    if (connecting) CircularProgressIndicator(color = Theme.onAccent, strokeWidth = 2.dp, modifier = Modifier.size(18.dp))
                    Text(if (connecting) camera.status ?: "Connecting…" else if (joinsWifi) "Join Wi-Fi and Connect" else "Connect",
                        maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
            }
        }
    }

    if (showReport) ReportProblemPage(camera = camera, onDismiss = { showReport = false })
}

/** The brands as radio rows (105): the ring on the left, an outlined badge after the name. */
@Composable
private fun BrandList(selection: CameraBrand?, enabled: Boolean, onSelect: (CameraBrand?) -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        CapsLabel("Camera")
        Column(Modifier.fillMaxWidth().alpha(if (enabled) 1f else 0.5f)) {
            Box(Modifier.fillMaxWidth().height(1.dp).background(Theme.stroke))
            BrandRow(null, selection == null, enabled) { onSelect(null) }
            CameraBrand.entries.forEach { brand ->
                Box(Modifier.fillMaxWidth().height(1.dp).background(Theme.stroke))
                BrandRow(brand, selection == brand, enabled) { onSelect(brand) }
            }
        }
    }
}

@Composable
private fun BrandRow(brand: CameraBrand?, on: Boolean, enabled: Boolean, onClick: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().heightIn(min = 60.dp)
            .selectable(selected = on, enabled = enabled, role = Role.RadioButton, onClick = onClick)
            .padding(vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Box(Modifier.size(22.dp).border(2.dp, if (on) Theme.accent else Theme.tertiary, CircleShape), contentAlignment = Alignment.Center) {
            if (on) Box(Modifier.size(10.dp).background(Theme.accent, CircleShape))
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                Text(brand?.title ?: "Automatic", color = Theme.text, fontSize = 16.sp, fontWeight = FontWeight.Medium)
                if (brand == null) OutlineBadge("Recommended", Theme.green)
                else if (brand.isBeta) OutlineBadge("Beta", Theme.accent)
            }
            Text(brand?.coverage ?: "Works out which camera it is from its Wi-Fi", color = Theme.secondary, fontSize = 13.sp, lineHeight = 17.sp)
        }
    }
}

@Composable
private fun OutlineBadge(text: String, color: Color) {
    Text(text, color = color, maxLines = 1,
        style = TextStyle(fontSize = 11.sp, fontWeight = FontWeight.Medium, letterSpacing = 0.07.em),
        modifier = Modifier.border(1.dp, color, Pill).padding(horizontal = 7.dp, vertical = 1.dp))
}

/** A numbered step (105): the first in an accent disc, the rest in an outlined ring, over a hairline. */
@Composable
private fun StepRow(number: Int, title: String, detail: String) {
    // One TalkBack stop per step; "▸" reads as "then".
    Row(
        Modifier.fillMaxWidth().hairRow().padding(vertical = 12.dp)
            .clearAndSetSemantics { contentDescription = "Step $number: $title. ${detail.replace(" ▸ ", ", then ")}" },
        horizontalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Box(
            Modifier.size(30.dp).then(if (number == 1) Modifier.background(Theme.accent, CircleShape)
            else Modifier.border(1.5.dp, Theme.tertiary, CircleShape)),
            contentAlignment = Alignment.Center,
        ) {
            Text("$number", style = Theme.num(18.sp), color = if (number == 1) Theme.onAccent else Theme.secondary)
        }
        Column(Modifier.weight(1f).padding(top = 4.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(title, color = Theme.text, fontSize = 16.sp, fontWeight = FontWeight.Medium)
            Text(detail, color = Theme.secondary, fontSize = 13.sp, lineHeight = 18.sp)
        }
    }
}

private const val UNREADABLE_CODE =
    "Shutterlink can't read this camera's code yet. Type the network name and password shown next to the code instead."

/**
 * Runs an action that joins a camera's Wi-Fi, asking first for the permission Android wants for that
 * (Nearby Wi-Fi devices on Android 13+, location before). Without it, the error says what to do instead.
 */
@Composable
fun rememberWifiJoinPermission(camera: CameraModel): ((() -> Unit) -> Unit) {
    val context = LocalContext.current
    val permission = if (Build.VERSION.SDK_INT >= 33) Manifest.permission.NEARBY_WIFI_DEVICES else Manifest.permission.ACCESS_FINE_LOCATION
    var pending by remember { mutableStateOf<(() -> Unit)?>(null) }
    val ask = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        val action = pending
        pending = null
        if (granted) action?.invoke()
        else camera.lastError = "Android needs the ${if (Build.VERSION.SDK_INT >= 33) "Nearby devices" else "location"} permission for Shutterlink to join the camera's Wi-Fi. You can still join it in Settings ▸ Wi-Fi, then connect."
    }
    return { action ->
        if (ContextCompat.checkSelfPermission(context, permission) == PackageManager.PERMISSION_GRANTED) action()
        else {
            pending = action
            ask.launch(permission)
        }
    }
}

/**
 * Shutterlink joins the camera's network itself (WifiNetworkSpecifier: Android asks the user to
 * confirm, and the phone stays on it while Shutterlink holds it), from its QR code or its name and
 * password, and remembers it so the camera's card does everything next time.
 */
@Composable
private fun WifiCard(camera: CameraModel, typeLabel: String) {
    val enabled = camera.phase == ConnectionPhase.DISCONNECTED
    Column(Modifier.fillMaxWidth().surface(RoundedCornerShape(20.dp)).padding(18.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        CapsLabel(typeLabel, color = Theme.accent)
        Text("The network name and password shown on the camera. Shutterlink joins it for you (Android asks you to confirm), and next time tapping the camera joins and connects in one go. Leave it empty if the phone is already on the camera's Wi-Fi.",
            color = Theme.secondary, fontSize = 13.sp, lineHeight = 18.sp)
        Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(Theme.surfaceRaised).alpha(if (enabled) 1f else 0.6f)) {
            PlainField(camera.wifiSsid, { camera.wifiSsid = it }, "Network name", "Camera network name", enabled,
                Modifier.fillMaxWidth().padding(horizontal = 14.dp))
            Box(Modifier.padding(start = 14.dp).fillMaxWidth().height(1.dp).background(Theme.stroke))
            // Shown in clear: it's printed on the camera's screen anyway, and easy to mistype.
            PlainField(camera.wifiPassword, { camera.wifiPassword = it }, "Password", "Camera network password", enabled,
                Modifier.fillMaxWidth().padding(horizontal = 14.dp))
        }
    }
}

/** A bare one-line text field in monospace (network names and passwords mix l, 1 and I), with a placeholder. */
@Composable
private fun PlainField(value: String, onValueChange: (String) -> Unit, placeholder: String, description: String, enabled: Boolean,
                       modifier: Modifier, keyboardType: KeyboardType = KeyboardType.Ascii, textAlign: TextAlign = TextAlign.Start) {
    val style = TextStyle(fontFamily = FontFamily.Monospace, fontSize = 16.sp, color = Theme.text, textAlign = textAlign)
    BasicTextField(
        value, onValueChange, modifier.semantics { contentDescription = description },
        enabled = enabled, singleLine = true, textStyle = style,
        keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.None, autoCorrectEnabled = false, keyboardType = keyboardType),
        cursorBrush = SolidColor(Theme.accent),
        decorationBox = { field ->
            Box(Modifier.fillMaxWidth().heightIn(min = Theme.target),
                contentAlignment = if (textAlign == TextAlign.End) Alignment.CenterEnd else Alignment.CenterStart) {
                if (value.isEmpty()) Text(placeholder, style = style.copy(color = Theme.tertiary), maxLines = 1, modifier = Modifier.fillMaxWidth())
                field()
            }
        },
    )
}

@Composable
private fun AdvancedCard(camera: CameraModel) {
    val context = LocalContext.current
    val mockHint = " For the mock cameras in the Android emulator, use 10.0.2.2 with the mock's port: 8080 Olympus, 8082 LUMIX, 15740 Nikon, 8084 Canon, 8086 Sony."
    Column(Modifier.fillMaxWidth().surface(RoundedCornerShape(24.dp)).padding(20.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Text("Camera address", color = Theme.text, fontSize = 16.sp)
            PlainField(camera.host, { camera.host = it.trim(); camera.saveSettings() },
                placeholder = if (camera.autoDetectBrand) "Automatic" else camera.brand.defaultHost, description = "Camera address",
                enabled = camera.phase == ConnectionPhase.DISCONNECTED, modifier = Modifier.weight(1f),
                keyboardType = KeyboardType.Uri, textAlign = TextAlign.End)
        }
        if (camera.brand == CameraBrand.OLYMPUS && !camera.autoDetectBrand) {
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text("User-Agent", color = Theme.secondary, fontSize = 15.sp)
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    CameraModel.userAgents.forEach { ua ->
                        ChipButton(ua, selected = camera.userAgent == ua) { camera.userAgent = ua; camera.saveSettings() }
                    }
                }
            }
        }
        if (!camera.autoDetectBrand && camera.brand.defaultLiveViewSizes.isNotEmpty()) {
            var open by remember { mutableStateOf(false) }
            Box {
                Row(Modifier.fillMaxWidth().heightIn(min = Theme.target).clickable(role = Role.Button) { open = true },
                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("Live view size", color = Theme.secondary, fontSize = 15.sp, modifier = Modifier.weight(1f))
                    Text(CameraModel.liveViewLabel(camera.liveViewQuality), color = Theme.text, fontSize = 15.sp)
                    Icon(Icons.Filled.KeyboardArrowDown, null, tint = Theme.tertiary, modifier = Modifier.size(18.dp))
                }
                DropdownMenu(open, { open = false }, containerColor = Theme.surface) {
                    camera.brand.defaultLiveViewSizes.forEach { q ->
                        DropdownMenuItem({ Text(CameraModel.liveViewLabel(q), color = if (q == camera.liveViewQuality) Theme.accent else Theme.text) },
                            { open = false; camera.liveViewQuality = q; camera.saveSettings() })
                    }
                }
            }
        }
        Text(
            if (camera.autoDetectBrand) "Leave the address empty and the app looks for the camera at each brand's usual address.$mockHint"
            else "The ${camera.brand.shortTitle} camera is normally at ${camera.brand.defaultHost}.$mockHint",
            color = Theme.secondary, fontSize = 13.sp, lineHeight = 18.sp,
        )
        SurfaceButton(onClick = { context.startActivity(Intent(Settings.ACTION_WIFI_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) }) {
            Icon(Icons.Filled.Settings, null, Modifier.size(18.dp))
            Text("Open Wi-Fi settings")
        }
    }
}
