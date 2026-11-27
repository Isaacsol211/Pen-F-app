# Results: Olympus PEN-F (mock)

Checks, steps and pass criteria: [`../TEST-PLAN.md`](../TEST-PLAN.md). Screenshots are in `img/olympus-pen-f/`.

**Result:** `P` pass · `F` fail · `UX` works but a UX failure showed · `N/A` this model can't · `—` not run (reason given).

## Run

| | |
|---|---|
| Sheet | `olympus-pen-f` |
| Run type | Full run of the simulator-driven checks that could be done in one pass; many UI checks are still `—` (see the checklist) |
| Date | 2026-11-25 |
| Tester | Claude (Sonnet 5.5), driven by the iOS Simulator tool |
| Build | test/plan worktree on main 5da84a8 + the plan commit (app code unchanged), Debug, version 1.1 (5) |
| Device | iPhone 17 simulator (iOS 27.2) |
| Camera | Mock: `python3 -I -u mock_penf.py --model PEN-F` (127.0.0.1:8080) |
| Pro state(s) used | unlocked (default Debug), then `-pro locked` |

## Summary

| | Count |
|---|---|
| Checks with a result | 61 of 256 (the rest are `—`: not run in this pass, or need a real device/camera) |
| P | 39 |
| UX | 20 |
| F | 0 (but see F1: one hang/termination not reproduced) |
| N/A | 2 |
| Findings S1 / S2 / S3 / S4 | 0 / 1 (unreproduced) / 8 / 9 |

**Top problems**

1. **F1** The app stopped responding and then terminated (back to the home screen) while the Bracket sheet was open after applying Astro. Not reproduced in two more tries and no crash log, so it is recorded as unconfirmed.
2. **F2/F3/F4** The strip and its panels mislead on exactly the settings a PEN-F user touches: EV says AUTO in M mode, the Drive cell is a bare square, and the Drive panel shows only 1.5 rows of its 12 options.
3. **F5** A preset that is "on" is invisible from the remote screen and is forgotten if the app restarts, leaving the camera on the preset's settings with no Undo.

**Value verdict** (`VAL-10`): on a PEN-F the $9.99 is **fair but fragile**: Presets, Astro, Interval, Bracket, ND and Motion all work end to end on the mock and the one-tap Astro/Moon setups are genuinely useful, but two of the headline Pro rows (High Res helper, Olympus focus stack) are instructions only, and the free app does not show what Pro does until a user taps a lock. See "Pro scorecard".

## Findings

