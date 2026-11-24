# Results: <brand> <model>

Copy this file to `results/<brand>-<model>.md` (e.g. `olympus-pen-f.md`) and fill it in. The checks, their steps
and what counts as a pass are in [`../TEST-PLAN.md`](../TEST-PLAN.md); this sheet only records results.

**Result:** `P` pass · `F` fail · `UX` works but a UX failure showed · `N/A` this model can't (say why) · `—` not
run (say why). Every `F` and `UX` gets a row in [Findings](#findings).

## Run

| | |
|---|---|
| Sheet | `<brand>-<model>` |
| Run type | Full / Short (as `<first sheet of the brand>`) |
| Date | |
| Tester | |
| Build | `git rev-parse --short HEAD` → |
| Device | iPhone 17 simulator / iPad Pro 13 simulator / real iPhone … (iOS version) |
| Camera | Mock: `python3 -I -u mock_….py …` / Real: model, firmware |
| Pro state(s) used | unlocked / `-pro locked` / `-pro trial` |

## Summary

| | Count |
|---|---|
| Checks run | |
| P | |
| F | |
| UX | |
| N/A | |
| Not run | |
| Findings S1 / S2 / S3 / S4 | / / / |

**Top problems** (three lines at most):

1.
2.
3.

**Value verdict** (`VAL-10`): fair / generous / a stretch, because …

## Findings

| ID | Sev | Check | What happens | Steps | Evidence | Suggested fix |
|---|---|---|---|---|---|---|
| `<sheet>-F1` | S? | `UI-…` | | | `img/<sheet>/….png` | |

## Mockup record (section 14)

### MODEL-01 Identity

| | |
|---|---|
| Model as reported | |
| Profile matched | name / `none` |
| Support level shown | Tested on this camera / Researched… / Not supported |
| Crop factor | |
| Notes shown after connecting | |
| Capabilities | live view sizes: · tap AF: · movie: · video switch: · last-shot review: · clock sync: · High Res: · card: · power off: · focus drive: |

### MODEL-02 to MODEL-05 What the camera offers, and what the app does with it

"Where" is one of: **strip**, **mode**, **tool** (name it), **settings** (All camera settings only),
**background** (used, not shown), **not used**.

| Command or property | Camera: settable / read-only / command | Options | Where in the app | Gap? worth adding? (S/M/L) |
|---|---|---|---|---|
| | | | | |

**The camera can, the app doesn't (`MODEL-04`):**

-

**The app shows, the camera can't (`MODEL-05`):**

-

### MODEL-06 Main-row budget

| Setting | Tier it should be (1 / 2 / 3) | Where it is now | Taps to change | OK? |
|---|---|---|---|---|
| Mode | 1 | | | |
| Aperture | 1 | | | |
| Shutter | 1 | | | |
| ISO | 1 | | | |
| EV | 1 | | | |
| White balance | 2 | | | |
| Drive / self-timer | 2 | | | |
| Picture quality | 2 | | | |
| Focus mode / AF area | 2 | | | |
| Photo / video | 2 | | | |
| Movie exposure | 2 | | | |
| (others this model has) | | | | |

Cells on the strip for this model: … of which visible without scrolling on the smallest iPhone: …

### MODEL-07 What the live screen should show

Describe or attach an annotated screenshot: the cells and their order, what replaces a cell this model can't use,
read-only indicators (mode dial, drive dial), and which tools show.

### MODEL-08 How the UI should behave for this model

-

### MODEL-09 Screenshots

| Screen | File |
|---|---|
| Remote, portrait | `img/<sheet>/remote-portrait.png` |
| Remote, landscape | `img/<sheet>/remote-landscape.png` |
| Tools grid | `img/<sheet>/tools.png` |
| All camera settings | `img/<sheet>/settings.png` |
| ⋯ menu | `img/<sheet>/menu.png` |
| A preset's steps | `img/<sheet>/preset-steps.png` |

## Pro scorecard (`VAL-01`)

**Full** works end to end from the phone · **Part** needs steps on the camera · **Guide** only instructions ·
**None** not available.

| Pro feature | Full / Part / Guide / None | Note |
|---|---|---|
| Preset: Astro | | |
| Preset: Moon | | |
| Preset: Fireworks | | |
| Preset: Landscape | | |
| Preset: Action | | |
| Preset: Macro | | |
| Preset: Light trails & silky water | | |
| Undo / My presets | | |
| Star trails | | |
| Interval timer | | |
| Follow the light | | |
| Exposure bracket | | |
| Focus stack | | |
| ND filter | | |
| Expose to the right | | |
| Motion trigger | | |
| High Res helper | | |
| Watch remote | | |
| Scene suggestions that run a setup | | |

Full: … · Part: … · Guide: … · None: …

**Sells it for this model (`VAL-07`):**

**Makes $9.99 feel not worth it here (`VAL-04`):**

## Self-test output (section 4)

```text
(paste the SELFTEST lines)
```

## Resource samples (section 13)

| Check | Time | Footprint | Note |
|---|---|---|---|
| RES-01 | 0:00 | | |
| | 1:00 | | |
| | 10:00 | | |

Disk (`RES-08`): Documents … · Caches … · Application Support … · tmp …

## Checklist

One row per check in the plan. A short run fills in sections marked in the plan and writes "as `<sheet>`" in the
note for the rest.

### Self-test

| ID | Run | Check | Result | Note / evidence |
|---|---|---|---|---|
| ST-01 | A | Connect |  |  |
| ST-02 | A | Profile |  |  |
| ST-03 | A | Live view |  |  |
| ST-04 | A | Settings read |  |  |
| ST-05 | A | Set each exposure setting |  |  |
| ST-06 | A | Tap focus |  |  |
| ST-07 | A | Shoot and review |  |  |
| ST-08 | A | Movie |  |  |
| ST-09 | A | Interval |  |  |
| ST-10 | A | Bracket |  |  |
| ST-11 | A | Focus stack |  |  |
| ST-12 | A | Scene assistant |  |  |
| ST-13 | A | Every preset |  |  |
| ST-14 | A | Undo and saved preset |  |  |
| ST-15 | A | ND setup |  |  |
| ST-16 | A | Motion trigger |  |  |
| ST-17 | A | Expose to the right |  |  |
| ST-18 | A | Battery |  |  |
| ST-19 | A | Card |  |  |
| ST-20 | A | Back to live view |  |  |
| ST-21 | A | Refuses real cameras |  |  |

### Home, Add a camera, QR

| ID | Run | Check | Result | Note / evidence |
|---|---|---|---|---|
| UI-HOME-01 | S | First launch |  |  |
| UI-HOME-02 | S | Wi-Fi status line |  |  |
| UI-HOME-03 | S | Saved camera card |  |  |
| UI-HOME-04 | S | Reconnect from the card |  |  |
| UI-HOME-05 | S | Card with the camera off |  |  |
| UI-HOME-06 | S | Forget a camera |  |  |
| UI-HOME-07 | S | Two cameras, right Wi-Fi each |  |  |
| UI-HOME-08 | S | Most recent first |  |  |
| UI-HOME-09 | S | Shortcut tip |  |  |
| UI-ADD-01 | S | Open Add a camera |  |  |
| UI-ADD-02 | S | Steps change with the brand |  |  |
| UI-ADD-03 | S | Advanced |  |  |
| UI-ADD-04 | S | Connect, right brand |  |  |
| UI-ADD-05 | S | Connect, Automatic |  |  |
| UI-ADD-06 | S | Wrong brand picked |  |  |
| UI-ADD-07 | S | Unsupported body |  |  |
| UI-ADD-08 | S | One-time model note |  |  |
| UI-ADD-09 | S | Camera says No (LUMIX) |  |  |
| UI-ADD-10 | S | Newer LUMIX pairing |  |  |
| UI-ADD-11 | S | Nothing at the address |  |  |
| UI-ADD-12 | S | Cancel while connecting |  |  |
| UI-ADD-13 | S | Type the camera's Wi-Fi |  |  |
| UI-QR-01 | S | Scanner without camera access |  |  |
| UI-QR-02 | H | Scan a real code |  |  |
| UI-QR-03 | H | Scan something else |  |  |

### Remote screen

| ID | Run | Check | Result | Note / evidence |
|---|---|---|---|---|
| UI-REMOTE-01 | S | First screen after connect |  |  |
| UI-REMOTE-02 | S | Top bar values |  |  |
| UI-REMOTE-03 | S | Dynamic Type |  |  |
| UI-REMOTE-04 | S | Small phone |  |  |
| UI-REMOTE-05 | S | Error banner |  |  |
| UI-REMOTE-06 | S | Connection lost |  |  |
| UI-REMOTE-07 | S | Background and return |  |  |
| UI-REMOTE-08 | S | Toasts |  |  |
| UI-STRIP-01 | S | Which cells show |  |  |
| UI-STRIP-02 | S | AUTO marks |  |  |
| UI-STRIP-03 | S | Aperture dial |  |  |
| UI-STRIP-04 | S | Shutter dial |  |  |
| UI-STRIP-05 | S | ISO dial |  |  |
| UI-STRIP-06 | S | EV dial |  |  |
| UI-STRIP-07 | S | White balance |  |  |
| UI-STRIP-08 | S | Drive |  |  |
| UI-STRIP-09 | S | Quality |  |  |
| UI-STRIP-10 | S | Locked setting explains itself |  |  |
| UI-STRIP-11 | S | Movie exposure cell |  |  |
| UI-STRIP-12 | S | One panel at a time |  |  |
| UI-STRIP-13 | S | Values follow the camera |  |  |
| UI-STRIP-14 | S | Strip while busy |  |  |
| UI-MODE-01 | S | Change mode |  |  |
| UI-MODE-02 | S | Mode can't be set (physical dial) |  |  |
| UI-MODE-03 | S | Mode during exposure |  |  |
| UI-MODE-04 | S | Video switch |  |  |
| UI-SHUT-01 | S·H | Single shot |  |  |
| UI-SHUT-02 | S·H | Burst |  |  |
| UI-SHUT-03 | S·H | Long timed exposure |  |  |
| UI-SHUT-04 | S·H | Bulb / Live Time / Live Composite |  |  |
| UI-SHUT-05 | S·H | Movie record |  |  |
| UI-SHUT-06 | S | Tap AF vs Tap shoots |  |  |
| UI-SHUT-07 | S | Last-shot button |  |  |
| UI-SHUT-08 | S | Keyboard (iPad/Mac) |  |  |
| UI-LV-01 | S·H | Runs and fits |  |  |
| UI-LV-02 | S | Size picker |  |  |
| UI-LV-03 | S | No frames arriving |  |  |
| UI-LV-04 | S | Restart live view |  |  |
| UI-LV-05 | S | Frame data |  |  |
| UI-LV-06 | S | Scene suggestion pill |  |  |
| UI-AID-01 | S | Grid |  |  |
| UI-AID-02 | S | Histogram |  |  |
| UI-AID-03 | S | Peaking |  |  |
| UI-AID-04 | S | Loupe |  |  |
| UI-AID-05 | S | Night mode |  |  |
| UI-AID-06 | S | Aids are still reachable when the row hides |  |  |

### Tools

| ID | Run | Check | Result | Note / evidence |
|---|---|---|---|---|
| UI-TOOLS-01 | S | Grid contents |  |  |
| UI-TOOLS-02 | S | Open and close |  |  |
| UI-TOOLS-03 | S | Running state on the button |  |  |
| PRESET-01 | S | List |  |  |
| PRESET-02 | S | Apply |  |  |
| PRESET-03 | S | Stays on |  |  |
| PRESET-04 | S | Turn off puts settings back |  |  |
| PRESET-05 | S | Switch presets |  |  |
| PRESET-06 | S | Skipped steps say what to do |  |  |
| PRESET-07 | S | Preset the camera half-refuses |  |  |
| PRESET-08 | S | Save current / My presets |  |  |
| PRESET-09 | S | Macro hands over to focus stack |  |  |
| PRESET-10 | S | Expose to the right |  |  |
| PRESET-11 | H | Do the presets give a good picture |  |  |
| ASTRO-01 | S | Sheet |  |  |
| ASTRO-02 | S | Shutter follows focal length |  |  |
| ASTRO-03 | S | Apply and turn off |  |  |
| ASTRO-04 | S | Star trails with Live Composite |  |  |
| ASTRO-05 | S | Star trails without Live Composite |  |  |
| ASTRO-06 | S | Series can be stopped |  |  |
| INT-01 | S | Sheet |  |  |
| INT-02 | S | Run 3 frames at 3 s |  |  |
| INT-03 | S | Stop mid-run |  |  |
| INT-04 | S | Interval shorter than the exposure |  |  |
| INT-05 | S | Refuses Live modes |  |  |
| INT-06 | S | Follow the light |  |  |
| INT-07 | S | Survives the sheet closing and pocket mode |  |  |
| INT-08 | H | An hour on a real camera |  |  |
| BRK-01 | S | Sheet |  |  |
| BRK-02 | S | Run 3 frames |  |  |
| BRK-03 | S | Cancel |  |  |
| BRK-04 | S | Range ends |  |  |
| BRK-05 | S | Mode dial unknown |  |  |
| FSTK-01 | S | Focus stack where the camera can |  |  |
| FSTK-02 | S | Focus stack where it can't |  |  |
| FSTK-03 | H | Real stack |  |  |
| ND-01 | S | Meter |  |  |
| ND-02 | S | Pick a strength |  |  |
| ND-03 | S | Set up, short |  |  |
| ND-04 | S | Set up, longer than the camera's speeds |  |  |
| MOT-01 | S | Arm |  |  |
| MOT-02 | S | Sensitivity and wait |  |  |
| MOT-03 | S | Disarm and refusals |  |  |
| HIRES-01 | S | Helper on a High Res body |  |  |
| HIRES-02 | S | Hidden elsewhere |  |  |
| HIRES-03 | H | Real High Res shot |  |  |
| MISC-01 | S | Pocket mode |  |  |
| MISC-02 | S | Geotag |  |  |
| MISC-03 | S | Timed Bulb |  |  |

### Card browser and auto-save

| ID | Run | Check | Result | Note / evidence |
|---|---|---|---|---|
| GAL-01 | S | Open |  |  |
| GAL-02 | S | Empty and failed states |  |  |
| GAL-03 | S | Folders |  |  |
| GAL-04 | S | View a photo |  |  |
| GAL-05 | S | Save a JPEG |  |  |
| GAL-06 | S | Star |  |  |
| GAL-07 | S | Download RAWs of starred |  |  |
| GAL-08 | S | RAW badge |  |  |
| GAL-09 | S | Cancel a big download |  |  |
| GAL-10 | S | Locked during an exposure |  |  |
| GAL-11 | S | No card browser on this body |  |  |
| GAL-12 | H | Real card, hundreds of files |  |  |
| ASAVE-01 | S | Turn on |  |  |
| ASAVE-02 | S | Access refused |  |  |
| ASAVE-03 | S | Sequences aren't saved one by one |  |  |
| ASAVE-04 | S | LUMIX saves later |  |  |
| ASAVE-05 | S | What gets saved |  |  |
| ASAVE-06 | S | Doesn't slow the shutter |  |  |

### ⋯ menu, settings, log

| ID | Run | Check | Result | Note / evidence |
|---|---|---|---|---|
| MENU-01 | S | Contents |  |  |
| MENU-02 | S | Sync camera clock |  |  |
| MENU-03 | S | Disconnect |  |  |
| MENU-04 | S | Turn camera off |  |  |
| MENU-05 | S | Pro status line |  |  |
| SET-01 | S | All camera settings |  |  |
| SET-02 | S | Change one |  |  |
| SET-03 | S | Locked row |  |  |
| SET-04 | S | What deserves promoting |  |  |
| LOG-01 | S | Request log |  |  |
| LOG-02 | S | Copy and Clear |  |  |
| LOG-03 | S | Support level is honest |  |  |

### Pro

| ID | Run | Check | Result | Note / evidence |
|---|---|---|---|---|
| PRO-01 | S | Which tools are locked |  |  |
| PRO-02 | S | A locked tool opens the Pro screen |  |  |
| PRO-03 | S | Pro screen content |  |  |
| PRO-04 | S | Free things stay free |  |  |
| PRO-05 | S | Scene suggestions under lock |  |  |
| PRO-06 | S | Other routes to locked features |  |  |
| PRO-07 | S | Prices don't load |  |  |
| PRO-08 | S | Locked state is discoverable but not nagging |  |  |
| PRO-09 | S | Trial state |  |  |
| PRO-10 | S | Unlocked state |  |  |
| PRO-11 | H | Real trial and purchase |  |  |
| PRO-12 | H | Trial ends mid-use |  |  |
| PRO-13 | H | Offline |  |  |
| PRO-14 | H | Early users keep Pro |  |  |
| PRO-15 | H | Watch without Pro |  |  |

### Watch, iPad, Mac

| ID | Run | Check | Result | Note / evidence |
|---|---|---|---|---|
| WATCH-01 | H | Not connected |  |  |
| WATCH-02 | H | Live view and status |  |  |
| WATCH-03 | H | Shutter |  |  |
| WATCH-04 | H | Self-timer |  |  |
| WATCH-05 | H | Digital Crown |  |  |
| WATCH-06 | H | iPhone app goes to the background |  |  |
| PAD-01 | S | Workspace, landscape |  |  |
| PAD-02 | S | Workspace, portrait and split view |  |  |
| PAD-03 | S | Tools as side panels |  |  |
| PAD-04 | S | Card browser |  |  |
| PAD-05 | S | Keyboard |  |  |
| MAC-01 | H | Window |  |  |
| MAC-02 | H | Menus |  |  |
| MAC-03 | H | Mac wording |  |  |
| MAC-04 | H | Saving |  |  |
| MAC-05 | H | Stays awake |  |  |

### UX sweep

| ID | Run | Check | Result | Note / evidence |
|---|---|---|---|---|
| UX-01 | S | Dead ends |  |  |
| UX-02 | S | Shown but not usable |  |  |
| UX-03 | S | "Not offered" without a next step |  |  |
| UX-04 | S | Missing feedback |  |  |
| UX-05 | S | Labels |  |  |
| UX-06 | S | Buried controls |  |  |
| UX-07 | S | State you can't see |  |  |
| UX-08 | S | Undo and recovery |  |  |
| UX-09 | S | Consistency |  |  |
| UX-10 | S | Accessibility |  |  |
| UX-11 | S | First five minutes |  |  |
| UX-12 | S | Honesty about experimental support |  |  |

### Storage and resources

| ID | Run | Check | Result | Note / evidence |
|---|---|---|---|---|
| RES-01 | S | Live view, 10 minutes idle |  |  |
| RES-02 | S | Live view with every aid on |  |  |
| RES-03 | S | Live view size changes |  |  |
| RES-04 | S | Shooting loop |  |  |
| RES-05 | S | Card browser |  |  |
| RES-06 | S | JPEG downloads |  |  |
| RES-07 | S | RAW downloads |  |  |
| RES-08 | S | Disk use |  |  |
| RES-09 | S | LUMIX menu cache |  |  |
| RES-10 | S | Request log cap |  |  |
| RES-11 | S | Auto-save over a long session |  |  |
| RES-12 | S | Reconnect loop |  |  |
| RES-13 | S | CPU at idle |  |  |
| RES-14 | H | Battery and heat, one hour |  |  |
| RES-15 | H | Battery and heat, pocket mode |  |  |
| RES-16 | H | Memory on the device |  |  |
| RES-17 | H | Low storage |  |  |

### Value and pricing

| ID | Run | Check | Result | Note / evidence |
|---|---|---|---|---|
| VAL-01 | S | Pro scorecard for this model |  |  |
| VAL-02 | S | Does the Pro screen promise only what this model gets |  |  |
| VAL-03 | S | "Guide" features behind the paywall |  |  |
| VAL-04 | S | What breaks or is missing in Pro |  |  |
| VAL-05 | S | Free tier is complete |  |  |
| VAL-06 | S | The trial shows the value |  |  |
| VAL-07 | S | Which single feature sells it for this model |  |  |
| VAL-08 | S | Beta brands |  |  |
| VAL-09 | H | One real outing |  |  |
| VAL-10 | S | Verdict |  |  |

### Real camera only

| ID | Run | Check | Result | Note / evidence |
|---|---|---|---|---|
| HW-01 | H | Join and connect by hand |  |  |
| HW-02 | H | Join from the app |  |  |
| HW-03 | H | Every strip setting takes effect on the camera |  |  |
| HW-04 | H | What the body refuses |  |  |
| HW-05 | H | Physical dials |  |  |
| HW-06 | H | Live view quality and lag |  |  |
| HW-07 | H | Shutter, burst, Bulb, Live modes, video |  |  |
| HW-08 | H | Auto-save size |  |  |
| HW-09 | H | Card: real JPEG and RAW |  |  |
| HW-10 | H | Range and dropouts |  |  |
| HW-11 | H | Camera sleeps or its battery dies |  |  |
| HW-12 | H | Phone locks |  |  |
| HW-13 | H | Maker's app open at the same time |  |  |
| HW-14 | H | Model-specific notes are true |  |  |
| HW-15 | H | Nothing changed on the camera afterwards |  |  |
