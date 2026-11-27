package com.apexcommerce.shutterlink.ui

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.FileProvider
import com.apexcommerce.shutterlink.BuildConfig
import com.apexcommerce.shutterlink.camera.CameraModel
import com.apexcommerce.shutterlink.camera.CameraNetwork
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File

/**
 * Report a problem (port of ReportProblemView.swift): what happened in the tester's words, plus the
 * camera log and this phone's details, by email with the log attached as shutterlink-report.txt. Where
 * no mail app takes it, the share sheet and Copy instead. Opened from More ▸ Report a problem and from
 * the connection-error banners.
 */
@Composable
fun ReportProblemPage(camera: CameraModel, onDismiss: () -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var note by rememberSaveable { mutableStateOf("") }
    var noMailApp by remember { mutableStateOf(false) }
    var copied by remember { mutableStateOf(false) }
    // Android doesn't say whether the mail was sent: once it's handed over, Cancel becomes Done.
    var handedOver by remember { mutableStateOf(false) }
    val device = if (LocalConfiguration.current.smallestScreenWidthDp >= 600) "tablet" else "phone"

    FullScreenPage(onDismiss, camera) {
        Column(Modifier.fillMaxSize()) {
            ScreenHeader("Report a problem", centred = true, leading = {
                HeaderButton(if (handedOver) "Done" else "Cancel", color = if (handedOver) Theme.text else Theme.secondary, onClick = onDismiss)
            })
            Column(
                Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(20.dp),
                verticalArrangement = Arrangement.spacedBy(16.dp),
            ) {
                NoteField(note) {
                    note = it
                    copied = false
                }
                Text("The report adds the camera log, the camera's model, your $device model and Android version. Wi-Fi passwords are left out.",
                    color = Theme.secondary, fontSize = 13.sp, lineHeight = 18.sp)
                if (!noMailApp) {
                    AccentButton(onClick = {
                        scope.launch {
                            val taken = ProblemReport.email(context, camera, note)
                            if (taken) handedOver = true
                            noMailApp = !taken
                        }
                    }, modifier = Modifier.fillMaxWidth()) { Text("Email the report") }
                } else {
                    AccentButton(onClick = {
                        if (ProblemReport.share(context, camera, note)) handedOver = true
                    }, modifier = Modifier.fillMaxWidth()) { Text("Send the report") }
                    OutlineButton(onClick = {
                        ProblemReport.copy(context, camera, note)
                        copied = true
                    }, modifier = Modifier.fillMaxWidth()) { Text(if (copied) "Copied" else "Copy the report") }
                    SelectionContainer {
                        Text("Send it to ${ProblemReport.ADDRESS}", color = Theme.secondary, fontSize = 13.sp)
                    }
                }
            }
        }
    }
}

@Composable
private fun NoteField(value: String, onChange: (String) -> Unit) {
    val style = TextStyle(color = Theme.text, fontSize = 16.sp, lineHeight = 22.sp)
    BasicTextField(
        value, onChange,
        Modifier.fillMaxWidth().background(Theme.surface, RoundedCornerShape(16.dp)).padding(16.dp),
        textStyle = style,
        keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Sentences),
        minLines = 5,
        maxLines = 12,
        cursorBrush = SolidColor(Theme.accent),
        decorationBox = { field ->
            Box {
                if (value.isEmpty()) Text("What happened? What did you tap, and what did you expect?", style = style.copy(color = Theme.tertiary))
                field()
            }
        },
    )
}

/** Building the report and handing it to a mail app, the share sheet or the clipboard. */
object ProblemReport {
    /** The developer's support address (the same as the iOS app's). */
    const val ADDRESS = "isaacsolomon211@gmail.com"
    private const val FILE_NAME = "shutterlink-report.txt"
    /** The command list can be long; the copies that travel as text keep this much of it. */
    private const val TEXT_COMMAND_LIST = 20_000

    val appVersion: String
        get() = "${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE})${if (BuildConfig.DEBUG) " debug" else ""}"

    /** e.g. "Google Pixel 8 (shiba), Android 16 (API 36)"; the emulator says so. */
    val device: String
        get() {
            val emulator = Build.HARDWARE == "ranchu" || Build.HARDWARE == "goldfish"
            return "${Build.MANUFACTURER} ${Build.MODEL} (${Build.DEVICE})${if (emulator) ", emulator" else ""}, " +
                "Android ${Build.VERSION.RELEASE} (API ${Build.VERSION.SDK_INT})"
        }

    fun subject(camera: CameraModel) = "Shutterlink problem: ${camera.cameraName ?: camera.brand.title} (Android $appVersion)"

