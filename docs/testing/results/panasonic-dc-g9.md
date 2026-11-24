# Results: Panasonic LUMIX G9 (mock)

Plan: [`../TEST-PLAN.md`](../TEST-PLAN.md). Result key: `P` pass · `F` fail · `UX` works, UX failure · `N/A` · `—` not run.

| | |
|---|---|
| Sheet | `panasonic-dc-g9` |
| Stands for | G9 (2017) — profile note: High Resolution Mode |
| Flagship | no |
| Run type | Full self-test |
| Date | 2026-11-25 |
| Tester | Claude (Sonnet 5.5) |
| Build | test/plan worktree on main 5da84a8 (app code unchanged), Debug 1.1 (5), iPhone 17 simulator |
| Camera | Mock: `python3 -I -u mock_lumix.py --model DC-G9` |
| Self-test | `panasonic-g9`: failures=0 |

## Checks

| ID | Result | Note |
|---|---|---|
| ST-01 | P | SELFTEST PASS connect brand=panasonic name=LUMIX G9 error=- |
| ST-02 | P | SELFTEST INFO profile=LUMIX G9 support=Researched, not yet tried on this camera crop=2.0 note=High Resolution Mode can't be started from Shutterlink; set it on the camera. |
| ST-03 | P | SELFTEST PASS live view fps=15 frame=640x480 |
| ST-04–ST-20 | P | full self-test failures=0 |
| UI-ADD-08 | P | Note present: "High Resolution Mode can't be started from Shutterlink; set it on the camera." Shown only after connecting. |

## Findings

| ID | Sev | Check | What happens | Suggested fix |
|---|---|---|---|---|
| panasonic-dc-g9-F1 | S3 | HIRES-01 | The G9's signature feature (High Resolution Mode) is not startable; the note says so only after connecting, and the Tools grid has no High Res tile for LUMIX, so a G9 owner has no place that explains it. | Add a LUMIX-flavoured High Res guide (like the Olympus one) behind Pro or free. |

## Mockup record

Strip cells on the LUMIX mock (7): F-STOP, SHUT… (label truncated), ISO, EV, WB, DRIVE (icon only), QUALI… (truncated). On an iPhone 17 portrait the last two labels are cut with an ellipsis.

## Value and pricing

G9 owner: wants remote High Resolution Mode (80 MP) and 20 fps bursts; the app offers burst via Drive but High Res is camera-side. **Fair, 4 Full / 4 Part**.

## Self-test output

```text
# panasonic-g9
SELFTEST PASS connect brand=panasonic name=LUMIX G9 error=-
SELFTEST INFO profile=LUMIX G9 support=Researched, not yet tried on this camera crop=2.0 note=High Resolution Mode can't be started from Shutterlink; set it on the camera.
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
SELFTEST PASS shoot
SELFTEST PASS movie
SELFTEST PASS interval shots=2
SELFTEST PASS bracket shots=3
SELFTEST PASS focus stack shots=3
SELFTEST PASS sky positions sun 62.0° (≈62), full 1.00, new 0.00
SELFTEST PASS scene rules night=astro moon=moon water=water-nd bird=bird clipping=["clipping"]
SELFTEST PASS scene analysis  suggestion=-
SELFTEST PASS preset astro takemode=M focalvalue=F1.7 shutspeedvalue=8" isospeedvalue=1600 wbvalue=Incandescent drivemode=Self-timer 2 s
SELFTEST PASS preset moon takemode=M focalvalue=F8.0 shutspeedvalue=1/250 isospeedvalue=200 wbvalue=Sunny drivemode=Self-timer 2 s
SELFTEST PASS preset fireworks takemode=M focalvalue=F8.0 shutspeedvalue=4" isospeedvalue=100 wbvalue=Sunny drivemode=Self-timer 2 s
SELFTEST PASS preset landscape takemode:skip focalvalue=F8.0 isospeedvalue=100 expcomp=±0.0 drivemode=Self-timer 2 s
SELFTEST PASS preset action takemode:skip shutspeedvalue=1/1000 isospeedvalue=Auto expcomp=±0.0 drivemode:skip
SELFTEST PASS preset macro takemode:skip focalvalue=F8.0 isospeedvalue=100 expcomp=±0.0 drivemode=Self-timer 2 s
SELFTEST PASS preset trails takemode=M focalvalue=F11 shutspeedvalue=15" isospeedvalue=100 drivemode=Self-timer 2 s
SELFTEST PASS saved preset 6 values: focalvalue=F11 shutspeedvalue=15" isospeedvalue=100 expcomp=±0.0 wbvalue=Sunny drivemode=Self-timer 2 s
SELFTEST PASS nd setup metered 15.0s → 960.0s, shutter now bulb
SELFTEST PASS motion trigger shots=1 peak=0.0234 threshold=0.01
SELFTEST PASS ettr ev 0.0 → 0.0 Live view doesn't get brighter with the exposure, so the highlights can't be judged. Turn off Live View Boost (or exposure preview) on the camera and try again.
SELFTEST PASS battery 100%
SELFTEST PASS card list 102 files in ["LUMIX G9"]
SELFTEST PASS thumbnail P0001060.JPG
SELFTEST PASS preview 640x480
SELFTEST PASS download P0001060.JPG 25246 bytes
SELFTEST PASS download RAW P0001060.RW2 4000000 bytes
SELFTEST PASS live view after card fps=15
SELFTEST DONE failures=0
```
