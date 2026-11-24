package com.apexcommerce.shutterlink.ui

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.gestures.rememberTransformableState
import androidx.compose.foundation.gestures.transformable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Download
import androidx.compose.material.icons.filled.PhotoLibrary
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.SdCard
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.StarBorder
import androidx.compose.material.icons.filled.Videocam
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
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
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.apexcommerce.shutterlink.camera.CameraImage
import com.apexcommerce.shutterlink.camera.CameraModel
import com.apexcommerce.shutterlink.camera.MediaSaver
import com.apexcommerce.shutterlink.camera.cancelRawImport
import com.apexcommerce.shutterlink.camera.downloadStarredRaws
import com.apexcommerce.shutterlink.camera.isStarred
import com.apexcommerce.shutterlink.camera.toggleStar
import kotlinx.coroutines.launch

/**
 * Browses the SD card (port of GalleryView.swift). The camera has to be in playback mode for this,
 * so live view stops while it's open and restarts on Done.
 */
@Composable
fun GalleryScreen(camera: CameraModel, onDone: () -> Unit) {
    val scope = rememberCoroutineScope()
    var starredOnly by remember { mutableStateOf(false) }
    var viewing by remember { mutableStateOf<CameraImage?>(null) }
    LaunchedEffect(Unit) { camera.openGallery() }
    BackHandler { if (viewing != null) viewing = null else onDone() }

    val visible = if (starredOnly) camera.images.filter { camera.isStarred(it) } else camera.images
    val starredCount = camera.images.count { camera.isStarred(it) }

    viewing?.let { start ->
        PhotoPager(camera, visible.ifEmpty { listOf(start) }, start) { viewing = null }
        return
    }

    Column(Modifier.fillMaxSize().background(Theme.background).safeDrawingPadding()) {
        Row(Modifier.fillMaxWidth().padding(horizontal = 10.dp, vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
            SurfaceButton(onClick = { scope.launch { camera.openGallery() } }, circle = true, enabled = !camera.galleryLoading) {
                Icon(Icons.Filled.Refresh, "Reload")
            }
            Text(if (camera.images.isEmpty()) "On the card" else "On the card · ${camera.images.size}", fontSize = 17.sp,
                fontWeight = FontWeight.SemiBold, textAlign = TextAlign.Center, modifier = Modifier.weight(1f))
            SurfaceButton(onClick = onDone, circle = true) { Icon(Icons.Filled.Check, "Done") }
        }
        Box(Modifier.weight(1f)) {
            val error = camera.galleryError
            when {
                camera.galleryLoading && camera.images.isEmpty() -> Centered {
                    CircularProgressIndicator(color = Theme.accent)
                    Text("Reading the card…", color = Theme.secondary)
                }
                error != null && camera.images.isEmpty() -> EmptyState(Icons.Filled.SdCard, "Couldn't read the card", error)
                camera.images.isEmpty() -> EmptyState(Icons.Filled.PhotoLibrary, "No photos", "Nothing on the card yet.")
                starredOnly && starredCount == 0 ->
                    EmptyState(Icons.Filled.StarBorder, "No starred photos", "Tap and hold a photo to star it, or use the star when viewing it.")
                else -> LazyVerticalGrid(GridCells.Adaptive(104.dp), Modifier.fillMaxSize(),
                    horizontalArrangement = Arrangement.spacedBy(3.dp), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                    for (folder in camera.cardFolders) {
                        val files = visible.filter { it.directory == folder.path }
                        if (starredOnly && files.isEmpty()) continue
                        item(key = "h:" + folder.path, span = { GridItemSpan(maxLineSpan) }) {
                            Column(Modifier.padding(horizontal = 14.dp, vertical = 10.dp)) {
                                Row(verticalAlignment = Alignment.CenterVertically) {
                                    CapsLabel(folder.name, color = Color.White)
                                    Spacer(Modifier.weight(1f))
                                    Text("${folder.count}", color = Theme.tertiary, style = monoStyle(12.sp))
                                }
                                if (folder.isForeign && folder.count == 0) {
                                    Text("Made by another camera; this camera doesn't list its files over Wi-Fi.", color = Theme.tertiary, fontSize = 12.sp)
                                }
                            }
                        }
                        items(files, key = { it.path }) { image -> ThumbnailCell(camera, image) { viewing = image } }
                    }
                }
            }
        }
        BottomBar(camera, starredOnly, starredCount, { starredOnly = !starredOnly })
    }
}

@Composable
private fun Centered(content: @Composable () -> Unit) {
    Column(Modifier.fillMaxSize().padding(32.dp), horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(12.dp, Alignment.CenterVertically)) { content() }
}

@Composable
private fun EmptyState(icon: ImageVector, title: String, detail: String) = Centered {
    Icon(icon, null, Modifier.size(40.dp), tint = Theme.secondary)
    Text(title, fontSize = 20.sp, fontWeight = FontWeight.Bold)
    Text(detail, color = Theme.secondary, textAlign = TextAlign.Center)
}

@Composable
private fun BottomBar(camera: CameraModel, starredOnly: Boolean, starredCount: Int, toggleStarred: () -> Unit) {
    Column(Modifier.fillMaxWidth().padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        camera.rawImport?.let { progress ->
            Column(Modifier.fillMaxWidth().surface(RoundedCornerShape(16.dp)).padding(12.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                val message = progress.message
                if (message != null) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(message, fontSize = 13.sp, modifier = Modifier.weight(1f))
                        SurfaceButton(onClick = { camera.rawImport = null }) { Text("OK") }
                    }
                } else {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text("RAW ${progress.done + 1} of ${progress.total}${progress.current?.let { " · $it" } ?: ""}", fontSize = 13.sp, modifier = Modifier.weight(1f))
                        SurfaceButton(onClick = { camera.cancelRawImport() }) { Text("Stop") }
                    }
                    LinearProgressIndicator(progress = { if (progress.total > 0) progress.done / progress.total.toFloat() else 0f },
                        modifier = Modifier.fillMaxWidth(), color = Theme.accent, trackColor = Color.White.copy(alpha = 0.15f))
                }
            }
        }
        if (camera.images.isNotEmpty()) {
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                SurfaceButton(onClick = toggleStarred, modifier = Modifier.weight(1f), tint = if (starredOnly) Theme.accent.copy(alpha = 0.22f) else null) {
                    Icon(if (starredOnly) Icons.Filled.Star else Icons.Filled.StarBorder, null, tint = if (starredOnly) Theme.accent else Color.White)
                    Text(if (starredOnly) "Starred ($starredCount)" else "All photos", fontWeight = FontWeight.SemiBold)
                }
                SurfaceButton(onClick = { camera.downloadStarredRaws() }, enabled = camera.rawImportJob == null) {
                    Icon(Icons.Filled.Download, "Download the RAW files of starred photos")
                    Text("RAWs", fontWeight = FontWeight.SemiBold)
                }
            }
        }
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun ThumbnailCell(camera: CameraModel, image: CameraImage, onOpen: () -> Unit) {
    val haptics = LocalHapticFeedback.current
    val thumb by produceState<ImageBitmap?>(null, image.path) { value = camera.thumbnail(image)?.asImageBitmap() }
    val starred = camera.isStarred(image)
    Box(Modifier.aspectRatio(1f).background(Theme.surface).combinedClickable(
        onClick = onOpen,
        onLongClick = {
            haptics.performHapticFeedback(HapticFeedbackType.LongPress)
            camera.toggleStar(image)
        },
    )) {
        thumb?.let { Image(it, image.name, Modifier.fillMaxSize(), contentScale = ContentScale.Crop) }
        val ext = image.fileExtension
        val badge = when {
            image.isVideo -> null
            ext in MediaSaver.rawExtensions -> ext
            ext != "JPG" && ext != "JPEG" -> ext
            image.size > 30_000_000 -> "50 MP"
            else -> null
        }
        if (image.isVideo) Icon(Icons.Filled.Videocam, "Video", Modifier.align(Alignment.BottomStart).padding(5.dp).size(16.dp))
        badge?.let {
            Text(it, color = Color.White, style = monoStyle(9.sp, FontWeight.Bold),
                modifier = Modifier.align(Alignment.BottomStart).padding(4.dp).background(Color.Black.copy(alpha = 0.6f), RoundedCornerShape(4.dp))
                    .padding(horizontal = 4.dp, vertical = 1.dp))
        }
        if (starred) Icon(Icons.Filled.Star, "Starred", Modifier.align(Alignment.TopEnd).padding(4.dp).size(16.dp), tint = Theme.accent)
    }
}

