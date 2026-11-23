# Shutterlink

An iPhone (and Apple Watch) remote for cameras, over the camera's own Wi-Fi. It started as a remote for the
Olympus PEN-F and now covers **every Wi-Fi Olympus / OM System and Panasonic LUMIX body**, with experimental
drivers for **Nikon, Canon and Sony**. Pick the brand on the Connect screen, or leave it on **Auto** and the app
works out which camera it's talking to. Only the PEN-F has been tried on a real camera so far.

## Supported cameras

Each brand has a driver behind one interface (`Camera/CameraDriver.swift`) that says what the camera can do,
so the app hides what a body can't (live-view size, Bulb, video, clock sync, High Res Shot, card browser…).
On top of that, a per-model table (`Camera/ModelProfiles.swift`) holds what a camera doesn't report about
itself: which bodies have High Res Shot, which compacts have fixed or physical controls, pairing quirks, and
advice shown once after connecting (e.g. "set Wi-Fi to Private" on the E-M1). Bodies missing from the table
still connect; they just get the brand's defaults.

**Auto** picks the brand from the camera network's address range (Olympus 192.168.0.x, LUMIX 192.168.54.x,
Sony 192.168.122.x, Nikon/Canon 192.168.1.x), then asks each candidate a read-only question in its own protocol.

**Bluetooth is never needed.** Every Olympus/OM and LUMIX body here lets the phone join the camera's own Wi-Fi
directly; on the newer ones Bluetooth is optional (OM System: Device Connection works with Bluetooth off; LUMIX
Sync bodies: Remote Shooting & View works over Wi-Fi alone). A shutter-only Bluetooth fallback for bodies
without Wi-Fi remote isn't built; the driver interface leaves room for it.

| Brand | How the phone joins | Transport | What works in the app | Status |
|---|---|---|---|---|
| Olympus / OM System | Camera's access point (Connection to Smartphone / Device Connection: SSID + password + QR on screen) | OI.Share HTTP at 192.168.0.10, RTP live view over UDP. Each body lists its own commands, live-view sizes and settable properties, which the app reads | Live view, every Wi-Fi-settable setting, Bulb / Live Time / Live Composite, video, last-shot review, card with RAW download, clock sync, High Res Shot guide where the body has it | PEN-F **tested on hardware**; the rest researched (table below) |
| Panasonic LUMIX | Camera's access point (Remote Shooting & View); approve this iPhone on the camera the first time | `cam.cgi` HTTP at 192.168.54.1, one JPEG per UDP datagram. Newer bodies: `req_acc_g`/`req_acc_e` pairing and an `X-SESSION_ID` header | Live view, aperture/shutter/ISO/EV/WB (where the body allows), tap AF, shoot, Bulb, video (app's Video switch), card with RAW download | GH5 **mock only**; the rest researched (table below). Newer pairing unverified on any real camera |
| Nikon | Z / SnapBridge bodies: **Connect to smart device ▸ Wi-Fi connection ▸ Establish Wi-Fi connection** (no Bluetooth pairing); older DSLRs: Wi-Fi ▸ Network connection ▸ Enable. Not "Connect to PC". Turn off live view on the camera first | PTP/IP on TCP 15740 at 192.168.1.1 | Live view, aperture/shutter/ISO (incl. auto)/EV/WB, tap AF, shoot, video (Z), last-shot review, card with RAW download in 1 MB pieces. No Bulb/Time | **Experimental**, mock only (Z 6II-style and D750-style). Third-party clients have worked on Z6/Z7, Zfc, Z30, D5300, D750, D7200; Z6III/Zf/Z8/Z9 unconfirmed |
| Canon | **CCAPI must be activated once per camera** with Canon's free tool and developer account; then the camera's CCAPI Wi-Fi connection. Turn HTTPS and user authentication off; the camera shows its "CCAPI top URL" | CCAPI: REST + JSON on port 8080 | Live view (polled JPEGs), aperture/shutter/ISO/EV/WB, AF point, shoot, Bulb, video, last-shot review, card | **Experimental**, mock only (EOS R6). CCAPI bodies: R3, R5, R6, R6 II, R7, R8, R10, R50, R100, RP, 90D, 850D, 250D, M50 II, M200, G5 X II, G7 X III, SX70 HS (activation); R1, R5 II, R50 V, V10 (built in). Not the original EOS R |
| Sony | Smart Remote Control / Ctrl w/ Smartphone (DIRECT-… network) | Camera Remote API: JSON-RPC at 192.168.122.1:8080, HTTP live-view stream | Live view, aperture/shutter/ISO/EV/WB, touch AF, shoot, Bulb, video, last-shot review, card | **Experimental**, mock only (a6000). Bodies up to ~2019; not the a7 IV, a7S III, a1, ZV-E10, a6700 or later |
| Fujifilm | Camera access point at 192.168.0.1; newer bodies pair over Bluetooth first | A PTP/IP variant on ports 55740–55742 | – | Not supported (researched only) |

### Olympus / OM System bodies

Strings the cameras report have only been seen for the E-M10 ("E-M10") and TG-5 ("TG-5"); the rest are matched
by name in any spelling ("E-M10MarkIII", "E-M10 Mark III"…). Live Composite / Live Time / Bulb, movie and
live-view sizes come from each camera's own lists, so they need no table entry.

