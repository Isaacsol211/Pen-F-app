package com.apexcommerce.shutterlink.ui

import android.content.Context
import android.text.format.Formatter
import androidx.activity.compose.BackHandler
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.gestures.rememberTransformableState
import androidx.compose.foundation.gestures.transformable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowCircleDown
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Photo
import androidx.compose.material.icons.filled.RadioButtonUnchecked
import androidx.compose.material.icons.filled.SdCard
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.StarBorder
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.apexcommerce.shutterlink.camera.CameraImage
import com.apexcommerce.shutterlink.camera.CameraModel
import com.apexcommerce.shutterlink.camera.CardFolder
import com.apexcommerce.shutterlink.camera.RawImportProgress
import com.apexcommerce.shutterlink.camera.cancelRawImport
import com.apexcommerce.shutterlink.camera.downloadStarredRaws
import com.apexcommerce.shutterlink.camera.isStarred
import com.apexcommerce.shutterlink.camera.rawCompanion
import com.apexcommerce.shutterlink.camera.toggleStar
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch
import java.text.DateFormat
import java.util.Date
import kotlin.math.min

// The card browser, direction D (port of GalleryView.swift; design 401–404): each folder's photos as
// strips of film, sprocket holes above and below and the frame number in gold under each frame; a
// starred frame gets a red hand-drawn circle. The viewer is black with the photo's name, details, the
// star and Save on a card at the bottom.

/** The film base between the sprocket holes. */
private val FilmBase = Color(0xFF161513)
/** A frame before its thumbnail arrives. */
private val FrameEmpty = Color(0xFF1F1F1D)
/** Frame numbers, as printed on the film's edge. */
private val FrameGold = Color(0xFFE8B04A)
/** The marker pen round a starred frame. */
private val ScribbleRed = Color(0xFFFF4B3A)

/** Body text with a line height that suits its size (the default typography's is 24 sp for everything). */
private fun galleryText(size: TextUnit, weight: FontWeight = FontWeight.Normal) =
    TextStyle(fontSize = size, fontWeight = weight, lineHeight = size * 1.4f)

/** The photos as they were when the viewer opened, so unstarring one while Starred is on doesn't pull it away. */
private class Viewing(val images: List<CameraImage>, val start: CameraImage)

/**
 * Browses the SD card (port of GalleryView.swift). The camera has to be in playback mode for this,
 * so live view stops while it's open and restarts on Done.
 */
