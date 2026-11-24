# Shutterlink for Mac

Branch `feature/mac-catalyst` (from `main` 2a87c6e). One App Store purchase for iPhone, iPad and Mac:
the Mac app is the same target and the same bundle ID, `com.apexcommerce.shutterlink`.

## Catalyst or a native macOS target?

| | Mac Catalyst ("Optimize for Mac") | Native macOS target |
|---|---|---|
| Code | The existing target, built for Mac too | A second target; everything UIKit replaced |
| UIKit in the app today | Works as is (46 `UIImage` uses, `UIGraphicsImageRenderer`, `fullScreenCover`, sheet detents, `UIViewRepresentable`, `UIPasteboard`) | Each needs an AppKit or cross-platform version |
| Layout | The iPad workspace layouts, unchanged | Same SwiftUI, but sheets, menus and covers behave differently and need rework |
| Universal purchase | Automatic (same bundle ID) | Possible, but only if the target is set to the same bundle ID |
| Feel | Mac menus, windows and panels; controls look like the iPad app | Most Mac-like |
| Cost | ~20 files, mostly guards and copy | Weeks, plus two apps to keep in step |

**Chosen: Mac Catalyst.** The app is SwiftUI on UIKit, and the iPad layouts already fit a Mac window.

## What changed

- **Project:** `SUPPORTS_MACCATALYST`, Mac idiom (`TARGETED_DEVICE_FAMILY = 1,2,6`), the same bundle ID
  (`DERIVE_MACCATALYST_PRODUCT_BUNDLE_IDENTIFIER = NO`), category Photography, hardened runtime on Mac.
  The Watch app is built and embedded for iOS only (platform filter).
- **Entitlements** (`Shutterlink-Mac.entitlements`, macOS SDK only; the iOS app still has none): App Sandbox,
  network client (HTTP and PTP/IP to the camera), network server (UDP live view from Olympus and LUMIX),
  Photos, Location (geotagging), user-selected files read/write (Save As…, RAWs to a folder).
- **iOS-only pieces guarded:** `WatchBridge` and its start-up; pocket mode's `UIScreen` brightness and idle
  timer; `WindowSceneReader` and the Dynamic Island orientation check in `RemoteView`; the Action button tip
  (the Mac version points to Spotlight and the Shortcuts app; the "Connect to Camera" intent works on Mac).
- **Staying awake:** `KeepAwake` uses the idle timer on iOS (as before). On a Mac it keeps the system awake
  while connected and opts out of App Nap, so live view and interval timers don't stall when the window is covered.
- **Wi-Fi:** on a Mac the Wi-Fi interface isn't always `en0` (desktops with Ethernet), so it's looked up with
  `NWPathMonitor`.
- **Window:** 1280×860 by default, never smaller than 980×740, so a Mac always gets the iPad workspace
  layouts and never the phone ones. Resizing switches between the wide and tall workspace layouts. One window
  only: File ▸ New Window and the document items are removed; closing the window and clicking the Dock icon
  brings it back.
- **Saving on a Mac:** a photo's **Save** still goes to Photos. **Save As…** writes the original to a folder you pick.
  **RAWs…** saves the RAWs of starred photos into a folder you pick, as they came off the card.
- **Copy:** on a Mac, messages say Mac, macOS, System Settings and "click"; on iOS every string is word for
  word what it was (`Platform` in `Camera/Platform.swift`).

## Menus and keyboard (Mac menu bar; iPad keyboard shortcuts too)

| Menu | Item | Key |
|---|---|---|
| Camera | Take Picture / Start–Stop Recording / Start–End Exposure | Space |
| | Restart Live View | ⌘R |
| | Browse Card… | ⌘O |
| | All Camera Settings… | ⌘I |
| | Request Log | ⌥⌘L |
| | Disconnect… | ⇧⌘D |
| Exposure | Aperture, Shutter Speed, ISO, Exposure Compensation, White Balance, Drive Mode (opens that dial) | ⌘1–⌘6 |
| | Next Value / Previous Value (steps the open dial) | ⌘→ / ⌘← |
| Tools | Every tool tile (Presets, Astro, Interval, Bracket, ND, Motion…) | Loupe ⌘L, Grid ⌘', Peaking ⇧⌘P, Night ⇧⌘N |

Space typed in a text field (naming a preset) stays in the field and doesn't fire the shutter (checked).

## What was tested on the Mac

Driver self-test (Debug, `-selfTest <brand> 127.0.0.1:<port>`) against the mocks, Mac build:

| Brand | Result |
|---|---|
| Olympus PEN-F | 0 failures: connect, UDP live view, settings, shoot, movie, interval, bracket, presets, ND, motion, card list, thumbnails, preview, JPEG + RAW download |
| Nikon Z 6 II | 0 failures |
| Canon EOS R6 | 0 failures |
| LUMIX GH5 | 1 failure: card list. The app always uses port 60606 for the LUMIX card, which was reserved for other test sessions, so the mock ran it elsewhere. Not a Mac problem. |
| Sony a6000 | 1 failure: scene analysis (no live frame to analyse). In the same run the motion trigger saw no movement and the ND meter saw a very dark frame, so Sony live view seems to go stale after the long-exposure steps. Same networking code as iOS; not yet compared on iOS. |

By hand against the PEN-F mock: the workspace layout, the menus, ⌘1–6 and ⌘→ (ISO 200 → 250 → 320 → 400, checked
against the mock), Space to shoot, the card browser split view, the Save As… panel (opens with the card's file name), the
RAWs… folder picker, closing and reopening the window. Builds: Mac Release universal (arm64 + x86_64, sandbox
entitlements in the signature, no Watch app inside), iOS Release for devices (Watch app embedded), iOS Simulator Debug.

## Not working or not checked yet

- **Writing files from Save As… and RAWs…:** both panels open, but the test automation can't press Save or
  Open in a Mac file panel, so writing the file wasn't confirmed. Try each once by hand.
- **Saving to Photos and geotagging on a Mac:** not tried; they'd add test pictures to the real library and
  ask for Location.
- **A real camera from a Mac:** not tried. The Mac has to join the camera's Wi-Fi itself (it loses internet
  meanwhile). A desktop Mac whose Ethernet LAN also uses 192.168.0.x may send camera traffic to Ethernet;
  unplug it or turn it off.
- **Sony scene-analysis failure** above, and LUMIX card browsing on a Mac.
- **Seen once, not reproduced:** while the user was trying the app, the ISO tile showed 400 while the mock was at
  200. After a reconnect, stepping and reopening the dial stayed in step with the camera.
- **View ▸ Show Tab Bar** is still in the View menu (UIKit adds it); its "+" might open a second window. Not tried.
- macOS remembers the last window size, so the 1280×860 default only applies the first time.
- The Mac app needs macOS 26 (it follows the iOS 26 deployment target).

## App Store Connect: what's needed to ship it

1. **Don't touch iOS 1.0 (4)** while it's in review. Ship the Mac app as its own macOS version once that's
   settled; bump `CURRENT_PROJECT_VERSION` before archiving (iOS and Mac share it).
2. **Add the macOS platform to the existing Shutterlink app record** (the app's page ▸ Add Platform ▸ macOS).
   Same bundle ID, so it's a universal purchase automatically: one price, and people who bought it on iPhone/iPad
   get it on Mac. If the price goes to $10, that one price covers all three.
3. **Signing:** in Xcode, archive with the destination **Any Mac (Mac Catalyst)** and Distribute ▸ App Store Connect.
   Automatic signing with team 9FK83T63MP creates the Mac Catalyst provisioning profile. Uploading a Mac app
   also needs a **Mac Installer Distribution** certificate (an Admin or the Account Holder on the team can let
   Xcode create it). No new App ID capabilities are needed: the sandbox, Photos and Location are entitlements only.
4. **macOS version page:** Mac screenshots (16:10, e.g. 2880×1800 or 1440×900), description, keywords and
   What's New (each platform has its own), plus review notes (same camera/mock explanation as iOS).
   Privacy labels, age rating, category and price are shared with iOS.
5. **Mac availability:** today the iPad app is offered on Apple silicon Macs ("Designed for iPad"). Once the Mac
   Catalyst version is live with the same bundle ID, it takes that place on the Mac App Store.
6. **TestFlight for Mac** works the same way as iOS if you want testers first.

## Build and test locally

`xcodebuild` hangs inside ~/Documents (iCloud), so copy the project out first:

```sh
rsync -a --delete --exclude .git --exclude android ./ /tmp/shutterlink-src/
cd /tmp/shutterlink-src
xcodebuild -project Shutterlink.xcodeproj -scheme Shutterlink -configuration Debug \
  -destination 'generic/platform=macOS,variant=Mac Catalyst' -derivedDataPath /tmp/shutterlink-dd \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= build
open /tmp/shutterlink-dd/Build/Products/Debug-maccatalyst/Shutterlink.app
```

(`CODE_SIGN_IDENTITY=-` signs it locally, so nothing is registered with the Apple account.) Start a mock, e.g.
`python3 mock-camera/mock_penf.py --port 8280`, then in the app: Add your camera ▸ Advanced ▸ Camera address
`127.0.0.1:8280` ▸ Connect. Self-test:
`…/Shutterlink.app/Contents/MacOS/Shutterlink -selfTest olympus 127.0.0.1:8280` (prints SELFTEST lines).