| ID | Sev | Check | What happens | Steps | Evidence | Suggested fix |
|---|---|---|---|---|---|---|
| olympus-pen-f-F1 | S2 (unreproduced) | UI-TOOLS-02 | The UI stopped responding to taps for over a minute (main thread busy in SwiftUI's renderer, `sample` showed `RendererEffectDisplayList.value.getter`), then the app was gone (home screen). No crash report in DiagnosticReports. A log line `LittleGlowView ... composite animation already running` appeared repeatedly. | Mock PEN-F, Pro unlocked. Tools > Astro > Apply astro settings; Tools > Bracket (opened wrongly, the Tools grid had shifted); tap Focus/Frames "5"/the tick: nothing responded. Ran `sample` on the process and the app disappeared (the sampling itself may have caused it). Repeating Tools > Bracket > Focus on a fresh launch worked. | none (no screenshot of the freeze; frozen frames saved only in the scratchpad) | Run with Instruments (Hangs) and the Debug assertion `-UIViewAnimationDecomposition`; check the glow animation on the tool/shutter button when a sheet is presented while Tools closes. |
| olympus-pen-f-F2 | S3 | UI-STRIP-02, UI-STRIP-10 | In M mode the EV cell is labelled AUTO and its panel says "The camera sets this itself in M mode." with a "Switch to A" button. In M the camera does not set EV; EV simply has no effect. | Connect, mode M, tap the EV cell. | `ev-locked-in-M.png` | In M show "n/a in M" (or hide the cell) and say "EV only works in P, A and S"; keep "Switch to A" if wanted. |
| olympus-pen-f-F3 | S3 | UI-STRIP-08 | The Drive cell is a bare square. Single and Anti-shock Single look identical, as do all continuous modes (stack icon). The cell has no text. | Look at the strip with Single and then Anti-shock Single (Astro or Moon sets the latter). | `remote-portrait.png`, `astro-on-no-indicator.png` | Show a short word under the icon ("Single", "Anti-shock", "Cont H", "Timer 12s"). |
| olympus-pen-f-F4 | S3 | UI-STRIP-08 | The Drive panel is about 1.5 tiles tall while the camera lists 12 options: tiles are cropped, labels such as "Anti-shock Cont. H" are cut, and there is no scroll cue. | Tap Drive; swipe up inside the panel. | `drive-grid-clipped.png` | Give the grid its full height (it is a bottom panel; the live view can shrink), or use a list with names. |
| olympus-pen-f-F5 | S3 | PRESET-03, UX-07, UX-08 | After applying a preset (Moon, Astro) nothing on the remote screen shows it is on: the Tools button and tiles look the same. If the app is closed or killed the camera stays on the preset's settings and the app no longer offers Undo. | Apply Astro, close the sheet, look at the screen; then quit and relaunch: the strip still shows F1.8, 5", ISO 1600 and no Undo exists. | `astro-on-no-indicator.png` | Light the Tools button or show a small "Astro" chip on the strip while a preset is on; persist the "settings before" in UserDefaults so Undo survives a restart. |
| olympus-pen-f-F6 | S3 | UI-REMOTE-06 | When the camera disappears the app stays on the remote screen with a frozen frame, a greyed-out shutter and a 9-line red banner that includes jargon and "[code -1004]". The banner has no Reconnect or Disconnect button and covers the live view. | Connect, stop the mock, wait 12 s. | `connection-lost-banner.png` | Shorter message (what happened, one thing to try) and two buttons: Reconnect, Disconnect. Dim or stamp the frozen frame. |
| olympus-pen-f-F7 | S3 | PRO-03 | The Pro screen's benefit list is clipped after "Exposure tools" with no scroll cue, so High Res helper, Apple Watch and scene suggestions can't be seen on an iPhone 17. | Launch with `-pro locked`, Tools > High Res. | `pro-screen-locked.png` | Make the whole screen scroll, or shorten the rows; show a fade at the bottom of the list. |
| olympus-pen-f-F8 | S3 | UI-MODE-01 | In M the mode carousel shows `A S M ART VIDEO`; P and AUTO are scrolled off to the left with nothing hinting that they exist. | Open the remote screen in M. | `remote-portrait.png` | Show an edge fade, or centre-snap with partial neighbours on both sides. (Not confirmed by swiping.) |
| olympus-pen-f-F9 | S4 | UI-HOME-04 | After a fresh launch the first tap on the saved camera did nothing and showed no state; the second tap connected. | Relaunch the app, tap the PEN-F card. | – | Show "Connecting…" immediately on the first tap, or ignore taps until the list is ready. |
| olympus-pen-f-F10 | S4 | UI-REMOTE-01 | A black band sits above the live view and another large gap between the quick-aid row and the mode row; the live view also resizes and jumps when a settings panel opens. | Look at the remote screen; tap Shutter then EV then Drive. | `remote-portrait.png` | Anchor live view to the top, let panels overlay or reserve the height. |
| olympus-pen-f-F11 | S4 | MENU-01 | ⋯ menu is taller than the screen: Request log, Disconnect and Turn camera off are below the fold; "Scene suggestions" hyphenates as "sug-gestions"; "Shutterlink Pro" shows no status line (the README says it does). | Tap ⋯. | `menu.png` | Widen the menu or shorten labels; show the Pro status as a subtitle. |
| olympus-pen-f-F12 | S4 | SET-01 | All camera settings shows raw property names under each row ("focalvalue . 23 options"), labels the colour tone as "Picture", and locked rows say nothing about why until tapped. | ⋯ > All camera settings. | `settings.png` | Hide the raw names (or move them into Request log), name rows as the camera does, add "unlocks in A or M". |
| olympus-pen-f-F13 | S4 | GAL-03, GAL-08 | The empty "other camera" folder banner fills a third of the first card screen; RAW files are separate tiles (with an ORF badge) and count in "On the card . 26", so the photo count is inflated. | Open the card on the mock PEN-F. | `card.png` | Collapse empty other-camera folders to one line; show RAW as a badge on its JPEG and count pairs once. |
| olympus-pen-f-F14 | S4 | UI-HOME-02 | The home status line "Wi-Fi 192.168.0.223. Check Settings > Wi-Fi shows the camera's network." never says whether the phone is on the camera or not. | Open the home screen on a LAN that uses 192.168.0.x. | – | Say "Looks like your home Wi-Fi, not the camera's" when the SSID is known, or hide when ambiguous. |
| olympus-pen-f-F15 | S4 | PRO-07 | With no StoreKit the Pro screen's "Try free for 7 days" looks disabled and "Buy Pro" has no price; only a small "Prices load from the App Store." explains it. | `-pro locked`, open the Pro screen. | `pro-screen-locked.png` | Show a spinner/"Loading price…" and a Retry; disable visibly with a reason. |
| olympus-pen-f-F16 | S4 | PRESET-02 | The Moon step reads "Daylight white balance … Sunny": the title and the value use different words. | Expand Moon in Presets. | `preset-moon-on.png` | Use the camera's name ("Sunny") in both. |
| olympus-pen-f-F17 | S4 (test infra) | ST-04 | The Olympus mock reports `artfilter` and `colortone`, which the real PEN-F (firmware 3.1) does not, and lacks `exposemovie` and `colorphase`. All camera settings therefore shows rows a real PEN-F will not have. | Compare the self-test `settings read` line with `penf-probe/desclist.xml`. | `settings.png` | Make `mock_penf.py` serve the real PEN-F desclist (from `penf-probe/`). |
| olympus-pen-f-F18 | S4 (plan) | INT-01 | The Interval sheet has a third starting point, "Trails", that the plan did not list. | Open Interval. | – | Update the plan (not the app). |

## Mockup record (section 14)

### MODEL-01 Identity

| | |
|---|---|
| Model as reported | `PEN-F (mock)` (the app strips "(mock)") |
| Profile matched | PEN-F, 2016 |
| Support level shown | Tested on this camera |
| Crop factor | 2.0 |
| Notes shown after connecting | none |
| Capabilities | live view sizes: yes (camera list) · tap AF: yes · movie: yes (carousel VIDEO) · video switch: no · last-shot review: yes · clock sync: yes · High Res: yes · card: yes · power off: yes · focus drive: no |

### MODEL-02 to MODEL-05 What the camera offers, and what the app does with it

Baseline is the real PEN-F (firmware 3.1) from `PEN-F Remote/penf-probe/` (report.md). "Where": strip, mode, tool, settings (All camera settings only), background, not used.

| Command or property | Camera: settable / read-only / command | Options | Where in the app | Gap? worth adding? (S/M/L) |
|---|---|---|---|---|
| takemode | settable | iAuto P A S M ART movie | mode carousel | – |
| drivemode | settable | 12 | strip (icon only) | S: add text to the cell |
| focalvalue | settable (A, M) | 23 | strip | – |
| shutspeedvalue | settable (S, M) | 61 incl. Live Comp / Time / Bulb | strip + shutter dial | – |
| expcomp | settable (P, A, S) | 31 | strip | – |
| isospeedvalue | settable | 24 | strip | – |
| wbvalue | settable | 13 | strip | – |
| exposemovie | settable (real camera) | P A S M | strip in movie mode | – |
| colorphase (Hue) | settable (real camera) | – | settings only | S: only worth promoting for B&W shooters |
| artfilter / colortone | **mock only** | 14 / 9 | settings | not on the real PEN-F |
| noisereduction, NoiseReductionExposureTime | read-only | off/on/auto | not used | S: show "NR on: a 30 s shot takes 60 s" in the long-exposure countdown |
| bulbtimelimit | read-only | minutes | not used | S: cap the Stop-after choices at the camera's limit |
| lowvibtime, SilentTime | read-only | ms | not used | S: show the real anti-shock delay in the Drive panel |
| digitaltelecon | read-only | on/off | not used | S |
| touchactiveframe | read-only | area | not used | S: ignore taps outside it |
| QualityMovie2 (+Pixel/Comp/FrameRate sets) | read-only | presets | not used | M: show movie size and frame rate in the VIDEO view |
| ctrlzoom | command | power zoom | not used | M: only for EZ lenses |
| get_unusedcapacity, get_dcffilenum | command | – | not used | S: free space on the card in the card header |
| get_screennail | command | 1920x1440 preview inside every file incl. RAW | not used | M: sharper card previews without a full download |
| get_rsvimglist, clear_resvflg | command | share-order marks | not used | S |
| req_storegpsinfo, req_attachexifgps | command | GPS into the camera | not used | M: write the phone's location into the camera files |
| exec_shutter (cable release mode) | command | half/full press | not used | M: real half-press AF + shutter like the button |
| get_movplaytime | command | – | not used | S |

**The camera can, the app doesn't (`MODEL-04`):** noise-reduction awareness, free card space, screennail previews, GPS into the camera, power zoom, half-press shutter (exec_shutter), movie size/frame-rate display.

**The app shows, the camera can't (`MODEL-05`):** none seen. The mock's art filter and colour tone rows appear in All camera settings but a real PEN-F does not report them (F17).

### MODEL-06 Main-row budget

| Setting | Tier it should be | Where it is now | Taps to change | OK? |
|---|---|---|---|---|
| Mode | 1 | mode carousel (P/AUTO hidden off-screen) | 1 | UX (F8) |
| Aperture | 1 | strip | 2 | yes |
| Shutter | 1 | strip | 2 | yes |
| ISO | 1 | strip | 2 | yes |
| EV | 1 | strip (labelled AUTO in M, F2) | 2 | UX |
| White balance | 2 | strip | 2 | yes |
| Drive / self-timer | 2 | strip (icon only, panel clipped, F3/F4) | 2 | UX |
| Picture quality | 2 | not available on the PEN-F over Wi-Fi | – | no cell by design; say once where it is on the camera |
| Focus mode / AF area | 2 | not available over Wi-Fi | – | same |
| Photo / video | 2 | carousel VIDEO | 1 | yes |
| Movie exposure | 2 | strip in movie mode | 2 | not visited |
| Hue | 3 | All camera settings | 3 | fine |

Cells on the strip: 6 of 6 fit on the iPhone 17 without scrolling.

### MODEL-07 What the live screen should show

Six cells fit, and the PEN-F can only change eight things over Wi-Fi, so **nothing needs hiding**: mode (with P and AUTO reachable), F-STOP, SHUTTER, ISO, EV, WB, DRIVE. Changes for this body: (1) in M show EV greyed as "n/a" and let ISO take the cell's emphasis; (2) put a word under the Drive icon; (3) put a "Preset: Astro" chip above the strip while a preset is on; (4) move the quick-aid row up against the live view and let the live view take the black band above it; (5) because Hue is the only Tier 3 setting, All camera settings can stay as it is.

### MODEL-08 How the UI should behave for this model

- Keep High Res in Tools (the PEN-F has it) but label it "Guide" and say the camera must be set by hand.
- Focus stack: replace the generic Olympus text with a model line ("PEN-F: Focus BKT is in MENU > Shooting menu 2").
- Presets: the PEN-F accepts every step the presets use; no camera-side steps were needed on the mock.
- Quality/Focus mode: add one line on first connect, "Image quality and AF mode are set on the camera (the PEN-F doesn't allow them over Wi-Fi)".
- Label: "Tested on this camera" is right for this body.

### MODEL-09 Screenshots

| Screen | File |
|---|---|
| Remote, portrait | `img/olympus-pen-f/remote-portrait.png` |
| Remote, landscape | not taken |
| Tools grid | `img/olympus-pen-f/tools.png`, `tools-pro-locked.png` |
| All camera settings | `img/olympus-pen-f/settings.png` |
| ⋯ menu | `img/olympus-pen-f/menu.png` |
| A preset's steps | `img/olympus-pen-f/preset-moon-on.png` |
| Others | `ev-locked-in-M.png`, `drive-grid-clipped.png`, `astro-on-no-indicator.png`, `bracket-focus-guide.png`, `pro-screen-locked.png`, `card.png`, `connection-lost-banner.png`, `tools-with-af-pill.png` |

## Pro scorecard (`VAL-01`)

All "Full" ratings are against the mock; none is confirmed on a real PEN-F.

| Pro feature | Full / Part / Guide / None | Note |
|---|---|---|
| Preset: Astro | Full | 5" at 30 mm / 60 mm equivalent, stays on, turn off in sheet |
| Preset: Moon | Full | Screen shows steps then "On" |
| Preset: Fireworks | Full | Live Composite on Olympus; self-test pass |
| Preset: Landscape | Full | self-test pass |
| Preset: Action | Full | self-test pass |
| Preset: Macro | Full | "Focus stack next" leads to a guide on Olympus (F-STK) |
| Preset: Light trails & silky water | Full | self-test pass |
| Undo / My presets | Full | Undo lost on restart (F5) |
| Star trails | Full | Live Composite on the PEN-F; sheet tab not opened |
| Interval timer | Full | self-test pass; sheet seen |
| Follow the light | Part | not run |
| Exposure bracket | Full | self-test pass |
| Focus stack | Guide | camera's own Focus BKT |
| ND filter | Full | up to Live Time; self-test pass |
| Expose to the right | Part | needs Live View Boost off; refused cleanly on the mock |
| Motion trigger | Full | passes only barely (peak 0.0104 / threshold 0.01) |
| High Res helper | Guide | instructions only |
| Watch remote | — | not testable in this pass |
| Scene suggestions that run a setup | Part | classifier does not run in the simulator |

Full: 10 · Part: 3 · Guide: 2 · None: 0 (Watch and Follow-the-light not run). This meets the plan's bar (at least 8 Full, at most 2 None).

**Sells it for this model (`VAL-07`):** Astro and Moon one-tap setups (clear, previewed before applying, with a Turn off that restores the settings), and Live Composite star trails (a true PEN-F strength). Easy to find: both are in the first Tools row.

**Makes $9.99 feel not worth it here (`VAL-04`):** two of the six benefit rows lean on the camera's own menus (High Res helper, focus stacking), the locked Shooting row is almost the whole row (7 of 8 tiles), and the Pro screen is clipped (F7), so a free user sees locks but can't see all they are buying.

## Self-test output (section 4)

```text
SELFTEST PASS connect brand=olympus name=PEN-F error=-
SELFTEST INFO profile=PEN-F support=Tested on this camera crop=2.0 note=-
SELFTEST PASS live view fps=11 frame=640x480
SELFTEST PASS settings read artfilter=popart(ro)[14] colortone=natural[9] drivemode=normal[12] expcomp=0.0[31] focalvalue=5.6(ro)[23] isospeedvalue=Auto[24] shutspeedvalue=250(ro)[61] takemode=P[7] wbvalue=0[13]
SELFTEST PASS set expcomp 0.0 → -5.0 / set isospeedvalue Auto → Low / set wbvalue 0 → 18
SELFTEST PASS tap focus · shoot · last-shot review · movie
SELFTEST PASS interval shots=2 · bracket shots=3
SELFTEST PASS preset astro takemode=M focalvalue=F1.8 shutspeedvalue=8" isospeedvalue=1600 wbvalue=Fluorescent drivemode=Anti-shock Single
SELFTEST PASS preset moon / fireworks (Live Comp) / landscape / action / macro / trails
SELFTEST PASS preset undo mode M → M · saved preset 6 values
SELFTEST PASS nd setup metered 15.0s → 960.0s, shutter now livetime
SELFTEST PASS motion trigger shots=1 peak=0.0104 threshold=0.01
SELFTEST PASS ettr ev 0.0 → 0.0 Live view doesn't get brighter with the exposure…
SELFTEST PASS battery 72%
SELFTEST PASS card list 24 files in ["116_PANA", "100OLYMP"] · thumbnail · preview 640x480 · download 24227 bytes · download RAW 1500004 bytes
SELFTEST PASS live view after card fps=5
SELFTEST DONE failures=0
```

## Resource samples (section 13)

Not measured in this pass (`RES-01` to `RES-13` are `—`). One data point: RSS of the simulator process was 275 MB (`ps`) after about 5 minutes of use including the card browser.

## Checklist



One row per check in the plan. A short run fills in sections marked in the plan and writes "as `<sheet>`" in the
note for the rest.

### Self-test

| ID | Run | Check | Result | Note / evidence |
|---|---|---|---|---|
| ST-01 | A | Connect | P | brand=olympus name=PEN-F |
| ST-02 | A | Profile | P | profile PEN-F, "Tested on this camera", crop 2.0 |
| ST-03 | A | Live view | P | fps=11, 640x480 (fps=5 right after closing the card, see ST-20) |
| ST-04 | A | Settings read | P | 9 props: artfilter(ro) colortone drivemode expcomp focalvalue(ro) isospeedvalue shutspeedvalue(ro) takemode wbvalue. Mock only: artfilter/colortone (real PEN-F fw 3.1 lacks them); missing vs real: exposemovie, colorphase |
| ST-05 | A | Set each exposure setting | P | expcomp, isospeedvalue, wbvalue set; focalvalue/shutspeedvalue read-only in P (no line, expected) |
| ST-06 | A | Tap focus | P |  |
| ST-07 | A | Shoot and review | P | shoot + last-shot review |
| ST-08 | A | Movie | P |  |
| ST-09 | A | Interval | P | shots=2 |
| ST-10 | A | Bracket | P | shots=3, setting restored |
| ST-11 | A | Focus stack | N/A | Olympus has no Wi-Fi focus drive |
| ST-12 | A | Scene assistant | P | scene analysis gave no suggestion in the simulator (classifier does not run there) |
| ST-13 | A | Every preset | P | All 7 presets PASS, none skipped/FAILED on the mock. Astro self-test shutter 8" (500 rule) differs from the sheet default (300 rule = 5"): self-test does not cover the default sheet plan |
| ST-14 | A | Undo and saved preset | P | "preset undo mode M -> M" is a weak check (mode was already M) |
| ST-15 | A | ND setup | P | 15 s -> 960 s (6 stops), shutter set to livetime |
| ST-16 | A | Motion trigger | P | peak 0.0104 vs threshold 0.01: passes only barely |
| ST-17 | A | Expose to the right | P | Refused with "Live view does not get brighter..." and left EV unchanged (good) |
| ST-18 | A | Battery | P | 72% |
| ST-19 | A | Card | P | 24 files in 116_PANA (empty) + 100OLYMP; RAW 1,500,004 bytes |
| ST-20 | A | Back to live view | P | failures=0; fps=5 after card closed vs 11 before |
| ST-21 | A | Refuses real cameras | — | not run in this pass |

