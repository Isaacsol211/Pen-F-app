# Results: Sony a6000 (mock, ILCE-6000)

Plan: [`../TEST-PLAN.md`](../TEST-PLAN.md). Result key: `P` pass · `F` fail · `UX` works, UX failure · `N/A` · `—` not run.

| | |
|---|---|
| Sheet | `sony-a6000` |
| Stands for | Sony Smart Remote bodies up to ~2019: a6000, a6300, a6400 (flagged by name only), a7 II/III, a7R II/III, a9, RX100 |
| Flagship | no |
| Run type | Full self-test + UI via self-test launch |
| Date | 2026-11-25 |
| Tester | Claude (Sonnet 5.5) |
| Build | test/plan worktree on main 5da84a8 (app code unchanged), Debug 1.1 (5), iPhone 17 simulator |
| Camera | Mock: `python3 -I -u mock_sony.py  (scratch copy reporting any name via MOCKMODEL)` |
| Self-test | `sony-a6000`: failures=1 |

## Checks

| ID | Result | Note |
|---|---|---|
| ST-01 | P | SELFTEST PASS connect brand=sony name=ILCE-6000 error=- |
| ST-02 | UX | SELFTEST INFO profile=none support=- crop=1.5 note=- No model profile exists for this brand: nothing shows the user "Beta / mock only" per body. |
| ST-03 | P | SELFTEST PASS live view fps=15 frame=640x480 |
| ST-04–ST-20 | F | full self-test failures=1 |
| PRESET-06 | F | Action preset FAILED: "The camera refused 1/1000. Is the camera's mode dial on S?" (the mock is in M and refuses the shutter step); `takemode:skip` |
| ST-11 | N/A | No focus drive for Sony (guide only) |

## Findings

| ID | Sev | Check | What happens | Suggested fix |
|---|---|---|---|---|
| sony-a6000-F1 | S2 | PRESET-06 | The Action preset fails on the Sony mock with "The camera refused 1/1000. Is the camera's mode dial on S?": the preset skipped the mode step (cannot set mode) then failed the shutter step. Same pattern as the LUMIX G7 drive failure: a camera-side step turns into a red FAILED. | Treat a refused step after a skipped prerequisite as "skipped: turn the mode dial to S" and report the preset as applied. |
| sony-a6000-F2 | S3 | VAL-08 | Sony support is limited to bodies up to ~2019, which the Add a camera line says, but nothing on the Pro screen or trial tells an a7 IV / a1 owner that the app won't connect. | Detect modern bodies and say so before offering Pro. |

## Mockup record

Strip: F-STOP, SHUTTER, ISO, EV, WB. Sony's Camera Remote API also offers drive mode, still quality, focus mode and exposure mode (`getAvailable…`); the app reads none.

Crop-factor probes: a6000 1.5, a6400 (ILCE-6400) 1.5, a6700 1.5, **ZV-E10 1.5 (APS-C: correct), ZV-E1 1.5 (full frame: WRONG)**, a7 III (ILCE-7M3) 1.0, a7 IV 1.0, a7R V 1.0, a1 1.0, a9 III 1.0, a7S III 1.0, a7C II 1.0, RX100 VII 2.7.

## Value and pricing

**VAL-08 (is it clear before paying that this brand is beta / mock-only?): No.** The Connect screen shows a small flask line ("Newer in Shutterlink… please tell us") under the brand's steps, but the Add a camera list has no Beta tag, the Pro screen does not mention beta or mock-only status, and the Pro trial is offered before any connect. A user can buy Pro for a body that has only ever been tested against a mock. (`img/nikon-z6ii/add-camera-brands-no-beta-mark.png`, `pro-screen-no-beta-mention.png`)

**Pro on an a6000:** Full for Interval, Bracket, ND (Bulb), Motion, most presets; Action preset fails; Focus stack Guide only. **Verdict: a stretch** (beta brand, older bodies).

## Self-test output

```text
# sony-a6000
SELFTEST PASS connect brand=sony name=ILCE-6000 error=-
SELFTEST INFO profile=none support=- crop=1.5 note=-
SELFTEST PASS live view fps=15 frame=640x480
SELFTEST PASS settings read expcomp=0.0[19] focalvalue=4.0[19] isospeedvalue=auto[25] shutspeedvalue=125[53] takemode=M(ro)[1] wbvalue=0[10]
SELFTEST PASS set expcomp 0.0 → -3.0, now -3.0
SELFTEST PASS set focalvalue 4.0 → 2.8, now 2.8
SELFTEST PASS set shutspeedvalue 125 → 30", now 30"
SELFTEST PASS set isospeedvalue auto → 100, now 100
SELFTEST PASS set wbvalue 0 → 18, now 18
SELFTEST PASS tap focus afState=1
SELFTEST PASS shoot
SELFTEST PASS last-shot review
SELFTEST PASS movie
SELFTEST PASS interval shots=2
SELFTEST PASS bracket shots=3
SELFTEST PASS sky positions sun 62.0° (≈62), full 1.00, new 0.00
SELFTEST PASS scene rules night=astro moon=moon water=water-nd bird=bird clipping=["clipping"]
SELFTEST PASS scene analysis  suggestion=-
SELFTEST PASS preset astro takemode=M focalvalue=F2.8 shutspeedvalue=10" isospeedvalue=1600 wbvalue=Fluorescent drivemode:skip
SELFTEST PASS preset moon takemode=M focalvalue=F8.0 shutspeedvalue=1/250 isospeedvalue=200 wbvalue=Sunny drivemode:skip
SELFTEST PASS preset fireworks takemode=M focalvalue=F8.0 shutspeedvalue=4" isospeedvalue=100 wbvalue=Sunny drivemode:skip
SELFTEST PASS preset landscape takemode:skip focalvalue=F8.0 isospeedvalue=100 expcomp=±0.0 drivemode:skip
SELFTEST FAIL preset action takemode:skip shutspeedvalue:FAILED(The camera refused 1/1000. Is the camera's mode dial on S?) isospeedvalue=Auto expcomp=±0.0 drivemode:skip
SELFTEST PASS preset macro takemode:skip focalvalue=F8.0 isospeedvalue=100 expcomp=±0.0 drivemode:skip
SELFTEST PASS preset trails takemode=M focalvalue=F11 shutspeedvalue=15" isospeedvalue=100 drivemode:skip
SELFTEST PASS saved preset 5 values: focalvalue=F11 shutspeedvalue=15" isospeedvalue=100 expcomp=±0.0 wbvalue=Sunny
SELFTEST PASS nd setup metered 15.0s → 960.0s, shutter now bulb
SELFTEST PASS motion trigger shots=1 peak=0.0221 threshold=0.01
SELFTEST PASS ettr ev 0.0 → 0.0 Live view doesn't get brighter with the exposure, so the highlights can't be judged. Turn off Live View Boost (or exposure preview) on the camera and try again.
SELFTEST PASS battery 75%
SELFTEST PASS card list 171 files in ["ILCE-6000"]
SELFTEST PASS thumbnail DSC01138.JPG
SELFTEST PASS preview 640x480
SELFTEST PASS download DSC01138.JPG 25705 bytes
SELFTEST PASS download RAW DSC01129.ARW 3000000 bytes
SELFTEST PASS live view after card fps=15
SELFTEST DONE failures=1
```
