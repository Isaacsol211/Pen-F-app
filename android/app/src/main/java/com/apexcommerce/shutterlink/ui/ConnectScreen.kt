package com.apexcommerce.shutterlink.ui

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.provider.Settings
import android.text.format.DateUtils
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
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
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.PhotoCamera
import androidx.compose.material.icons.filled.QrCodeScanner
import androidx.compose.material.icons.filled.RadioButtonUnchecked
import androidx.compose.material.icons.filled.Science
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material.icons.filled.Wifi
import androidx.compose.material.icons.filled.WifiOff
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
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

/**
 * The home screen while not connected (port of ConnectView.swift): the cameras this phone knows as
 * cards (one tap to reconnect) and "Add a camera" for a new one. First run shows an empty state.
 */
@Composable
fun ConnectScreen(camera: CameraModel) {
    var showAdd by remember { mutableStateOf(false) }
    var connectingId by remember { mutableStateOf<String?>(null) }
    var forgetting by remember { mutableStateOf<SavedCamera?>(null) }
    var scanNote by remember { mutableStateOf<String?>(null) }
    val empty = camera.savedCameras.isEmpty()
    LaunchedEffect(camera.phase) { if (camera.phase != ConnectionPhase.CONNECTING) connectingId = null }
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

    Box(Modifier.fillMaxSize().background(Theme.background)) {
        ConnectBackground()
        Column(Modifier.fillMaxSize().safeDrawingPadding()) {
            BoxWithConstraints(Modifier.weight(1f)) {
                val compact = maxHeight < 600.dp
                Column(
                    Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 20.dp).padding(bottom = 24.dp),
                    verticalArrangement = Arrangement.spacedBy(24.dp),
                ) {
                    if (empty) {
                        Column(Modifier.padding(top = if (compact) 16.dp else 32.dp), verticalArrangement = Arrangement.spacedBy(if (compact) 10.dp else 16.dp)) {
                            BrandLockup(if (compact) 38.dp else 48.dp)
                            Text("Shoot from\nyour phone.", fontSize = if (compact) 30.sp else 38.sp, fontWeight = FontWeight.Black, lineHeight = if (compact) 34.sp else 42.sp)
                            Text("Remote control for Olympus, OM System and Panasonic LUMIX cameras over their own Wi-Fi, with Nikon, Canon and Sony in beta.",
                                color = Theme.secondary, fontSize = 15.sp)
                        }
                    } else Box(Modifier.padding(top = 20.dp)) { BrandLockup(40.dp) }
                    scan?.let { ScanToConnectCard(camera, busy = connectingId == null, note = scanNote) { scanNote = null; it() } }
                    Column(verticalArrangement = Arrangement.spacedBy(if (empty) 14.dp else 12.dp)) {
                        CapsLabel("Your cameras")
                        if (empty) {
                            Column(Modifier.fillMaxWidth().dashedBorder(22.dp).padding(vertical = 28.dp, horizontal = 20.dp),
                                horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(14.dp)) {
                                Icon(Icons.Filled.PhotoCamera, null, Modifier.size(34.dp), tint = Theme.accent)
                                Text("No cameras yet", fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
                                Text("Add your camera once. After that it waits here: turn on its Wi-Fi and tap it.",
                                    color = Theme.secondary, fontSize = 15.sp, textAlign = TextAlign.Center)
                            }
                        } else {
                            Text("Turn on the camera's Wi-Fi and tap it. A camera saved with its Wi-Fi joins it by itself; for others, join it in Settings ▸ Wi-Fi first.",
                                color = Theme.secondary, fontSize = 15.sp, modifier = Modifier.padding(bottom = 4.dp))
                            camera.savedCameras.forEach { saved ->
                                SavedCameraCard(camera, saved, connecting = camera.phase == ConnectionPhase.CONNECTING && connectingId == saved.id,
                                    onTap = {
                                        connectingId = saved.id
                                        // In the camera's own scope: this screen goes away once it's connected,
                                        // and its scope with it, which would cancel the end of the connection.
                                        // A camera saved with its network joins it first, which needs Android's permission.
                                        if (saved.ssid != null) withWifiPermission { camera.scope.launch { camera.connect(saved) } }
                                        else camera.scope.launch { camera.connect(saved) }
                                    },
                                    onLongPress = { forgetting = saved })
                            }
                            Row(Modifier.fillMaxWidth().heightIn(min = 60.dp).dashedBorder(20.dp)
                                .clickable(enabled = camera.phase == ConnectionPhase.DISCONNECTED) { showAdd = true },
                                horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically) {
                                Icon(Icons.Filled.Add, null, tint = Theme.accent)
                                Text("Add a camera", color = Theme.accent, fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
                            }
                        }
                    }
                    if (!empty) Text("Long-press a camera to forget it.", color = Theme.tertiary, fontSize = 13.sp)
                }
            }
            Column(Modifier.fillMaxWidth().background(Theme.background).padding(horizontal = 20.dp).padding(top = 12.dp, bottom = 8.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp)) {
                camera.lastError?.let { ConnectErrorBanner(it) }
                WifiStatusRow(camera)
                if (empty) {
                    AccentButton(onClick = { showAdd = true }, modifier = Modifier.fillMaxWidth()) {
                        Icon(Icons.Filled.Add, null)
                        Text("Add your camera")
                    }
                }
            }
        }
    }

    forgetting?.let { saved ->
        ConfirmDialog("Forget ${saved.name}?", "Forget", { forgetting = null },
            text = { Text("It disappears from this list. You can add it again any time.") }) { camera.forget(saved) }
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun SavedCameraCard(camera: CameraModel, saved: SavedCamera, connecting: Boolean, onTap: () -> Unit, onLongPress: () -> Unit) {
    val lastUsed = DateUtils.getRelativeTimeSpanString(saved.lastUsed, System.currentTimeMillis(), DateUtils.MINUTE_IN_MILLIS).toString()
    val shape = RoundedCornerShape(20.dp)
    Row(
        Modifier.fillMaxWidth().heightIn(min = 84.dp)
            .background(if (connecting) Theme.surfaceRaised else Theme.surface, shape)
            .border(1.dp, if (connecting) Theme.accent.copy(alpha = 0.6f) else Theme.stroke, shape)
            .combinedClickable(enabled = camera.phase == ConnectionPhase.DISCONNECTED, onClick = onTap, onLongClick = onLongPress)
            .padding(16.dp)
            .semantics { contentDescription = "${saved.name}, ${saved.brand.title}, last used $lastUsed" },
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Box(Modifier.size(50.dp).background(Theme.accent, RoundedCornerShape(13.dp)), contentAlignment = Alignment.Center) {
            Icon(Icons.Filled.PhotoCamera, null, tint = Theme.onAccent)
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(5.dp)) {
            Text(saved.name, fontSize = 20.sp, fontWeight = FontWeight.Black, maxLines = 1)
            if (connecting) {
                Text(camera.status ?: "Connecting…", color = Theme.accent, fontSize = 13.sp, maxLines = 1)
            } else {
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                    CapsLabel(saved.brand.shortTitle)
                    if (saved.brand.isBeta) BetaBadge()
                    Text("· $lastUsed", color = Theme.tertiary, fontSize = 13.sp, maxLines = 1)
                }
            }
        }
        if (connecting) CircularProgressIndicator(color = Theme.accent, strokeWidth = 2.dp, modifier = Modifier.size(20.dp))
        else Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, null, tint = Theme.tertiary)
    }
}

/** Pure black with a large, faint amber aperture breaking out of the top-right corner. */
@Composable
private fun ConnectBackground() {
    Canvas(Modifier.fillMaxSize()) {
        val side = maxOf(size.width, size.height) * 0.8f
        // Centred at (width − 8 % of the mark, 18 % of the mark), like the iOS cover.
        translate(size.width - side * 0.58f, -side * 0.32f) {
            drawAperture(Theme.accent.copy(alpha = 0.16f), Size(side, side))
        }
    }
}

private fun Modifier.dashedBorder(radius: Dp): Modifier = this.drawBehind {
    drawRoundRect(Theme.stroke, cornerRadius = CornerRadius(radius.toPx()),
        style = Stroke(1.5.dp.toPx(), pathEffect = PathEffect.dashPathEffect(floatArrayOf(6.dp.toPx(), 5.dp.toPx()))))
}

@Composable
private fun ConnectErrorBanner(text: String) {
    Row(Modifier.fillMaxWidth().background(Theme.red.copy(alpha = 0.18f), RoundedCornerShape(16.dp))
        .border(1.dp, Theme.red.copy(alpha = 0.5f), RoundedCornerShape(16.dp)).padding(14.dp),
        horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        Icon(Icons.Filled.WifiOff, null, tint = Theme.red, modifier = Modifier.size(20.dp))
        Text(text, fontSize = 15.sp)
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
                modifier = Modifier.clickable {
                    askLocation.launch(arrayOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION))
                }.padding(vertical = 6.dp))
        }
    }
}

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
    var showAdvanced by remember { mutableStateOf(false) }
    var scanNote by remember { mutableStateOf<String?>(null) }
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
    androidx.activity.compose.BackHandler(enabled = !connecting) { onClose() }

    Column(Modifier.fillMaxSize().background(Theme.background).safeDrawingPadding().imePadding()) {
        Row(Modifier.fillMaxWidth().padding(horizontal = 10.dp, vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
            TextButton(onClick = onClose, enabled = !connecting) { Text("Cancel", color = Theme.accent) }
            Text("Add a camera", fontSize = 17.sp, fontWeight = FontWeight.SemiBold, textAlign = TextAlign.Center, modifier = Modifier.weight(1f))
            Spacer(Modifier.size(72.dp, 1.dp))
        }
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = 20.dp, vertical = 12.dp).widthIn(max = 560.dp),
            verticalArrangement = Arrangement.spacedBy(24.dp)) {
            scan?.let { open ->
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    AccentButton(onClick = { scanNote = null; open() }, modifier = Modifier.fillMaxWidth(), enabled = !connecting) {
                        Icon(Icons.Filled.QrCodeScanner, null)
                        Text("Scan the camera's QR code")
                    }
                    Text("Start the camera's smartphone connection so it shows a QR code. Shutterlink joins its Wi-Fi and connects.",
                        color = Theme.secondary, fontSize = 13.sp)
                    scanNote?.let { Text(it, color = Theme.orange, fontSize = 13.sp) }
                }
            }
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                CapsLabel("Camera")
                Column(Modifier.fillMaxWidth().surface(RoundedCornerShape(20.dp))) {
                    BrandRow(null, selection == null, enabled = !connecting) { camera.selectBrand(null) }
                    CameraBrand.entries.forEach { brand ->
                        HorizontalDivider(color = Theme.stroke, modifier = Modifier.padding(start = 16.dp))
                        BrandRow(brand, selection == brand, enabled = !connecting) { camera.selectBrand(brand) }
                    }
                }
            }
            Column(Modifier.fillMaxWidth().surface(RoundedCornerShape(20.dp)).padding(18.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
                CapsLabel("How to connect", color = Theme.accent)
                steps(selection).forEachIndexed { index, (title, detail) -> StepRow(index + 1, title, detail) }
                selection?.supportNote?.let { note ->
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Icon(Icons.Filled.Science, null, Modifier.size(16.dp), tint = Theme.secondary)
                        Text(note, color = Theme.secondary, fontSize = 13.sp)
                    }
                }
            }
            WifiCard(camera, typeLabel = if (scan != null) "Or type the camera's Wi-Fi" else "The camera's Wi-Fi")
            Row(Modifier.fillMaxWidth().heightIn(min = Theme.target).clickable { showAdvanced = !showAdvanced }.padding(horizontal = 6.dp),
                verticalAlignment = Alignment.CenterVertically) {
                CapsLabel("Advanced")
                Spacer(Modifier.weight(1f))
                Icon(Icons.Filled.KeyboardArrowDown, if (showAdvanced) "Collapse" else "Expand", tint = Theme.secondary,
                    modifier = Modifier.rotate(if (showAdvanced) 0f else -90f))
            }
            if (showAdvanced) AdvancedCard(camera)
        }
        Column(Modifier.fillMaxWidth().padding(horizontal = 20.dp).padding(top = 12.dp, bottom = 8.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            camera.lastError?.let { ConnectErrorBanner(it) }
            WifiStatusRow(camera)
            AccentButton(onClick = {
                // The camera's scope, not this screen's (which closes as soon as it's connected).
                if (joinsWifi) withWifiPermission { camera.scope.launch { camera.joinAndConnect() } }
                else camera.scope.launch { camera.connect() }
            }, modifier = Modifier.fillMaxWidth(), enabled = !connecting) {
                if (connecting) CircularProgressIndicator(color = Theme.onAccent, strokeWidth = 2.dp, modifier = Modifier.size(18.dp))
                Text(if (connecting) camera.status ?: "Connecting…" else if (joinsWifi) "Join Wi-Fi and Connect" else "Connect", maxLines = 1)
            }
        }
    }
}

