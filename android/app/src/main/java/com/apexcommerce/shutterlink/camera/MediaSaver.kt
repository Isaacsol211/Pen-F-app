package com.apexcommerce.shutterlink.camera

import android.content.ContentValues
import android.content.Context
import android.os.Environment
import android.provider.MediaStore
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * Saves card files on the phone through MediaStore (Android 10+ needs no storage permission for
 * files the app adds itself). Photos and videos go to Pictures/Shutterlink and show up in the
 * gallery apps; RAW files (.ORF, .RW2, .NEF…) go to Download/Shutterlink/RAW, since most gallery
 * apps can't show them. The iOS app does the same with Photos and Files.
 */
object MediaSaver {
    val rawExtensions = setOf("ORF", "RW2", "DNG", "NEF", "NRW", "CR3", "CR2", "ARW", "RAF")

    /** Returns where the file went, for a toast. */
    suspend fun save(context: Context, data: ByteArray, image: CameraImage): String = withContext(Dispatchers.IO) {
        val resolver = context.contentResolver
        val ext = image.fileExtension
        val (collection, mime, folder) = when {
            image.isVideo -> Triple(
                MediaStore.Video.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY),
                if (ext == "MOV") "video/quicktime" else "video/mp4",
                Environment.DIRECTORY_MOVIES + "/Shutterlink",
            )
            ext in rawExtensions -> Triple(
                MediaStore.Downloads.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY),
                "application/octet-stream",
                Environment.DIRECTORY_DOWNLOADS + "/Shutterlink/RAW",
            )
            else -> Triple(
                MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY),
                if (ext == "HEIC" || ext == "HIF" || ext == "HEIF") "image/heic" else "image/jpeg",
                Environment.DIRECTORY_PICTURES + "/Shutterlink",
            )
        }
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, image.name)
            put(MediaStore.MediaColumns.MIME_TYPE, mime)
            put(MediaStore.MediaColumns.RELATIVE_PATH, folder)
            put(MediaStore.MediaColumns.IS_PENDING, 1)
            if (image.date > 0 && !image.isVideo && ext !in rawExtensions) {
                put(MediaStore.Images.Media.DATE_TAKEN, image.date)
            }
        }
        val uri = resolver.insert(collection, values) ?: throw CameraException("The phone refused to save ${image.name}.")
        try {
            resolver.openOutputStream(uri)?.use { it.write(data) } ?: throw CameraException("Couldn't write ${image.name}.")
            resolver.update(uri, ContentValues().apply { put(MediaStore.MediaColumns.IS_PENDING, 0) }, null, null)
        } catch (e: Exception) {
            resolver.delete(uri, null, null)
            throw e
        }
        // "Pictures ▸ Shutterlink", "Download ▸ Shutterlink ▸ RAW"…
        folder.replace("/", " ▸ ")
    }
}