| Body | Year | Status | Differences the app handles |
|---|---|---|---|
| PEN E-P5 | 2013 | Researched only | – |
| OM-D E-M1 | 2013 | Researched only | Wi-Fi must be set to **Private**; no movie mode over Wi-Fi |
| Stylus 1 / 1s | 2013 | Researched only | – |
| OM-D E-M10 | 2014 | Researched only | – |
| Stylus SH-1 | 2014 | Researched only | – |
| Tough TG-3 | 2014 | Researched only | – |
| PEN E-PL7 | 2014 | Researched only | – |
| OM-D E-M5 Mark II | 2015 | Researched only | High Res Shot |
| Stylus SH-2 | 2015 | Researched only | – |
| Tough TG-4 | 2015 | Researched only | – |
| Tough TG-860 / TG-870 | 2015 | Researched only | – |
| OM-D E-M10 Mark II | 2015 | Researched only | – |
| AIR A01 | 2015 | Not supported | The AIR A01 speaks Olympus's Open Platform API |
| PEN-F | 2016 | **Tested on hardware** | High Res Shot |
| Stylus SH-3 | 2016 | Researched only | – |
| PEN E-PL8 | 2016 | Researched only | – |
| OM-D E-M1 Mark II | 2016 | Researched only | High Res Shot |
| TG-Tracker | 2016 | Not supported | The TG-Tracker works with OI.Track, not remote shooting |
| Tough TG-5 | 2017 | Researched only | – |
| OM-D E-M10 Mark III | 2017 | Researched only | – |
| PEN E-PL9 | 2018 | Researched only | – |
| OM-D E-M1X | 2019 | Researched only | High Res Shot; Olympus may limit other apps to downloads on this body |
| Tough TG-6 | 2019 | Researched only | – |
| OM-D E-M5 Mark III | 2019 | Researched only | High Res Shot |
| PEN E-PL10 | 2019 | Researched only | – |
| OM-D E-M1 Mark III | 2020 | Researched only | High Res Shot; Olympus may limit other apps to downloads on this body |
| OM-D E-M10 Mark IV | 2020 | Researched only | only some settings over Wi-Fi |
| PEN E-P7 | 2021 | Researched only | – |
| OM System OM-1 | 2022 | Researched only | High Res Shot; Device Connection, Bluetooth can stay off; newer protocol unconfirmed |
| OM System OM-5 | 2022 | Researched only | High Res Shot; Device Connection, Bluetooth can stay off; newer protocol unconfirmed |
| OM System TG-7 | 2023 | Researched only | Device Connection, Bluetooth can stay off; newer protocol unconfirmed |
| OM System OM-1 Mark II | 2024 | Researched only | High Res Shot; Device Connection, Bluetooth can stay off; newer protocol unconfirmed |
| OM System OM-3 | 2025 | Researched only | High Res Shot; Device Connection, Bluetooth can stay off; newer protocol unconfirmed |
| OM System OM-5 Mark II | 2025 | Researched only | High Res Shot; Device Connection, Bluetooth can stay off; newer protocol unconfirmed |

### Panasonic LUMIX bodies

Matched by the camera's UPnP `modelNumber` (e.g. `DC-GH5`, `DMC-GX80`). Image App-era bodies (to 2019) pair with
the plain `req_acc`; GH3/GH4 skip it; the S5 uses the plain one too. Whether the LUMIX Sync bodies from 2021 on
use the newer pairing is only known for the S5 IIX and G9 II.

| Body | Year | Status | Differences the app handles |
|---|---|---|---|
| LUMIX GH3 | 2012 | Researched only | no pairing step |
| LUMIX G6 | 2013 | Researched only | – |
| LUMIX GF6 | 2013 | Researched only | no ISO from the phone |
| LUMIX LF1 | 2013 | Researched only | no ISO from the phone |
| LUMIX GX7 | 2013 | Researched only | – |
| LUMIX GM1 / GM1S | 2013 | Researched only | – |
| LUMIX TS5 / FT5 | 2013 | Researched only | – |
| LUMIX TZ40 / ZS30 | 2013 | Researched only | – |
| LUMIX FZ70 / FZ72 | 2013 | Researched only | – |
| LUMIX GH4 | 2014 | Researched only | no pairing step |
| LUMIX TZ60 / ZS40 | 2014 | Researched only | no aperture/shutter from the phone |
| LUMIX TZ55 / ZS35 | 2014 | Researched only | no aperture/shutter from the phone; no video |
| LUMIX SZ8 | 2014 | Researched only | no aperture/shutter from the phone; no video |
| LUMIX LX100 | 2014 | Researched only | no aperture/shutter from the phone; no EV from the phone |
| LUMIX FZ1000 | 2014 | Researched only | – |
| LUMIX GM5 | 2014 | Researched only | – |
| LUMIX G7 / G70 | 2015 | Researched only | – |
| LUMIX GF7 | 2015 | Researched only | – |
| LUMIX TZ70 / ZS50 | 2015 | Researched only | no ISO from the phone |
| LUMIX FZ300 / FZ330 | 2015 | Researched only | – |
| LUMIX TS6 / FT6, TS30 | 2015 | Researched only | – |
| LUMIX TZ57 / ZS45 | 2015 | Researched only | no video |
| LUMIX SZ10 | 2015 | Researched only | no aperture/shutter from the phone; no video |
| LUMIX GX8 | 2015 | Researched only | no EV from the phone |
| LUMIX GX80 / GX85 / GX7 II | 2016 | Researched only | – |
| LUMIX G80 / G85 / G81 | 2016 | Researched only | – |
| LUMIX GF8 | 2016 | Researched only | – |
| LUMIX TZ80 / ZS60 | 2016 | Researched only | – |
| LUMIX TZ100 / ZS100 | 2016 | Researched only | – |
| LUMIX LX10 / LX15 | 2016 | Researched only | – |
| LUMIX FZ2000 / FZ2500 | 2016 | Researched only | – |
| LUMIX GH5 | 2017 | Mock only | – |
| LUMIX GF9 / GX800 / GX850 | 2017 | Researched only | – |
| LUMIX G9 | 2017 | Researched only | High Resolution Mode not from the app |
| LUMIX TZ90 / ZS70 | 2017 | Researched only | – |
| LUMIX FZ80 / FZ82 | 2017 | Researched only | – |
| LUMIX GH5S | 2018 | Researched only | – |
| LUMIX GX9 / GX7 III | 2018 | Researched only | – |
| LUMIX TZ200 / ZS200 | 2018 | Researched only | – |
| LUMIX LX100 II | 2018 | Researched only | – |
| LUMIX GF10 / GF90 | 2018 | Researched only | – |
| LUMIX FT7 / TS7 | 2018 | Researched only | no aperture/shutter from the phone; 4K off while Wi-Fi is on |
| LUMIX G90 / G95 / G91 | 2019 | Researched only | – |
| LUMIX TZ95 / ZS80 | 2019 | Researched only | – |
| LUMIX FZ1000 II | 2019 | Researched only | – |
| LUMIX S1 / S1R / S1H | 2019 | Researched only | – |
| LUMIX G100 | 2020 | Researched only | – |
| LUMIX S5 | 2020 | Researched only | 16:9 live view |
| LUMIX BGH1 | 2020 | Researched only | – |
| LUMIX GH5 II | 2021 | Researched only | Wi-Fi password always on since firmware 1.4 |
| LUMIX GH6 | 2022 | Researched only | – |
| LUMIX BS1H | 2022 | Researched only | – |
| LUMIX S5 II | 2023 | Researched only | may use the newer pairing (experimental); Wi-Fi password always on since the 2025 firmware |
| LUMIX S5 IIX | 2023 | Researched only | newer pairing (experimental); Wi-Fi password always on since the 2025 firmware |
| LUMIX G9 II | 2023 | Researched only | newer pairing (experimental); Wi-Fi password always on since the 2025 firmware |
| LUMIX TZ99 / ZS99 | 2023 | Researched only | – |
| LUMIX G97 | 2024 | Researched only | – |
| LUMIX GH7 | 2024 | Researched only | may use the newer pairing (experimental); Wi-Fi password always on since the 2025 firmware |
| LUMIX S9 | 2024 | Researched only | remote shooting needs firmware 1.1+; may use the newer pairing (experimental); Wi-Fi password always on since the 2025 firmware |
| LUMIX G100D | 2024 | Researched only | – |
| LUMIX S1 II / S1R II / L10 | 2025 | Researched only | LUMIX Lab/Flow era: the older Wi-Fi remote protocol may be gone |