### Home, Add a camera, QR

| ID | Run | Check | Result | Note / evidence |
|---|---|---|---|---|
| UI-HOME-01 | S | First launch | — | not run in this pass |
| UI-HOME-02 | S | Wi-Fi status line | UX | Status line "Wi-Fi 192.168.0.223. Check Settings > Wi-Fi shows the camera's network." is a hedge: it never says whether this is right or wrong. S4. img/olympus-pen-f/ (home not saved; see olympus-pen-f-F14) |
| UI-HOME-03 | S | Saved camera card | P | Name, OLYMPUS, "14 seconds ago"; Add a camera under the list |
| UI-HOME-04 | S | Reconnect from the card | UX | After a relaunch the first tap on the card did nothing and gave no feedback; the second tap connected (once, may be launch timing). S3 |
| UI-HOME-05 | S | Card with the camera off | — | not run in this pass |
| UI-HOME-06 | S | Forget a camera | — | not run in this pass |
| UI-HOME-07 | S | Two cameras, right Wi-Fi each | — | not run in this pass |
| UI-HOME-08 | S | Most recent first | — | not run in this pass |
| UI-HOME-09 | S | Shortcut tip | P | Tip names the Action button path |
| UI-ADD-01 | S | Open Add a camera | — | not run in this pass |
| UI-ADD-02 | S | Steps change with the brand | — | not run in this pass |
| UI-ADD-03 | S | Advanced | — | not run in this pass |
| UI-ADD-04 | S | Connect, right brand | — | not run in this pass |
| UI-ADD-05 | S | Connect, Automatic | — | not run in this pass |
| UI-ADD-06 | S | Wrong brand picked | — | not run in this pass |
| UI-ADD-07 | S | Unsupported body | — | not run in this pass |
| UI-ADD-08 | S | One-time model note | — | not run in this pass |
| UI-ADD-09 | S | Camera says No (LUMIX) | — | not run in this pass |
| UI-ADD-10 | S | Newer LUMIX pairing | — | not run in this pass |
| UI-ADD-11 | S | Nothing at the address | — | not run in this pass |
| UI-ADD-12 | S | Cancel while connecting | — | not run in this pass |
| UI-ADD-13 | S | Type the camera's Wi-Fi | — | not run in this pass |
| UI-QR-01 | S | Scanner without camera access | — | not run in this pass |
| UI-QR-02 | H | Scan a real code | — | needs a real device/camera |
| UI-QR-03 | H | Scan something else | — | needs a real device/camera |