@Composable
fun GalleryScreen(camera: CameraModel, onDone: () -> Unit) {
    val scope = rememberCoroutineScope()
    val feedback = rememberFeedback()
    var starredOnly by remember { mutableStateOf(false) }
    var viewing by remember { mutableStateOf<Viewing?>(null) }
    // Select mode: tap frames to tick them, then save them or their RAWs together.
    var selecting by remember { mutableStateOf(false) }
    var picked by remember { mutableStateOf<Set<String>>(emptySet()) }
    var selectionProgress by remember { mutableStateOf<Pair<Int, Int>?>(null) }
    // Out here so the grid keeps its place while a photo is open.
    val listState = rememberLazyListState()
    LaunchedEffect(Unit) { camera.openGallery() }
    BackHandler {
        when {
            viewing != null -> viewing = null
            selecting -> { selecting = false; picked = emptySet() }
            else -> onDone()
        }
    }

    val visible = if (starredOnly) camera.images.filter { camera.isStarred(it) } else camera.images
    val starredCount = camera.images.count { camera.isStarred(it) }
    val importing = camera.rawImport.let { it != null && it.message == null }

    viewing?.let { v ->
        PhotoViewer(camera, v.images, v.start) { viewing = null }
        return
    }

    /** Saves the ticked photos (or their RAW files) one by one, with the same per-photo save as the viewer's Save. */
    fun saveSelection(raws: Boolean) {
        val images = camera.images.filter { it.path in picked && !(raws && it.isVideo) }
        if (images.isEmpty()) return
        selectionProgress = 0 to images.size
        scope.launch {
            var saved = 0
            var failed = 0
            var withoutRaw = 0
            for ((index, image) in images.withIndex()) {
                selectionProgress = index to images.size
                val target = if (raws) camera.rawCompanion(image) else image
                if (target == null) {
                    withoutRaw++
                } else {
                    try {
                        camera.saveOriginal(target)
                        saved++
                    } catch (e: CancellationException) {
                        throw e
                    } catch (e: Exception) {
                        failed++
                    }
                }
            }
            var message = when {
                saved == 0 -> "Nothing was saved."
                raws -> "Saved $saved RAW file${if (saved == 1) "" else "s"} to Download ▸ Shutterlink ▸ RAW."
                else -> "Saved $saved photo${if (saved == 1) "" else "s"} to the gallery."
            }
            if (failed > 0) message += " $failed couldn't be downloaded."
            if (withoutRaw > 0) message += " $withoutRaw ${if (withoutRaw == 1) "has" else "have"} no RAW."
            camera.rawImport = RawImportProgress(done = saved, total = images.size, message = message)
            selectionProgress = null
            selecting = false
            picked = emptySet()
        }
    }

    Box(Modifier.fillMaxSize().background(Theme.background).safeDrawingPadding()) {
        Column(Modifier.fillMaxSize()) {
            ScreenHeader(
                if (camera.images.isEmpty()) "On the card" else "On the card · ${camera.images.size}",
                centred = true,
                leading = {
                    if (selecting) HeaderButton("Cancel") { selecting = false; picked = emptySet() }
                    else HeaderButton("Reload", Theme.secondary, enabled = !camera.galleryLoading) {
                        scope.launch { camera.openGallery() }
                    }
                },
                trailing = { HeaderButton("Done", onClick = onDone) },
            )
            Box(Modifier.weight(1f).fillMaxWidth()) {
                // 403: a state is a Barlow title and a line under it, centred.
                val error = camera.galleryError
                when {
                    camera.galleryLoading && camera.images.isEmpty() -> GalleryState("Reading the card…", busy = true)
                    error != null && camera.images.isEmpty() -> GalleryState("Couldn't read the card", error)
                    camera.images.isEmpty() && camera.cardFolders.isEmpty() -> GalleryState("No photos", "Nothing on the card yet.")
                    starredOnly && starredCount == 0 ->
                        GalleryState("No starred photos", "Tap and hold a photo to star it, or use the star when viewing it.")
                    else -> FilmRolls(
                        camera, visible, starredOnly, listState, selecting, picked,
                        onTap = { image ->
                            if (selecting) {
                                picked = if (image.path in picked) picked - image.path else picked + image.path
                                feedback(Feedback.Moment.SELECT)
                            } else {
                                viewing = Viewing(visible.ifEmpty { listOf(image) }, image)
                            }
                        },
                    )
                }
            }
            GalleryBottomBar(
                camera, selecting, starredOnly, starredCount, importing, picked.size, selectionProgress,
                setStarredOnly = { if (starredOnly != it) { starredOnly = it; feedback(Feedback.Moment.SELECT) } },
                startSelecting = { selecting = true },
                saveSelection = ::saveSelection,
            )
        }
        Toast(camera, Modifier.align(Alignment.TopCenter).padding(top = Theme.target))
    }
}

/** A gallery state (403): an optional accent spinner, the title in Barlow, a line under it. */
@Composable
private fun GalleryState(title: String, detail: String? = null, busy: Boolean = false) {
    Column(Modifier.fillMaxSize().padding(horizontal = 30.dp).semantics(mergeDescendants = true) {},
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(8.dp, Alignment.CenterVertically)) {
        if (busy) CircularProgressIndicator(color = Theme.accent)
        Text(title, style = Theme.num(28.sp), color = Theme.text, textAlign = TextAlign.Center)
        if (detail != null) Text(detail, style = galleryText(13.sp), color = Theme.secondary, textAlign = TextAlign.Center)
    }
}

