package com.apexcommerce.shutterlink.ui

import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.ui.platform.LocalContext
import com.apexcommerce.shutterlink.camera.debugLog
import com.google.android.gms.common.ConnectionResult
import com.google.android.gms.common.GoogleApiAvailability
import com.google.android.gms.common.moduleinstall.ModuleInstall
import com.google.android.gms.common.moduleinstall.ModuleInstallRequest
import com.google.mlkit.common.MlKitException
import com.google.mlkit.vision.barcode.common.Barcode
import com.google.mlkit.vision.codescanner.GmsBarcodeScannerOptions
import com.google.mlkit.vision.codescanner.GmsBarcodeScanning

/**
 * Opens Google's code scanner (it runs in Google Play services with its own camera screen, so the app
 * needs no camera permission) and hands back the QR code's text. Returns null on phones without Google
 * Play services: the scan buttons then stay hidden and the network name and password are typed instead.
 */
@Composable
fun rememberQrScanner(onCode: (String) -> Unit, onError: (String) -> Unit): (() -> Unit)? {
    val context = LocalContext.current
    val available = remember {
        runCatching { GoogleApiAvailability.getInstance().isGooglePlayServicesAvailable(context) == ConnectionResult.SUCCESS }
            .getOrDefault(false)
    }
    if (!available) return null
    val code by rememberUpdatedState(onCode)
    val error by rememberUpdatedState(onError)
    val scanner = remember {
        GmsBarcodeScanning.getClient(
            context,
            GmsBarcodeScannerOptions.Builder().setBarcodeFormats(Barcode.FORMAT_QR_CODE).enableAutoZoom().build(),
        )
    }
    // The scanner is a Play services module. A Play Store install fetches it with the app (see the
    // manifest); otherwise ask for it now, so it's there by the time the button is tapped.
    LaunchedEffect(scanner) { requestScannerModule(context, scanner) }
    return remember(scanner) {
        {
            scanner.startScan()
                .addOnSuccessListener { barcode ->
                    val text = barcode.rawValue
                    if (text.isNullOrBlank()) error("That QR code has no text Shutterlink can read. Type the network name and password instead.")
                    else code(text)
                }
                .addOnCanceledListener { debugLog("QR scan cancelled") }
                .addOnFailureListener { e ->
                    debugLog("QR scan failed: $e (code ${(e as? MlKitException)?.errorCode})")
                    val downloading = (e as? MlKitException)?.errorCode == MlKitException.UNAVAILABLE ||
                        e.message?.contains("download", ignoreCase = true) == true
                    if (downloading) requestScannerModule(context, scanner)
                    error(if (downloading) "Google Play services is still downloading the scanner (once only). Try again in a minute, or type the network name and password."
                        else "Couldn't open the scanner. Type the network name and password instead.")
                }
            Unit
        }
    }
}

/** Asks Google Play services to download the scanner module if it doesn't have it yet. */
private fun requestScannerModule(context: android.content.Context, scanner: com.google.mlkit.vision.codescanner.GmsBarcodeScanner) {
    val modules = ModuleInstall.getClient(context)
    modules.areModulesAvailable(scanner)
        .addOnSuccessListener { response ->
            if (response.areModulesAvailable()) return@addOnSuccessListener
            debugLog("QR scanner module: downloading")
            modules.installModules(ModuleInstallRequest.newBuilder().addApi(scanner).build())
                .addOnSuccessListener { debugLog("QR scanner module: ${if (it.areModulesAlreadyInstalled()) "installed" else "download started"}") }
                .addOnFailureListener { e -> debugLog("QR scanner module: $e") }
        }
        .addOnFailureListener { e -> debugLog("QR scanner module check: $e") }
}
