package com.apexcommerce.shutterlink

import android.content.Intent
import android.graphics.Color
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.SystemBarStyle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalView
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.ProcessLifecycleOwner
import com.apexcommerce.shutterlink.camera.CameraBrand
import com.apexcommerce.shutterlink.camera.CameraModel
import com.apexcommerce.shutterlink.camera.CameraNetwork
import com.apexcommerce.shutterlink.camera.ConnectionPhase
import com.apexcommerce.shutterlink.camera.DriverSelfTest
import com.apexcommerce.shutterlink.ui.ConnectScreen
import com.apexcommerce.shutterlink.ui.RemoteScreen
import com.apexcommerce.shutterlink.ui.ShutterlinkTheme
import com.apexcommerce.shutterlink.ui.Theme
import kotlinx.coroutines.launch

/** The single activity: the connect screen while disconnected, the remote while connected. */
class MainActivity : ComponentActivity() {
    private lateinit var camera: CameraModel

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge(SystemBarStyle.dark(Color.BLACK), SystemBarStyle.dark(Color.BLACK))
        camera = CameraModel.get(this)

        // Live view stops while the app is in the background and resumes when it's back.
        ProcessLifecycleOwner.get().lifecycle.addObserver(object : DefaultLifecycleObserver {
            override fun onStart(owner: LifecycleOwner) = camera.appBackgrounded(false)
            override fun onStop(owner: LifecycleOwner) = camera.appBackgrounded(true)
        })

        setContent {
            ShutterlinkTheme { App(camera) }
        }
        if (savedInstanceState == null) handleDebugIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleDebugIntent(intent)
    }

    /**
     * Debug builds: `--es selfTest <brand|auto> --es host 10.0.2.2:<port>` runs the driver self-test,
     * `--es connect <brand|auto> --es host …` just connects. Both only accept the Mac running the mocks.
     */
    private fun handleDebugIntent(intent: Intent?) {
        if (!BuildConfig.DEBUG || intent == null) return
        val host = intent.getStringExtra("host") ?: return
        if (!CameraNetwork.isLocalTestHost(host)) return
        camera.forceWifiBinding = intent.getBooleanExtra("bindWifi", false)
        // "night_sky:0.97,sky:0.9" stands in for ML Kit's labels, to try the scene suggestions.
        camera.sceneLabelOverride = intent.getStringExtra("sceneLabels")?.split(",")?.mapNotNull { pair ->
            val parts = pair.split(":")
            parts.getOrNull(1)?.toFloatOrNull()?.let { parts[0] to it }
        }?.toMap()
        intent.getStringExtra("selfTest")?.let { brand ->
            camera.scope.launch { DriverSelfTest.run(camera, brand, host) }
            return
        }
        intent.getStringExtra("connect")?.let { brand ->
            if (camera.phase != ConnectionPhase.DISCONNECTED) return
            camera.selectBrand(CameraBrand.fromId(if (brand == "lumix") "panasonic" else brand))
            camera.host = host
            camera.connectInBackground()
        }
    }
}

@Composable
fun App(camera: CameraModel) {
    // The phone stays awake while connected (live view, long exposures, interval runs).
    val view = LocalView.current
    val connected = camera.phase == ConnectionPhase.CONNECTED
    DisposableEffect(connected) {
        view.keepScreenOn = connected
        onDispose { view.keepScreenOn = false }
    }
    Box(Modifier.fillMaxSize().background(Theme.background)) {
        if (connected) RemoteScreen(camera) else ConnectScreen(camera)
    }
}