**Apple Watch** works the same with every brand: it talks to the iPhone app, not the camera.

**iPhone Duo:** the app runs full screen on both screens, folded and open. On the outer screen it keeps
clear of the camera bar on the right edge. Open, it switches to its landscape layout with the shutter rail
on the left. Live view keeps running through a fold. Checked in the Simulator only.

**What it does**

- **A camera-style screen, portrait and landscape:** black, with one amber accent.
  - A top bar shows the camera, battery and shots left.
  - Aperture, shutter, ISO, EV, white balance and drive are big monospaced readouts. **AUTO** marks the ones the camera is choosing itself.
  - A mode dial sits above the shutter.
  - A quick row gives one-tap grid, histogram, peaking, loupe and night mode (on taller iPhones).
  - The **tools grid** (⊞ next to the shutter) floats over the picture. **Shooting** opens Astro, Interval, Bracket, Pocket and High Res; **Switches** turns aids on and off, lit amber when on.
  - In landscape the shutter rail sits on the side away from the Dynamic Island.
  - Text size is capped so the layout can't break.
- **Live view up to 30 fps.**
  - Shutter, aperture, EV and ISO, plus **battery %, shots left and lens focal length**, are read from each frame.
  - Live histogram and composition grid.
- **Tap a readout and its options open in place:**
  - a swipe dial for aperture, shutter, ISO, EV and hue;
  - a button grid for mode, white balance, drive and movie exposure;
  - Live Comp / Live Time / Live Bulb as their own segments.
  - A locked setting explains why and offers a one-tap unlock, e.g. "Switch to S".
- **Tap to focus** with the camera's AF result box. A **focus loupe** (4×, switches to 1280×960 by itself) helps nail manual focus on stars.
- **Focus peaking:** sharp edges are outlined in red, in the viewfinder and inside the loupe. It runs on its own thread at up to 12 fps and skips frames when busy, so live view keeps its frame rate.
- **The shutter does everything:**
  - single, burst (hold) and movie record;
  - long exposures with a countdown ring;
  - Live Composite / Time / Bulb with tap-to-stop and an elapsed timer.
  - Settings and Card lock while an exposure runs, and the phone stays awake.
- **Astro preset:**
  - picks up your lens's focal length and uses the 300/500 rule for a star-sharp shutter;
  - sets M, the widest aperture, ISO, ~4000 K and anti-shock.
  - Star trails use Live Composite.
- **Interval timer** for time-lapse and star stacking, with a progress ring around the shutter.
- **Timed Bulb:** Bulb, Live Time and Live Composite can stop by themselves after 30 s, 1–10 min or any length you pick, with a countdown in the shutter.
- **Exposure bracketing:** 3, 5, 7 or 9 frames, ⅓ to 2 EV apart. It varies exposure compensation in P, A and S and the shutter speed in M (or whichever you choose), shows what it will shoot first, can be cancelled, and puts the setting back afterwards. No focus bracketing: there's no Wi-Fi command to step the focus, so use the camera's own Focus BKT.
- **Pocket mode:** a black screen with a dim red countdown for long night sessions. The screen has to stay on, because iOS stops the app's Wi-Fi when the iPhone locks; for hours-long star trails, use the camera's own Live Composite or interval shooting.
- **Night mode:** red UI to keep your eyes dark-adapted.
- **Geotagging:** while connected, the app can log where you are (When In Use only, kept for two weeks on the phone). Photos you save to Photos get the logged position nearest their capture time, within 10 minutes. The capture time comes from the camera's clock, so sync it first (··· ▸ Sync camera clock).
- **Last-shot thumbnail** after every capture.
- **Card browser:**
  - zoom transition, swipe between photos, pinch/double-tap zoom;
  - a 50 MP badge on High Res Shot files;
  - save originals to Photos;
  - **star** photos (tap and hold, or the star when viewing one), show **Starred** only, and **download the RAWs of starred photos**: the RAW file (.ORF, .RW2, .NEF, .CR3, .ARW…) next to each starred JPEG goes to Photos, or to Files ▸ On My iPhone ▸ Shutterlink ▸ RAW if Photos won't take it. Stars are remembered per file name and size.
