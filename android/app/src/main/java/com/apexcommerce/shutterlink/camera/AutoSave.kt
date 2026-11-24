package com.apexcommerce.shutterlink.camera

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

// "Save new photos to the gallery" (port of AutoSave.swift): each photo taken while connected goes to
// the phone's gallery (Pictures ▸ Shutterlink) as it's taken, like the camera makers' auto transfer.
// Drivers report a new photo with a way to download it during live view; cameras that can't send files
// during live view (LUMIX) have it saved from the card the next time it's opened. The JPEG (or HEIF) is
// saved; RAW files stay on the card for the card browser. Interval, bracketing and focus-stack sequences
// aren't auto-saved, so a time-lapse doesn't fill the gallery. MediaStore needs no permission for this.

val CameraModel.autoSaveApplies: Boolean
    get() = autoSaveNewPhotos && !interval.running && !bracket.running

fun CameraModel.changeAutoSave(on: Boolean) {
    autoSaveNewPhotos = on
    prefs.edit().putBoolean("autoSave", on).apply()
}

/**
 * A photo was just taken and `fetch` downloads it without leaving live view. Saves run one at a time,
 * after one another, so they never hold up the shutter.
 */
fun CameraModel.autoSave(name: String, fetch: suspend () -> ByteArray) {
    if (!autoSaveApplies) return
    val previous = autoSaveChain
    autoSaveChain = scope.launch {
        previous?.join()
        try {
            val data = fetch()
            if (!isPhotoFile(data)) {
                debugLog("auto-save $name: not a JPEG or HEIF (${data.size} bytes), skipped")
                return@launch
            }
            MediaSaver.save(context, data, CameraImage("", name, data.size.toLong(), 0, System.currentTimeMillis()))
            autoSavedCount += 1
            debugLog("auto-save $name: saved (${data.size / 1024} KB)")
            showToast("Saved to the gallery")
        } catch (e: CancellationException) {
            throw e
        } catch (e: Throwable) {
            debugLog("auto-save $name: $e")
            showToast("Couldn't save the new photo to the gallery")
        }
    }
}

/** A photo was just taken but the camera can't send it during live view: save it from the card later. */
fun CameraModel.autoSaveLater() {
    if (autoSaveApplies) autoSavePending += 1
}

private val autoSaveExtensions = setOf("JPG", "JPEG", "HIF", "HEIF", "HEIC")

/** After the card opens: saves the newest photos that auto-save couldn't fetch during live view. */
suspend fun CameraModel.savePendingAutoSaves() {
    if (autoSavePending <= 0) return
    val count = autoSavePending
    autoSavePending = 0
    if (!autoSaveNewPhotos) return
    val newest = images
        .filter { !it.isDirectory && it.fileExtension in autoSaveExtensions }
        .sortedWith(compareByDescending<CameraImage> { it.date }.thenByDescending { it.name })
        .take(count)
    var saved = 0
    for (image in newest.reversed()) {
        try {
            saveOriginal(image)
            saved += 1
        } catch (e: CancellationException) {
            throw e
        } catch (e: Throwable) {
            debugLog("auto-save ${image.name}: $e")
        }
    }
    autoSavedCount += saved
    if (saved > 0) showToast(if (saved == 1) "Saved the new photo to the gallery" else "Saved $saved new photos to the gallery")
}

/** JPEG starts FF D8; HEIF has "ftyp" at byte 4. */
fun isPhotoFile(data: ByteArray): Boolean =
    (data.size > 3 && data[0] == 0xFF.toByte() && data[1] == 0xD8.toByte()) || (data.size > 12 && String(data, 4, 4, Charsets.US_ASCII) == "ftyp")

/** A name for a photo the camera sends without its card file name (Olympus' last JPEG). */
fun CameraModel.autoSaveName(ext: String = "JPG"): String {
    val stamp = SimpleDateFormat("yyyyMMdd-HHmmss", Locale.US).format(Date())
    val model = (cameraName ?: brand.title).replace(" ", "-")
    return "$model-$stamp.$ext"
}
