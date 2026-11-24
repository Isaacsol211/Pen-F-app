package com.apexcommerce.shutterlink.camera

import android.annotation.SuppressLint
import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.wifi.WifiManager
import android.net.wifi.WifiNetworkSpecifier
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withTimeoutOrNull
import java.net.Inet4Address
import kotlin.coroutines.resume

/**
 * Android's side of "talk to the camera over its own Wi-Fi".
 *
 * A camera's access point has no internet, so Android keeps mobile data as the default network and
 * would send the app's requests there, where 192.168.0.10 doesn't exist. The app therefore asks for
 * the Wi-Fi network explicitly (requestNetwork without the INTERNET capability, which also stops
 * Android from dropping a Wi-Fi it considers useless) and binds the whole process to it with
 * bindProcessToNetwork, so HTTP, TCP (PTP/IP) and the UDP live-view socket all use the camera's Wi-Fi.
 *
 * It can also join a camera's network itself with WifiNetworkSpecifier (Android shows its own
 * "Connect to this device?" dialog); that network exists only while the app holds the request.
 */
@SuppressLint("MissingPermission")
object CameraNetwork {
    private lateinit var cm: ConnectivityManager
    private lateinit var wifi: WifiManager

    private var wifiCallback: ConnectivityManager.NetworkCallback? = null
    private var joinCallback: ConnectivityManager.NetworkCallback? = null
    @Volatile var boundNetwork: Network? = null
        private set
    /** The network the app joined itself (WifiNetworkSpecifier), while it holds it. */
    @Volatile var joinedSsid: String? = null
        private set

    fun init(context: Context) {
        cm = context.getSystemService(ConnectivityManager::class.java)
        wifi = context.applicationContext.getSystemService(WifiManager::class.java)
    }

    /** The phone's current Wi-Fi network, internet or not. */
    @Suppress("DEPRECATION")
    fun wifiNetwork(): Network? {
        boundNetwork?.let { n -> if (cm.getNetworkCapabilities(n) != null) return n }
        return cm.allNetworks.firstOrNull { cm.getNetworkCapabilities(it)?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) == true }
    }

    /** IPv4 address of this phone on Wi-Fi, or null when it isn't on Wi-Fi. */
    fun wifiAddress(): String? {
        val network = wifiNetwork() ?: return null
        return cm.getLinkProperties(network)?.linkAddresses
            ?.firstOrNull { it.address is Inet4Address }?.address?.hostAddress
    }

    /**
     * The Wi-Fi network's name. Android only reveals it with location permission and location on;
     * otherwise null.
     */
    @Suppress("DEPRECATION")
    fun wifiSsid(): String? {
        joinedSsid?.let { return it }
        val ssid = runCatching { wifi.connectionInfo?.ssid }.getOrNull() ?: return null
        if (ssid == WifiManager.UNKNOWN_SSID || ssid.isBlank()) return null
        return ssid.removeSurrounding("\"")
    }

    /**
     * Holds on to the Wi-Fi network and binds the app to it. Returns false when the phone isn't on
     * Wi-Fi (the app then uses whatever network Android picks, e.g. the emulator's).
     */
    suspend fun acquireWifi(timeoutMs: Long = 4000): Boolean {
        boundNetwork?.let { if (cm.getNetworkCapabilities(it) != null) return true }
        val request = NetworkRequest.Builder()
            .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
            .removeCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            .build()
        val network = withTimeoutOrNull(timeoutMs) {
            suspendCancellableCoroutine { cont ->
                val callback = object : ConnectivityManager.NetworkCallback() {
                    override fun onAvailable(network: Network) {
                        if (cont.isActive) cont.resume(network)
                    }

                    override fun onLost(network: Network) {
                        if (network == boundNetwork) {
                            debugLog("Wi-Fi network lost")
                            unbind()
                        }
                    }
                }
                releaseWifiCallback()
                wifiCallback = callback
                runCatching { cm.requestNetwork(request, callback) }.onFailure {
                    debugLog("requestNetwork failed: $it")
                    if (cont.isActive) cont.resume(null)
                }
            }
        }
        if (network == null) {
            releaseWifiCallback()
            return false
        }
        bind(network)
        return true
    }

    private fun bind(network: Network) {
        val ok = cm.bindProcessToNetwork(network)
        boundNetwork = if (ok) network else null
        debugLog("bindProcessToNetwork($network) → $ok")
    }

    fun unbind() {
        cm.bindProcessToNetwork(null)
        boundNetwork = null
    }

    private fun releaseWifiCallback() {
        wifiCallback?.let { runCatching { cm.unregisterNetworkCallback(it) } }
        wifiCallback = null
    }

    /** Lets go of the camera's network when the app disconnects (the joined one too). */
    fun release() {
        unbind()
        releaseWifiCallback()
    }

    /**
     * Joins a camera's Wi-Fi from the app (Android 10+). Android asks the user to confirm; the network
     * stays up while the app holds the request, and the app is bound to it. Returns an error message,
     * or null on success.
     */
    suspend fun join(ssid: String, passphrase: String?, timeoutMs: Long = 45_000): String? {
        leaveJoined()
        val specifier = WifiNetworkSpecifier.Builder().setSsid(ssid).apply {
            if (!passphrase.isNullOrEmpty()) setWpa2Passphrase(passphrase)
        }.build()
        val request = NetworkRequest.Builder()
            .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
            .removeCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            .setNetworkSpecifier(specifier)
            .build()
        val result = withTimeoutOrNull(timeoutMs) {
            suspendCancellableCoroutine<Network?> { cont ->
                val callback = object : ConnectivityManager.NetworkCallback() {
                    override fun onAvailable(network: Network) {
                        if (cont.isActive) cont.resume(network)
                    }

                    override fun onUnavailable() {
                        if (cont.isActive) cont.resume(null)
                    }

                    override fun onLost(network: Network) {
                        if (network == boundNetwork) unbind()
                        joinedSsid = null
                    }
                }
                joinCallback = callback
                runCatching { cm.requestNetwork(request, callback) }.onFailure {
                    debugLog("join requestNetwork failed: $it")
                    if (cont.isActive) cont.resume(null)
                }
            }
        }
        if (result == null) {
            leaveJoined()
            return "Couldn't join $ssid. Check the network name and password the camera shows, and that its Wi-Fi is on."
        }
        joinedSsid = ssid
        releaseWifiCallback()
        bind(result)
        return null
    }

    fun leaveJoined() {
        joinCallback?.let { runCatching { cm.unregisterNetworkCallback(it) } }
        joinCallback = null
        joinedSsid = null
    }

    /** Emulator or loopback addresses: the Mac running the mock cameras. */
    fun isLocalTestHost(host: String): Boolean {
        val ip = host.substringBefore(':')
        return ip.startsWith("127.") || ip == "10.0.2.2" || ip == "localhost"
    }
}