### Remote screen

| ID | Run | Check | Result | Note / evidence |
|---|---|---|---|---|
| UI-REMOTE-01 | S | First screen after connect | UX | All elements present. Wasted space: black bar above live view and a large gap between quick row and mode row; live view jumps when a panel opens. img/olympus-pen-f/remote-portrait.png. S4 |
| UI-REMOTE-02 | S | Top bar values | P | 72% and 4,382 shots; count dropped after shots |
| UI-REMOTE-03 | S | Dynamic Type | — | not run in this pass |
| UI-REMOTE-04 | S | Small phone | — | not run in this pass |
| UI-REMOTE-05 | S | Error banner | — | not run in this pass |
| UI-REMOTE-06 | S | Connection lost | UX | Mock stopped: after ~12 s orange dot, shutter greyed, last frame frozen, a 9-line red banner with jargon and error code -1004. No Reconnect/Disconnect button in the banner. S3. connection-lost-banner.png |
| UI-REMOTE-07 | S | Background and return | — | not run in this pass |
| UI-REMOTE-08 | S | Toasts | — | not run in this pass |
| UI-STRIP-01 | S | Which cells show | UX | Cells: F-STOP SHUTTER ISO EV WB DRIVE. No Quality (Olympus does not report it; by design). Hue only in All camera settings. Drive cell is an icon with no text |
| UI-STRIP-02 | S | AUTO marks | UX | EV cell says AUTO in M mode, but EV has no effect in M: misleading. S3. ev-locked-in-M.png |
| UI-STRIP-03 | S | Aperture dial | — | not run in this pass |
| UI-STRIP-04 | S | Shutter dial | P | Timed / Live Comp / Live Time / Live Bulb segments and dial work |
| UI-STRIP-05 | S | ISO dial | — | not run in this pass |
| UI-STRIP-06 | S | EV dial | — | not run in this pass |
| UI-STRIP-07 | S | White balance | — | not run in this pass |
| UI-STRIP-08 | S | Drive | UX | Drive cell shows a bare square for both Single and Anti-shock Single; option panel shows ~1.5 rows of 12 options, tiles cropped, no scroll cue. S3. drive-grid-clipped.png |
| UI-STRIP-09 | S | Quality | — | not run in this pass |
| UI-STRIP-10 | S | Locked setting explains itself | UX | EV in M: "The camera sets this itself in M mode." + "Switch to A" (unlock offered; not tapped). Text is wrong for EV in M. S3 |
| UI-STRIP-11 | S | Movie exposure cell | — | not run in this pass |
| UI-STRIP-12 | S | One panel at a time | — | not run in this pass |
| UI-STRIP-13 | S | Values follow the camera | — | not run in this pass |
| UI-STRIP-14 | S | Strip while busy | — | not run in this pass |
| UI-MODE-01 | S | Change mode | UX | Carousel in M shows A S M ART VIDEO: P and AUTO are off-screen to the left with no cue (not scrolled to confirm). S3 |
| UI-MODE-02 | S | Mode can't be set (physical dial) | — | not run in this pass |
| UI-MODE-03 | S | Mode during exposure | — | not run in this pass |
| UI-MODE-04 | S | Video switch | — | not run in this pass |
| UI-SHUT-01 | S·H | Single shot | — | not run in this pass |
| UI-SHUT-02 | S·H | Burst | — | not run in this pass |
| UI-SHUT-03 | S·H | Long timed exposure | — | not run in this pass |
| UI-SHUT-04 | S·H | Bulb / Live Time / Live Composite | — | not run in this pass |
| UI-SHUT-05 | S·H | Movie record | — | not run in this pass |
| UI-SHUT-06 | S | Tap AF vs Tap shoots | — | not run in this pass |
| UI-SHUT-07 | S | Last-shot button | — | not run in this pass |
| UI-SHUT-08 | S | Keyboard (iPad/Mac) | — | not run in this pass |
| UI-LV-01 | S·H | Runs and fits | — | not run in this pass |
| UI-LV-02 | S | Size picker | — | not run in this pass |
| UI-LV-03 | S | No frames arriving | — | not run in this pass |
| UI-LV-04 | S | Restart live view | — | not run in this pass |
| UI-LV-05 | S | Frame data | — | not run in this pass |
| UI-LV-06 | S | Scene suggestion pill | — | not run in this pass |
| UI-AID-01 | S | Grid | — | not run in this pass |
| UI-AID-02 | S | Histogram | — | not run in this pass |
| UI-AID-03 | S | Peaking | — | not run in this pass |
| UI-AID-04 | S | Loupe | — | not run in this pass |
| UI-AID-05 | S | Night mode | — | not run in this pass |
| UI-AID-06 | S | Aids are still reachable when the row hides | — | not run in this pass |