/** Swipe between photos, pinch or double-tap to zoom, star and save. */
@Composable
private fun PhotoPager(camera: CameraModel, images: List<CameraImage>, start: CameraImage, onClose: () -> Unit) {
    val scope = rememberCoroutineScope()
    val pager = rememberPagerState(images.indexOf(start).coerceAtLeast(0)) { images.size }
    val current = images.getOrNull(pager.currentPage) ?: start
    var saving by remember { mutableStateOf(false) }
    Box(Modifier.fillMaxSize().background(Color.Black)) {
        HorizontalPager(pager, Modifier.fillMaxSize(), key = { images[it].path }) { index -> PhotoPage(camera, images[index]) }
        Row(Modifier.fillMaxWidth().safeDrawingPadding().padding(10.dp), verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            SurfaceButton(onClick = onClose, circle = true) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Back") }
            Text(current.name, style = monoStyle(13.sp), modifier = Modifier.weight(1f).surface(Pill).padding(horizontal = 12.dp, vertical = 8.dp))
            val starred = camera.isStarred(current)
            SurfaceButton(onClick = { camera.toggleStar(current) }, circle = true) {
                Icon(if (starred) Icons.Filled.Star else Icons.Filled.StarBorder, if (starred) "Remove star" else "Star",
                    tint = if (starred) Theme.accent else Color.White)
            }
            SurfaceButton(onClick = {
                saving = true
                scope.launch {
                    try {
                        val where = camera.saveOriginal(current)
                        camera.showToast("Saved to $where")
                    } catch (e: Exception) {
                        camera.showToast(e.message ?: "Couldn't save")
                    } finally {
                        saving = false
                    }
                }
            }, enabled = !saving) {
                if (saving) CircularProgressIndicator(color = Theme.accent, strokeWidth = 2.dp, modifier = Modifier.size(16.dp))
                else Icon(Icons.Filled.Download, null)
                Text("Save", fontWeight = FontWeight.SemiBold)
            }
        }
        Toast(camera, Modifier.align(Alignment.BottomCenter).padding(bottom = 40.dp))
    }
}

