# PEN-F Remote

A small iPhone test app that controls an Olympus PEN-F over the camera's own Wi-Fi.
It uses the same protocol as Olympus's OI.Share / OM Image Share app.

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
- **Night mode:** red UI to keep your eyes dark-adapted.
- **Last-shot thumbnail** after every capture.
- **Card browser:**
  - zoom transition, swipe between photos, pinch/double-tap zoom;
  - a 50 MP badge on High Res Shot files;
  - save originals to Photos.
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

## Test without the camera (mock PEN-F)

`mock-camera/mock_penf.py` pretends to be the camera, live view included.
It needs only Python 3 and Swift, both on macOS already.

```bash
python3 mock-camera/mock_penf.py
```

- **In the Simulator:** Connect screen ▸ Advanced ▸ Camera address = `127.0.0.1:8080`.
- **On a real iPhone on the same Wi-Fi:** run it with `--bind 0.0.0.0` and use `<your Mac's IP>:8080`.

Like the real camera, the mock rejects commands sent in the wrong mode (HTTP 520) and rejects unknown User-Agents.

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

## Files

```
PenFRemote/
  PenFRemoteApp.swift        app entry, theme
  Camera/OlympusClient.swift HTTP commands, request log, card listing parser
  Camera/LiveView.swift      UDP socket, RTP reassembly, frame metadata parser
  Camera/CameraModel.swift   connection/mode state machine, shooting, settings, gallery
  Camera/XML.swift           tiny XML parser + camera command list
  Camera/PropertyFormat.swift labels for raw property values
  Views/…                    SwiftUI screens
mock-camera/
  mock_penf.py               fake PEN-F (HTTP + RTP live view)
  make_frames.swift          renders the fake live-view frames
```
