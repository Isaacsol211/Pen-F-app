# Results: Canon EOS R6 (mock)

Plan: [`../TEST-PLAN.md`](../TEST-PLAN.md). Result key: `P` pass · `F` fail · `UX` works, UX failure · `N/A` · `—` not run.

| | |
|---|---|
| Sheet | `canon-eos-r6` |
| Stands for | Canon CCAPI mirrorless: R, RP, R6, R6 II ★, R5 ★, R3 ★, R7, R8, R10, R50, 90D (flagged by name only) |
| Flagship | no |
| Run type | Full self-test + UI via self-test launch and saved card |
| Date | 2026-11-25 |
| Tester | Claude (Sonnet 5.5) |
| Build | test/plan worktree on main 5da84a8 (app code unchanged), Debug 1.1 (5), iPhone 17 simulator |
| Camera | Mock: `python3 -I -u mock_canon.py  (scratch copy reporting any name via MOCKMODEL)` |
| Self-test | `canon-r6`: failures=0 |

## Checks

| ID | Result | Note |
|---|---|---|
| ST-01 | P | SELFTEST PASS connect brand=canon name=EOS R6 error=- |
| ST-02 | UX | SELFTEST INFO profile=none support=- crop=1.0 note=- No model profile exists for this brand: nothing shows the user "Beta / mock only" per body. |
| ST-03 | P | SELFTEST PASS live view fps=22 frame=640x480 |
| ST-04–ST-20 | P | full self-test failures=0 |
| UI-ADD-02 | P | Canon steps start with "Unlock CCAPI once" (one-time developer-account tool) and a flask note. add-camera-canon-note.png |
| UI-ADD-04 | F | Adding Canon after Nikon: the Advanced address still held `127.0.0.1:15740` (the Nikon mock). Connect then failed with a 12-line error ("127.0.0.1:15740 refused…"). stale-address-after-brand-switch.png |
| UI-ADD-11 | UX | The error banner stayed pinned over the sheet, covered the brand list, Advanced and address field (stale-error-covers-brand-list.png), survived Cancel and reopen, and also sat on the home screen. The only way to continue was to launch the self-test path. |
| UI-REMOTE-01 | UX | 5 cells: F-STOP SHUTTER ISO EV WB; WB shows the raw code "awb_white" during the self-test (wb-raw-code-awb_white.png) and "Sunny" after a preset. No Drive/Quality; no shots-left. remote-portrait.png |

## Findings

| ID | Sev | Check | What happens | Suggested fix |
|---|---|---|---|---|
| canon-eos-r6-F1 | S2 | UI-ADD-04 | Switching brand in Add a camera keeps the previous brand's typed address, so a Canon connect goes to the Nikon port and fails with a long network error. | Reset the address when the brand changes (or show it prominently). |
| canon-eos-r6-F2 | S3 | UI-ADD-11 | A failed connect leaves a 12-line banner on the Add a camera sheet that covers the form, reappears after Cancel and on the home screen, and has no dismiss button. | Dismiss on Cancel/brand change; show two lines with a "Details" link. |
| canon-eos-r6-F3 | S3 | UI-STRIP-07 | WB shows the raw CCAPI code "awb_white" instead of a name. | Map Canon WB codes to the app's names. |
| canon-eos-r6-F4 | S3 | VAL-08 | CCAPI needs a developer account and a USB activation, and the app is mock-only for Canon: nothing before Pro says either. | Show a "Needs CCAPI activation / beta" line in the Pro screen for Canon. |

## Mockup record

Strip: F-STOP, SHUTTER, ISO, EV, WB (5). Canon's CCAPI supports drive mode, image quality, AF mode and metering in the real API, none of which the app uses. Live screen should add DRIVE and QUALITY (RAW/JPEG) as for LUMIX.

Crop-factor probes: R6 1.0, R6 Mark II 1.0, R5 1.0, R3 1.0, R8 1.0, RP 1.0, R1 1.0, **R7 1.6, R10 1.6, R50 1.6, 90D 1.6** correct; **"EOS R6m2" and "EOS R5m2" (the short names Canon may report) fall to 1.6 (APS-C), so a full-frame R6 II/R5 II would get a star-trail shutter 60% too long**.