- **One-tap connect:** a "Connect to Camera" shortcut for the Action button, Siri and Shortcuts (see below).
- **Apple Watch remote:** live view, exposure, shutter, self-timer, Bulb and the Digital Crown for EV (see below).
- **··· menu:** live view size, camera clock sync, High Res Shot guide, all settings, request log, disconnect, power off.

## Run it on your iPhone

1. Open `Shutterlink.xcodeproj` in Xcode.
2. Select the **Shutterlink** target ▸ **Signing & Capabilities** ▸ **Team**, and pick your Apple ID.
   The project is signed with the Apexmerce team. With your own team (a free "Personal Team" works), change
   `com.apexcommerce.shutterlink` (and the Watch app's `com.apexcommerce.shutterlink.watchkitapp`) to anything unique.
3. Plug in the iPhone. Choose it as the run destination and press ▶.
   The first time, iOS asks you to:
   - enable **Developer Mode** (Settings ▸ Privacy & Security), and
   - trust the developer profile (Settings ▸ General ▸ VPN & Device Management).

   Free-team builds expire after 7 days. Press ▶ again to refresh.

**Coming from PEN-F Remote?** Shutterlink has a new bundle ID, so it installs as a separate app: delete
the old PEN-F Remote from the iPhone, and on the Watch install Shutterlink from the Watch app ▸ Available Apps.
Settings (brand, address, stars) start fresh, and iOS asks for Local Network, Photos and Location again.

## Connect to the camera

The home screen lists **your cameras**: every camera this iPhone has connected to, most recent first.
Turn on the camera's Wi-Fi, join its network in Settings ▸ Wi-Fi, and tap its card. Long-press a card to
forget it.

The first time, tap **Add your camera** (later, **Add a camera** under the list):

1. Pick **Automatic** (recommended: the app works out the brand) or your brand. Nikon, Canon and Sony are
   marked Beta.
2. Follow the steps the sheet shows for that brand. For the PEN-F: start **Connection to Smartphone**, then
   in Settings ▸ Wi-Fi join `PEN-F-P-…` with the 8-digit password shown on the camera.
3. Tap **Connect** and allow **Local Network** access when asked. Once it connects, the camera is saved.

**Advanced** in the sheet holds the camera address (for the mock cameras, or a camera on another network),
the Olympus User-Agent and the live-view size. Close OI.Share / OM Image Share / LUMIX Sync first so the
apps don't compete for the camera.

### One tap next time (Action button)

The app adds a **Connect to Camera** shortcut. Put it on the Action button (Settings ▸ Action Button ▸ Shortcut ▸ Shutterlink), or say "Connect to my camera with Shutterlink". It opens the app and keeps trying to connect for 30 seconds.

Once you've joined the camera's Wi-Fi in Settings, iOS rejoins it by itself whenever the camera's Wi-Fi is on, so the flow is: turn on Wi-Fi on the camera, press the Action button, shoot.

The app doesn't join the camera's Wi-Fi itself. That needs Apple's Hotspot Configuration capability, which Apple only grants to paid developer accounts. The app doesn't use it yet, so the Wi-Fi join is left to iOS. Now that it's signed with a paid team, `NEHotspotConfiguration` could be added to make it truly one-tap.

### Friends: try this first

Only the PEN-F has been tried on a real camera. If you have another body, these few checks tell the most.
If anything fails, open ··· ▸ **Request log** and send it over.

- **Olympus / OM System:** start **Connection to Smartphone** and join the network. Check live view, change
  EV, take one shot. E-M1 (Mark I): set the camera's Wi-Fi to **Private** first.
- **LUMIX:** use **Remote Shooting & View** and choose **Yes** when the camera asks. Check live view, take
  one shot. On an S5 II, G9 II or GH7 the pairing is the big unknown, so say exactly what the camera shows.
- **Nikon (Beta):** turn off live view on the camera. Use **Connect to smart device ▸ Wi-Fi connection**, not
  "Connect to PC". Check live view, take one shot, open the card. Lengthen the camera's standby timer.
- **Canon (Beta):** the camera needs CCAPI activated first. That takes Canon's free tool, a Canon developer
  account and a USB cable. Then turn off HTTPS and user authentication in the camera's CCAPI settings, and
  type the "CCAPI top URL" the camera shows into Advanced if Automatic doesn't find it. The original EOS R
  has no CCAPI.
- **Sony (Beta):** only bodies up to about 2019 with Smart Remote Control work. An a7 IV or ZV-E10 won't.

## Apple Watch remote

The Watch app is a remote for the iPhone app: the iPhone stays connected to the camera, and the Watch
talks to the iPhone over Bluetooth/Wi-Fi (WatchConnectivity). A Watch can't stay on the camera's own
Wi-Fi, so this is how camera Watch remotes generally work.

- **Live view** at about 3 frames a second while the Watch app is on screen. It stops when you lower your wrist, to save battery.
- **Battery, shots left** and the exposure the iPhone's strip shows (aperture, shutter, ISO, EV).
- **Shutter:** takes a picture, starts and stops Bulb / Live modes, or records video in movie mode. A tap on your wrist confirms each shot.
- **Self-timer:** Off, 2 s or 10 s, with a countdown over the live view and a cancel button. The cancel button also stops an interval run or a bracket.
- **Digital Crown:** turns exposure compensation when the camera allows it (EV shows in orange).
- Timed Bulb shows its countdown, and a running exposure or video shows its clock.

Keep Shutterlink open on the iPhone while you use the Watch: iOS stops the app's camera
connection in the background. Pocket mode is a good way to leave it running. If the iPhone app stops
answering, the Watch says so instead of showing an old picture.

**Installing it:** it's part of the Shutterlink scheme. Run that on your iPhone from Xcode, and the
Watch app installs on the paired Watch (or install it from the Watch app ▸ Available Apps). The first
time, turn on Developer Mode on the Watch (Settings ▸ Privacy & Security ▸ Developer Mode). It's signed
with the same team as the iPhone app, and a free-team build expires with it.

## Android

`android/` is the Android version: Kotlin and Jetpack Compose, one activity, the same drivers, screens and
black/amber look as the iPhone app. Android 10 (API 29) or later.

**Build it.** Needs a JDK 17+ (21 works) and the Android SDK (platform 36, build-tools 36.0.0). The Gradle
wrapper fetches Gradle 8.14.3 itself.

```bash
cd android && JAVA_HOME=/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home ./gradlew assembleDebug
```

The APK lands in `android/app/build/outputs/apk/debug/`. Install it with `adb install -r` on that file.

**How it reaches the camera.** A camera's Wi-Fi has no internet, so Android keeps mobile data as the default
network and would send the app's requests there. On Connect the app asks Android for the Wi-Fi network
(`requestNetwork` without the internet capability, which also stops Android dropping a Wi-Fi it thinks is
useless) and binds the whole app to it with `bindProcessToNetwork`: HTTP, PTP/IP and the UDP live-view socket
all go over the camera's Wi-Fi. If Android says the network has no internet, choose to stay connected.

**Joining the camera's Wi-Fi from the app.** Add a camera ▸ Join camera Wi-Fi from the app: type the network
name and password the camera shows. Android asks you to confirm (`WifiNetworkSpecifier`), then keeps the phone
on that network while the app holds it. Joining it in Settings ▸ Wi-Fi works too.

**Permissions**, all asked only when needed:
- **Nearby Wi-Fi devices** (Android 13+; location on Android 10–12): only for joining a camera's Wi-Fi from the app.
- **Location**: only to show the Wi-Fi network's name on the Connect screen (Android hides SSIDs without it). Optional.
- **Photos and media**: none. Saved photos and videos go to Pictures/Shutterlink and Movies/Shutterlink through
  MediaStore; RAW files go to Download/Shutterlink/RAW, since most gallery apps can't show them.

**In the emulator, against the mocks.** The Mac is `10.0.2.2`. The mocks send live view back to `127.0.0.1` on
the Mac, so forward the live-view port into the emulator once per boot:

```bash
adb emu redir add udp:40000:40000
```

Then Add a camera ▸ Advanced ▸ Camera address `10.0.2.2:8080` (PEN-F), `:8082` (LUMIX), `:15740` (Nikon),
`:8084` (Canon) or `:8086` (Sony). Debug builds also run the driver self-test from adb (it refuses anything but
the Mac running the mocks):

```bash
adb shell am start -n com.apexcommerce.shutterlink/.MainActivity --es selfTest olympus --es host 10.0.2.2:8080
adb logcat -s Shutterlink | grep SELFTEST
```

**Status (emulator and mocks only; not yet on a real phone or camera).**
- All five drivers pass the self-test against their mocks in a Pixel 9a emulator (Android 15): Olympus/OM and
  LUMIX, plus Nikon, Canon and Sony (Beta, as on iOS).
- Checked by hand there:
  - portrait and landscape layouts, the setting dials, mode dial, tools tray, loupe and grid;
  - the card browser with stars, swipe-through viewer, Save, and the RAW download of starred photos;
  - binding to the Wi-Fi network (with the debug `--ez bindWifi true` extra, since the mocks' address
    normally skips it).
- Not tried yet:
  - joining a camera's Wi-Fi from the app (`WifiNetworkSpecifier`) and the permission prompts;
  - a real phone on a real camera's network.
- Not ported yet: geotagging, the "Connect to Camera" shortcut, and a Wear OS remote.

## Test without the camera (mock cameras)

`mock-camera/` has a fake camera for every brand, live view included. They need only Python 3 and Swift,
both on macOS already.

| Mock | Pretends to be | Simulator address | Options |
|---|---|---|---|
| `mock_penf.py` | Olympus PEN-F (OI.Share HTTP + RTP live view) | `127.0.0.1:8080` | `--model E-M1` (or any body) to report another model |
| `mock_lumix.py` | Panasonic GH5 (`cam.cgi`, UDP live view, UPnP card on 60606, files on 50001) | `127.0.0.1:8082` | `--refuse` (camera says No), `--encrypted` (newer pairing + session id), `--model DC-LX100` (or any body) |
| `mock_nikon.py` | Nikon Z 6II (PTP/IP) | `127.0.0.1:15740` | `--dslr` (D750-style: 1/10000 s shutter units, older capture and event ops) |
| `mock_canon.py` | Canon EOS R6 (CCAPI) | `127.0.0.1:8084` | |
| `mock_sony.py` | Sony a6000 (Camera Remote API, live-view stream, description on 64321) | `127.0.0.1:8086` | |

```bash
python3 mock-camera/mock_nikon.py
```

- **In the Simulator:** Connect screen ▸ Auto (or the brand) ▸ Advanced ▸ Camera address = the address above.
- **On a real iPhone on the same Wi-Fi:** run the mock with `--bind 0.0.0.0` and use `<your Mac's IP>:<port>`.

Like the real PEN-F, the PEN-F mock rejects commands sent in the wrong mode (HTTP 520) and rejects unknown User-Agents.
Its card has RAW+JPEG pairs (fake `.ORF` files that Photos rejects, so RAW downloads fall back to Files), and it offers Live Composite / Time / Bulb in M.
The other mocks also refuse values a real camera wouldn't take, report busy while "writing to the card", and have RAW files on the card.

**Driver self-test.** A Debug build launched with `-selfTest <brand|auto> <127.0.0.1:port>` runs a driver through
connect, live view, every settable setting, tap AF, a shot, last-shot review, video, battery, the card (thumbnail,
preview, JPEG and RAW download) and back to live view, and prints `SELFTEST PASS/FAIL` lines. It refuses any
address that isn't on this Mac, because it takes pictures and changes settings.

```bash
xcrun simctl launch --console booted com.apexcommerce.shutterlink -selfTest nikon 127.0.0.1:15740
```

All five drivers (and LUMIX `--encrypted`, Nikon `--dslr`) pass it against their mocks, and Auto picks the
right brand for each mock from the address alone.

To try the Watch app in the Simulator, pair a Watch simulator with the iPhone one
(`xcrun simctl pair <watch> <iphone>`), then run the Shutterlink scheme on the iPhone and the
ShutterlinkWatch scheme on the Watch. A Debug Watch build launched with `-crownSteps 2` turns the
crown two clicks by itself, since the Simulator tools can't.

The Simulator has no Shortcuts app. To run what the shortcut runs, launch a Debug build with `-connectFromShortcut`:

```bash
xcrun simctl launch booted com.apexcommerce.shutterlink -connectFromShortcut
```
The LUMIX mock asks for approval the first time a phone pairs (`--refuse` makes it say No), only browses
the card in playback mode, and stops live view if the app stops polling it. It also serves its media server
and files on the real camera's ports, 60606 and 50001.

## How the Olympus protocol works

| What | How |
|---|---|
| Transport | Camera is a Wi-Fi access point at `192.168.0.10`. Commands are plain HTTP/1.1 on port 80, sent one at a time. |
| Headers | `Host: 192.168.0.10` and `User-Agent: OI.Share v2`. `OlympusCameraKit` is an alternative, selectable under Advanced. |
| Modes | `switch_cammode.cgi?mode=rec&lvqty=0640x0480` for shooting and settings. `mode=play` to read the card. |
| Live view | `exec_takemisc.cgi?com=startliveview&port=40000`. The camera then streams RTP/UDP JPEG to that port on the phone. The first packet of each frame carries an extension with AF frame, shutter, F-number, EV and ISO. The marker bit ends the frame. |
| Focus / shoot | `exec_takemotion.cgi?com=takeready&point=0320x0240` (falls back to `assignafframe`). Then `com=starttake[&point=…]`, and `com=stoptake` for continuous drive. Points are in live-view pixels. |
| Settings | `get_camprop.cgi?com=desc&propname=desclist` lists all properties with value, `get`/`getset` and allowed values. `set_camprop.cgi?com=set&propname=X` is a POST with body `<?xml version="1.0"?><set><value>…</value></set>`. |
| Card | `get_imglist.cgi?DIR=/DCIM/100OLYMP` returns one line per file (`dir,name,size,attr,fatdate,fattime`). Also `get_thumbnail.cgi?DIR=…` and `get_resizeimg.cgi?DIR=…&size=1600`. Originals are a plain `GET /DCIM/100OLYMP/P….JPG`. |

Sources: Olympus *OPC Communication Protocol 1.0a*, and the open-source clients
[joergmlpts/olympus-wifi](https://github.com/joergmlpts/olympus-wifi) and
[ccrome/olympus-omd-remote-control](https://github.com/ccrome/olympus-omd-remote-control).

## What we learned from the real PEN-F (firmware 1.1)

Verified on the camera:

- **Live view frame rate is limited by the camera's Wi-Fi (~800 packets/s, about 9 Mbit/s).** 320×240 and 640×480 run at ~30 fps; 1280×960 frames are ~116 KB, so they top out at 8–10 fps.
- **Changing the live-view size is ignored while the camera is already in recording mode.** The app switches to playback and back with the new `lvqty`.
- **AF points are in the pixel space of the frames actually arriving.** `exec_takemotion.cgi?com=assignafframe&point=XXXXxYYYY` replies `<affocus>ok</affocus><afframepoint>…</afframepoint><afframesize>…</afframesize>`, then `takeready` focuses there. AF box coordinates in the frame metadata are signed 16-bit and can go negative at the edges.
- **Frame metadata differs from Olympus's OPC spec for shutter speed.** Field 8 has 3 words, each packed `numerator << 16 | denominator`, not 6 separate words.
- **Settable over Wi-Fi:** only `takemode` (iAuto P A S M movie), `drivemode`, `focalvalue`, `expcomp`, `shutspeedvalue` (including livecomp/livetime/livebulb), `isospeedvalue`, `wbvalue`, `exposemovie` and `colorphase`.
  - **Not settable:** RAW/JPEG quality, Picture Mode, Color/Mono Profile, Art filters and High Res Shot. Set those on the camera; the front Creative dial controls Color/Mono/CRT/Art.
- **The camera's `focalvalue` lists F1.0–F91 whatever the lens.** The lens's real range comes from frame metadata field 9 (f/1.4–f/16 on the lens used here), and the dial only offers that range.

Still unconfirmed:

- **White balance names**: the camera sends codes (0, 16, 17, 18…), and the labels are mapped from menu order. The picker shows the raw code next to each label.
- **`colorphase` (Hue dial)**: probably the Color Creator hue. Test it with the Creative dial on CRT.
- **Astro preset and Live Composite**: tested against the mock only.

## Panasonic LUMIX (GH5) — experimental

Written for the GH5 from open-source descriptions of Panasonic's Wi-Fi protocol. Other bodies that work
with Image App / LUMIX Sync speak the same protocol and should mostly work; see
[Supported cameras](#supported-cameras) for which, and for the newer bodies' pairing.
**None of this has been tried on a real LUMIX camera yet.**

### Connect

1. On the GH5: **MENU ▸ Setup ▸ Wi-Fi ▸ Wi-Fi Function ▸ New Connection ▸ Remote Shooting & View.**
   The camera shows its network name (e.g. `GH5-XXXXXX`).
2. On the iPhone: Settings ▸ Wi-Fi ▸ that network. A Wi-Fi password is off by default on the GH5;
   if you turned it on, enter it.
3. In the app pick **Panasonic LUMIX** ▸ **Connect to camera**. The first time, the camera asks whether to
   connect to "PENF-Remote": choose **Yes** on the camera. Later connections skip this.

The camera is always at `192.168.54.1`. Close Image App / LUMIX Sync on other phones first; the camera talks to one app at a time.

### What works (against the mock)

- Pairing with the on-camera Yes/No prompt, and readable errors when the camera says No or is busy.
- Live view (640×480 or 320×240) with the histogram, grid, loupe and night mode.
- Battery %, shots left and an overheating warning, polled every second (this also keeps the stream alive).
- Aperture (limited to the lens's real range), shutter including Bulb, ISO including iAuto, EV and white balance,
  on the same dials and haptics as the PEN-F.
- Tap to focus, single shots, long exposures with a countdown, Bulb with tap-to-stop.
- **Video:** turn on **Video** in the tools grid (the GH5's mode dial can't be read or turned over Wi-Fi),
  then the shutter becomes a record button.
- Card browser over the camera's media server: JPG, RW2 and MP4, with thumbnails, preview and saving
  originals to Photos.
- The Astro preset and interval timer use whatever the camera accepts (aperture, shutter, ISO).

### What doesn't

- **Mode dial, drive mode, Photo Style, quality and other menus:** not settable from the app. Set them on the camera.
- **Last-shot thumbnail:** LUMIX review images need playback mode, which stops live view, so open the card instead.
- **Clock sync** and **High Res Shot** are Olympus features and are hidden for LUMIX.

### How the LUMIX protocol works

| What | How |
|---|---|
| Commands | `GET http://192.168.54.1/cam.cgi?mode=…`. Replies are XML (`<camrply><result>ok</result>…`) or CSV (`ok,…`); errors start with `err_`. |
| Pairing | `mode=accctrl&type=req_acc&value=<phone UUID>&value2=<name>`. While the camera shows its prompt it answers `ok_under_research`; the app asks again every second. |
| State | `mode=getstate` (battery, shots left, temperature, mode). The app polls it every second as a keep-alive. `getinfo&type=lens` gives the lens's aperture and shutter limits. |
| Live view | `mode=startstream&value=<UDP port>`. Each datagram is one JPEG after a 32-byte header; bytes 30–31 give the length of a second header before the JPEG. |
| Settings | `getsetting` / `setsetting` with `type=focal`, `shtrspeed`, `iso`, `exposure`, `whitebalance`. Aperture and shutter are APEX × 256 written `n/256`: f-number = 2^(n/512), time = 2^(−n/256); Bulb is `16384/256`. |
| Shooting | `camcmd&value=capture` (and `capture_cancel` to end Bulb), `video_recstart` / `video_recstop`, `camctrl&type=touch&value=x/y` for touch AF on a 0–1000 grid. |
| Card | `camcmd&value=playmode`, then UPnP ContentDirectory `Browse` on port 60606 (paged 50 at a time). Each item links its original (`CAM_ORG`), RAW (`CAM_RAW`) and thumbnails (`CAM_TN`, `CAM_LRGTN`) on port 50001. |

Sources: [Rambalac/GMaster](https://github.com/Rambalac/GMaster),
[peci1/lumix-link-desktop](https://github.com/peci1/lumix-link-desktop),
[cleverfox/lumixproto](https://github.com/cleverfox/lumixproto),
[klausweiss/lumix-upnp-dump](https://github.com/klausweiss/lumix-upnp-dump) and
[libgphoto2's LUMIX driver](https://github.com/gphoto/libgphoto2).

Worth checking first on a real GH5: the pairing reply, the live-view header, the exact white-balance names,
and whether `touch` or `touchaf` is the focus command.

## Nikon, Canon and Sony: how the protocols work

| | Nikon | Canon | Sony |
|---|---|---|---|
| Transport | PTP/IP: two TCP connections to port 15740 (commands, events), little-endian packets | CCAPI: `GET /ccapi` lists the APIs; REST + JSON | JSON-RPC: `POST /sony/camera {"method", "params", "id", "version"}` |
| Session | Init Command Request (our GUID, name) → Ack; Init Event Request → Ack; OpenSession(1) with transaction id 0; GetDeviceInfo | Device information, battery | `getVersions`, `startRecMode` where listed, `getAvailableApiList` |
| Live view | ChangeCameraMode(1), StartLiveView 0x9201, wait on DeviceReady 0x90C8, then GetLiveViewImage 0x9203 in a loop (128/384-byte header, then JPEG) | `POST shooting/liveview {"liveviewsize":"small"}`, then `GET shooting/liveview/flip` in a loop | `startLiveview` → URL of an endless stream: 8-byte header + 128-byte header (`24 35 68 79`, JPEG size) + JPEG |
| Settings | GetDevicePropDesc / SetDevicePropValue: FNumber 0x5007 (f×100), Nikon shutter 0xD100 (num<<16 \| den; 0x500D in 1/10000 s on older bodies), ISO 0x500F + auto 0xD054, EV 0x5010 (1/1000 EV), WB 0x5005 | `shooting/settings/{tv,av,iso,exposure,wb}` → `{"value","ability"}`; PUT `{"value"}`. `"f5.6"`, `"1/125"`, `"0\"5"`, `"+1_1/3"` | `getAvailable…` → `[current, [choices]]`, `set…`. EV is an index (⅓ or ½ steps) |
| Shoot | InitiateCaptureRecInMedia 0x9207 (0xFFFFFFFF, 0 = to card) or InitiateCapture 0x100E; retry while busy; ObjectAdded from GetEvent 0x90C7 / GetEventEx 0x941C | `POST shooting/control/shutterbutton {"af":true}`; Bulb with `shutterbutton/manual` full_press / release | `actTakePicture` (→ postview URL), `startBulbShooting` / `stopBulbShooting` |
| Card | GetStorageIDs, GetObjectHandles, GetObjectInfo, GetThumb, GetLargeThumb 0x90C4, GetPartialObject in 1 MB pieces | `contents` → storage → folder (`?kind=number`, `?page=N`) → file `?kind=thumbnail\|display`, plain GET for the original | `setCameraFunction "Contents Transfer"`, then avContent `getContentList` (v1.3) |

Sources: libgphoto2 (`ptpip.c`, `ptp.h`, `config.c`, `library.c`), Nikon's online manuals and SnapBridge help,
airmtp, digiCamControl; Canon's camera manuals and CCAPI sample code, Canomate, ccapi.py; pysony. LUMIX's newer
pairing: liblumix and the lumix-remote protocol notes.

## Files

```
Shutterlink/
  ShutterlinkApp.swift       app entry, launch hand-off
  Camera/CameraDriver.swift  the driver interface and capability flags every brand implements
  Camera/CameraBrand.swift   brands: addresses, Wi-Fi names, default capabilities
  Camera/BrandDetector.swift Auto: subnet guess plus a read-only probe per protocol
  Camera/ModelProfiles.swift every Wi-Fi Olympus/OM and LUMIX body: features, pairing, notes
  Camera/CameraHTTPClient.swift HTTP commands (one at a time), request log, Olympus card listing parser
  Camera/OlympusDriver.swift Olympus / OM System (OI.Share)
  Camera/Panasonic.swift     LUMIX driver: pairing (both kinds), keep-alive, settings, shooting, UPnP card browser
  Camera/PTPIP.swift         PTP/IP transport and PTP datasets
  Camera/Nikon.swift         Nikon driver (PTP/IP + Nikon vendor operations)
  Camera/Canon.swift         Canon CCAPI driver
  Camera/Sony.swift          Sony Camera Remote API driver
  Camera/LiveStreams.swift   pulled live view (Nikon, Canon) and Sony's HTTP stream
  Camera/LiveView.swift      UDP socket, RTP reassembly, frame metadata parser, LUMIX JPEG datagrams, pushed frames
  Camera/CameraModel.swift   connection/mode state machine; forwards everything to the driver
  Camera/SavedCameras.swift  the home screen's saved cameras and one-tap reconnect
  Camera/SelfTest.swift      Debug-only -selfTest against the mocks
  Camera/Extras.swift        timed bulb, bracketing, stars and RAW download, shortcut connect
  Camera/FocusPeaking.swift  Core Image edge overlay for focus peaking
  Camera/Geotag.swift        location log (When In Use) and nearest-point lookup
  Camera/Shortcuts.swift     "Connect to Camera" App Intent and App Shortcut
  Camera/WatchBridge.swift   iPhone end of the Watch remote: status, commands, preview frames
  Camera/StripValues.swift   the exposure strip's values (shared with the Watch)
  Camera/XML.swift           tiny XML parser + camera command list
  Camera/PropertyFormat.swift labels for raw property values
  Views/Design.swift         colours, surfaces and button styles shared by every screen
  Views/BrandMark.swift      the Shutterlink aperture mark, name lockup and launch hand-off
  Views/ExtrasViews.swift    bracketing sheet, pocket mode, bulb timer, RAW download bar
  Views/…                    SwiftUI screens
ShutterlinkWatch/            Apple Watch remote (SwiftUI, WatchConnectivity)
  PhoneLink.swift            Watch end of the link to the iPhone app
  WatchRemoteView.swift      live view, values, self-timer, shutter, Digital Crown EV
Shared/
  WatchProtocol.swift        messages and status shared by the iPhone and Watch apps
android/                     Android app (Kotlin, Jetpack Compose); same structure as the iOS app
  app/src/main/java/com/apexcommerce/shutterlink/
    camera/                  drivers (Olympus, Panasonic, Nikon + PtpIp, Canon, Sony), CameraModel, live view,
                             BrandDetector, ModelProfiles, Features, CameraNetwork (Wi-Fi binding), SelfTest
    ui/                      Compose screens: Connect, Remote, Controls, OptionPanel, LiveViewPane, Gallery, Sheets
    MainActivity.kt          the single activity, debug self-test hooks
mock-camera/
  mock_penf.py               fake PEN-F (HTTP + RTP live view)
  mock_lumix.py              fake LUMIX GH5 (cam.cgi, UDP live view, UPnP card, file server; --encrypted)
  mock_nikon.py              fake Nikon Z 6II / D750 (PTP/IP)
  mock_canon.py              fake Canon EOS R6 (CCAPI)
  mock_sony.py               fake Sony a6000 (Camera Remote API, live-view stream)
  make_frames.swift          renders the fake live-view frames
tools/
  make_icon.swift            renders the app and Watch icons and the launch-screen mark
```
