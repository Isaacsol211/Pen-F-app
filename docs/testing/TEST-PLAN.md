# Shutterlink test plan

One plan for every brand and model. A run against a camera (mock or real) fills in a copy of
[`results/TEMPLATE.md`](results/TEMPLATE.md), saved as `results/<brand>-<model>.md`. Nobody writes a new plan per
camera: a check that doesn't apply to a model is marked **N/A** with the reason.

Written against `main` 5da84a8 (1.1 in progress: Shutterlink Pro, $9.99 once, 7-day trial).

## Contents

1. [How to use this plan](#1-how-to-use-this-plan)
2. [Setup](#2-setup)
3. [Which cameras to run](#3-which-cameras-to-run)
4. [Automatic: the built-in self-test](#4-automatic-the-built-in-self-test) (`ST-`)
5. [Home, saved cameras, Add a camera, QR](#5-home-saved-cameras-add-a-camera-qr) (`UI-HOME-`, `UI-ADD-`, `UI-QR-`)
6. [Remote screen](#6-remote-screen) (`UI-REMOTE-`, `UI-STRIP-`, `UI-MODE-`, `UI-SHUT-`, `UI-LV-`, `UI-AID-`)
7. [Tools](#7-tools) (`UI-TOOLS-`, `PRESET-`, `ASTRO-`, `INT-`, `BRK-`, `FSTK-`, `ND-`, `MOT-`, `HIRES-`, `MISC-`)
8. [Card browser and auto-save](#8-card-browser-and-auto-save) (`GAL-`, `ASAVE-`)
9. [⋯ menu, All camera settings, Request log](#9--menu-all-camera-settings-request-log) (`MENU-`, `SET-`, `LOG-`)
10. [Pro screen and locks](#10-pro-screen-and-locks) (`PRO-`)
11. [Watch, iPad, Mac](#11-watch-ipad-mac) (`WATCH-`, `PAD-`, `MAC-`)
12. [UX sweep](#12-ux-sweep) (`UX-`)
13. [Storage and resources](#13-storage-and-resources) (`RES-`)
14. [Per-model mockup record](#14-per-model-mockup-record) (`MODEL-`)
15. [Value and pricing](#15-value-and-pricing) (`VAL-`)
16. [Real camera only](#16-real-camera-only) (`HW-`)
17. [What applies to which brand](#17-what-applies-to-which-brand)

---

## 1. How to use this plan

### The three ways a check runs

| Tag | Means | Who |
|---|---|---|
| **A** | Automatic: the Debug build's self-test against a mock. No screen needed. | A script |
| **S** | Simulator: the app in the iOS Simulator against a mock, driven by tapping and screenshots. | An agent or a person |
| **H** | Human with a real camera (and a real iPhone, Watch or Mac where the check says so). | A person |

A check tagged **S·H** runs on the mock first and is repeated on a real camera when one is available. A mock only
proves the app's side; anything about what a real body accepts stays "mock only" until an **H** run.

### Results

Each row in the per-model sheet gets one of:

| Result | Use it when |
|---|---|
| **P** | It did what "Pass" says, and nothing in "UX failure" showed up. |
| **F** | It didn't do what "Pass" says. Write a finding (below). |
| **UX** | It works, but something in "UX failure" showed up. Write a finding. |
| **N/A** | The model can't do this. Say why in one phrase ("no card browser on this body"). |
| **—** | Not run. Say why ("needs a real camera", "simulator has no Watch"). |

**N/A is a result, not a skip.** Before marking N/A, check the app *hides or explains* the feature for this model
(that is `UX-02` and `UX-03`). A control that is shown but does nothing is an **F**, not N/A.

### Findings

One entry per problem, in the sheet's Findings table:

- **ID:** `<sheet>-F<n>`, e.g. `olympus-pen-f-F3`. Name the check that found it.
- **Severity:**
  - **S1** blocks shooting or loses photos (crash, hang, wrong setting sent, card data lost);
  - **S2** a feature doesn't work on this model, or a paying user would ask for a refund;
  - **S3** works but confuses (dead end, missing feedback, wrong label, buried control);
  - **S4** polish (spacing, wording, truncation).
- **Steps** to reproduce, from a named starting state.
- **Evidence:** a screenshot in `results/img/<sheet>/`, a `SELFTEST` line, or request-log lines.
- **Suggested fix:** one or two sentences. Runs don't change app code.

### Rules for every run

- **Never test against a real camera unless the check is tagged H and a person is holding it.** The self-test takes
  pictures and changes settings; it refuses any address that isn't `127.x` or `localhost`. Nothing in this plan
  flashes firmware or formats a card.
- **One heavy job at a time** on the test Mac: one build, or one simulator, never both, never two simulators.
  Shut the simulator down when a run ends (`xcrun simctl shutdown all`).
- Record the build (`git rev-parse --short HEAD`), the simulator or device, the mock command line and the date at
  the top of the sheet.
- Take a screenshot for every **UX** and **F** result that is about what the screen shows.
- Don't fix as you go. If a check is blocked by an earlier failure, mark it **—** "blocked by `<finding>`".

---

## 2. Setup

### Build (Debug, simulator)

`xcodebuild` hangs inside `~/Documents` (iCloud). Copy the checkout out first and keep DerivedData outside
Documents too:

```bash
rsync -a --delete --exclude .git --exclude android --exclude 'mock-camera/frames' "$SRC/" "$SP/src/"
```

```bash
cd "$SP/src" && xcodebuild -project Shutterlink.xcodeproj -scheme Shutterlink -destination 'platform=iOS Simulator,id=B6378FC4-7AF8-4AB3-8FD7-FE5DBB452A46' -derivedDataPath "$SP/DD" -quiet build
```

`$SRC` is the checkout under test, `$SP` a scratch folder outside Documents. The app lands in
`$SP/DD/Build/Products/Debug-iphonesimulator/Shutterlink.app`. Simulators: iPhone 17
`B6378FC4-7AF8-4AB3-8FD7-FE5DBB452A46`, iPad Pro 13 `33DC2F61-721D-49DB-806F-F5E1F844F0FE`.

### Mocks (`mock-camera/`)

Run with `python3 -I -u <mock> …`. Each listens on 127.0.0.1.

| Brand | Mock | Port | Options that change what the app sees |
|---|---|---|---|
| Olympus / OM System | `mock_penf.py` | 8080 | `--model <name>`: what `get_caminfo` reports (`PEN-F` default, `E-M10MarkIII`, `OM-1`, `AIR-A01`…). The settings and command list are the same for every name. |
| Panasonic LUMIX | `mock_lumix.py` | 8082 | `--model DC-GH5` (default) or `DMC-G7` (serves the real G7's menu); `--sticky-drive` (drive can't be changed, like a physical dial); `--refuse` (camera answers No to pairing); `--encrypted` (newer pairing) |
| Nikon | `mock_nikon.py` | 15740 | `--dslr` (D750-style instead of Z 6II-style) |
| Canon | `mock_canon.py` | 8084 | – (EOS R6-style) |
| Sony | `mock_sony.py` | 8086 | – (a6000-style) |

**What the mocks don't model** (so a pass here proves less than it looks):

- The Olympus mock has the same properties whatever `--model` says. Per-model differences in the app come only
  from `ModelProfiles.swift` (High Res Shot, notes, unsupported bodies). It offers `artfilter` and `colortone`,
  which the real PEN-F (firmware 3.1) does not, and lacks the PEN-F's `exposemovie` and `colorphase`. It sends
  640×480 for `getlastjpg`.
- Mock RAW files are random bytes: Photos refuses them, so the app's "save to Files instead" path is what gets tested.
- No mock drops Wi-Fi, runs out of battery, overheats or fills its card by itself.

### Launch arguments (Debug builds)

| Argument | Effect |
|---|---|
| `-selfTest <olympus\|panasonic\|nikon\|canon\|sony\|auto> 127.0.0.1:<port>` | Runs the self-test (section 4). The app **stays connected** afterwards, which is a quick way into the remote screen. |
| `-pro locked` | Pro locked: test the locks and the Pro screen. |
| `-pro trial` | Shows the trial state ("Trial: 6 days left (debug)"). |
| `-pro store` | The real App Store logic (use with `Shutterlink.storekit` from Xcode). |
| (none) | Pro unlocked ("Unlocked (developer build)"). |
| `-sceneLabels night_sky:0.97,sky:0.9` | Stands in for the scene classifier, which doesn't run in the Simulator. |
| `-connectFromShortcut` | Same as running the "Connect to Camera" shortcut. |

```bash
xcrun simctl launch --console-pty --terminate-running-process B6378FC4-7AF8-4AB3-8FD7-FE5DBB452A46 com.apexcommerce.shutterlink -selfTest olympus 127.0.0.1:8080
```

### Connecting by hand in the simulator

Add a camera ▸ pick the brand (or Automatic) ▸ **Advanced** ▸ **Camera address** `127.0.0.1:<port>` ▸ **Connect**.

### Fresh state

Some checks need a first launch: `xcrun simctl uninstall <sim> com.apexcommerce.shutterlink`, then install again.
This also clears saved cameras, the LUMIX menu cache and stars.

---

## 3. Which cameras to run

Run **one sheet per row**. Start with Olympus, report, and wait before the next brand.

| Order | Sheet | Mock command | Why this one |
|---|---|---|---|
| 1 | `olympus-pen-f` | `mock_penf.py` | The only Olympus body tried on hardware. Full run of every section. |
| 2 | `olympus-e-m10-mark-iii` | `mock_penf.py --model E-M10MarkIII` | A body without High Res Shot: checks the tool is hidden and nothing else changes. |
| 3 | `olympus-e-m1` | `mock_penf.py --model E-M1` | Has a one-time note ("Wi-Fi set to Private", no movie mode). |
| 4 | `olympus-e-m1-mark-iii` | `mock_penf.py --model E-M1MarkIII` | "Olympus may restrict remote shooting" note + High Res Shot. |
| 5 | `olympus-om-1` | `mock_penf.py --model OM-1` | OM System note (Device Connection, newer protocol unconfirmed). |
| 6 | `olympus-tg-5` | `mock_penf.py --model TG-5` | A compact: brand defaults, no notes. |
| 7 | `olympus-air-a01` | `mock_penf.py --model AIR-A01` | **Unsupported**: must refuse with a reason, not half-connect. |
| 8 | `olympus-tg-tracker` | `mock_penf.py --model TG-Tracker` | Unsupported, second reason text. |
| 9 | `olympus-unknown` | `mock_penf.py --model E-XYZ9` | A body not in the table: must still connect with brand defaults. |
| 10 | `panasonic-dmc-g7` | `mock_lumix.py --model DMC-G7 --sticky-drive` | Tried on hardware. No mode or drive control over Wi-Fi. |
| 11 | `panasonic-dc-gh5` | `mock_lumix.py` | Default LUMIX; add `--refuse` and `--encrypted` passes for `UI-ADD-09` and `UI-ADD-10`. |
| 12 | `nikon-z6ii` | `mock_nikon.py` | Mirrorless, with video. |
| 13 | `nikon-d750` | `mock_nikon.py --dslr` | DSLR: no video. |
| 14 | `canon-eos-r6` | `mock_canon.py` | CCAPI. |
| 15 | `sony-a6000` | `mock_sony.py` | Camera Remote API. |

**Full run vs short run.** The first sheet of each brand is a full run (every section). Other models of the same
brand run the **short run**: sections 4, 5 (`UI-ADD-06` to `-08` only), 6, 14 and 15, plus any check whose result
could differ because of that model's profile. Write "as `<first sheet>`" for the rest.

The other bodies in `ModelProfiles.swift` (35 Olympus / OM System, about 60 LUMIX) follow the same rule: pick one
from each group that differs in its profile (a note, `highResShot`, `fixedExposure`, `noISO`, `noExposureComp`,
`noVideo`, `pairing`) and run the short run. For LUMIX profile flags, the mock doesn't change its menu, so those are
checked by reading what the app hides, and confirmed only on hardware.

---

## 4. Automatic: the built-in self-test

Launch with `-selfTest` (section 2) and collect the `SELFTEST` lines until `SELFTEST DONE failures=<n>`. Allow four
minutes. Paste the lines into the sheet. Each check below is one line; a missing line means the app skipped it for
this camera (say why), and a `FAIL` is a finding.

| ID | Run | Check and steps | Pass | UX failure |
|---|---|---|---|---|
| ST-01 | A | **Connect.** Line `connect`. | `PASS`, with the right `brand=` and a `name=`. Auto-detect (`-selfTest auto`) picks the same brand. | Name is empty or carries "(mock)" clutter into the UI in a way a real name wouldn't. |
| ST-02 | A | **Profile.** Line `INFO profile=… support=… crop=… note=…`. | Profile matches the model in the sheet (or `none` for an unknown body); crop factor is right for the sensor (2.0 for Micro Four Thirds, 1.5/1.6 APS-C, 1.0 full frame). | Wrong crop factor: Astro's 300/500-rule shutter will be wrong. |
| ST-03 | A | **Live view.** Line `live view`. | `PASS`, fps above 2 (expect 10 to 30 on a mock), frame size as the mock sends. | – |
| ST-04 | A | **Settings read.** Line `settings read`. | Lists every property with its option count. Copy it to the mockup record (section 14). | A property with `[0]` options that the strip still shows. |
| ST-05 | A | **Set each exposure setting.** Lines `set expcomp`, `set focalvalue`, `set shutspeedvalue`, `set isospeedvalue`, `set wbvalue` (LUMIX also `drivemode`, `colormode`, `afmode`, Kelvin). | Each present line is `PASS`. A missing line means "not settable in the current mode": list which. | – |
| ST-06 | A | **Tap focus.** Line `tap focus`. | `PASS`, or absent where the camera has no tap AF. | – |
| ST-07 | A | **Shoot and review.** Lines `shoot`, `last-shot review`. | Both `PASS` (review absent where the body can't). | – |
| ST-08 | A | **Movie.** Line `movie`. | `PASS`, or absent where the body has no video. | – |
| ST-09 | A | **Interval.** Line `interval`. | `shots=2`. | – |
| ST-10 | A | **Bracket.** Line `bracket`. | Shot count equals the frames, and the setting went back afterwards. | – |
| ST-11 | A | **Focus stack.** Line `focus stack`. | `shots=3` on LUMIX, Nikon, Canon; absent on Olympus and Sony. | – |
| ST-12 | A | **Scene assistant.** Lines `sky positions`, `scene rules`, `scene analysis`. | All `PASS`. | – |
| ST-13 | A | **Every preset.** Lines `preset astro`, `preset moon`, … one per recipe. | Each `PASS`. Copy each line to the sheet: every step reads `property=value`, `:skip` or `:FAILED(why)`. **Any `:FAILED` is a finding**, and every `:skip` goes to `PRESET-06` to check its wording. | – |
| ST-14 | A | **Undo and saved preset.** Lines `preset undo`, `saved preset`. | Both `PASS`; `saved preset` reports more than 0 values. | – |
| ST-15 | A | **ND setup.** Line `nd setup`. | `PASS`, and the reported shutter is the metered one × 2^6 (or Bulb when longer than the camera's longest). | – |
| ST-16 | A | **Motion trigger.** Line `motion trigger`. | `shots` ≥ 1 and `peak` above `threshold`. | – |
| ST-17 | A | **Expose to the right.** Line `ettr`. | `PASS` (it finishes). Note what it did to EV. | It left EV changed with no message. |
| ST-18 | A | **Battery.** Line `battery`. | A percentage. | – |
| ST-19 | A | **Card.** Lines `card list`, `thumbnail`, `preview`, `download`, `download RAW`. | All `PASS` where the body has a card browser; RAW is over 100 KB. | – |
| ST-20 | A | **Back to live view.** The lines after the card closes, and `SELFTEST DONE`. | `failures=0`, and live view is running again when the test ends. | – |
| ST-21 | A | **Refuses real cameras.** Launch with `-selfTest olympus 192.168.0.10`. | One line `SELFTEST refused`, and no request is sent. | – |

---

## 5. Home, saved cameras, Add a camera, QR

Start from a fresh install unless the check says otherwise.

| ID | Run | Check and steps | Pass | UX failure |
|---|---|---|---|---|
| UI-HOME-01 | S | **First launch.** Fresh install, open the app. | "Shoot from your phone." with the brand line, "No cameras yet", **Add your camera**, and (iPhone/iPad) **Scan the camera's QR code**. | No obvious first step; text truncated; a blank area where the list will be. |
| UI-HOME-02 | S | **Wi-Fi status line.** Read the status under the title with the Mac on normal Wi-Fi. | It says which network situation this is ("On another Wi-Fi network (…). Join the camera's network first.") | It says nothing, or shows a raw IP with no instruction. |
| UI-HOME-03 | S | **Saved camera card.** After one successful connect, disconnect. | The camera appears under "Your cameras" with name, brand and "last used"; **Add a camera** moves under the list. | Mock clutter in the name; brand mark wrong; no "last used". |
| UI-HOME-04 | S | **Reconnect from the card.** Tap the card with the mock running. | "Connecting…" then the remote screen, within 5 s. | No progress shown; the card can be tapped twice and connects twice. |
| UI-HOME-05 | S | **Card with the camera off.** Stop the mock, tap the card. | A clear failure within about 10 s that says what to do (turn on Wi-Fi, join the network), and the card is tappable again. | Spinner forever; a raw `URLError`; the error stays on screen after a later success. |
| UI-HOME-06 | S | **Forget a camera.** Long-press the card ▸ **Forget this camera**. | It asks or acts at once, the card goes, and its Wi-Fi password is gone with it. | No way to find Forget without knowing about long-press (note it as S3). |
| UI-HOME-07 | S | **Two cameras, right Wi-Fi each.** Connect to two mocks of different brands, each added with its own network name typed in. Tap each card. | Each card connects to its own address and brand, and keeps its own network (regression: saved cameras used to take the wrong Wi-Fi). | The second camera's network overwrote the first. |
| UI-HOME-08 | S | **Most recent first.** Connect to the older camera again. | It moves to the top. | – |
| UI-HOME-09 | S | **Shortcut tip.** Read the tip under the list. | It names the "Connect to Camera" shortcut and where to put it (Action button on iPhone; Spotlight/Shortcuts on Mac). | The tip shows before any camera is saved, or names a button the device doesn't have (iPad, Mac). |
| UI-ADD-01 | S | **Open Add a camera.** Tap **Add your camera**. | Sheet with **Automatic** (Recommended) and each brand, "How to connect" steps, **Connect**, **Cancel**. | Brand list scrolls off with no hint; Beta brands not marked as Beta. |
| UI-ADD-02 | S | **Steps change with the brand.** Tap each brand in turn. | The three steps name that brand's own menu path (Olympus "Connection to Smartphone", LUMIX "Remote Shooting & View", Nikon "Connect to smart device", Canon "Unlock CCAPI once", Sony "Smart Remote"). | Steps for the wrong brand; Canon's CCAPI requirement not visible before the user tries. |
| UI-ADD-03 | S | **Advanced.** Open **Advanced**. | Camera address (placeholder "Automatic"), User-Agent (Olympus), Live view size, and the hint naming the mock ports. | Advanced is needed for an ordinary connection; fields unlabeled. |
| UI-ADD-04 | S | **Connect, right brand.** Pick the brand, set the mock address, **Connect**. | Remote screen opens; the camera is saved. | – |
| UI-ADD-05 | S | **Connect, Automatic.** Same with **Automatic**. | Same camera and brand as `UI-ADD-04`. | It tries every brand slowly with no progress text. |
| UI-ADD-06 | S | **Wrong brand picked.** Pick a different brand than the mock, same address. | A failure that says the camera didn't answer as that brand and suggests Automatic. | Hangs; connects half-way; a protocol error shown raw. |
| UI-ADD-07 | S | **Unsupported body.** Run the mock as an unsupported model (`AIR-A01`, `TG-Tracker`). | The app stops and shows the profile's reason, and doesn't save the camera as working. | It connects and shows a broken remote screen; reason is technical ("switch_cameramode") with nothing the user can do. |
| UI-ADD-08 | S | **One-time model note.** Connect to a body with a profile note (E-M1, E-M1 Mark III, OM-1, E-M10 Mark IV, LUMIX G9, S5…). | The note shows once after connecting, can be dismissed, and is in the request log. It doesn't show for bodies without one. | The note covers the shutter or the strip; shows on every connect; can't be dismissed. |
| UI-ADD-09 | S | **Camera says No (LUMIX).** `mock_lumix.py --refuse`. | "Approve on the camera" style message, and a retry works after restarting the mock without `--refuse`. | A generic "couldn't connect". |
| UI-ADD-10 | S | **Newer LUMIX pairing.** `mock_lumix.py --encrypted`. | Connects, live view runs. | – |
| UI-ADD-11 | S | **Nothing at the address.** No mock running, address `127.0.0.1:8080`. | "No answer yet, retrying (2/3)…" then a failure that names the next step. Takes under 15 s. | Silent wait; **Connect** stays disabled afterwards. |
| UI-ADD-12 | S | **Cancel while connecting.** Start a connect to a dead address, tap **Cancel**. | The sheet closes and no late error or late connect appears. | The remote screen opens after Cancel. |
| UI-ADD-13 | S | **Type the camera's Wi-Fi.** Fill "Network name" and "Password" (iPhone/iPad). | The button becomes **Join Wi-Fi and Connect**. In the Simulator the join itself fails: the message must say so plainly. | Password shown in clear with no option; button label doesn't change. |
| UI-QR-01 | S | **Scanner without camera access.** Tap **Scan the camera's QR code** in the Simulator. | "Camera access is off…" with the way to turn it on, or the scanner's "Type It Instead". | A black screen with no way out. |
| UI-QR-02 | H | **Scan a real code.** On a real camera's Wi-Fi screen. | Olympus/OM `OIS1,…`, standard `WIFI:` and Sony `W01:` codes join and connect in one go; the code is written to the request log. | An unreadable code gives no "type it instead" route. |
| UI-QR-03 | H | **Scan something else.** Point at a non-camera QR code. | "Shutterlink can't read this camera's code yet…", and typing is offered. | It tries to join a network named after the code. |

---

## 6. Remote screen

Connected, Pro unlocked, iPhone portrait unless a check says otherwise. Repeat `UI-REMOTE-01` and `UI-STRIP-01` in
landscape.

### Layout and top bar

| ID | Run | Check and steps | Pass | UX failure |
|---|---|---|---|---|
| UI-REMOTE-01 | S | **First screen after connect.** Screenshot portrait and landscape. | Top bar (camera name, battery %, shots left), live view, exposure strip, mode carousel, shutter, Tools button, last-shot/Card button, quick-aid row, ⋯. Nothing overlaps or is cut off; the shutter rail in landscape is on the side away from the Dynamic Island. | "Reading camera settings…" for more than 3 s; an empty strip; controls under the Dynamic Island or home indicator. |
| UI-REMOTE-02 | S | **Top bar values.** Compare battery and shots left with what the mock reports. | Both match and update after a shot. Hot-camera warning ("Camera is hot") shows only when reported. | A battery icon with no number; "0" shots left when unknown instead of hiding it. |
| UI-REMOTE-03 | S | **Dynamic Type.** Set the largest text size, reopen. | Layout holds (text size is capped); nothing truncates to "…". | Strip values truncated; buttons pushed off screen. |
| UI-REMOTE-04 | S | **Small phone.** Run on the smallest supported iPhone simulator if one is installed. | Strip, mode and shutter all fit; the quick-aid row may hide (it's for taller phones) but its tools are still in the Tools grid. | A control exists only in the row that got hidden. |
| UI-REMOTE-05 | S | **Error banner.** Cause a refused setting (stop the mock for one request, or set a value the mode refuses). | A yellow banner says what was refused and why, and has Dismiss. The old value is put back on the strip. | The strip keeps showing the value the camera refused; banner never goes away; banner hides the shutter. |
| UI-REMOTE-06 | S | **Connection lost.** Kill the mock while connected. | Within about 10 s the app says the camera stopped answering and returns to home (or offers Reconnect). Running interval/bracket stops cleanly. | Frozen last frame with live-looking controls; taps do nothing with no message. |
| UI-REMOTE-07 | S | **Background and return.** Send the app to the background for 30 s, return. | Either still connected with live view restarted, or a clear "reconnect" state. | Black live view with no "Restart live view"; stale values. |
| UI-REMOTE-08 | S | **Toasts.** Do three things that toast (geotag on, save, sync clock). | Each toast is readable for about 2 s and they don't stack over the shutter. | A toast is the only feedback for something important and is easy to miss (note which). |

### Exposure strip

The strip holds, in order: aperture (F-stop), shutter, ISO, EV, WB, Drive, Quality, and Video (movie exposure) in
movie mode. A cell only exists when the camera reports that property.

| ID | Run | Check and steps | Pass | UX failure |
|---|---|---|---|---|
| UI-STRIP-01 | S | **Which cells show.** Screenshot the strip. List the cells. | Every property the camera reports from the list above has a cell; none is missing or doubled; all fit without clipping, or the strip scrolls with a visible cue. | A cell is off-screen with no hint the strip scrolls; Drive or Quality pushed out of sight on this model. |
| UI-STRIP-02 | S | **AUTO marks.** In P, then A, S, M (where the mode can be set). | Cells the camera is choosing say **AUTO** above the live value; Drive and Quality never say AUTO. | AUTO on a value the user just set; no visible difference between settable and camera-chosen cells. |
| UI-STRIP-03 | S | **Aperture dial.** In A or M, tap F-stop, swipe to another value. | The dial opens in place with the camera's own list, including the **widest** aperture the lens offers (regression: the widest value was missing on LUMIX); the camera takes the value; the strip shows it. | First or last value unreachable; dial lists values the lens doesn't have; no haptic or highlight on the selected value. |
| UI-STRIP-04 | S | **Shutter dial.** In S or M, tap Shutter. | Timed speeds on the dial; Bulb / Live Time / Live Composite as separate segments where the camera lists them; the note under a Live mode explains tap-to-start/stop. | Bulb hidden at the far end of a long dial; "livecomp" or another raw code shown. |
| UI-STRIP-05 | S | **ISO dial.** Tap ISO, pick a number, then Auto. | Both taken; Auto reads "AUTO" not "auto"; "Low" (Olympus) reads sensibly. | Raw values ("Auto" vs "auto" both listed). |
| UI-STRIP-06 | S | **EV dial.** In P/A/S, tap EV, move ±. | Thirds from the camera's range; 0 easy to return to; the strip shows a sign. | No quick way back to 0; −0.0 shown. |
| UI-STRIP-07 | S | **White balance.** Tap WB, pick Daylight, then Auto. | A grid or dial with names and icons, never codes ("18"); custom/Kelvin entries labeled. | Numbers instead of names; four identical "Custom" entries with no number. |
| UI-STRIP-08 | S | **Drive.** Tap Drive, pick continuous, then self-timer, then single. | Grid with icons and names; camera takes each. On a body whose drive is a physical dial (LUMIX G7, `--sticky-drive`), the cell shows the camera's current drive and the panel says to turn the dial. | Raw names ("lowvib-continuous-L"); a grid of options that all get refused with only an error banner. |
| UI-STRIP-09 | S | **Quality.** Tap Quality (where the camera reports it), switch between JPEG, RAW and RAW+JPEG. | The camera takes it and the cell shows it in words. Where the camera doesn't report quality over Wi-Fi (Olympus), there is no cell: note in the mockup record whether a user would look for it. | Cell shows a code; choosing RAW gives no warning that auto-save only saves JPEG/HEIF. |
| UI-STRIP-10 | S | **Locked setting explains itself.** In P, tap Shutter (and F-stop; in M, tap EV). | "The camera sets this itself in P mode." and a one-tap unlock ("Switch to S (shutter priority)") that works. Where the app can't change the mode (G7), it says to turn the mode dial and to which letter. | A dial that moves but snaps back; an unlock button that fails silently; no explanation. |
| UI-STRIP-11 | S | **Movie exposure cell.** Switch to movie mode. | A Video cell appears (where the camera reports `exposemovie`), with P/A/S/M. Leaving movie mode closes its panel. | The cell stays in photo mode; it's the 8th cell and falls off screen. |
| UI-STRIP-12 | S | **One panel at a time.** Open ISO, then tap EV, then tap live view. | The panel swaps, then closes; the selection highlight follows. | Two panels; a panel that needs its small ✕ to close. |
| UI-STRIP-13 | S | **Values follow the camera.** Change a setting on the mock side (or let P mode change the shutter). | The strip updates within a second or two without a tap. | Stale value until the panel is opened. |
| UI-STRIP-14 | S | **Strip while busy.** During a long exposure or interval run, tap a cell. | Cells are visibly disabled (or changes are refused with a reason). | Looks enabled, does nothing. |

### Mode carousel

| ID | Run | Check and steps | Pass | UX failure |
|---|---|---|---|---|
| UI-MODE-01 | S | **Change mode.** Swipe or tap P → A → S → M → movie (and iAuto/ART where listed). | The camera takes each; the strip's AUTO marks and locks change to match; "iauto" reads AUTO and "movie" reads VIDEO. | Mode changes but the strip still shows the old locks. |
| UI-MODE-02 | S | **Mode can't be set (physical dial).** A body that reports the mode read-only (LUMIX G7) or not at all. | The carousel shows the camera's mode as a read-only indicator, or is hidden, and a first tap explains "turn the camera's mode dial". Presets tell the user which letter to turn to. | A carousel that scrolls but changes nothing; no mode shown at all, so the user can't tell why aperture is locked. |
| UI-MODE-03 | S | **Mode during exposure.** Start a long exposure, try to change mode. | Disabled until it ends. | – |
| UI-MODE-04 | S | **Video switch.** A brand whose photo/video mode the app can't read (LUMIX, Nikon, Canon, Sony). | A **Video** tool appears in Tools; on, the shutter becomes a record button. | No sign which mode the app thinks it is in. |

### Shutter

| ID | Run | Check and steps | Pass | UX failure |
|---|---|---|---|---|
| UI-SHUT-01 | S·H | **Single shot.** Tap the shutter. | One shot; shutter animates; shots-left drops; last-shot thumbnail appears where the body supports review. | No feedback between tap and thumbnail on a slow camera. |
| UI-SHUT-02 | S·H | **Burst.** Drive on continuous, hold the shutter 2 s, release. | A burst starts and stops with the finger. Where the brand can't hold (note which), a single shot plus a hint. | Burst keeps running after release. |
| UI-SHUT-03 | S·H | **Long timed exposure.** M, 4 s. | A countdown ring and seconds; "NR" (or similar) while the camera finishes; strip and Card locked meanwhile; the screen stays awake. | Shutter looks idle during the exposure; a second tap queues a second shot. |
| UI-SHUT-04 | S·H | **Bulb / Live Time / Live Composite.** Pick each from the shutter segments. | First tap opens the shutter and shows an elapsed timer; second tap closes it. "Stop after" (30 s, 1–10 min, custom) stops it by itself with a countdown. | No sign the exposure is still running; timer choices hidden unless the user knows to look. |
| UI-SHUT-05 | S·H | **Movie record.** Movie mode (or Video switch), tap the shutter twice. | Red record state with a clock; second tap stops; a finished clip counts as a shot. Absent on bodies without video. | Record button looks like the photo shutter. |
| UI-SHUT-06 | S | **Tap AF vs Tap shoots.** Tools ▸ **Tap AF** toggle to **Tap shoots**; tap live view. | Tap AF: an AF box with the camera's result (green/red) and a "Clear focus point" control. Tap shoots: focuses then shoots. | The toggle's two states aren't distinguishable; a stray tap takes a picture with no warning that Tap shoots is on. |
| UI-SHUT-07 | S | **Last-shot button.** After a shot, tap the thumbnail. | Opens the card on that photo. With no shot yet, it reads "Card". | – |
| UI-SHUT-08 | S | **Keyboard (iPad/Mac).** Space, ⌘R, ⌘O, ⌘I, ⌘1–⌘6, ⌘←/→. | Each does what the menu says; Space in a text field types a space. | – |

### Live view

| ID | Run | Check and steps | Pass | UX failure |
|---|---|---|---|---|
| UI-LV-01 | S·H | **Runs and fits.** Watch 30 s. | Smooth (no growing lag), right aspect ratio for the body (4:3, 3:2, 16:9 on the S5), no stretched frame. | Letterboxing that wastes the screen while controls are cramped. |
| UI-LV-02 | S | **Size picker.** ⋯ ▸ **Live view size** (where the camera lists sizes). | Each size takes effect; the choice survives a reconnect. Hidden where the camera lists none. | Raw "0640x0480" labels. |
| UI-LV-03 | S | **No frames arriving.** Block the stream (stop the mock's stream or change the UDP port). | "No live view frames are arriving." with the Local Network hint and **Restart live view**. | Black rectangle, no text. |
| UI-LV-04 | S | **Restart live view.** ⋯ ▸ **Restart live view**. | Stream back within 3 s. | – |
| UI-LV-05 | S | **Frame data.** Compare the strip with the values inside the frames (Olympus). | Aperture, shutter, ISO, EV, battery, shots and focal length come from the frames and match. | – |
| UI-LV-06 | S | **Scene suggestion pill.** Launch with `-sceneLabels night_sky:0.97,sky:0.9`. | One pill over live view ("Night sky → Astro"); tapping runs it; × hides it for ten minutes; ⋯ ▸ **Scene suggestions** turns them off. | The pill covers the AF point or the histogram; it reappears right after ×. |

### Quick aids

| ID | Run | Check and steps | Pass | UX failure |
|---|---|---|---|---|
| UI-AID-01 | S | **Grid.** Toggle from the quick row and from Tools. | Thirds grid over live view; both toggles stay in step; survives relaunch. | – |
| UI-AID-02 | S | **Histogram.** Toggle. | A live histogram that moves with the scene and doesn't cover the AF point. | Histogram of a stale frame. |
| UI-AID-03 | S | **Peaking.** Toggle. | Red edges on sharp detail; live view frame rate holds (compare the fps before and after). | Peaking lags seconds behind; fps halves. |
| UI-AID-04 | S | **Loupe.** Toggle; drag; change zoom. | A 4× loupe; live view switches to the camera's largest size while it's open and back after; the focus meter ("SHARPEST" / "keep turning") moves. | Live view size not restored after closing. |
| UI-AID-05 | S | **Night mode.** Toggle. | Whole UI red, including sheets and the card browser. | A white sheet or system dialog in night mode (note which). |
| UI-AID-06 | S | **Aids are still reachable when the row hides.** Landscape and small phones. | Every aid is in the Tools grid under **Switches**, lit amber when on. | – |

---

## 7. Tools

Open with the Tools button next to the shutter. **Shooting** holds tools that open a panel; **Switches** holds
toggles. Run with Pro unlocked; the locks are section 10.

| ID | Run | Check and steps | Pass | UX failure |
|---|---|---|---|---|
| UI-TOOLS-01 | S | **Grid contents.** Open Tools, screenshot. | Shooting: Presets, Astro, Interval, Bracket, ND filter, Motion, Pocket, High Res (only on bodies with it). Switches: Loupe, Night, Histogram, Grid, Peaking, Geotag, Tap AF (only with tap AF), Video (only with the video switch). | A tool for something this body can't do; more than two rows hidden below the fold with no cue. |
| UI-TOOLS-02 | S | **Open and close.** Open each Shooting tool and close it. | Each opens as a sheet (iPhone) or side panel (iPad/Mac) with a title and Done/✕; closing returns to live view. | A sheet that covers live view when the tool needs live view (Motion's box, ND metering). |
| UI-TOOLS-03 | S | **Running state on the button.** Start an interval; arm Motion. | The Tools button shows a count badge; the tool tile is lit. | No sign from the main screen that something is armed. |

### Presets (one-tap setups that stay on until turned off)

| ID | Run | Check and steps | Pass | UX failure |
|---|---|---|---|---|
| PRESET-01 | S | **List.** Tools ▸ Presets. | Astro, Moon, Fireworks, Landscape, Action, Macro, Light trails & silky water; **My presets** with **Save current**; **Expose to the right**. Each says in a line what it sets. | Names with no description; the user can't tell what will change before tapping. |
| PRESET-02 | S | **Apply.** Tap **Apply Moon** (then each other preset). | "Applying…", then a step list: each step is done (with the value), or skipped with what to do on the camera. The strip shows the new values. | Steps flash by; no summary of what changed. |
| PRESET-03 | S | **Stays on.** Close the sheet, change nothing, reopen. | The preset reads as on (tile lit; "Turn off · put back the settings from before"). | It looks "applied once" with no on/off state. |
| PRESET-04 | S | **Turn off puts settings back.** Note mode/aperture/shutter/ISO/WB/drive before applying; turn the preset off. | Every setting the preset changed is back to the noted value. | Only some go back; mode stays on M. |
| PRESET-05 | S | **Switch presets.** With Moon on, apply Landscape, then turn it off. | Settings return to what they were **before Moon** (not Moon's values), or the sheet says which. | Turning off lands on the previous preset's values with no explanation. |
| PRESET-06 | S | **Skipped steps say what to do.** For every `:skip` from `ST-13` and every skipped step on screen. | The step names the camera-side action ("Turn the camera's mode dial to M", "Set Auto ISO on the camera", "a 2 s self-timer…"). | A bare "Not offered by the camera over Wi-Fi" / "Not offered by the camera now" / "Not settable in this mode" with no next step. **List each one**: this was a real complaint. |
| PRESET-07 | S | **Preset the camera half-refuses.** Use a body with a physical mode dial (G7 mock) or stop the mock mid-apply. | Steps that worked stay marked done, the failed one says why, and Undo still puts back what changed. | "Applying…" forever; a half-applied preset shown as on. |
| PRESET-08 | S | **Save current / My presets.** Set a distinctive exposure, **Save current**, name it, change settings, apply it. | It's listed under My presets for this brand, applies the saved values, and can be deleted. It doesn't appear when connected to another brand. | No rename or delete; an empty name is accepted. |
| PRESET-09 | S | **Macro hands over to focus stack.** Apply Macro. | "Focus stack next" opens Bracket ▸ Focus on brands that can drive focus; elsewhere it points to the camera's own focus bracketing. | Button leads to a sheet that says it can't. |
| PRESET-10 | S | **Expose to the right.** Tap it with live view running. | "Measuring…", EV rises in steps and stops a step short of clipping, with a toast of the result. It refuses with a reason when live view doesn't follow exposure, and when EV isn't settable (M mode). | It runs with no visible progress; leaves EV changed after refusing. |
| PRESET-11 | H | **Do the presets give a good picture.** On a real camera, each preset on a matching scene. | The exposure is usable without further changes. | A preset a photographer would have to undo (wrong ISO floor, wrong WB). |

### Astro and star trails

| ID | Run | Check and steps | Pass | UX failure |
|---|---|---|---|---|
| ASTRO-01 | S | **Sheet.** Tools ▸ Astro. | Focal length picked up from the lens ("From your lens (… mm)") or a picker; 300 / 500 rule choice; "Will set" list; "Before you shoot" tips. | Focal length defaults to something unrelated to the lens with no note. |
| ASTRO-02 | S | **Shutter follows focal length.** Change focal length and rule. | Shutter = rule ÷ (focal length × crop factor), rounded down to a speed the camera has. Check one value by hand with the crop from `ST-02`. | Uses full-frame maths on a crop body. |
| ASTRO-03 | S | **Apply and turn off.** **Apply astro settings**, then "Astro is on · Tap to turn off". | M, widest aperture, the shutter above, ISO, about 4000 K white balance (or the nearest preset, with the reason shown). Turning off puts everything back. | White balance step silently skipped. |
| ASTRO-04 | S | **Star trails with Live Composite.** Turn on **Star trails** on a body that lists Live Composite (Olympus). | Shutter goes to Live Composite, and the tip says to set the base exposure on the camera and tap to start and stop. | No mention that the base exposure is set on the camera. |
| ASTRO-05 | S | **Star trails without Live Composite.** Same on a body without it (LUMIX, Nikon, Canon, Sony). | The sheet says it will shoot a series of 30 s frames with the interval timer, shows "Start the series: N frames, about M min", and starting it runs the interval with a progress ring. | A dead "not offered" step; the series starts with ramping left on from an earlier time-lapse. |
| ASTRO-06 | S | **Series can be stopped.** Start the series, stop after two frames. | Stops after the current frame; the count is right; settings stay as set (still in Astro). | – |

### Interval timer

| ID | Run | Check and steps | Pass | UX failure |
|---|---|---|---|---|
| INT-01 | S | **Sheet.** Tools ▸ Interval. | Frames (incl. "until stopped"), seconds, **Star stack** / **Time-lapse** starting points, a summary line ("N frames over about … At 25 fps that's a … s clip."). | No estimate of total time. |
| INT-02 | S | **Run 3 frames at 3 s.** | Three shots, start-to-start 3 s; a progress ring on the shutter; "Next shot in … s"; a badge on Tools. Ends by itself. | No countdown between frames. |
| INT-03 | S | **Stop mid-run.** | Stops at once or after the current frame, and says so. | – |
| INT-04 | S | **Interval shorter than the exposure.** Shutter 4 s, interval 2 s. | Warning "The interval is shorter than the exposure…", and it runs back to back without errors. | – |
| INT-05 | S | **Refuses Live modes.** Shutter on Bulb/Live Composite. | "Interval shooting needs a timed shutter speed…" and Start disabled. | Start enabled, then nothing happens. |
| INT-06 | S | **Follow the light.** Turn on **Follow the light** outside M, then in M. | Outside M: "Switch the camera to M…". In M: runs, and a ramp note appears when it changes shutter/ISO; never above **Highest ISO**. | Ramping silently off. |
| INT-07 | S | **Survives the sheet closing and pocket mode.** Start, close the sheet, open Pocket. | Keeps counting; pocket mode shows "next frame · N taken". | – |
| INT-08 | H | **An hour on a real camera.** 120 frames at 30 s. | All frames on the card; no missed frame; the phone doesn't lock. | – |

### Bracket and focus stack

| ID | Run | Check and steps | Pass | UX failure |
|---|---|---|---|---|
| BRK-01 | S | **Sheet.** Tools ▸ Bracket ▸ Exposure. | Frames 3/5/7/9, step ⅓–2 EV, what varies (Auto / EV / Shutter), and a "Will shoot" list of the actual values. | The list shows values the camera doesn't have. |
| BRK-02 | S | **Run 3 frames.** | Three shots with the listed values; progress "1/3 · +1.0" on the shutter; the setting goes back afterwards, as the sheet promised. | – |
| BRK-03 | S | **Cancel.** Cancel after the first frame. | Stops, puts the setting back. | Setting left at a bracket value. |
| BRK-04 | S | **Range ends.** 9 frames at 2 EV. | "Some frames reach the end of the camera's range and repeat a value." | Silent repeats. |
| BRK-05 | S | **Mode dial unknown.** A body whose mode can't be read (G7). | "Auto varies EV. In M, choose Shutter: the app can't read this camera's mode dial." | Bracket in M varies EV and shoots identical frames. |
| FSTK-01 | S | **Focus stack where the camera can.** LUMIX, Nikon, Canon: Bracket ▸ Focus, 3 frames, Medium. | Three shots with a focus step between; stops early at infinity with a message; "Not yet tried on a real camera of this brand" shown where true. | – |
| FSTK-02 | S | **Focus stack where it can't.** Olympus, Sony. | The Focus tab says the camera has no Wi-Fi command to move focus and points to the camera's own Focus BKT, with where to find it. | A Shoot button that errors; the tab hidden so the user thinks the feature doesn't exist (it's on the Pro list). |
| FSTK-03 | H | **Real stack.** A macro subject, 10 frames. | Focus visibly walks through the subject; frames stack cleanly. | Steps too coarse/fine for the labels. |

### ND filter, Motion trigger, High Res, the rest

| ID | Run | Check and steps | Pass | UX failure |
|---|---|---|---|---|
| ND-01 | S | **Meter.** Tools ▸ ND filter, step 1. | Shows the camera's current exposure; **Use this exposure** / **Meter again**; a hint to use A or P with a fixed ISO. | "Waiting for the camera's exposure…" forever in M. |
| ND-02 | S | **Pick a strength.** 3, 6, 10, 15 stops and the slider to 20. | The new shutter is metered × 2^stops, shown in plain time ("2 min 8 s"). | – |
| ND-03 | S | **Set up, short.** 6 stops from 1/60 s. | M with the metered aperture and ISO and about 1 s; the shutter button reads "Shoot 1 s". | – |
| ND-04 | S | **Set up, longer than the camera's speeds.** 15 stops. | "Longer than the camera's own speeds: the app runs Bulb and stops it. Keep Shutterlink open." and the exposure ends by itself. On a body with no Bulb over Wi-Fi (Nikon), it says so and what to do. | A Bulb exposure the app never stops. |
| MOT-01 | S | **Arm.** Tools ▸ Motion; drag the box over the mock's frame counter; arm. | The box shows on live view and can be dragged; "Armed · N shots so far" counts up; "Movement level" bar moves. | The sheet hides the box it's asking the user to drag. |
| MOT-02 | S | **Sensitivity and wait.** Lowest sensitivity, box on a still area; then wait 5 s. | No shots on a still area; never fires faster than the wait. | – |
| MOT-03 | S | **Disarm and refusals.** Disarm; try with Bulb. | Stops at once; "The motion trigger needs a timed shutter speed…". | Stays armed after the sheet closes with no sign on the main screen. |
| HIRES-01 | S | **Helper on a High Res body.** Tools ▸ High Res (PEN-F, E-M5 II, E-M1 II and later…). | A guide: turn it on at the camera (menu path), tripod tips, what the app waits for, the 50 MP badge. | It reads like a switch but is a guide: the title or first line must say the camera has to be set by hand. |
| HIRES-02 | S | **Hidden elsewhere.** A body without High Res (E-M10 III, TG-5, other brands). | No High Res tile, no ⋯ entry. | – |
| HIRES-03 | H | **Real High Res shot.** | The app waits for the merge and shows the thumbnail; the card shows the 50 MP badge. | App times out during the merge. |
| MISC-01 | S | **Pocket mode.** Tools ▸ Pocket. | Black screen, dim red status ("Ready · …", countdowns); double-tap leaves; the text explains the screen must stay on. | A single stray tap leaves it or fires the shutter. |
| MISC-02 | S | **Geotag.** Toggle; allow location. | Toast "Geotagging on: saved photos get your location"; saved photos carry a position (check one in Photos); off stops logging. | Permission denied leaves the toggle looking on. |
| MISC-03 | S | **Timed Bulb.** With Bulb selected, **Stop after** 30 s. | Countdown in the shutter; ends by itself. | – |

---

## 8. Card browser and auto-save

| ID | Run | Check and steps | Pass | UX failure |
|---|---|---|---|---|
| GAL-01 | S | **Open.** Tap Card / the last-shot thumbnail. | "Reading the card…" then "On the card · N" with a thumbnail grid, newest first. Live view stops and restarts on close. | A long blank wait; live view not restarted after closing. |
| GAL-02 | S | **Empty and failed states.** A camera with no photos; stop the mock while it reads. | "No photos / Nothing on the card yet." and "Couldn't read the card" with a retry. | A spinner forever. |
| GAL-03 | S | **Folders.** A card with more than one folder (and one from another camera, where the mock has it). | Folder chips with counts; "other camera" folders explained ("…lists this folder as empty…"). | – |
| GAL-04 | S | **View a photo.** Tap a thumbnail; pinch; double-tap; swipe. | Zoom transition, zoom and swipe work; date · size line; "From another camera" where true; High Res badge on big files. | Preview stays thumbnail-soft with no loading sign. |
| GAL-05 | S | **Save a JPEG.** Save one photo. | "Saved the full-size original to Photos." (with "its location" when geotagged). The file in Photos has the original pixel size. | Photos permission denied gives no route to Settings. |
| GAL-06 | S | **Star.** Tap and hold a thumbnail; star in the viewer; **Starred** filter. | Star badge; "Starred · N"; "No starred photos" hint when empty; stars survive closing the card and reconnecting. | Tap-and-hold is the only way and nothing says so. |
| GAL-07 | S | **Download RAWs of starred.** Star two photos that have RAWs; download. | "RAW 1 of 2" progress; each lands in Photos, or in Files ▸ On My iPhone ▸ Shutterlink ▸ RAW when Photos refuses it, and the message says where. Photos without a RAW are skipped with a count. | Progress hidden if the sheet closes; no cancel; the user can't find the files. |
| GAL-08 | S | **RAW badge.** | Photos with a RAW beside them show "Has a RAW file". | – |
| GAL-09 | S | **Cancel a big download.** Start a RAW download, close the card. | Stops cleanly; no partial file left; live view returns. | – |
| GAL-10 | S | **Locked during an exposure.** Start a long exposure, tap Card. | Disabled until it ends. | – |
| GAL-11 | S | **No card browser on this body.** | The Card button is hidden or says why. | A button that opens an empty sheet. |
| GAL-12 | H | **Real card, hundreds of files.** | The list loads in reasonable time and scrolls smoothly; thumbnails fill in as they arrive. | Loads every thumbnail before showing anything. |
| ASAVE-01 | S | **Turn on.** ⋯ ▸ **Save new photos to Photos**; take a shot. | Asks for add-only Photos access once; "Saved to Photos" toast; one new photo in Photos. | Nothing tells the user a save failed. |
| ASAVE-02 | S | **Access refused.** Deny Photos. | "Photos access is off, so auto-save is off" and the menu item is unticked. | Item stays ticked. |
| ASAVE-03 | S | **Sequences aren't saved one by one.** Run a 3-frame interval and a bracket with auto-save on. | Nothing added to Photos during them. | A time-lapse fills Photos. |
| ASAVE-04 | S | **LUMIX saves later.** LUMIX: take two shots, open the card. | "Saved 2 new photos to Photos" on opening the card, and the ⋯ item or a hint tells the user that LUMIX photos are saved when the card opens. | The user is never told; photos seem lost. |
| ASAVE-05 | S | **What gets saved.** Check the saved file's size against the card's. | Full-size JPEG/HEIF (the mock sends 640×480 for Olympus: record the size, confirm on hardware in `HW-08`). RAW is never auto-saved, and the user is told when the camera is set to RAW only. | A small preview saved as if it were the photo. |
| ASAVE-06 | S | **Doesn't slow the shutter.** Five shots quickly with auto-save on. | Every shot fires on tap; saves queue behind. | Shutter waits for the save. |

---

## 9. ⋯ menu, All camera settings, Request log

| ID | Run | Check and steps | Pass | UX failure |
|---|---|---|---|---|
| MENU-01 | S | **Contents.** Open ⋯, screenshot. | Under the camera's name: Live view size (if sizes), Restart live view, Scene suggestions, Save new photos to Photos, Shutterlink Pro + status, High Res Shot helper (if the body has it), Sync camera clock (if it can), All camera settings, Request log, Disconnect, Turn camera off (if it can). | An item for something this body can't do. |
| MENU-02 | S | **Sync camera clock.** | Toast "Camera clock set to this iPhone"; hidden where unsupported. | – |
| MENU-03 | S | **Disconnect.** | Confirmation "Disconnect from the camera?", then home, with the camera saved. | – |
| MENU-04 | S | **Turn camera off.** | Confirmation that explains Wi-Fi must be restarted on the camera; then home. | – |
| MENU-05 | S | **Pro status line.** With each `-pro` state. | "Unlocked (developer build)", "Trial: 6 days left (debug)", or the locked text; tapping opens the Pro screen. | – |
| SET-01 | S | **All camera settings.** ⋯ ▸ All camera settings. | Every property from `ST-04`, with a readable name and value, grouped or ordered sensibly; "Locked rows can't be changed in the current mode." | Raw property names as the only label ("isospeedvalue"); hundreds of rows with no search or sections. |
| SET-02 | S | **Change one.** Change a setting that isn't on the strip (Olympus: art filter, colour tone, hue; LUMIX: Photo Style, AF mode). | The camera takes it; the row updates; the strip stays right. | – |
| SET-03 | S | **Locked row.** Tap a locked row. | Explains which mode unlocks it. | A picker that opens and then gets refused. |
| SET-04 | S | **What deserves promoting.** Read the whole list for this model. | Record in the mockup record (section 14) every setting here that a photographer changes shot to shot (focus mode, metering, picture style, image stabilisation, flash). | An everyday setting only reachable here. |
| LOG-01 | S | **Request log.** ⋯ ▸ Request log. | Camera name, support level ("Tested on this camera" / "Researched…"), connect mode, protocol version, live-view port, command list and settings dump, then requests newest first with milliseconds. | – |
| LOG-02 | S | **Copy and Clear.** | Copy puts the whole log on the clipboard; Clear empties it. No Wi-Fi password appears in the log (search it for the password typed in `UI-ADD-13`). | **A password in the log is S1.** |
| LOG-03 | S | **Support level is honest.** Compare the level shown with the README table for this body. | They agree. (Known mismatch to check: the LUMIX GH5 profile says "Tested on this camera" while the README says mock only.) | "Tested on this camera" for a body nobody has tried. |

---

## 10. Pro screen and locks

Launch with `-pro locked` for `PRO-01` to `PRO-08`.

| ID | Run | Check and steps | Pass | UX failure |
|---|---|---|---|---|
| PRO-01 | S | **Which tools are locked.** Open Tools, screenshot. | A lock on Presets, Astro, Interval, Bracket, ND filter, Motion, High Res. No lock on Loupe, Night, Histogram, Grid, Peaking, Geotag, Tap AF, Pocket, Video. | A free feature locked; a locked tile with no lock mark. |
| PRO-02 | S | **A locked tool opens the Pro screen.** Tap each locked tool. | The Pro screen opens with "<feature> is part of Shutterlink Pro" naming the tool tapped. Closing returns to live view with nothing changed. | Generic title; the tool half-opens behind the screen. |
| PRO-03 | S | **Pro screen content.** Read it. | Title, the six benefit rows, "Free stays free: …", "One purchase for iPhone, iPad and Mac. Yours to keep, no subscription.", **Try free for 7 days**, **Buy Pro · $9.99**, **Restore purchase**, and the trial small print. | A benefit listed that this camera can't use, with nothing saying so (see `VAL-02`). |
| PRO-04 | S | **Free things stay free.** With Pro locked: connect, live view, every strip setting, shutter, video, Bulb / Live Composite, card, save, auto-save, geotag, QR/Wi-Fi join, All camera settings. | All work with no Pro prompt. | Any prompt on that list. |
| PRO-05 | S | **Scene suggestions under lock.** `-pro locked -sceneLabels night_sky:0.97,sky:0.9`, then a clipping scene. | A suggestion that runs a setup (Astro) opens the Pro screen; one that changes a single setting (−⅔ EV) just does it. | A locked suggestion looks the same as a free one until tapped. |
| PRO-06 | S | **Other routes to locked features.** Macro's "Focus stack next", the Mac/iPad Tools menu and keyboard shortcuts, the ⋯ High Res entry, "Connect to Camera" shortcut. | Every route to a Pro tool goes through the same lock. | A menu item or shortcut opens a Pro tool unlocked. |
| PRO-07 | S | **Prices don't load.** With no StoreKit configuration (plain simulator launch). | "Prices load from the App Store." (or similar) and the buttons don't dead-end; Restore says what happened. | Buttons that spin forever; a blank where the price goes. |
| PRO-08 | S | **Locked state is discoverable but not nagging.** Use the free app for five minutes. | Locks are visible in Tools and the ⋯ menu; no pop-up appears unless a locked thing is tapped. | A prompt on launch or on connect. |
| PRO-09 | S | **Trial state.** `-pro trial`. | Everything unlocked; ⋯ shows "Trial: N days left"; the Pro screen shows the trial as running and still offers Buy. | No way to see how long is left. |
| PRO-10 | S | **Unlocked state.** No flag. | No locks anywhere; Pro screen says "Pro is unlocked". | – |
| PRO-11 | H | **Real trial and purchase** (Xcode with `Shutterlink.storekit`, or the sandbox). Start the trial; buy; Restore on a second device; iPad and Mac with the same account. | Trial unlocks for 7 days from its purchase date and can't be started twice; purchase unlocks for good on every platform; Restore finds it. | – |
| PRO-12 | H | **Trial ends mid-use.** With StoreKit time controls, let the trial expire during an interval run and with a preset on. | The run in progress finishes (or stops with a clear message); the preset can still be **turned off** so settings go back. | The user is locked out of Undo and stuck with a preset's settings. |
| PRO-13 | H | **Offline.** On the camera's Wi-Fi (no internet): relaunch after purchase. | Pro stays unlocked; a non-buyer sees the Pro screen explain that buying needs internet. | Pro locks because the App Store can't be reached. |
| PRO-14 | H | **Early users keep Pro.** A production install whose first version was 1.0 (builds 1–4), updated to 1.1. | "Unlocked: thanks for being an early user". | – |
| PRO-15 | H | **Watch without Pro.** Locked on the iPhone, open the Watch app. | The Watch says the remote is part of Pro and how to get it (on the iPhone). | A dead Watch screen. |

---

## 11. Watch, iPad, Mac

| ID | Run | Check and steps | Pass | UX failure |
|---|---|---|---|---|
| WATCH-01 | H | **Not connected.** Open the Watch app with the iPhone app closed, then open but not connected. | "Open Shutterlink on your iPhone and connect to the camera." / "Connect Shutterlink on your iPhone to the camera." | An old picture shown as if live. |
| WATCH-02 | H | **Live view and status.** Connected. | Live view at about 3 fps while the app is on screen; battery, shots left, aperture, shutter, ISO, EV as on the iPhone. | Values differ from the iPhone's strip. |
| WATCH-03 | H | **Shutter.** Tap it in photo, Bulb and movie modes. | Takes a picture / starts and stops; a wrist tap confirms. | – |
| WATCH-04 | H | **Self-timer.** Off / 2 s / 10 s; cancel during the countdown. | Countdown over live view; cancel works; cancel also stops an interval or bracket. | – |
| WATCH-05 | H | **Digital Crown.** Turn it in P/A/S, then M. | EV changes in thirds (EV shown in orange); in M it does nothing and looks that way. | Crown changes EV where the camera will refuse it. |
| WATCH-06 | H | **iPhone app goes to the background.** | The Watch says the iPhone stopped answering. | – |
| PAD-01 | S | **Workspace, landscape.** iPad Pro 13 simulator, connected. | Live view with the exposure grid (F-stop, Shutter, ISO, EV, WB, Drive, Quality), histogram card, tool tiles and a side panel, all visible at once without overlap. | Phone layout stretched; big empty areas while controls are small. |
| PAD-02 | S | **Workspace, portrait and split view.** Rotate; use Split View at half and a third. | Tall workspace layout; at a third width it falls back to the phone layout cleanly. | Controls cut off at an in-between width. |
| PAD-03 | S | **Tools as side panels.** Open Presets, Interval, Bracket, ND, Motion, High Res. | Each opens beside live view (not over it), and live view stays usable (the Motion box can be dragged with the panel open). | – |
| PAD-04 | S | **Card browser.** | Grid plus a large preview ("No photo selected / Pick a photo to see it here."), **Full screen**. | – |
| PAD-05 | S | **Keyboard.** `UI-SHUT-08` with a hardware keyboard. | As listed. | – |
| MAC-01 | H | **Window.** Build "My Mac (Mac Catalyst)". | Opens 1280×860, never smaller than 980×740, always a workspace layout; one window only; closing and clicking the Dock icon brings it back. | – |
| MAC-02 | H | **Menus.** Camera, Exposure, Tools menus. | Every item works or is disabled with "Connect to a camera first"; shortcuts as in `MAC.md`. | An enabled item that does nothing. |
| MAC-03 | H | **Mac wording.** Read Add a camera, errors and pocket mode. | "Mac", "System Settings", "click" – never "iPhone" or "tap". No Action-button tip, no QR scan button. | iPhone wording on the Mac. |
| MAC-04 | H | **Saving.** Save, **Save As…**, **RAWs…**. | Photos, a chosen folder, a chosen folder. | – |
| MAC-05 | H | **Stays awake.** Cover the window for 10 min during an interval. | No stalled frames. | – |

---

## 12. UX sweep

Run this sweep **once per sheet, after** sections 5 to 11, looking across the whole app with this model connected.
Each check asks one question; list every place it fails.

| ID | Run | Check and steps | Pass | UX failure |
|---|---|---|---|---|
| UX-01 | S | **Dead ends.** Is there any screen, sheet or state with no way forward or back (no Done, no retry, no explanation)? | None. | List each: where, how you got there. |
| UX-02 | S | **Shown but not usable.** Is any control visible that can never work on this model (physical dial, not in its command list, wrong mode forever)? | None: such controls are hidden, or shown read-only with the reason. | List each control. |
| UX-03 | S | **"Not offered" without a next step.** Search every sheet, preset step and banner for "not offered", "not settable", "can't", "unavailable", "refused". | Each one says what to do instead (on the camera, in another mode, with another tool). | List each bare message with its screen. |
| UX-04 | S | **Missing feedback.** For every action that talks to the camera: is there a visible change within half a second (pressed state, spinner, value change) and a result (value, toast, banner)? | Yes for all. | List actions with no feedback, or where a toast is the only sign of a failure. |
| UX-05 | S | **Labels.** Any raw protocol word (`livecomp`, `lowvib-normal`, `0640x0480`, `isospeedvalue`, WB "18"), mock clutter, jargon without explanation, or two labels for one thing ("F-stop" / "Aperture", "Drive" / "Drive Mode", "Histo" / "Histogram")? | None that a photographer wouldn't understand. | List each. |
| UX-06 | S | **Buried controls.** How many taps to: change WB; change drive; change quality; turn on the self-timer; switch photo/video; open the card; start an interval; turn a preset off; disconnect? | Each of the first six in **2 taps or fewer** from the remote screen; the rest in 3 or fewer. | List anything deeper, and anything important that lives only in All camera settings. |
| UX-07 | S | **State you can't see.** With each of these on, can you tell from the remote screen alone: a preset, Astro, interval running, motion armed, bracket running, geotag, auto-save, Tap shoots, night mode, video mode, timed Bulb? | Yes for each. | List the invisible ones. |
| UX-08 | S | **Undo and recovery.** After each of: a preset, Astro, ND set-up, a bracket, ETTR, Follow the light: can the user get back to the settings from before? | Yes, in one or two taps, and it's obvious how. | List what leaves the camera changed. |
| UX-09 | S | **Consistency.** Do sheets close the same way; do toggles look the same; is amber only "on/selected"; do the same words mean the same thing on every screen and on the Watch? | Yes. | List each inconsistency. |
| UX-10 | S | **Accessibility.** VoiceOver labels on the shutter, strip cells, tools, ⋯ ("More"), and toggles with On/Off values; contrast of grey text on black; hit targets at least 44 pt. | All labeled; nothing unreadable. | List unlabeled or tiny controls. |
| UX-11 | S | **First five minutes.** As a new user with this camera: from install to first photo saved to the phone, count the steps and every moment of doubt. | Under 10 steps, no moment where the next step isn't on screen. | Write the journey with the doubts marked. |
| UX-12 | S | **Honesty about experimental support.** For a Beta brand or a "Researched" body: does the app say so before the user relies on it? | Yes (Beta mark, one-time note, log). | A paying user finds out by failing. |

---

## 13. Storage and resources

Measure with `footprint -p <pid>` (the app's process in the simulator: `pgrep -f 'Shutterlink.app/Shutterlink'`),
sampled every 10 s, and write the samples into the sheet. A simulator's numbers are for **trend**, not absolutes;
real-device numbers come from Xcode's memory gauge or Instruments.

| ID | Run | Check and steps | Pass | UX failure |
|---|---|---|---|---|
| RES-01 | S | **Live view, 10 minutes idle.** Connect, leave live view running, sample memory for 10 min. | Footprint flat after the first minute: the last sample within 20 MB of the 1-minute sample (regression: live view used to keep every frame and grow without limit). | Growth of more than 2 MB/min. |
| RES-02 | S | **Live view with every aid on.** Histogram, peaking, grid, loupe, scene suggestions on, 5 min. | Flat, as `RES-01`; fps within 20% of aids-off. | – |
| RES-03 | S | **Live view size changes.** Switch size 10 times, open and close the loupe 10 times. | Memory returns to the baseline within 30 s. | – |
| RES-04 | S | **Shooting loop.** A 100-frame interval at 2 s with last-shot review. | Flat; `shotCounter` 100; no frame missed. | – |
| RES-05 | S | **Card browser.** Open the card, scroll all thumbnails, open 20 previews, close. Repeat 5 times. | Memory after closing returns near the baseline each time (the thumbnail cache is cleared on disconnect: check it doesn't grow without limit on a big card). | Growth per open/close cycle. |
| RES-06 | S | **JPEG downloads.** Save 20 originals. | Peak memory rises by no more than about 2× one file's size and returns; nothing left in `tmp/` or `Caches/`. | – |
| RES-07 | S | **RAW downloads.** Download the RAWs of 6 starred photos. | Same as `RES-06`; RAWs that Photos refuses are in `Documents/RAW` once each (no duplicates when repeated). | Each repeat adds another copy. |
| RES-08 | S | **Disk use.** After a full run, list the app container: `du -sh` on `Documents`, `Library/Caches`, `Library/Application Support`, `tmp` (path from `xcrun simctl get_app_container <sim> com.apexcommerce.shutterlink data`). | Caches: only `lumix-allmenu-<key>.xml` per LUMIX camera (tens of KB). Application Support: the geotag log (two weeks at most). Documents: only RAWs the user downloaded. `tmp` empty. | Anything else growing; no way for the user to clear downloaded RAWs. |
| RES-09 | S | **LUMIX menu cache.** LUMIX: connect fresh (time it), disconnect, connect again (time it); then change `--model` and connect. | The second connect is faster and doesn't fetch the full menu again (check the request log); a different model gets its own cache file, never another body's menu. | A stale menu after a firmware or model change, with no way to refresh. |
| RES-10 | S | **Request log cap.** Run a 200-frame interval, open the log. | At most 400 entries; opening it is instant. | – |
| RES-11 | S | **Auto-save over a long session.** 50 shots with auto-save on. | 50 photos in Photos, none twice, none missing; memory flat. | – |
| RES-12 | S | **Reconnect loop.** Connect and disconnect 20 times (the mock restarted in between twice). | No growth; no second live-view socket left open (`lsof -p <pid>` shows one UDP socket for live view). | – |
| RES-13 | S | **CPU at idle.** `top -pid <pid>` during live view with aids off, then peaking on. | Record both. A high number here predicts heat and battery on a phone. | – |
| RES-14 | H | **Battery and heat, one hour.** Real iPhone and camera, live view for 60 min at default brightness. | Record the iPhone's battery drop, whether it got warm, and the camera's battery drop. A drop of more than about 25% an hour on the phone is a finding. | The phone dims or shows a temperature warning. |
| RES-15 | H | **Battery and heat, pocket mode.** A 60-min interval in pocket mode. | Record the same; expect clearly less than `RES-14`. | Pocket mode saves nothing. |
| RES-16 | H | **Memory on the device.** Xcode memory gauge, 30 min of live view on the real camera (30 fps, real frame sizes). | Flat. | – |
| RES-17 | H | **Low storage.** With the iPhone nearly full, save a RAW. | A clear "not enough space" message; nothing half-written. | – |

---

## 14. Per-model mockup record

Fill this in for **every** sheet, including short runs. It is the reference for how the app *should* look for that
model, so write the "should" columns as recommendations even where the app already matches.

| ID | Run | Check and steps | Pass | UX failure |
|---|---|---|---|---|
| MODEL-01 | A·S | **Identity.** Model as reported, profile matched, support level, crop factor, notes (from `ST-01`, `ST-02`, the request log). | Recorded. | – |
| MODEL-02 | A·S | **What the camera offers over Wi-Fi.** From the request log: the command list (Olympus `get_commandlist`, LUMIX capability and menu, Nikon/Canon/Sony their lists) and every property with settable / read-only and option count (from `ST-04`). For a real body use its probe files (PEN-F: `penf-probe/`). | Complete list in the sheet. | – |
| MODEL-03 | S | **What the app exposes.** For each row of `MODEL-02`: on the strip, in a tool, in All camera settings, used behind the scenes, or **not used**. | Table filled in. | – |
| MODEL-04 | S | **Gaps: the camera can, the app doesn't.** List every "not used" command or property with what a user would gain (e.g. power zoom, free space on the card, a bigger preview, noise reduction, the share-order list). | Each gap has a one-line "worth adding?" and a rough size (small / medium / large). | – |
| MODEL-05 | S | **Gaps the other way: the app shows, the camera can't.** Anything in the UI for this model that the camera doesn't accept. | None, or listed as findings. | – |
| MODEL-06 | S | **Main-row budget.** Count the cells the strip shows for this model on the smallest supported iPhone, and what it would take to show all of them. Then rank this model's settings into tiers (below). | Tier 1 is all on the main row; every Tier 2 setting is one tap away; nothing a user changes shot to shot is Tier 3. | A Tier 1 setting off the row; a cell spent on something that can never change on this model. |
| MODEL-07 | S | **What the live screen should show for this model.** Draw (in words or an annotated screenshot) the remote screen as it should be: which cells, in which order, what replaces a cell this model can't use, which read-only indicators (mode dial position, drive dial, focus mode), which tools. | A concrete layout another person could build from. | – |
| MODEL-08 | S | **How the UI should behave for this model.** Rules specific to it: which presets need a camera-side step, which tools to hide, which notes to show, what "Tested / Researched / Beta" label it carries. | Written. | – |
| MODEL-09 | S | **Screenshots.** Remote screen portrait and landscape, Tools grid, All camera settings (top), ⋯ menu, one preset's step list. | Saved in `results/img/<sheet>/` and linked. | – |

### The tiers (the rule `MODEL-06` applies)

The main row has room for about six cells on a phone. It can't hold everything, but nothing important may be tucked
away.

| Tier | Where it lives | What belongs there |
|---|---|---|
| **1: always visible** | The strip and the shutter cluster | Mode (or a read-only mode indicator), aperture, shutter, ISO, EV; battery and shots left; the shutter and what it will do (photo / video / Bulb) |
| **2: one tap** | A strip cell at the end, a Tools tile, or the quick row | White balance, drive / self-timer, picture quality (RAW/JPEG), focus mode or AF area where settable, photo/video switch, movie exposure in movie mode |
| **3: two taps or more** | All camera settings | Picture style, art filters, colour tone, hue, noise reduction, anything set once per outing |

Per-model adjustments to write down in `MODEL-07`:

- **A setting the camera never lets the phone change** (LUMIX G7 mode and drive dials; LX100 aperture, shutter and
  EV; compacts with `fixedExposure`): show it read-only in a smaller form, don't spend a full cell on a dial that
  can't turn, and give the freed room to the next Tier 2 setting.
- **A setting the camera doesn't report at all** (picture quality on Olympus): no cell. If users will look for it,
  say where it is on the camera, once.
- **A body with a signature feature** (Live Composite, High Res Shot, 4K Photo, focus drive): it should be reachable
  from the main screen for that body, not three levels down.

### Facts from real cameras (use these as the baseline, not the mock)

- **Olympus PEN-F, firmware 3.1** (`PEN-F Remote/penf-probe/`): settable over Wi-Fi are **only** mode (`takemode`),
  drive (`drivemode`), aperture, EV, shutter, ISO, white balance, movie exposure (`exposemovie`) and hue
  (`colorphase`). Not settable or not reported: picture quality, focus mode, metering, art filter, colour tone.
  Commands the camera lists that the app doesn't use: `ctrlzoom` (power zoom), `get_screennail` (1920×1440
  preview, RAW included), `get_unusedcapacity` (free space), `get_dcffilenum`, `get_movplaytime`,
  `get_rsvimglist` / `clear_resvflg` (share-order list), `req_storegpsinfo` / `req_attachexifgps` (GPS track into
  the camera), `exec_shutter` (cable-release mode), and read-only properties such as `noisereduction`,
  `bulbtimelimit`, `lowvibtime`, `SilentTime`, `digitaltelecon`. The Olympus mock differs: see section 2.
- **Panasonic LUMIX G7**: the mode dial (P/A/S/M) and the drive dial are physical. Neither can be set over Wi-Fi.
  The app must show both as they are and tell the user to turn the dial. `mock_lumix.py --model DMC-G7
  --sticky-drive` behaves this way.

---

## 15. Value and pricing

Pro is **$9.99, once, with a 7-day trial**. Free covers what the camera makers' own apps do. These checks ask, for
this model: would a user who paid feel it was worth it?

| ID | Run | Check and steps | Pass | UX failure |
|---|---|---|---|---|
| VAL-01 | S | **Pro scorecard for this model.** For each Pro feature, mark **Full** (works end to end from the phone), **Part** (works but needs steps on the camera), **Guide** (only tells the user what to do), **None** (not available): Presets ×7, Undo / My presets, Astro, Star trails, Interval, Follow the light, Exposure bracket, Focus stack, ND filter, Expose to the right, Motion trigger, High Res helper, Watch remote, scene suggestions that run a setup. | Recorded. **At least 8 of the 14 rows are Full**, and no more than 2 are None. | Fewer: this model is a refund risk. Say which features carry the price for it. |
| VAL-02 | S | **Does the Pro screen promise only what this model gets.** Compare `PRO-03`'s list with `VAL-01`. | Every benefit row is Full or Part for this model, or carries a qualifier ("on LUMIX, Nikon and Canon", "on Olympus and OM System bodies that have it"). | A benefit shown with no qualifier that is Guide or None here. |
| VAL-03 | S | **"Guide" features behind the paywall.** List every Pro feature that is only instructions on this model (High Res helper everywhere; focus stack on Olympus and Sony; presets on a body with a physical mode dial). | Each one still saves the user real effort, or is unlocked/free for this model. | The user pays, taps, and gets a page of text they could read in the manual. |
| VAL-04 | S | **What breaks or is missing in Pro.** From sections 4 and 7: every `:FAILED`, **F** and **UX** result on a Pro feature. | None at S1/S2. | List them: these are the "$10 isn't worth it" moments. |
| VAL-05 | S | **Free tier is complete.** From `PRO-04`: can a free user do everything the maker's app does (OI.Share / OM Image Share, LUMIX Sync, SnapBridge, Camera Connect, Imaging Edge)? Note anything the maker's app does free that is locked or absent here (interval shooting, a self-timer, geotag transfer, firmware update…). | Nothing the maker gives free is behind Pro. | List each. A free feature that the maker's app has and Shutterlink lacks goes in `MODEL-04`. |
| VAL-06 | S | **The trial shows the value.** As a free user: how many taps from the remote screen to starting the trial, and is there any moment that makes them want to (a locked tool at the moment they need it, a scene suggestion)? After starting it, does the app point at what to try first? | The trial is at most 2 taps from any lock; after it starts, something highlights the Pro tools. | The trial starts and nothing changes on screen. |
| VAL-07 | S | **Which single feature sells it for this model.** Name the one or two Pro features that work best here (e.g. Live Composite star trails on Olympus, focus stacking on LUMIX), and check each is easy to find and works first time. | Named, found within 2 taps, worked. | The best feature for this body is hidden or fragile. |
| VAL-08 | S | **Beta brands.** Nikon, Canon, Sony: is it clear before purchase that the driver is experimental and only tried against mocks? | Yes, on the Pro screen or at connect. | A Sony a7 IV owner can buy Pro and never connect. |
| VAL-09 | H | **One real outing.** A person shoots for an hour with the trial on a real camera and writes: three things that were worth paying for, three that weren't, and whether they'd buy. | Recorded verbatim. | – |
| VAL-10 | S | **Verdict.** One paragraph: for this model, is $9.99 fair, generous or a stretch, and the three changes that would most improve it. | Written, with the findings it rests on. | – |

**What Pro gives, by brand (the starting expectation; a run confirms or corrects it):**

| Pro feature | Olympus / OM | LUMIX | Nikon (Beta) | Canon (Beta) | Sony (Beta) |
|---|---|---|---|---|---|
| Presets, Undo, My presets | Full where mode is settable | Part on bodies with a physical mode dial (G7) | Full on the mock | Full on the mock | Full on the mock |
| Astro | Full | Full / Part (mode dial) | Full, no Bulb | Full | Full |
| Star trails | **Live Composite** | Interval series of 30 s frames | Interval series | Interval series | Interval series |
| Interval, Follow the light | Full | Full | Full | Full | Full |
| Exposure bracket | Full | Full (EV; shutter in M by choice) | Full | Full | Full |
| Focus stack | **Guide only** (camera's Focus BKT) | Full, camera in MF | Full, lens on AF | Full, lens on AF | **Guide only** |
| ND filter | Full, Bulb/Live Time for long | Full, Bulb | Part: no Bulb over Wi-Fi | Full, Bulb | Full, Bulb |
| Expose to the right, Motion | Full | Full | Full | Full | Full |
| High Res helper | **Guide only**, and only on High Res bodies | None | None | None | None |
| Watch remote | Full | Full | Full | Full | Full |

---

## 16. Real camera only

A person runs these with the camera in hand. Use a card with nothing that matters on it. Record the camera's
firmware version in the sheet.

| ID | Run | Check and steps | Pass | UX failure |
|---|---|---|---|---|
| HW-01 | H | **Join and connect by hand.** Start the camera's Wi-Fi, join in Settings, Connect with Automatic. | Connects first time; the right brand and model name; saved. | Local Network prompt appears late and the first try fails with no retry. |
| HW-02 | H | **Join from the app.** Scan the QR or type the name and password; later tap the saved card with the phone on home Wi-Fi. | iOS asks once to join; next time one tap joins and connects. | The phone hops back to home Wi-Fi mid-session with no warning. |
| HW-03 | H | **Every strip setting takes effect on the camera.** Change each and look at the camera's own screen. | Camera shows the same value each time. | The app shows a value the camera didn't take. |
| HW-04 | H | **What the body refuses.** Try each mode; note every setting the camera refuses and what the app says. | Matches the mockup record; each refusal explains itself. | – |
| HW-05 | H | **Physical dials.** Turn the mode dial, drive dial and EV dial on the camera while connected. | The app follows within 2 s; locks update. | Stale mode until reconnect. |
| HW-06 | H | **Live view quality and lag.** Wave a hand; time the delay. | Under about 0.3 s; steady frame rate; right aspect ratio. | – |
| HW-07 | H | **Shutter, burst, Bulb, Live modes, video.** `UI-SHUT-01` to `-05` on the camera. | All work; long-exposure noise reduction time is waited for. | – |
| HW-08 | H | **Auto-save size.** Auto-save one photo and compare its pixel size with the card's file. | Full size (on Olympus, confirm `getlastjpg` isn't a reduced copy; on Sony, postview set to Original). | A small copy saved without telling the user. |
| HW-09 | H | **Card: real JPEG and RAW.** Save one of each. | JPEG in Photos at full size with EXIF; the RAW opens in Photos or lands in Files, and the message says where. | – |
| HW-10 | H | **Range and dropouts.** Walk away until live view breaks, come back. | The app says the camera stopped answering, and reconnects (by itself or with one tap). | Frozen frame; app needs a force-quit. |
| HW-11 | H | **Camera sleeps or its battery dies.** Let the camera sleep; pull its battery during an interval. | The app notices, stops the run, says how many frames were taken. | – |
| HW-12 | H | **Phone locks.** Lock the iPhone for a minute while connected. | On unlock: reconnected, or a clear prompt. Pocket mode is offered as the way to keep going. | – |
| HW-13 | H | **Maker's app open at the same time.** Open OI.Share / LUMIX Sync, then Shutterlink. | A message says to close the other app. | Random refusals with no explanation. |
| HW-14 | H | **Model-specific notes are true.** For a body with a profile note, check the note against the camera. | The note is right and useful. | A note that's wrong for this firmware. |
| HW-15 | H | **Nothing changed on the camera afterwards.** After disconnecting: mode, drive, WB, image quality and clock on the camera. | As the user left them (or as the user set them from the app), and never a setting the app changed silently. | A preset's settings left on the camera after "turn off". |

---

## 17. What applies to which brand

Use this to decide N/A quickly. "Camera-listed" means the app reads it from the camera, so check the mock or body.

| Feature | Olympus / OM | LUMIX | Nikon | Canon | Sony |
|---|---|---|---|---|---|
| Mode settable from the app | Yes | Body-dependent (not G7) | Mock: yes | Mock: yes | Mock: yes |
| Drive on the strip | Yes | Yes, read-only with a physical dial | Camera-listed | Camera-listed | Camera-listed |
| Quality on the strip | No (not reported over Wi-Fi) | Yes | Camera-listed | Camera-listed | Camera-listed |
| Live view size picker | Yes (camera-listed) | Yes (the brand's fixed list) | No | No | No |
| Bulb / Live Time / Live Composite | Yes / Yes / Yes | Bulb | None | Bulb | Bulb |
| Video | Movie mode on the carousel (not E-M1) | Video switch (not `noVideo` bodies) | Video switch, Z only | Video switch | Video switch |
| Last-shot review | Yes | No (card later) | Camera-listed | Camera-listed | Yes (postview) |
| Auto-save during live view | Yes | No, on opening the card | Yes | Yes | Yes |
| Clock sync | Yes | No | No | No | No |
| Turn camera off | Yes | Yes | No | No | No |
| High Res helper | Bodies with High Res Shot | No | No | No | No |
| Focus stack | Guide | Yes | Yes | Yes | Guide |
| QR join | `OIS1` codes | `WIFI:` if shown | `WIFI:` if shown | `WIFI:` if shown | `W01:` |
| One-time notes | E-M1, E-M1X, E-M1 III, E-M10 IV, OM System bodies | LX100, GX8, G9, FT7, S5, GH5 II, S5 II/IIX, G9 II, GH7, S9, S1 II | – | – | – |
| Unsupported bodies | AIR A01, TG-Tracker | – | – | Original EOS R (no CCAPI) | Bodies from about 2020 on |
