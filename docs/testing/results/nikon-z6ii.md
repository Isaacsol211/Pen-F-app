# Results: Nikon Z 6II (mock)

Plan: [`../TEST-PLAN.md`](../TEST-PLAN.md). Result key: `P` pass · `F` fail · `UX` works, UX failure · `N/A` · `—` not run.

| | |
|---|---|
| Sheet | `nikon-z6ii` |
| Stands for | Nikon Z bodies (mirrorless, video): Z 5, Z 6, Z 6II, Z 6III ★, Z 7/Z 7II, Z 8 ★, Z 9 ★, Zf ★, Z 50, Z fc, Z 30 |
| Flagship | no |
| Run type | Full self-test + by-hand UI pass (Pro locked) |
| Date | 2026-11-25 |
| Tester | Claude (Sonnet 5.5) |
| Build | test/plan worktree on main 5da84a8 (app code unchanged), Debug 1.1 (5), iPhone 17 simulator |
| Camera | Mock: `python3 -I -u mock_nikon.py  (scratch copy reporting any name via MOCKMODEL)` |
| Self-test | `nikon-z6ii`: failures=0 |

## Checks

| ID | Result | Note |
|---|---|---|
| ST-01 | P | SELFTEST PASS connect brand=nikon name=Z 6 II error=- |
| ST-02 | UX | SELFTEST INFO profile=none support=- crop=1.0 note=- No model profile exists for this brand: nothing shows the user "Beta / mock only" per body. |
| ST-03 | P | SELFTEST PASS live view fps=32 frame=640x480 |
| ST-04–ST-20 | P | full self-test failures=0 |
| UI-HOME-01 | UX | First launch is clear. Add a camera lists five brands with no Beta marker (nikon-z6ii/add-camera-brands-no-beta-mark.png) |
| UI-ADD-02 | P | Nikon steps are right ("Connect to smart device > Wi-Fi connection > Establish Wi-Fi connection") and a flask note says it is newer. add-camera-nikon-note.png |
| UI-ADD-04 | UX | Connect works only after typing 127.0.0.1:15740 in Advanced; the address hint names the mock ports (simulator only). |
| UI-REMOTE-01 | UX | 5 cells: F-STOP SHUTTER ISO EV WB. No Drive, Quality or shots-left count; top bar shows battery only. remote-portrait.png |
| PRO-01 | P | Presets, Astro, Interval, Bracket, ND, Motion locked; Pocket and switches free; Video appears as a switch tile. tools-pro-locked.png |
| PRO-03 | UX | Pro screen says "focus stacks on LUMIX, Nikon and Canon" but never says Nikon is beta; list is clipped as on Olympus. pro-screen-no-beta-mention.png |
| PRESET-06 | UX | Every preset shows `drivemode:skip` with no explanation of what the user should set on the camera (checked in the self-test lines; wording not read on screen) |

## Findings

| ID | Sev | Check | What happens | Suggested fix |
|---|---|---|---|---|
| nikon-z6ii-F1 | S3 | VAL-08 | Nothing before the Pro purchase says Nikon support is beta and mock-only. | Add a "Beta" tag next to Nikon/Canon/Sony in Add a camera and one line on the Pro screen ("Pro tools for Nikon have only been tested against a simulator"). |
| nikon-z6ii-F2 | S3 | UI-STRIP-01 | No Drive and no Quality cell, no shots-left in the top bar: a Nikon user can't pick burst/self-timer or RAW/JPEG from the phone and nothing says so. | Show "Drive/Quality: set on the camera" once, or add the Nikon PTP properties. |
| nikon-z6ii-F3 | S3 | PRESET-06 | Preset steps for drive are skipped with no camera-side instruction on this brand. | Name the action ("set continuous shooting on the camera"). |
| nikon-z6ii-F4 | S4 | ST-02 | No model profile for Nikon: the camera shows no per-body notes (e.g. "turn off live view on the camera first"), and Z 5/Z 6 vs Z 8/Z 9 are not distinguished beyond the crop factor. | Add a Nikon table like Olympus/LUMIX. |

## Mockup record

Strip on the mock: F-STOP, SHUTTER, ISO, EV, WB (5 cells). Mode shown read-only (M). Video is a Tools switch. Missing vs the camera menus (not available in the mock): drive/release mode, picture control, AF-area, quality. Live screen should add DRIVE and a shots-left count; Z 8/Z 9 owners also expect subject-detection AF and pre-release capture.

Crop factor from the reported name: Z 6 II 1.0, Z 6 III 1.0, Z 8 1.0, Z 9 1.0, Z 5 1.0, Z f 1.0, Z 7 II 1.0, **Z 50 1.5, Z fc 1.5**, D850 1.0, D7200 1.5: all correct (probes in `nikon-*`).

## Value and pricing

**VAL-08 (is it clear before paying that this brand is beta / mock-only?): No.** The Connect screen shows a small flask line ("Newer in Shutterlink… please tell us") under the brand's steps, but the Add a camera list has no Beta tag, the Pro screen does not mention beta or mock-only status, and the Pro trial is offered before any connect. A user can buy Pro for a body that has only ever been tested against a mock. (`img/nikon-z6ii/add-camera-brands-no-beta-mark.png`, `pro-screen-no-beta-mention.png`)

**Pro on a Z 6II:** Presets Full (drive step skipped), Astro Full, Star trails via interval, Interval Full, Bracket Full, Focus stack Full (lens on AF; mock only), ND Part (no Bulb over PTP: shutter 'bulb' reported on the mock, unverified), Motion Full. **Verdict: a stretch until a real body connects**; for owners who have never seen the app run on a real Z camera, the risk is high.

## Self-test output

```text
# nikon-z6ii
SELFTEST PASS connect brand=nikon name=Z 6 II error=-
SELFTEST INFO profile=none support=- crop=1.0 note=-
SELFTEST PASS live view fps=32 frame=640x480
SELFTEST PASS settings read expcomp=0.0[31] focalvalue=4.0[20] isospeedvalue=400[25] shutspeedvalue=125[57] takemode=M(ro)[1] wbvalue=0[9]
SELFTEST PASS set expcomp 0.0 → -5.0, now -5.0
SELFTEST PASS set focalvalue 4.0 → 1.8, now 1.8
SELFTEST PASS set shutspeedvalue 125 → 30", now 30"
SELFTEST PASS set isospeedvalue 400 → 100, now 100
SELFTEST PASS set wbvalue 0 → 18, now 18
SELFTEST PASS tap focus afState=1
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
SELFTEST PASS motion trigger shots=1 peak=0.0221 threshold=0.01
SELFTEST PASS ettr ev 0.0 → 0.0 Live view doesn't get brighter with the exposure, so the highlights can't be judged. Turn off Live View Boost (or exposure preview) on the camera and try again.
SELFTEST PASS battery 82%
SELFTEST PASS card list 65 files in ["100NZ6_2"]
SELFTEST PASS thumbnail _DSC1066.JPG
SELFTEST PASS preview 640x480
SELFTEST PASS download _DSC1066.JPG 25395 bytes
SELFTEST PASS download RAW _DSC1054.NEF 2500000 bytes
SELFTEST PASS live view after card fps=23
SELFTEST DONE failures=0
```
