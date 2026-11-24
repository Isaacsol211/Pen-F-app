# Results: Panasonic LUMIX GH5 II (mock)

Plan: [`../TEST-PLAN.md`](../TEST-PLAN.md). Result key: `P` pass · `F` fail · `UX` works, UX failure · `N/A` · `—` not run.

| | |
|---|---|
| Sheet | `panasonic-dc-gh5m2` |
| Stands for | GH5 II (password note) |
| Flagship | no |
| Run type | Probe |
| Date | 2026-11-25 |
| Tester | Claude (Sonnet 5.5) |
| Build | test/plan worktree on main 5da84a8 (app code unchanged), Debug 1.1 (5), iPhone 17 simulator |
| Camera | Mock: `python3 -I -u mock_lumix.py --model DC-GH5M2` |
| Self-test | `panasonic-DC-GH5M2`: failures=not reached (probe) |

## Checks

| ID | Result | Note |
|---|---|---|
| ST-01 | P | SELFTEST PASS connect brand=panasonic name=LUMIX GH5 II error=- |
| ST-02 | P | SELFTEST INFO profile=LUMIX GH5 II support=Researched, not yet tried on this camera crop=2.0 note=Since firmware 1.4 the camera's Wi-Fi always has a password, shown on the camera. |
| ST-03 | P | SELFTEST PASS live view fps=15 frame=640x480 |
| ST-04–ST-20 | — | probe only: stopped after connect, live view and the first settings |
| UI-ADD-08 | P | "Since firmware 1.4 the camera's Wi-Fi always has a password, shown on the camera." attached |

## Findings

None beyond those already recorded for the group's first sheet.

## Mockup record

Strip cells on the LUMIX mock (7): F-STOP, SHUT… (label truncated), ISO, EV, WB, DRIVE (icon only), QUALI… (truncated). On an iPhone 17 portrait the last two labels are cut with an ellipsis.

## Value and pricing

As GH5; **a stretch** for a video-first owner.

## Self-test output

```text
# panasonic-DC-GH5M2
SELFTEST PASS connect brand=panasonic name=LUMIX GH5 II error=-
SELFTEST INFO profile=LUMIX GH5 II support=Researched, not yet tried on this camera crop=2.0 note=Since firmware 1.4 the camera's Wi-Fi always has a password, shown on the camera.
SELFTEST PASS live view fps=15 frame=640x480
SELFTEST PASS settings read afmode=1area[7] aspectratio=4:3[4] colormode=standard[8] colortemp=[76] creativectrl=pop(ro)[5] drivemode=normal[16] expcomp=0.0[31] filter_setting=noeffect[5] flash=forcedflashoff[3] focalvalue=2.8[21] isospeedvalue=auto[27] lightmetering=multi[3] peaking=off[3] quality=fine[5] shutspeedvalue=125[59] takemode=M(ro)[1] videoformat=mp4[2] videoquality=mp4_30p_100mbps_4k[
SELFTEST PASS set expcomp 0.0 → -5.0, now -5.0
SELFTEST PASS set focalvalue 2.8 → 1.7, now 1.7
SELFTEST PASS set shutspeedvalue 125 → 60", now 60"
SELFTEST PASS set isospeedvalue auto → i_iso, now i_iso
SELFTEST PASS set wbvalue 0 → 18, now 18
SELFTEST PASS set drivemode normal → burst|sh, now burst|sh
SELFTEST PASS set colormode standard → vivid, now vivid
SELFTEST PASS set afmode 1area → facedetection, now facedetection
SELFTEST PASS set colortemp  → 2500, now 2500
SELFTEST PASS tap focus afState=0
```