### Tools

| ID | Run | Check | Result | Note / evidence |
|---|---|---|---|---|
| UI-TOOLS-01 | S | Grid contents | P | Presets Astro Interval Bracket ND Motion Pocket High Res / Loupe Night Histogram Grid Peaking Geotag Tap AF. tools.png |
| UI-TOOLS-02 | S | Open and close | P | Presets, Astro, Interval, Bracket open as sheets and close with the tick |
| UI-TOOLS-03 | S | Running state on the button | — | not run in this pass |
| PRESET-01 | S | List | P | Each preset has a one-line description |
| PRESET-02 | S | Apply | P | Tapping a preset row only expands its step list; the Apply button is below (scroll). Clear, but two steps. preset-moon-on.png |
| PRESET-03 | S | Stays on | UX | Sheet shows On + "Turn off" but the remote screen shows nothing (no badge, tile not lit). S3. astro-on-no-indicator.png |
| PRESET-04 | S | Turn off puts settings back | P | Toast "Settings from before Moon are back". Moon barely changed anything from the starting state, so a weak test |
| PRESET-05 | S | Switch presets | — | not run in this pass |
| PRESET-06 | S | Skipped steps say what to do | N/A | No step on the Olympus mock was skipped. Needs a body with a physical mode dial |
| PRESET-07 | S | Preset the camera half-refuses | — | not run in this pass |
| PRESET-08 | S | Save current / My presets | — | not run in this pass |
| PRESET-09 | S | Macro hands over to focus stack | — | not run in this pass |
| PRESET-10 | S | Expose to the right | — | not run in this pass |
| PRESET-11 | H | Do the presets give a good picture | — | not run in this pass |
| ASTRO-01 | S | Sheet | P | From your lens (30 mm), 300 rule, ISO 800-6400, Will set list |
| ASTRO-02 | S | Shutter follows focal length | P | 30 mm x crop 2.0 = 60 mm; 300/60 = 5.0 s; sheet shows 5" |
| ASTRO-03 | S | Apply and turn off | P | Applied: M, F1.8, 5", ISO 1600, Fluor. WB. Turn off not run |
| ASTRO-04 | S | Star trails with Live Composite | — | not run in this pass |
| ASTRO-05 | S | Star trails without Live Composite | — | not run in this pass |
| ASTRO-06 | S | Series can be stopped | — | not run in this pass |
| INT-01 | S | Sheet | P | Presets: Star stack, Time-lapse, Trails (plan listed two); "60 frames over about 20 min. At 25 fps that's a 2.4 s clip." |
| INT-02 | S | Run 3 frames at 3 s | — | not run in this pass |
| INT-03 | S | Stop mid-run | — | not run in this pass |
| INT-04 | S | Interval shorter than the exposure | — | not run in this pass |
| INT-05 | S | Refuses Live modes | — | not run in this pass |
| INT-06 | S | Follow the light | — | not run in this pass |
| INT-07 | S | Survives the sheet closing and pocket mode | — | not run in this pass |
| INT-08 | H | An hour on a real camera | — | not run in this pass |
| BRK-01 | S | Sheet | P | Frames 3/5/7/9, step 1/3..2, Vary Auto/EV/Shutter, helper text |
| BRK-02 | S | Run 3 frames | — | not run in this pass |
| BRK-03 | S | Cancel | — | not run in this pass |
| BRK-04 | S | Range ends | — | not run in this pass |
| BRK-05 | S | Mode dial unknown | — | not run in this pass |
| FSTK-01 | S | Focus stack where the camera can | — | not run in this pass |
| FSTK-02 | S | Focus stack where it can't | P | Focus tab: "Olympus and OM System cameras have no Wi-Fi command to move focus. Use Focus BKT..." Good, but it does not say which bodies have Focus BKT or Focus Stacking. bracket-focus-guide.png |
| FSTK-03 | H | Real stack | — | not run in this pass |
| ND-01 | S | Meter | — | not run in this pass |
| ND-02 | S | Pick a strength | — | not run in this pass |
| ND-03 | S | Set up, short | — | not run in this pass |
| ND-04 | S | Set up, longer than the camera's speeds | — | not run in this pass |
| MOT-01 | S | Arm | — | not run in this pass |
| MOT-02 | S | Sensitivity and wait | — | not run in this pass |
| MOT-03 | S | Disarm and refusals | — | not run in this pass |
| HIRES-01 | S | Helper on a High Res body | — | not run in this pass |
| HIRES-02 | S | Hidden elsewhere | — | not run in this pass |
| HIRES-03 | H | Real High Res shot | — | not run in this pass |
| MISC-01 | S | Pocket mode | — | not run in this pass |
| MISC-02 | S | Geotag | — | not run in this pass |
| MISC-03 | S | Timed Bulb | — | not run in this pass |

