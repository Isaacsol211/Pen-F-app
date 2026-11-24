# Results: Panasonic LUMIX LX100 (mock)

Plan: [`../TEST-PLAN.md`](../TEST-PLAN.md). Result key: `P` pass · `F` fail · `UX` works, UX failure · `N/A` · `—` not run.

| | |
|---|---|
| Sheet | `panasonic-dmc-lx100` |
| Stands for | fixedExposure + noExposureComp bodies: LX100 (aperture ring, shutter dial, EV dial physical) |
| Flagship | no |
| Run type | Probe |
| Date | 2026-11-25 |
| Tester | Claude (Sonnet 5.5) |
| Build | test/plan worktree on main 5da84a8 (app code unchanged), Debug 1.1 (5), iPhone 17 simulator |
| Camera | Mock: `python3 -I -u mock_lumix.py --model DMC-LX100` |
| Self-test | `panasonic-DMC-LX100`: failures=not reached (probe) |

## Checks

| ID | Result | Note |
|---|---|---|
| ST-01 | P | SELFTEST PASS connect brand=panasonic name=LUMIX LX100 error=- |
| ST-02 | P | SELFTEST INFO profile=LUMIX LX100 support=Researched, not yet tried on this camera crop=2.0 note=The LX100's aperture ring, shutter dial and EV dial are physical, so they can't be changed from the phone. |
| ST-03 | P | SELFTEST PASS live view fps=15 frame=640x480 |
| ST-04–ST-20 | — | probe only: stopped after connect, live view and the first settings |
| Flags | P | settings read: `focalvalue(ro)`, `expcomp(ro)`; no set lines for aperture, shutter or EV; ISO, WB, drive set fine |
| UI-ADD-08 | P | note about physical dials attached |

## Findings

| ID | Sev | Check | What happens | Suggested fix |
|---|---|---|---|---|
| panasonic-dmc-lx100-F1 | S2 | VAL-01 | With aperture, shutter and EV all read-only, Presets (other than WB/ISO), Astro, ND, Bracket (EV or shutter) and Expose-to-the-right cannot change exposure. The Pro screen still sells them. | On fixed-exposure bodies show "Pro tools that need exposure control are limited on this camera" on the Pro screen, or offer a camera-side guide. |

## Mockup record

Strip cells on the LUMIX mock (7): F-STOP, SHUT… (label truncated), ISO, EV, WB, DRIVE (icon only), QUALI… (truncated). On an iPhone 17 portrait the last two labels are cut with an ellipsis.

Three of the strip cells are read-only: show them as small read-only chips and give the width to ISO, WB, Quality.

## Value and pricing

**Poor value on the LX100:** with aperture, shutter and EV unchangeable, at least 6 of 14 Pro rows become Guide or None. Interval and Motion trigger still work. Verdict: a stretch.

## Self-test output

```text
# panasonic-DMC-LX100
SELFTEST PASS connect brand=panasonic name=LUMIX LX100 error=-
SELFTEST INFO profile=LUMIX LX100 support=Researched, not yet tried on this camera crop=2.0 note=The LX100's aperture ring, shutter dial and EV dial are physical, so they can't be changed from the phone.
SELFTEST PASS live view fps=15 frame=640x480
SELFTEST PASS settings read afmode=1area[7] aspectratio=4:3[4] colormode=standard[8] colortemp=[76] creativectrl=pop(ro)[5] drivemode=normal[16] expcomp=0.0(ro)[31] filter_setting=noeffect[5] flash=forcedflashoff[3] focalvalue=2.8(ro)[21] isospeedvalue=auto[27] lightmetering=multi[3] peaking=off[3] quality=fine[5] shutspeedvalue=125(ro)[59] takemode=M(ro)[1] videoformat=mp4[2] videoquality=mp4_30p
SELFTEST PASS set isospeedvalue auto → i_iso, now i_iso
SELFTEST PASS set wbvalue 0 → 18, now 18
SELFTEST PASS set drivemode normal → burst|sh, now burst|sh
SELFTEST PASS set colormode standard → vivid, now vivid
SELFTEST PASS set afmode 1area → facedetection, now facedetection
SELFTEST PASS set colortemp  → 2500, now 2500
SELFTEST PASS tap focus afState=0
SELFTEST PASS shoot
SELFTEST PASS movie
```