@Composable
private fun PhotoPage(camera: CameraModel, image: CameraImage) {
    var error by remember { mutableStateOf<String?>(null) }
    val picture by produceState<ImageBitmap?>(null, image.path) {
        value = try {
            camera.preview(image).asImageBitmap()
        } catch (e: Exception) {
            error = e.message
            camera.thumbnail(image)?.asImageBitmap()
        }
    }
    var scale by remember { mutableFloatStateOf(1f) }
    var offset by remember { mutableStateOf(Offset.Zero) }
    Box(Modifier.fillMaxSize().clipToBounds()
        .pointerInput(Unit) { detectTapGestures(onDoubleTap = { if (scale > 1f) { scale = 1f; offset = Offset.Zero } else scale = 2.5f }) }
        // Pinch to zoom; one-finger pans only once zoomed, so swipes still turn the page.
        .transformable(rememberTransformableState { zoom, pan, _ ->
            scale = (scale * zoom).coerceIn(1f, 6f)
            offset = if (scale == 1f) Offset.Zero else offset + pan
        }, canPan = { scale > 1f }),
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
            Text(it, color = Theme.secondary, fontSize = 13.sp, textAlign = TextAlign.Center,
                modifier = Modifier.align(Alignment.BottomCenter).padding(24.dp).surface(RoundedCornerShape(14.dp)).padding(12.dp))
        }
    }
}