### Card browser and auto-save

| ID | Run | Check | Result | Note / evidence |
|---|---|---|---|---|
| GAL-01 | S | Open | P | "On the card . 26" grid, newest first |
| GAL-02 | S | Empty and failed states | — | not run in this pass |
| GAL-03 | S | Folders | UX | Empty "other camera" folder banner takes about a third of the first screen. S4. card.png |
| GAL-04 | S | View a photo | — | not run in this pass |
| GAL-05 | S | Save a JPEG | — | not run in this pass |
| GAL-06 | S | Star | — | not run in this pass |
| GAL-07 | S | Download RAWs of starred | — | not run in this pass |
| GAL-08 | S | RAW badge | UX | RAW files appear as their own tiles (ORF badge, same picture) and count in the 26; plan expected "Has a RAW file" on the JPEG. S4 |
| GAL-09 | S | Cancel a big download | — | not run in this pass |
| GAL-10 | S | Locked during an exposure | — | not run in this pass |
| GAL-11 | S | No card browser on this body | — | not run in this pass |
| GAL-12 | H | Real card, hundreds of files | — | not run in this pass |
| ASAVE-01 | S | Turn on | — | not run in this pass |
| ASAVE-02 | S | Access refused | — | not run in this pass |
| ASAVE-03 | S | Sequences aren't saved one by one | — | not run in this pass |
| ASAVE-04 | S | LUMIX saves later | — | not run in this pass |
| ASAVE-05 | S | What gets saved | — | not run in this pass |
| ASAVE-06 | S | Doesn't slow the shutter | — | not run in this pass |

