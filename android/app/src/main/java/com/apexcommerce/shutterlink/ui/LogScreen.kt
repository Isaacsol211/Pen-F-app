package com.apexcommerce.shutterlink.ui

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.apexcommerce.shutterlink.camera.CameraModel
import com.apexcommerce.shutterlink.camera.LiveViewFormat
import com.apexcommerce.shutterlink.camera.LogEntry
import kotlinx.coroutines.delay
import java.util.Locale

// The camera log, direction D (port of LogView.swift; design 407): the camera's details as hairline
// rows, then every request the app sent and what the camera answered, newest first. This is where to
// look when something doesn't work.

private fun logText(size: TextUnit, weight: FontWeight = FontWeight.Normal, mono: Boolean = false) =
    TextStyle(fontSize = size, fontWeight = weight, lineHeight = size * 1.35f,
        fontFamily = if (mono) FontFamily.Monospace else FontFamily.Default)

/** One of the camera's own lists (command list, desclist), shown as it came. */
private class RawText(val title: String, val text: String)

private fun copyToClipboard(context: Context, label: String, text: String) {
    context.getSystemService(ClipboardManager::class.java)?.setPrimaryClip(ClipData.newPlainText(label, text))
}

/** Every request the app sent and what the camera answered, with the camera's details above. */
@Composable
fun LogScreen(camera: CameraModel, onDismiss: () -> Unit) {
    var raw by remember { mutableStateOf<RawText?>(null) }
    FullScreenPage(onDismiss = { if (raw != null) raw = null else onDismiss() }) {
        val open = raw
        if (open != null) RawTextPage(open) { raw = null }
        else LogList(camera, onDismiss) { raw = it }
    }
}

@Composable
private fun LogList(camera: CameraModel, onDismiss: () -> Unit, openRaw: (RawText) -> Unit) {
    val context = LocalContext.current
    var copied by remember { mutableStateOf(false) }
    LaunchedEffect(copied) {
        if (copied) {
            delay(2000)
            copied = false
        }
    }
    // The row whose path and summary are shown in full (tap a request to open or close it).
    var expanded by remember { mutableStateOf<LogEntry?>(null) }

    Column(Modifier.fillMaxSize()) {
        // 407: "Copy log · Clear log" as plain text on the left, the title, Done on the right.
        Row(Modifier.fillMaxWidth().heightIn(min = Theme.target).padding(horizontal = 20.dp),
            verticalAlignment = Alignment.CenterVertically) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                HeaderButton(if (copied) "Copied" else "Copy log", Theme.secondary) {
                    copyToClipboard(context, "Shutterlink log", logForClipboard(camera))
                    copied = true
                }
                Text("·", style = logText(15.sp), color = Theme.tertiary, modifier = Modifier.padding(horizontal = 4.dp))
                HeaderButton("Clear log", Theme.secondary) {
                    expanded = null
                    camera.clearLog()
                }
            }
            Spacer(Modifier.weight(1f))
            Text("Camera log", color = Theme.text, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, maxLines = 1,
                modifier = Modifier.semantics { heading() })
            Spacer(Modifier.weight(1f))
            HeaderButton("Done", onClick = onDismiss)
        }

        val log = camera.log
        val count = log.size
        LazyColumn(Modifier.fillMaxSize().padding(horizontal = 20.dp)) {
            item(key = "camera") {
                Column {
                    LogSection("Camera")
                    CameraDetails(camera, openRaw)
                }
            }
            item(key = "requests") { LogSection("Requests (newest first)") }
            if (count == 0) {
                item(key = "empty") {
                    Text("Nothing yet.", style = logText(15.sp), color = Theme.secondary,
                        modifier = Modifier.fillMaxWidth().hairRow(44.dp).padding(vertical = 12.dp))
                }
            }
            items(count) { index ->
                // Newest first; the list can change under us, so look the entry up defensively.
                val entry = log.getOrNull(log.size - 1 - index) ?: return@items
                if (entry.note) NoteLine(entry)
                else RequestLine(entry, open = expanded == entry) { expanded = if (expanded == entry) null else entry }
            }
            item(key = "end") { Spacer(Modifier.height(24.dp)) }
        }
    }
}

/** Everything the log shows, for pasting into a message: a header line, the log, and the camera's command list. */
private fun logForClipboard(camera: CameraModel): String = buildString {
    appendLine("Shutterlink Android · ${camera.cameraName ?: camera.brand.title} · ${camera.connectionHost}")
    camera.log.forEach { appendLine(it.line) }
    if (camera.rawCommandList.isNotEmpty()) appendLine("\n${camera.rawCommandList.take(20_000)}")
}

@Composable
private fun LogSection(title: String) {
    CapsLabel(title, modifier = Modifier.fillMaxWidth().padding(top = 22.dp, bottom = 8.dp))
}