@Composable
private fun BrandRow(brand: CameraBrand?, on: Boolean, enabled: Boolean, onClick: () -> Unit) {
    Row(Modifier.fillMaxWidth().heightIn(min = 60.dp).clickable(enabled = enabled, onClick = onClick).padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                Text(brand?.title ?: "Automatic", fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
                if (brand == null) Text("Recommended", color = Theme.accent, fontSize = 11.sp, fontWeight = FontWeight.Bold)
                if (brand?.isBeta == true) BetaBadge()
            }
            Text(brand?.coverage ?: "Works out which camera it is from its Wi-Fi", color = Theme.secondary, fontSize = 13.sp)
        }
        Icon(if (on) Icons.Filled.CheckCircle else Icons.Filled.RadioButtonUnchecked, null, tint = if (on) Theme.accent else Theme.tertiary)
    }
}

@Composable
private fun StepRow(number: Int, title: String, detail: String) {
    Row(horizontalArrangement = Arrangement.spacedBy(14.dp), modifier = Modifier.semantics {
        contentDescription = "Step $number: $title. ${detail.replace(" ▸ ", ", then ")}"
    }) {
        Box(Modifier.size(28.dp).background(Theme.accent, RoundedCornerShape(7.dp)), contentAlignment = Alignment.Center) {
            Text("$number", color = Theme.onAccent, style = monoStyle(15.sp, FontWeight.Black))
        }
        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(title, fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
            Text(detail, color = Theme.secondary, fontSize = 15.sp)
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

/** Home screen: scan the QR code on the camera's screen; Shutterlink joins its Wi-Fi, connects and saves it. */
@Composable
private fun ScanToConnectCard(camera: CameraModel, busy: Boolean, note: String?, onClick: () -> Unit) {
    val shape = RoundedCornerShape(20.dp)
    val connecting = busy && camera.phase == ConnectionPhase.CONNECTING
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(
            Modifier.fillMaxWidth().heightIn(min = 84.dp).background(Theme.surface, shape)
                .border(1.dp, Theme.accent.copy(alpha = 0.6f), shape)
                .clickable(enabled = camera.phase == ConnectionPhase.DISCONNECTED, onClick = onClick)
                .padding(16.dp)
                .semantics { contentDescription = "Scan the camera's QR code. Joins its Wi-Fi and connects." },
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            Box(Modifier.size(50.dp).background(Theme.accent, RoundedCornerShape(13.dp)), contentAlignment = Alignment.Center) {
                if (connecting) CircularProgressIndicator(color = Theme.onAccent, strokeWidth = 2.dp, modifier = Modifier.size(22.dp))
                else Icon(Icons.Filled.QrCodeScanner, null, tint = Theme.onAccent)
            }
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                Text(if (connecting) camera.status ?: "Connecting…" else "Scan the camera's QR code", fontSize = 17.sp, fontWeight = FontWeight.SemiBold, maxLines = 1)
                Text("Joins its Wi-Fi and connects. No trip to Settings.", color = Theme.secondary, fontSize = 13.sp)
            }
        }
        note?.let { Text(it, color = Theme.orange, fontSize = 13.sp) }
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
    Column(Modifier.fillMaxWidth().surface(RoundedCornerShape(20.dp)).padding(18.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        CapsLabel(typeLabel, color = Theme.accent)
        Text("The network name and password shown on the camera. Shutterlink joins it for you (Android asks you to confirm), and next time tapping the camera joins and connects in one go. Leave it empty if the phone is already on the camera's Wi-Fi.",
            color = Theme.secondary, fontSize = 13.sp)
        OutlinedTextField(camera.wifiSsid, { camera.wifiSsid = it }, label = { Text("Network name") }, singleLine = true, enabled = enabled,
            textStyle = monoStyle(16.sp, FontWeight.Normal), keyboardOptions = KeyboardOptions(autoCorrectEnabled = false, keyboardType = KeyboardType.Ascii),
            modifier = Modifier.fillMaxWidth().semantics { contentDescription = "Camera network name" })
        // Shown in clear: it's printed on the camera's screen anyway, and easy to mistype.
        OutlinedTextField(camera.wifiPassword, { camera.wifiPassword = it }, label = { Text("Password") }, singleLine = true, enabled = enabled,
            textStyle = monoStyle(16.sp, FontWeight.Normal), keyboardOptions = KeyboardOptions(autoCorrectEnabled = false, keyboardType = KeyboardType.Ascii),
            modifier = Modifier.fillMaxWidth().semantics { contentDescription = "Camera network password" })
    }
}

@Composable
private fun AdvancedCard(camera: CameraModel) {
    val context = LocalContext.current
    Column(Modifier.fillMaxWidth().surface(RoundedCornerShape(24.dp)).padding(20.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
        OutlinedTextField(
            camera.host, { camera.host = it.trim(); camera.saveSettings() },
            label = { Text("Camera address") },
            placeholder = { Text(if (camera.autoDetectBrand) "Automatic" else camera.brand.defaultHost, fontFamily = FontFamily.Monospace) },
            singleLine = true, textStyle = monoStyle(16.sp, FontWeight.Normal),
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri), modifier = Modifier.fillMaxWidth(),
        )
        if (camera.brand == CameraBrand.OLYMPUS && !camera.autoDetectBrand) {
            CapsLabel("User-Agent")
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                CameraModel.userAgents.forEach { ua -> Chip(ua, camera.userAgent == ua) { camera.userAgent = ua; camera.saveSettings() } }
            }
        }
        if (!camera.autoDetectBrand && camera.brand.defaultLiveViewSizes.isNotEmpty()) {
            CapsLabel("Live view size")
            camera.brand.defaultLiveViewSizes.forEach { q ->
                val on = camera.liveViewQuality == q
                Text(CameraModel.liveViewLabel(q), color = if (on) Theme.accent else Color.White, fontSize = 15.sp,
                    modifier = Modifier.fillMaxWidth().clickable { camera.liveViewQuality = q; camera.saveSettings() }.padding(vertical = 6.dp))
            }
        }
        Text(
            if (camera.autoDetectBrand) "Leave the address empty and the app looks for the camera at each brand's usual address. For the mock cameras in the Android emulator, enter 10.0.2.2 with the mock's port: 8080 Olympus, 8082 LUMIX, 15740 Nikon, 8084 Canon, 8086 Sony."
            else "The ${camera.brand.shortTitle} camera is normally at ${camera.brand.defaultHost}. For the mock cameras in the emulator, use 10.0.2.2 with the mock's port: 8080 Olympus, 8082 LUMIX, 15740 Nikon, 8084 Canon, 8086 Sony.",
            color = Theme.secondary, fontSize = 13.sp,
        )
        SurfaceButton(onClick = { context.startActivity(Intent(Settings.ACTION_WIFI_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) }) {
            Icon(Icons.Filled.Settings, null, Modifier.size(18.dp))
            Text("Open Wi-Fi settings", fontWeight = FontWeight.SemiBold)
        }
    }
}