### ⋯ menu, settings, log

| ID | Run | Check | Result | Note / evidence |
|---|---|---|---|---|
| MENU-01 | S | Contents | UX | Items present; Request log/Disconnect/Turn off are below the fold of the menu; "Scene sug-gestions" hyphenates; no Pro status text under "Shutterlink Pro". S4. menu.png |
| MENU-02 | S | Sync camera clock | — | not run in this pass |
| MENU-03 | S | Disconnect | — | not run in this pass |
| MENU-04 | S | Turn camera off | — | not run in this pass |
| MENU-05 | S | Pro status line | — | not run in this pass |
| SET-01 | S | All camera settings | UX | Shows raw names ("focalvalue . 23 options"), "Picture" for colortone, locked rows with a padlock and no reason until tapped. S4. settings.png |
| SET-02 | S | Change one | — | not run in this pass |
| SET-03 | S | Locked row | — | not run in this pass |
| SET-04 | S | What deserves promoting | — | not run in this pass |
| LOG-01 | S | Request log | — | not run in this pass |
| LOG-02 | S | Copy and Clear | — | not run in this pass |
| LOG-03 | S | Support level is honest | — | not run in this pass |

### Pro

| ID | Run | Check | Result | Note / evidence |
|---|---|---|---|---|
| PRO-01 | S | Which tools are locked | P | 7 locks (Presets Astro Interval Bracket ND Motion High Res); Pocket and all switches free. tools-pro-locked.png |
| PRO-02 | S | A locked tool opens the Pro screen | P | High Res opens the Pro screen: "The High Res Shot helper is part of Shutterlink Pro" |
| PRO-03 | S | Pro screen content | UX | Benefit list is clipped after "Exposure tools" with no scroll cue (High Res, Watch, scene suggestions hidden). S3. pro-screen-locked.png |
| PRO-04 | S | Free things stay free | — | not run in this pass |
| PRO-05 | S | Scene suggestions under lock | — | not run in this pass |
| PRO-06 | S | Other routes to locked features | — | not run in this pass |
| PRO-07 | S | Prices don't load | UX | Without StoreKit: "Try free for 7 days" looks disabled, "Buy Pro" has no price, only "Prices load from the App Store." S4 |
| PRO-08 | S | Locked state is discoverable but not nagging | — | not run in this pass |
| PRO-09 | S | Trial state | — | not run in this pass |
| PRO-10 | S | Unlocked state | — | not run in this pass |
| PRO-11 | H | Real trial and purchase | — | needs a real device/camera |
| PRO-12 | H | Trial ends mid-use | — | needs a real device/camera |
| PRO-13 | H | Offline | — | needs a real device/camera |
| PRO-14 | H | Early users keep Pro | — | needs a real device/camera |
| PRO-15 | H | Watch without Pro | — | needs a real device/camera |

### Watch, iPad, Mac

