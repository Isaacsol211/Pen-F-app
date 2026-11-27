# Results: Nikon D750 (mock, --dslr)

Plan: [`../TEST-PLAN.md`](../TEST-PLAN.md). Result key: `P` pass · `F` fail · `UX` works, UX failure · `N/A` · `—` not run.

| | |
|---|---|
| Sheet | `nikon-d750` |
| Stands for | DSLRs with built-in Wi-Fi (no video in the app): D750, D850, D7200 and similar |
| Flagship | no |
| Run type | Full self-test + probes (D850, D7200) |
| Date | 2026-11-25 |
| Tester | Claude (Sonnet 5.5) |
| Build | test/plan worktree on main 5da84a8 (app code unchanged), Debug 1.1 (5), iPhone 17 simulator |
| Camera | Mock: `python3 -I -u mock_nikon.py --dslr` |
| Self-test | `nikon-d750`: failures=0; `nikon-D850`: failures=not reached (probe); `nikon-D7200`: failures=not reached (probe) |

## Checks

| ID | Result | Note |
|---|---|---|
| ST-01 | P | SELFTEST PASS connect brand=nikon name=D750 error=- |
| ST-02 | UX | SELFTEST INFO profile=none support=- crop=1.0 note=- No model profile exists for this brand: nothing shows the user "Beta / mock only" per body. |
| ST-03 | P | SELFTEST PASS live view fps=28 frame=640x480 |
| ST-04–ST-20 | P | full self-test failures=0 |
| Movie | P | No `movie` self-test line: movie correctly absent for a DSLR |
| D850 | P | SELFTEST INFO profile=none support=- crop=1.0 note=- |
| D7200 | P | SELFTEST INFO profile=none support=- crop=1.5 note=- |

## Findings

| ID | Sev | Check | What happens | Suggested fix |
|---|---|---|---|---|
| nikon-d750-F1 | S3 | VAL-08 | As Nikon Z: no beta signal before purchase. | As Nikon Z. |

## Mockup record

Strip as Nikon Z. DSLRs: no Video tile (check: capabilities.movie false), live view must be started on the camera (turn-off-live-view note appears only on the Nikon steps).

## Value and pricing

**VAL-08 (is it clear before paying that this brand is beta / mock-only?): No.** The Connect screen shows a small flask line ("Newer in Shutterlink… please tell us") under the brand's steps, but the Add a camera list has no Beta tag, the Pro screen does not mention beta or mock-only status, and the Pro trial is offered before any connect. A user can buy Pro for a body that has only ever been tested against a mock. (`img/nikon-z6ii/add-camera-brands-no-beta-mark.png`, `pro-screen-no-beta-mention.png`)

**D750/D850 owner:** a still-photography crowd; Pro's Astro and Interval suit them, but no Bulb. **Fair, with the same beta risk.**

## Self-test output

```text
# nikon-d750
SELFTEST PASS connect brand=nikon name=D750 error=-
SELFTEST INFO profile=none support=- crop=1.0 note=-
SELFTEST PASS live view fps=28 frame=640x480
SELFTEST PASS settings read expcomp=0.0[31] focalvalue=4.0[20] isospeedvalue=400[25] shutspeedvalue=125[54] takemode=M(ro)[1] wbvalue=0[9]
SELFTEST PASS set expcomp 0.0 → -5.0, now -5.0
SELFTEST PASS set focalvalue 4.0 → 1.8, now 1.8
SELFTEST PASS set shutspeedvalue 125 → 30", now 30"
SELFTEST PASS set isospeedvalue 400 → 100, now 100
SELFTEST PASS set wbvalue 0 → 18, now 18
SELFTEST PASS tap focus afState=1
SELFTEST PASS shoot
SELFTEST PASS last-shot review
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
SELFTEST PASS motion trigger shots=1 peak=0.0169 threshold=0.01
SELFTEST PASS ettr ev 0.0 → 0.0 Live view doesn't get brighter with the exposure, so the highlights can't be judged. Turn off Live View Boost (or exposure preview) on the camera and try again.
SELFTEST PASS battery 82%
SELFTEST PASS card list 64 files in ["100NCD750"]
SELFTEST PASS thumbnail DSC_1065.JPG
SELFTEST PASS preview 640x480
SELFTEST PASS download DSC_1065.JPG 24167 bytes
SELFTEST PASS download RAW DSC_1054.NEF 2500000 bytes
SELFTEST PASS live view after card fps=29
SELFTEST DONE failures=0
# nikon-D850
SELFTEST PASS connect brand=nikon name=D850 error=-
SELFTEST INFO profile=none support=- crop=1.0 note=-
SELFTEST PASS live view fps=30 frame=640x480
SELFTEST PASS settings read expcomp=0.0[31] focalvalue=4.0[20] isospeedvalue=400[25] shutspeedvalue=125[57] takemode=M(ro)[1] wbvalue=0[9]
SELFTEST PASS set expcomp 0.0 → -5.0, now -5.0
SELFTEST PASS set focalvalue 4.0 → 1.8, now 1.8
SELFTEST PASS set shutspeedvalue 125 → 30", now 30"
SELFTEST PASS set isospeedvalue 400 → 100, now 100
SELFTEST PASS set wbvalue 0 → 18, now 18
SELFTEST PASS tap focus afState=1
# nikon-D7200
SELFTEST PASS connect brand=nikon name=D7200 error=-
SELFTEST INFO profile=none support=- crop=1.5 note=-
SELFTEST PASS live view fps=31 frame=640x480
SELFTEST PASS settings read expcomp=0.0[31] focalvalue=4.0[20] isospeedvalue=400[25] shutspeedvalue=125[57] takemode=M(ro)[1] wbvalue=0[9]
SELFTEST PASS set expcomp 0.0 → -5.0, now -5.0
SELFTEST PASS set focalvalue 4.0 → 1.8, now 1.8
SELFTEST PASS set shutspeedvalue 125 → 30", now 30"
SELFTEST PASS set isospeedvalue 400 → 100, now 100
SELFTEST PASS set wbvalue 0 → 18, now 18
SELFTEST PASS tap focus afState=1
```