/** A label on the left and its value on the right, over a hairline (407's camera rows). */
@Composable
private fun DetailRow(label: String, value: String, onClick: (() -> Unit)? = null) {
    Row(Modifier.fillMaxWidth().hairRow(42.dp)
        .then(if (onClick != null) Modifier.clickable(role = Role.Button, onClick = onClick) else Modifier)
        .padding(vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Text(label, style = logText(14.sp), color = Theme.secondary)
        Spacer(Modifier.weight(1f))
        SelectionContainer {
            Text(value, style = logText(14.sp), color = Theme.text, textAlign = TextAlign.End)
        }
    }
}

@Composable
private fun CameraDetails(camera: CameraModel, openRaw: (RawText) -> Unit) {
    Column(Modifier.fillMaxWidth().topRule()) {
        DetailRow("Model", camera.cameraName ?: "–")
        DetailRow("Support", camera.profile?.support?.text ?: "Not in Shutterlink's model table")
        camera.profile?.notes?.forEach { note ->
            Text(note, style = logText(13.sp), color = Theme.secondary,
                modifier = Modifier.fillMaxWidth().hairRow().padding(vertical = 10.dp))
        }
        DetailRow("Address", camera.connectionHost)
        // Only the cameras that send live view over UDP use the port (the others are fetched frame by frame).
        val format = camera.driver?.liveViewFormat
        if (format != null && format != LiveViewFormat.PUSHED) DetailRow("Live view port", "UDP ${camera.udpPort}")
        DetailRow("Command list", "›") { openRaw(RawText("Command list", camera.rawCommandList)) }
        DetailRow("Settings (desclist)", "›") { openRaw(RawText("desclist", camera.rawDescList)) }
    }
}

/** A hairline along the top, so the first row of a section has one above it too. */
private fun Modifier.topRule(): Modifier = this.drawBehind {
    drawRect(Theme.stroke, size = Size(size.width, 1.dp.toPx()))
}

private fun time(entry: LogEntry): String = String.format(Locale.US, "%tT", entry.date)

/**
 * 407: the status in Barlow (green, or red ERR), the method, the time it took, then the path on one
 * line; the clock time and the camera's answer under it. Tap to see the whole path and answer.
 */
@Composable
private fun RequestLine(entry: LogEntry, open: Boolean, onToggle: () -> Unit) {
    val good = entry.ok || entry.method == "PTP"
    Column(Modifier.fillMaxWidth().hairRow(40.dp).clickable(onClick = onToggle).padding(vertical = 8.dp),
        verticalArrangement = Arrangement.spacedBy(3.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Text(entry.status?.toString() ?: "ERR", style = Theme.num(16.sp), color = if (good) Theme.green else Theme.red,
                maxLines = 1, modifier = Modifier.width(34.dp))
            Text(entry.method, style = logText(13.sp), color = Theme.secondary, maxLines = 1, overflow = TextOverflow.Clip,
                modifier = Modifier.width(38.dp))
            Text("${entry.millis} ms", style = logText(13.sp).copy(fontFeatureSettings = "tnum"), color = Theme.secondary,
                maxLines = 1, overflow = TextOverflow.Clip, modifier = Modifier.width(50.dp))
            if (open) {
                SelectionContainer(Modifier.weight(1f)) {
                    Text(entry.path, style = logText(13.sp, FontWeight.SemiBold, mono = true), color = Theme.text)
                }
            } else {
                Text(entry.path, style = logText(13.sp, FontWeight.SemiBold, mono = true), color = Theme.text,
                    maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
            }
        }
        val detail = buildAnnotatedString {
            withStyle(SpanStyle(color = Theme.tertiary)) { append(time(entry)) }
            if (entry.summary.isNotEmpty()) {
                append("  ")
                append(entry.summary)
            }
        }
        if (open) {
            SelectionContainer { Text(detail, style = logText(11.sp, mono = true), color = Theme.secondary) }
        } else {
            Text(detail, style = logText(11.sp, mono = true), color = Theme.secondary, maxLines = 4, overflow = TextOverflow.Ellipsis)
        }
    }
}

/** A line from the app itself (live view's frame rates): its kind in the accent, then the text, wrapped. */
@Composable
private fun NoteLine(entry: LogEntry) {
    Column(Modifier.fillMaxWidth().hairRow(40.dp).padding(vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Text(entry.method, style = logText(13.sp, FontWeight.SemiBold), color = Theme.accent)
            Text(time(entry), style = logText(11.sp, mono = true), color = Theme.tertiary)
        }
        SelectionContainer {
            Text(entry.path, style = logText(13.sp), color = Theme.text)
        }
    }
}

/** The command list or desclist as the camera sent it, selectable, with Copy. */
@Composable
private fun RawTextPage(raw: RawText, onBack: () -> Unit) {
    val context = LocalContext.current
    var copied by remember { mutableStateOf(false) }
    LaunchedEffect(copied) {
        if (copied) {
            delay(2000)
            copied = false
        }
    }
    Column(Modifier.fillMaxSize()) {
        ScreenHeader(raw.title, centred = true,
            leading = { HeaderButton("Back", onClick = onBack) },
            trailing = {
                HeaderButton(if (copied) "Copied" else "Copy", enabled = raw.text.isNotEmpty()) {
                    copyToClipboard(context, raw.title, raw.text)
                    copied = true
                }
            })
        Box(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(20.dp)) {
            SelectionContainer {
                Text(raw.text.ifEmpty { "(nothing received)" }, style = logText(12.sp, mono = true),
                    color = if (raw.text.isEmpty()) Theme.secondary else Theme.text, modifier = Modifier.fillMaxWidth())
            }
        }
    }
}
