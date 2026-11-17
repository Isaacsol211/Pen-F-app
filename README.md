# PEN-F Remote

A small iPhone test app that controls an Olympus PEN-F over the camera's own Wi-Fi.
It uses the same protocol as Olympus's OI.Share / OM Image Share app.

It also has **experimental support for Panasonic LUMIX bodies (written for the GH5)**, using the
protocol of Panasonic's Image App / LUMIX Sync. Pick the camera brand on the Connect screen.
The LUMIX side is tested only against a mock camera so far; see
[Panasonic LUMIX (GH5)](#panasonic-lumix-gh5--experimental).

**What it does**

- **Liquid Glass UI (iOS 26+), portrait and landscape.**
  - In landscape the shutter rail sits on the side away from the Dynamic Island.
  - Text size is capped so the layout can't break.
- **Live view up to 30 fps.**
  - Shutter, aperture, EV and ISO, plus **battery %, shots left and lens focal length**, are read from each frame.
  - Live histogram and composition grid.
- **Every Wi-Fi-settable camera setting is an icon on the main screen.** Tap one and its options open in place:
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
  - **star** photos (tap and hold, or the star when viewing one), show **Starred** only, and **download the RAWs of starred photos**: the .ORF next to each starred JPEG goes to Photos, or to Files ▸ On My iPhone ▸ PEN-F Remote ▸ RAW if Photos won't take it. Stars are remembered per file name and size.
- **One-tap connect:** a "Connect to Camera" shortcut for the Action button, Siri and Shortcuts (see below).
- **Apple Watch remote:** live view, exposure, shutter, self-timer, Bulb and the Digital Crown for EV (see below).
- **··· menu:** live view size, camera clock sync, High Res Shot guide, all settings, request log, disconnect, power off.

## Run it on your iPhone

1. Open `PenFRemote.xcodeproj` in Xcode.
2. Select the **PenFRemote** target ▸ **Signing & Capabilities** ▸ **Team**, and pick your Apple ID.
   A free "Personal Team" works. If Xcode says the bundle ID is taken, change
   `dev.penfremote.remote4821` to anything unique.
3. Plug in the iPhone. Choose it as the run destination and press ▶.
   The first time, iOS asks you to:
   - enable **Developer Mode** (Settings ▸ Privacy & Security), and
   - trust the developer profile (Settings ▸ General ▸ VPN & Device Management).

   Free-team builds expire after 7 days. Press ▶ again to refresh.

## Connect to the camera

1. On the PEN-F, start **Connection to Smartphone**. You want the screen with the SSID, password and QR code.
2. On the iPhone, open Settings ▸ Wi-Fi ▸ `PEN-F-P-…` and enter the 8-digit password shown on the camera.
3. Open PEN-F Remote ▸ **Connect to camera**. Allow **Local Network** access when asked. If the first attempt fails because the prompt was up, tap Connect again.

The camera is always at `192.168.0.10`. Close OI.Share / OM Image Share first so the two apps don't compete for the camera.

### One tap next time (Action button)

The app adds a **Connect to Camera** shortcut. Put it on the Action button (Settings ▸ Action Button ▸ Shortcut ▸ PEN-F Remote), or say "Connect to my camera with PEN-F Remote". It opens the app and keeps trying to connect for 30 seconds.

Once you've joined the camera's Wi-Fi in Settings, iOS rejoins it by itself whenever the camera's Wi-Fi is on, so the flow is: turn on Wi-Fi on the camera, press the Action button, shoot.

The app doesn't join the camera's Wi-Fi itself. That needs Apple's Hotspot Configuration capability, which Apple only grants to paid developer accounts. This app is signed with a free Personal Team, so the Wi-Fi join is left to iOS. With a paid account, `NEHotspotConfiguration` could be added to make it truly one-tap.

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

Keep PEN-F Remote open on the iPhone while you use the Watch: iOS stops the app's camera
connection in the background. Pocket mode is a good way to leave it running. If the iPhone app stops
answering, the Watch says so instead of showing an old picture.

**Installing it:** it's part of the PenFRemote scheme. Run that on your iPhone from Xcode, and the
Watch app installs on the paired Watch (or install it from the Watch app ▸ Available Apps). The first
time, turn on Developer Mode on the Watch (Settings ▸ Privacy & Security ▸ Developer Mode). It uses
the same free Personal Team and expires with the iPhone app.

## Test without the camera (mock cameras)

`mock-camera/mock_penf.py` pretends to be the PEN-F and `mock-camera/mock_lumix.py` a LUMIX GH5,
live view included. They need only Python 3 and Swift, both on macOS already.

```bash
python3 mock-camera/mock_penf.py
```

```bash
python3 mock-camera/mock_lumix.py
```

- **In the Simulator:** Connect screen ▸ pick the brand ▸ Advanced ▸ Camera address =
  `127.0.0.1:8080` (PEN-F) or `127.0.0.1:8082` (LUMIX).
- **On a real iPhone on the same Wi-Fi:** run it with `--bind 0.0.0.0` and use `<your Mac's IP>:8080` / `:8082`.

Like the real PEN-F, the PEN-F mock rejects commands sent in the wrong mode (HTTP 520) and rejects unknown User-Agents.
Its card has RAW+JPEG pairs (fake `.ORF` files that Photos rejects, so RAW downloads fall back to Files), and it offers Live Composite / Time / Bulb in M.

To try the Watch app in the Simulator, pair a Watch simulator with the iPhone one
(`xcrun simctl pair <watch> <iphone>`), then run the PenFRemote scheme on the iPhone and the
PenFRemoteWatch scheme on the Watch. A Debug Watch build launched with `-crownSteps 2` turns the
crown two clicks by itself, since the Simulator tools can't.

The Simulator has no Shortcuts app. To run what the shortcut runs, launch a Debug build with `-connectFromShortcut`:

```bash
xcrun simctl launch booted dev.penfremote.remote4821 -connectFromShortcut
```
The LUMIX mock asks for approval the first time a phone pairs (`--refuse` makes it say No), only browses
the card in playback mode, and stops live view if the app stops polling it. It also serves its media server
and files on the real camera's ports, 60606 and 50001.

## How the protocol works

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
with Image App / LUMIX Sync (GH4, GH5S, G9, G80/G85, GX9, S-series…) speak the same protocol and
should mostly work. **None of this has been tried on a real LUMIX camera yet.**

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
- **Video:** turn on **Video** in the tools tray (the GH5's mode dial can't be read or turned over Wi-Fi),
  then the shutter becomes a record button.
- Card browser over the camera's media server: JPG, RW2 and MP4, with thumbnails, preview and saving
  originals to Photos.
- The Astro preset and interval timer use whatever the camera accepts (aperture, shutter, ISO).

### What doesn't

- **Mode dial, drive mode, Photo Style, quality and other menus:** not settable from the app. Set them on the camera.
- **Last-shot thumbnail:** LUMIX review images need playback mode, which stops live view, so open the card instead.
- **Clock sync** and **High Res Shot** are Olympus features and are hidden for LUMIX.

### How the protocol works

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

## Files

```
PenFRemote/
  PenFRemoteApp.swift        app entry, theme
  Camera/CameraBrand.swift   Olympus / Panasonic: addresses, Wi-Fi names, live-view format
  Camera/OlympusClient.swift HTTP commands, request log, card listing parser
  Camera/LiveView.swift      UDP socket, RTP reassembly, frame metadata parser, LUMIX JPEG datagrams
  Camera/CameraModel.swift   connection/mode state machine, shooting, settings, gallery
  Camera/Extras.swift        timed bulb, bracketing, stars and RAW download, shortcut connect
  Camera/FocusPeaking.swift  Core Image edge overlay for focus peaking
  Camera/Geotag.swift        location log (When In Use) and nearest-point lookup
  Camera/Shortcuts.swift     "Connect to Camera" App Intent and App Shortcut
  Camera/WatchBridge.swift   iPhone end of the Watch remote: status, commands, preview frames
  Camera/StripValues.swift   the exposure strip's values (shared with the Watch)
  Camera/Panasonic.swift     LUMIX driver: pairing, keep-alive, settings, shooting, UPnP card browser
  Camera/XML.swift           tiny XML parser + camera command list
  Camera/PropertyFormat.swift labels for raw property values
  Views/ExtrasViews.swift    bracketing sheet, pocket mode, bulb timer, RAW download bar
  Views/…                    SwiftUI screens
PenFRemoteWatch/             Apple Watch remote (SwiftUI, WatchConnectivity)
  PhoneLink.swift            Watch end of the link to the iPhone app
  WatchRemoteView.swift      live view, values, self-timer, shutter, Digital Crown EV
Shared/
  WatchProtocol.swift        messages and status shared by the iPhone and Watch apps
mock-camera/
  mock_penf.py               fake PEN-F (HTTP + RTP live view)
  mock_lumix.py              fake LUMIX GH5 (cam.cgi, UDP live view, UPnP card, file server)
  make_frames.swift          renders the fake live-view frames
```