| ID | Run | Check | Result | Note / evidence |
|---|---|---|---|---|
| WATCH-01 | H | Not connected | — | needs a real device/camera |
| WATCH-02 | H | Live view and status | — | needs a real device/camera |
| WATCH-03 | H | Shutter | — | needs a real device/camera |
| WATCH-04 | H | Self-timer | — | needs a real device/camera |
| WATCH-05 | H | Digital Crown | — | needs a real device/camera |
| WATCH-06 | H | iPhone app goes to the background | — | needs a real device/camera |
| PAD-01 | S | Workspace, landscape | — | iPad run not done in this pass |
| PAD-02 | S | Workspace, portrait and split view | — | iPad run not done in this pass |
| PAD-03 | S | Tools as side panels | — | iPad run not done in this pass |
| PAD-04 | S | Card browser | — | iPad run not done in this pass |
| PAD-05 | S | Keyboard | — | iPad run not done in this pass |
| MAC-01 | H | Window | — | needs a real device/camera |
| MAC-02 | H | Menus | — | needs a real device/camera |
| MAC-03 | H | Mac wording | — | needs a real device/camera |
| MAC-04 | H | Saving | — | needs a real device/camera |
| MAC-05 | H | Stays awake | — | needs a real device/camera |

### UX sweep

| ID | Run | Check | Result | Note / evidence |
|---|---|---|---|---|
| UX-01 | S | Dead ends | — | not run in this pass |
| UX-02 | S | Shown but not usable | — | not run in this pass |
| UX-03 | S | "Not offered" without a next step | — | not run in this pass |
| UX-04 | S | Missing feedback | — | not run in this pass |
| UX-05 | S | Labels | — | not run in this pass |
| UX-06 | S | Buried controls | — | not run in this pass |
| UX-07 | S | State you can't see | UX | Preset/Astro on, interval armed? Preset on is invisible on the remote screen (see PRESET-03) |
| UX-08 | S | Undo and recovery | UX | If the app is killed with a preset on, the camera keeps the preset settings and Undo is gone after relaunch (observed: F1.8, 5", ISO 1600 stayed) |
| UX-09 | S | Consistency | — | not run in this pass |
| UX-10 | S | Accessibility | — | not run in this pass |
| UX-11 | S | First five minutes | — | not run in this pass |
| UX-12 | S | Honesty about experimental support | — | not run in this pass |

### Storage and resources

| ID | Run | Check | Result | Note / evidence |
|---|---|---|---|---|
| RES-01 | S | Live view, 10 minutes idle | — | not run in this pass |
| RES-02 | S | Live view with every aid on | — | not run in this pass |
| RES-03 | S | Live view size changes | — | not run in this pass |
| RES-04 | S | Shooting loop | — | not run in this pass |
| RES-05 | S | Card browser | — | not run in this pass |
| RES-06 | S | JPEG downloads | — | not run in this pass |
| RES-07 | S | RAW downloads | — | not run in this pass |
| RES-08 | S | Disk use | — | not run in this pass |
| RES-09 | S | LUMIX menu cache | — | not run in this pass |
| RES-10 | S | Request log cap | — | not run in this pass |
| RES-11 | S | Auto-save over a long session | — | not run in this pass |
| RES-12 | S | Reconnect loop | — | not run in this pass |
| RES-13 | S | CPU at idle | — | not run in this pass |
| RES-14 | H | Battery and heat, one hour | — | needs a real device/camera |
| RES-15 | H | Battery and heat, pocket mode | — | needs a real device/camera |
| RES-16 | H | Memory on the device | — | needs a real device/camera |
| RES-17 | H | Low storage | — | needs a real device/camera |

### Value and pricing

| ID | Run | Check | Result | Note / evidence |
|---|---|---|---|---|
| VAL-01 | S | Pro scorecard for this model | P | See Pro scorecard |
| VAL-02 | S | Does the Pro screen promise only what this model gets | UX | Pro screen says focus stacks are LUMIX/Nikon/Canon (good) but lists High Res helper without saying it is a guide; list clipped |
| VAL-03 | S | "Guide" features behind the paywall | UX | High Res helper and the Olympus focus-stack tab are instructions only |
| VAL-04 | S | What breaks or is missing in Pro | — | not run in this pass |
| VAL-05 | S | Free tier is complete | — | not run in this pass |
| VAL-06 | S | The trial shows the value | — | not run in this pass |
| VAL-07 | S | Which single feature sells it for this model | — | not run in this pass |
| VAL-08 | S | Beta brands | — | not run in this pass |
| VAL-09 | H | One real outing | — | needs a real device/camera |
| VAL-10 | S | Verdict | P | See Value verdict |

### Real camera only

| ID | Run | Check | Result | Note / evidence |
|---|---|---|---|---|
| HW-01 | H | Join and connect by hand | — | needs a real device/camera |
| HW-02 | H | Join from the app | — | needs a real device/camera |
| HW-03 | H | Every strip setting takes effect on the camera | — | needs a real device/camera |
| HW-04 | H | What the body refuses | — | needs a real device/camera |
| HW-05 | H | Physical dials | — | needs a real device/camera |
| HW-06 | H | Live view quality and lag | — | needs a real device/camera |
| HW-07 | H | Shutter, burst, Bulb, Live modes, video | — | needs a real device/camera |
| HW-08 | H | Auto-save size | — | needs a real device/camera |
| HW-09 | H | Card: real JPEG and RAW | — | needs a real device/camera |
| HW-10 | H | Range and dropouts | — | needs a real device/camera |
| HW-11 | H | Camera sleeps or its battery dies | — | needs a real device/camera |
| HW-12 | H | Phone locks | — | needs a real device/camera |
| HW-13 | H | Maker's app open at the same time | — | needs a real device/camera |
| HW-14 | H | Model-specific notes are true | — | needs a real device/camera |
| HW-15 | H | Nothing changed on the camera afterwards | — | needs a real device/camera |