/** The card's folders, each a header and its photos on strips of film. */
@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun FilmRolls(
    camera: CameraModel,
    visible: List<CameraImage>,
    starredOnly: Boolean,
    listState: LazyListState,
    selecting: Boolean,
    picked: Set<String>,
    onTap: (CameraImage) -> Unit,
) {
    // Frame numbers count through the whole card, as on a roll of film.
    val frameNumbers = remember(camera.images) { camera.images.withIndex().associate { it.value.path to it.index + 1 } }
    BoxWithConstraints(Modifier.fillMaxSize()) {
        // Three frames to a strip on a phone, more on a wider screen.
        val perRow = ((maxWidth - 24.dp) / 112.dp).toInt().coerceIn(3, 8)
        val folders = camera.cardFolders.distinctBy { it.path }
            .filter { folder -> !starredOnly || visible.any { it.directory == folder.path } }
        LazyColumn(Modifier.fillMaxSize(), state = listState, contentPadding = PaddingValues(bottom = 20.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)) {
            for (folder in folders) {
                stickyHeader(key = "h:" + folder.path) { FolderHeader(folder) }
                val files = visible.filter { it.directory == folder.path }
                if (files.isEmpty()) {
                    if (!starredOnly) item(key = "e:" + folder.path) { EmptyFolder(folder) }
                } else {
                    itemsIndexed(files.chunked(perRow), key = { index, _ -> "r:${folder.path}:$perRow:$index" }) { _, row ->
                        FilmStrip {
                            row.forEach { image ->
                                Box(Modifier.weight(1f)) {
                                    FilmFrame(camera, image, frameNumbers[image.path] ?: 0, selecting, image.path in picked) { onTap(image) }
                                }
                            }
                            repeat(perRow - row.size) { Spacer(Modifier.weight(1f)) }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun FolderHeader(folder: CardFolder) {
    Row(Modifier.fillMaxWidth().background(Theme.background.copy(alpha = 0.92f))
        .padding(start = 20.dp, end = 20.dp, top = 14.dp, bottom = 8.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        Text(folder.name, style = Theme.num(20.sp).copy(letterSpacing = 0.8.sp), color = Theme.text, maxLines = 1,
            modifier = Modifier.semantics { heading() })
        Box(Modifier.height(20.dp).background(Theme.stroke, Pill).padding(horizontal = 8.dp), contentAlignment = Alignment.Center) {
            Text("${folder.count}", style = TextStyle(fontSize = 12.sp, lineHeight = 14.sp), color = Theme.text)
        }
        if (folder.isForeign) Text("other camera", style = TextStyle(fontSize = 12.sp, lineHeight = 14.sp), color = Theme.accent)
    }
}

/** A folder the camera lists with nothing in it: from another camera (whose files it won't serve), or empty. */
@Composable
private fun EmptyFolder(folder: CardFolder) {
    Row(Modifier.padding(horizontal = 10.dp).fillMaxWidth().surface(RoundedCornerShape(16.dp)).padding(14.dp),
        horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        Icon(if (folder.isForeign) Icons.Filled.SdCard else Icons.Filled.Photo, null, Modifier.size(18.dp), tint = Theme.secondary)
        Text(
            if (folder.isForeign) "The camera lists this folder (made by another camera) as empty, so nothing in it can be " +
                "fetched over Wi-Fi. If it holds photos, put the card in a USB-C SD card reader on your phone and copy " +
                "them with the Files app."
            else "No photos in this folder.",
            style = galleryText(13.sp), color = Theme.secondary,
        )
    }
}

/** A row of frames on a strip of film: sprocket holes above and below. */
@Composable
private fun FilmStrip(content: @Composable androidx.compose.foundation.layout.RowScope.() -> Unit) {
    Column(Modifier.fillMaxWidth().background(FilmBase).padding(start = 12.dp, end = 12.dp, top = 6.dp, bottom = 2.dp),
        verticalArrangement = Arrangement.spacedBy(4.dp)) {
        SprocketHoles()
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.Top,
            content = content)
        SprocketHoles()
    }
}

@Composable
private fun SprocketHoles() {
    Canvas(Modifier.fillMaxWidth().height(8.dp).clearAndSetSemantics {}) {
        val hole = 9.dp.toPx()
        val step = 18.dp.toPx()
        val radius = CornerRadius(2.dp.toPx())
        var x = 0f
        while (x < size.width) {
            drawRoundRect(Theme.background, Offset(x, 0f), Size(min(hole, size.width - x), size.height), radius)
            x += step
        }
    }
}

/** A normal PEN-F JPEG is ~8–12 MB and an ORF ~20–25 MB; High Res files are far bigger. */
private val CameraImage.looksHighRes: Boolean
    get() = urls == null && when (fileExtension) {
        "JPG" -> size > 18_000_000
        "ORF" -> size > 50_000_000
        else -> false
    }

/** One frame: the thumbnail, its file type, the red circle when starred, and the gold number under it. */
@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun FilmFrame(camera: CameraModel, image: CameraImage, number: Int, selecting: Boolean, picked: Boolean, onTap: () -> Unit) {
    val haptics = LocalHapticFeedback.current
    val starred = camera.isStarred(image)
    var thumbnail by remember(image.path) { mutableStateOf<ImageBitmap?>(null) }
    var missing by remember(image.path) { mutableStateOf(false) }
    LaunchedEffect(image.path) {
        val bitmap = camera.thumbnail(image)
        thumbnail = bitmap?.asImageBitmap()
        missing = bitmap == null
    }
    val ring by animateFloatAsState(if (starred) 1f else 0f, label = "star")
    val shown by animateFloatAsState(if (thumbnail != null) 1f else 0f, label = "thumbnail")
    Column(
        Modifier.fillMaxWidth()
            .combinedClickable(
                onClickLabel = if (selecting) (if (picked) "Deselect" else "Select") else "Open",
                onLongClickLabel = if (starred) "Remove star" else "Star",
                onLongClick = {
                    haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                    camera.toggleStar(image)
                },
                onClick = onTap,
            )
            .semantics(mergeDescendants = true) {
                contentDescription = "Frame $number, ${image.name}" + if (starred) ", starred" else ""
                if (selecting) selected = picked
            },
        verticalArrangement = Arrangement.spacedBy(3.dp),
    ) {
        Box(Modifier.fillMaxWidth().aspectRatio(3f / 2f)) {
            Box(Modifier.matchParentSize().clip(RoundedCornerShape(2.dp)).background(FrameEmpty).alpha(if (picked) 0.75f else 1f),
                contentAlignment = Alignment.Center) {
                val t = thumbnail
                when {
                    t != null -> Image(t, null, Modifier.fillMaxSize().alpha(shown), contentScale = ContentScale.Crop)
                    missing -> Column(Modifier.padding(4.dp), horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        Icon(Icons.Filled.Photo, null, Modifier.size(20.dp), tint = Theme.secondary)
                        Text(image.name, color = Theme.secondary, maxLines = 1, overflow = TextOverflow.Ellipsis,
                            style = TextStyle(fontSize = 9.sp, lineHeight = 11.sp, fontFamily = FontFamily.Monospace))
                    }
                    else -> CircularProgressIndicator(Modifier.size(16.dp), color = Theme.secondary, strokeWidth = 2.dp)
                }
            }
            Row(Modifier.align(Alignment.BottomStart).padding(4.dp), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                val ext = image.fileExtension
                if (ext.isNotEmpty() && ext != "JPG") FrameBadge(ext)
                if (image.looksHighRes) FrameBadge("50 MP", Theme.accent)
            }
            if (ring > 0f) Canvas(Modifier.matchParentSize()) { drawScribble(ring) }
            if (selecting) {
                // Select mode: a tick at the bottom right, and an accent edge round a ticked frame.
                if (picked) Box(Modifier.matchParentSize().border(2.dp, Theme.accent, RoundedCornerShape(6.dp)))
                Icon(if (picked) Icons.Filled.CheckCircle else Icons.Filled.RadioButtonUnchecked, null,
                    Modifier.align(Alignment.BottomEnd).padding(5.dp).size(22.dp)
                        .background(if (picked) Theme.background else Color.Black.copy(alpha = 0.3f), CircleShape),
                    tint = if (picked) Theme.accent else Theme.text)
            }
        }
        Text(if (number > 0) "$number" else "", style = Theme.num(13.sp, medium = true).copy(letterSpacing = 1.sp), color = FrameGold,
            maxLines = 1)
    }
}

@Composable
private fun FrameBadge(text: String, tint: Color = Color.White) {
    Text(text, color = tint, maxLines = 1,
        style = TextStyle(fontSize = 10.sp, lineHeight = 12.sp, fontWeight = FontWeight.Bold),
        modifier = Modifier.background(Color.Black.copy(alpha = 0.65f), RoundedCornerShape(4.dp)).padding(horizontal = 5.dp, vertical = 2.dp))
}

/** A hand-drawn red circle round a starred frame, a little wider than the frame. */
private fun DrawScope.drawScribble(alpha: Float) {
    val out = 3.dp.toPx()
    val w = size.width + 2 * out
    val h = size.height + 2 * out
    fun x(f: Float) = -out + w * f
    fun y(f: Float) = -out + h * f
    val path = Path().apply {
        moveTo(x(0.09f), y(0.51f))
        cubicTo(x(0.07f), y(0.15f), x(0.38f), y(0.03f), x(0.62f), y(0.06f))
        cubicTo(x(0.9f), y(0.1f), x(0.98f), y(0.36f), x(0.93f), y(0.62f))
        cubicTo(x(0.88f), y(0.9f), x(0.53f), y(1.0f), x(0.31f), y(0.92f))
        cubicTo(x(0.12f), y(0.86f), x(0.05f), y(0.7f), x(0.10f), y(0.44f))
    }
    drawPath(path, ScribbleRed, alpha = alpha, style = Stroke(3.dp.toPx(), cap = StrokeCap.Round))
}

/** The bar under the strips: RAW download progress, then the filter and RAWs, or Select mode's actions. */
@Composable
private fun GalleryBottomBar(
    camera: CameraModel,
    selecting: Boolean,
    starredOnly: Boolean,
    starredCount: Int,
    importing: Boolean,
    pickedCount: Int,
    selectionProgress: Pair<Int, Int>?,
    setStarredOnly: (Boolean) -> Unit,
    startSelecting: () -> Unit,
    saveSelection: (raws: Boolean) -> Unit,
) {
    if (camera.rawImport == null && camera.images.isEmpty() && !selecting) return
    Column(Modifier.fillMaxWidth().background(Theme.background).drawBehind {
        drawRect(Theme.stroke, size = Size(size.width, 1.dp.toPx()))
    }.padding(bottom = 4.dp)) {
        RawImportBar(camera)
        if (selecting) {
            val busy = selectionProgress != null
            Row(Modifier.fillMaxWidth().padding(start = 16.dp, end = 16.dp, top = 10.dp),
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(
                    when {
                        selectionProgress != null -> "Saving ${selectionProgress.first + 1} of ${selectionProgress.second}…"
                        pickedCount == 0 -> "Tap photos to select them"
                        else -> "$pickedCount selected"
                    },
                    style = galleryText(13.sp), color = Theme.secondary, maxLines = 2, overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f),
                )
                SurfaceButton(onClick = { saveSelection(true) }, enabled = pickedCount > 0 && !busy && !importing,
                    modifier = Modifier.semantics { contentDescription = "Save the RAW files of the selected photos" }) {
                    Text("RAWs")
                }
                AccentButton(onClick = { saveSelection(false) }, enabled = pickedCount > 0 && !busy && !importing) {
                    Text("Save to gallery", maxLines = 1)
                }
            }
        } else if (camera.images.isNotEmpty()) {
            BoxWithConstraints(Modifier.fillMaxWidth()) {
                val roomy = maxWidth >= 380.dp
                Row(Modifier.fillMaxWidth().padding(start = 16.dp, end = 16.dp, top = 10.dp),
                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    // One outlined pill, the chosen half filled (design 401).
                    Row(Modifier.border(1.dp, Theme.outline, Pill)) {
                        ChipButton("All", selected = !starredOnly, outlined = false) { setStarredOnly(false) }
                        ChipButton(if (starredCount > 0) "Starred · $starredCount" else "Starred", selected = starredOnly,
                            outlined = false) { setStarredOnly(true) }
                    }
                    Spacer(Modifier.weight(1f))
                    HeaderButton("Select", onClick = startSelecting)
                    AccentButton(onClick = { camera.downloadStarredRaws() }, enabled = starredCount > 0 && !importing,
                        modifier = Modifier.semantics { contentDescription = "Download the RAW files of starred photos" }) {
                        if (roomy) Icon(Icons.Filled.ArrowCircleDown, null, Modifier.size(20.dp))
                        Text("RAWs", maxLines = 1)
                    }
                }
            }
        }
    }
}

/** RAW download progress (starred RAWs or a selection), then what happened. */
@Composable
private fun RawImportBar(camera: CameraModel) {
    val progress = camera.rawImport ?: return
    Column(Modifier.padding(start = 12.dp, end = 12.dp, top = 10.dp).fillMaxWidth().surface(RoundedCornerShape(20.dp)).padding(12.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp)) {
        val message = progress.message
        if (message != null) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Icon(Icons.Filled.CheckCircle, null, Modifier.size(20.dp), tint = Theme.accent)
                Text(message, style = galleryText(13.sp), color = Theme.text, modifier = Modifier.weight(1f))
                SurfaceButton(onClick = { camera.rawImport = null }, circle = true) {
                    Icon(Icons.Filled.Close, "Close", Modifier.size(18.dp))
                }
            }
        } else {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text("RAW ${min(progress.done + 1, progress.total)} of ${progress.total}",
                        style = galleryText(15.sp, FontWeight.SemiBold), color = Theme.text)
                    progress.current?.let {
                        Text(it, style = galleryText(13.sp), color = Theme.secondary, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    }
                }
                SurfaceButton(onClick = { camera.cancelRawImport() }) { Text("Stop") }
            }
            val fraction = if (progress.total > 0) progress.done / progress.total.toFloat() else 0f
            val animated by animateFloatAsState(fraction.coerceIn(0f, 1f), label = "raw")
            Box(Modifier.fillMaxWidth().height(6.dp).clip(Pill).background(Theme.stroke)) {
                Box(Modifier.fillMaxWidth(animated).fillMaxHeight().clip(Pill).background(Theme.accent))
            }
        }
    }
}

// MARK: - Viewer (404)

/** Swipe between photos; each one zooms with a pinch or a double tap. "Done" and "12 of 42" at the top. */
@Composable
private fun PhotoViewer(camera: CameraModel, images: List<CameraImage>, start: CameraImage, onClose: () -> Unit) {
    val pager = rememberPagerState(images.indexOfFirst { it.path == start.path }.coerceAtLeast(0)) { images.size }
    Box(Modifier.fillMaxSize().background(Color.Black)) {
        HorizontalPager(pager, Modifier.fillMaxSize(), key = { images[it].path }) { index -> PhotoPage(camera, images[index]) }
        Row(Modifier.fillMaxWidth().safeDrawingPadding().padding(horizontal = 20.dp), verticalAlignment = Alignment.CenterVertically) {
            HeaderButton("Done", onClick = onClose)
            Spacer(Modifier.weight(1f))
            Text("${pager.currentPage + 1} of ${images.size}", style = galleryText(13.sp), color = Theme.secondary)
        }
        Toast(camera, Modifier.align(Alignment.TopCenter).safeDrawingPadding().padding(top = Theme.target))
    }
}

/** "25 Nov 2026, 14:05 · 8.4 MB · High Res", or "From another camera". */
private fun photoDetails(context: Context, image: CameraImage): String {
    if (image.size == 0L && image.urls == null) return "From another camera"
    val parts = mutableListOf<String>()
    if (image.date > 0) parts += DateFormat.getDateTimeInstance(DateFormat.MEDIUM, DateFormat.SHORT).format(Date(image.date))
    parts += Formatter.formatShortFileSize(context, image.size)
    if (image.looksHighRes) parts += "High Res"
    return parts.joinToString(" · ")
}

@Composable
private fun PhotoPage(camera: CameraModel, image: CameraImage) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val feedback = rememberFeedback()
    var error by remember { mutableStateOf<String?>(null) }
    val picture by produceState<ImageBitmap?>(null, image.path) {
        value = try {
            camera.preview(image).asImageBitmap()
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            error = e.message ?: "Couldn't load the photo."
            camera.thumbnail(image)?.asImageBitmap()
        }
    }
    var saving by remember { mutableStateOf(false) }
    var saveMessage by remember { mutableStateOf<String?>(null) }
    var scale by remember { mutableFloatStateOf(1f) }
    var offset by remember { mutableStateOf(Offset.Zero) }
    val starred = camera.isStarred(image)

    fun save() {
        if (saving) return
        saving = true
        saveMessage = null
        scope.launch {
            try {
                val where = camera.saveOriginal(image)
                saveMessage = "Saved the full-size original to $where."
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                saveMessage = e.message ?: "Couldn't save the photo."
            } finally {
                saving = false
            }
        }
    }

    Column(Modifier.fillMaxSize().safeDrawingPadding()) {
        Box(Modifier.weight(1f).fillMaxWidth().clipToBounds()
            .pointerInput(Unit) {
                detectTapGestures(onDoubleTap = { if (scale > 1f) { scale = 1f; offset = Offset.Zero } else scale = 3f })
            }
            // Pinch to zoom (up to 8×); one-finger pans only once zoomed, so swipes still turn the page.
            .transformable(rememberTransformableState { zoom, pan, _ ->
                scale = (scale * zoom).coerceIn(1f, 8f)
                offset = if (scale == 1f) Offset.Zero else offset + pan
            }, canPan = { scale > 1f })
            .semantics { contentDescription = "Photo. Pinch or double-tap to zoom. Swipe for the next photo" },
            contentAlignment = Alignment.Center) {
            val p = picture
            if (p != null) {
                Image(p, image.name, Modifier.fillMaxSize().graphicsLayer {
                    scaleX = scale; scaleY = scale; translationX = offset.x; translationY = offset.y
                }, contentScale = ContentScale.Fit)
            } else if (error == null) {
                CircularProgressIndicator(color = Theme.accent)
            }
            error?.let {
                Text(it, style = galleryText(13.sp), color = Theme.secondary, textAlign = TextAlign.Center,
                    modifier = Modifier.align(if (p == null) Alignment.Center else Alignment.BottomCenter).padding(24.dp)
                        .then(if (p == null) Modifier else Modifier.surface(RoundedCornerShape(14.dp)).padding(12.dp)))
            }
        }
        // 404: the name and details with the star at the top right, then Save across the card.
        val shape = RoundedCornerShape(22.dp)
        Column(Modifier.padding(start = 16.dp, end = 16.dp, top = 8.dp, bottom = 6.dp).fillMaxWidth()
            .background(Theme.surface, shape).border(1.dp, Theme.outline, shape).padding(18.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Row(verticalAlignment = Alignment.Top) {
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text(image.name, style = Theme.num(24.sp), color = Theme.text, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    Text(photoDetails(context, image), style = galleryText(13.sp), color = Theme.secondary)
                }
                Box(Modifier.offset(x = 10.dp, y = (-8).dp).size(Theme.target).clip(CircleShape)
                    .clickable(role = Role.Button) {
                        camera.toggleStar(image)
                        feedback(Feedback.Moment.SELECT)
                    }
                    .semantics { contentDescription = if (starred) "Remove star" else "Star" },
                    contentAlignment = Alignment.Center) {
                    Icon(if (starred) Icons.Filled.Star else Icons.Filled.StarBorder, null, Modifier.size(24.dp),
                        tint = if (starred) Theme.accent else Theme.text)
                }
            }
            AccentButton(onClick = ::save, modifier = Modifier.fillMaxWidth()) {
                if (saving) CircularProgressIndicator(Modifier.size(20.dp), color = Theme.onAccent, strokeWidth = 2.dp)
                else Text("Save")
            }
            saveMessage?.let {
                Text(it, style = galleryText(13.sp), color = if (it.startsWith("Saved")) Theme.green else Theme.secondary)
            }
        }
    }
}
