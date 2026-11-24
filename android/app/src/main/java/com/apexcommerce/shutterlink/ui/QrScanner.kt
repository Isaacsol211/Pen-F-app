package com.apexcommerce.shutterlink.ui

import androidx.compose.runtime.Composable

/**
 * Opens a QR-code scanner and hands back the code's text. Returns null while this build has no
 * scanner: the scan buttons then stay hidden and the typed network name and password do the job.
 *
 * Waiting on the choice of scanning library (Google code scanner, ML Kit barcode scanning or ZXing);
 * whichever is added only has to fill this in.
 */
@Composable
fun rememberQrScanner(onCode: (String) -> Unit, onCancel: () -> Unit = {}): (() -> Unit)? = null