## Value and pricing

**VAL-08 (is it clear before paying that this brand is beta / mock-only?): No.** The Connect screen shows a small flask line ("Newer in Shutterlink… please tell us") under the brand's steps, but the Add a camera list has no Beta tag, the Pro screen does not mention beta or mock-only status, and the Pro trial is offered before any connect. A user can buy Pro for a body that has only ever been tested against a mock. (`img/nikon-z6ii/add-camera-brands-no-beta-mark.png`, `pro-screen-no-beta-mention.png`)

**Pro on an R6:** Full for Presets (drive skipped), Astro, Interval, Bracket, Focus stack (mock), ND, Motion; Bulb on the mock. **Verdict: a stretch** until a real CCAPI body is proven.

## Self-test output

```text
# canon-r6
SELFTEST PASS connect brand=canon name=EOS R6 error=-
SELFTEST INFO profile=none support=- crop=1.0 note=-
SELFTEST PASS live view fps=22 frame=640x480
SELFTEST PASS settings read expcomp=0.0[19] focalvalue=4.0[23] isospeedvalue=auto[26] shutspeedvalue=125[56] takemode=M(ro)[1] wbvalue=0[10]
SELFTEST PASS set expcomp 0.0 → -3.0, now -3.0
SELFTEST PASS set focalvalue 4.0 → 1.8, now 1.8
SELFTEST PASS set shutspeedvalue 125 → 30", now 30"
SELFTEST PASS set isospeedvalue auto → 100, now 100
SELFTEST PASS set wbvalue 0 → awb_white, now awb_white
SELFTEST PASS tap focus afState=0
SELFTEST PASS shoot
SELFTEST PASS last-shot review
SELFTEST PASS movie
SELFTEST PASS interval shots=2
SELFTEST PASS bracket shots=3
SELFTEST PASS focus stack shots=3
SELFTEST PASS sky positions sun 62.0° (≈62), full 1.00, new 0.00
SELFTEST PASS scene rules night=astro moon=moon water=water-nd bird=bird clipping=["clipping"]
SELFTEST PASS scene analysis  suggestion=-
SELFTEST PASS preset astro takemode=M focalvalue=F1.8 shutspeedvalue=15" isospeedvalue=1600 wbvalue=Fluorescent drivemode:skip
SELFTEST PASS preset moon takemode=M focalvalue=F8.0 shutspeedvalue=1/250 isospeedvalue=200 wbvalue=Sunny drivemode:skip
SELFTEST PASS preset fireworks takemode=M focalvalue=F8.0 shutspeedvalue=4" isospeedvalue=100 wbvalue=Sunny drivemode:skip
SELFTEST PASS preset landscape takemode:skip focalvalue=F8.0 isospeedvalue=100 expcomp=±0.0 drivemode:skip
SELFTEST PASS preset action takemode:skip shutspeedvalue=1/1000 isospeedvalue=Auto expcomp=±0.0 drivemode:skip
SELFTEST PASS preset macro takemode:skip focalvalue=F8.0 isospeedvalue=100 expcomp=±0.0 drivemode:skip
SELFTEST PASS preset trails takemode=M focalvalue=F11 shutspeedvalue=15" isospeedvalue=100 drivemode:skip
SELFTEST PASS saved preset 5 values: focalvalue=F11 shutspeedvalue=15" isospeedvalue=100 expcomp=±0.0 wbvalue=Sunny
SELFTEST PASS nd setup metered 15.0s → 960.0s, shutter now bulb
SELFTEST PASS motion trigger shots=1 peak=0.0260 threshold=0.01
SELFTEST PASS ettr ev 0.0 → 0.0 Live view doesn't get brighter with the exposure, so the highlights can't be judged. Turn off Live View Boost (or exposure preview) on the camera and try again.
SELFTEST PASS battery 75%
SELFTEST PASS card list 179 files in ["100CANON"]
SELFTEST PASS thumbnail IMG_2151.JPG
SELFTEST PASS preview 640x480
SELFTEST PASS download IMG_2151.JPG 25189 bytes
SELFTEST PASS download RAW IMG_2136.CR3 3000000 bytes
SELFTEST PASS live view after card fps=37
SELFTEST DONE failures=0
```
