package com.apexcommerce.shutterlink.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AcUnit
import androidx.compose.material.icons.filled.BackHand
import androidx.compose.material.icons.filled.Fluorescent
import androidx.compose.material.icons.filled.WbCloudy
import androidx.compose.material.icons.filled.WbIncandescent
import androidx.compose.material.icons.filled.WbShade
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.Bolt
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.DarkMode
import androidx.compose.material.icons.filled.DirectionsCar
import androidx.compose.material.icons.filled.DirectionsRun
import androidx.compose.material.icons.filled.Filter
import androidx.compose.material.icons.filled.FlutterDash
import androidx.compose.material.icons.filled.Landscape
import androidx.compose.material.icons.filled.LocalFlorist
import androidx.compose.material.icons.filled.NightsStay
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material.icons.filled.Waves
import androidx.compose.material.icons.filled.WbSunny
import androidx.compose.material.icons.filled.WbTwilight
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.apexcommerce.shutterlink.camera.CameraModel
import com.apexcommerce.shutterlink.camera.SceneSuggestion
import com.apexcommerce.shutterlink.camera.dismissSceneSuggestion

private fun icon(name: String): ImageVector = when (name) {
    "fireworks" -> Icons.Filled.AutoAwesome
    "moon" -> Icons.Filled.DarkMode
    "astro" -> Icons.Filled.NightsStay
    "lightning" -> Icons.Filled.Bolt
    "nd" -> Icons.Filled.Filter
    "water" -> Icons.Filled.Waves
    "car" -> Icons.Filled.DirectionsCar
    "bird" -> Icons.Filled.FlutterDash
    "action" -> Icons.Filled.DirectionsRun
    "macro" -> Icons.Filled.LocalFlorist
    "warning" -> Icons.Filled.Warning
    "snow" -> Icons.Filled.AcUnit
    "sunset" -> Icons.Filled.WbTwilight
    "landscape" -> Icons.Filled.Landscape
    "shake" -> Icons.Filled.BackHand
    "lamp" -> Icons.Filled.WbIncandescent
    "tube" -> Icons.Filled.Fluorescent
    "shade" -> Icons.Filled.WbShade
    "cloud" -> Icons.Filled.WbCloudy
    else -> Icons.Filled.WbSunny
}

/**
 * The scene assistant's suggestion, floating over the bottom of live view: what it sees, why, and one
 * button. Nothing changes until that button is tapped; the cross keeps it away for a while.
 */
@Composable
fun SceneSuggestionPill(camera: CameraModel, suggestion: SceneSuggestion, onApply: () -> Unit, modifier: Modifier = Modifier) {
    val enabled = !camera.presetRunning && !camera.isShooting
    Row(
        modifier.widthIn(max = 520.dp).fillMaxWidth().surface(RoundedCornerShape(22.dp), overImage = true)
            .padding(start = 8.dp, end = 4.dp)
            .semantics { contentDescription = "${suggestion.title}. ${suggestion.detail}" },
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Box(Modifier.size(30.dp).background(Theme.accent, CircleShape), contentAlignment = Alignment.Center) {
            Icon(icon(suggestion.icon), null, Modifier.size(17.dp), tint = Theme.onAccent)
        }
        Column(Modifier.weight(1f).padding(vertical = 6.dp)) {
            Text(suggestion.title, fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
            Text(suggestion.detail, color = Theme.secondary, fontSize = 12.sp, maxLines = 2, lineHeight = 15.sp)
        }
        Box(Modifier.heightIn(min = Theme.target).clickable(enabled = enabled, onClick = onApply), contentAlignment = Alignment.Center) {
            Text(suggestion.actionTitle, color = Theme.onAccent, fontSize = 12.sp, fontWeight = FontWeight.Bold,
                modifier = Modifier.alpha(if (enabled) 1f else 0.5f).background(Theme.accent, Pill).padding(horizontal = 12.dp, vertical = 8.dp))
        }
        Box(Modifier.size(28.dp, Theme.target).clickable { camera.dismissSceneSuggestion() }
            .semantics { contentDescription = "Not now" }, contentAlignment = Alignment.Center) {
            Icon(Icons.Filled.Close, null, Modifier.size(16.dp), tint = Theme.secondary)
        }
    }
}