    /** Email with the full report attached. False when no mail app takes it. Main thread. */
    suspend fun email(context: Context, camera: CameraModel, note: String): Boolean {
        val report = camera.problemReport(note)
        val uri = withContext(Dispatchers.IO) { writeFile(context, report) }
        val send = Intent(Intent.ACTION_SEND).apply {
            type = "text/plain"
            putExtra(Intent.EXTRA_EMAIL, arrayOf(ADDRESS))
            putExtra(Intent.EXTRA_SUBJECT, subject(camera))
            if (uri != null) {
                putExtra(Intent.EXTRA_TEXT, camera.problemSummary(note) + "\n\nThe camera log is attached ($FILE_NAME).")
                putExtra(Intent.EXTRA_STREAM, uri)
                clipData = ClipData.newRawUri(FILE_NAME, uri)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            } else {
                putExtra(Intent.EXTRA_TEXT, camera.problemReport(note, TEXT_COMMAND_LIST))
            }
            // Only mail apps: the selector limits who can take it to apps that handle mailto: links.
            selector = Intent(Intent.ACTION_SENDTO, Uri.parse("mailto:"))
        }
        return start(context, send)
    }

    /** The share sheet, with the report as text. */
    fun share(context: Context, camera: CameraModel, note: String): Boolean {
        val send = Intent(Intent.ACTION_SEND).apply {
            type = "text/plain"
            putExtra(Intent.EXTRA_EMAIL, arrayOf(ADDRESS))
            putExtra(Intent.EXTRA_SUBJECT, subject(camera))
            putExtra(Intent.EXTRA_TEXT, camera.problemReport(note, TEXT_COMMAND_LIST))
        }
        return start(context, Intent.createChooser(send, "Send the report"))
    }

    fun copy(context: Context, camera: CameraModel, note: String) {
        val clipboard = context.getSystemService(ClipboardManager::class.java) ?: return
        clipboard.setPrimaryClip(ClipData.newPlainText("Shutterlink report", camera.problemReport(note, TEXT_COMMAND_LIST)))
    }

    private fun start(context: Context, intent: Intent): Boolean = try {
        if (context !is Activity) intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        context.startActivity(intent)
        true
    } catch (e: ActivityNotFoundException) {
        false
    }

    /** In the cache (reports/, shared by the FileProvider in the manifest), replaced each time. */
    private fun writeFile(context: Context, text: String): Uri? = runCatching {
        val dir = File(context.cacheDir, "reports").apply { mkdirs() }
        val file = File(dir, FILE_NAME)
        file.writeText(text)
        FileProvider.getUriForFile(context, "${context.packageName}.fileprovider", file)
    }.getOrNull()
}

/** The app, phone, camera and connection, one line each (the mail's body, and the top of the report). */
fun CameraModel.problemDetails(): List<String> = buildList {
    add("App: Shutterlink for Android ${ProblemReport.appVersion}")
    add("Device: ${ProblemReport.device}")
    val brandText = if (autoDetectBrand) "automatic (${brand.id})" else brand.id
    add("Camera: ${cameraName ?: "not connected"}, brand $brandText, address ${host.ifEmpty { "default" }} (using $connectionHost)")
    add("Model table: ${profile?.name ?: "not in the table"}")
    val liveView = if (liveViewRunning) "$liveViewQuality at $fps fps" else "$liveViewQuality, stopped"
    add("Connection: ${phase.name.lowercase()}, mode ${mode.name.lowercase()}, live view $liveView, " +
        "phone Wi-Fi ${CameraNetwork.wifiAddress() ?: "none"}")
    lastError?.let { add("Last error: $it") }
}

/** What happened, then the details: the mail's body (the log goes in the attachment). */
fun CameraModel.problemSummary(note: String): String =
    (listOf(note.trim().ifEmpty { "(no description)" }, "") + problemDetails()).joinToString("\n")

/**
 * Everything a problem report carries, as plain text: the details, the request log (oldest first) and
 * the camera's command list. Scanned QR codes are left out of the log: they can hold the camera's
 * Wi-Fi password.
 */
fun CameraModel.problemReport(note: String, commandListLimit: Int = Int.MAX_VALUE): String {
    val lines = mutableListOf("Shutterlink problem report", "", note.trim().ifEmpty { "(no description)" }, "")
    lines += problemDetails()
    lines += listOf("", "Camera log, oldest first:")
    lines += log.toList().map { entry ->
        if (entry.method == "QR") entry.copy(path = "(code left out)", millis = 0).line else entry.line
    }
    if (rawCommandList.isNotEmpty()) lines += listOf("", "Command list:", rawCommandList.take(commandListLimit))
    return lines.joinToString("\n")
}
