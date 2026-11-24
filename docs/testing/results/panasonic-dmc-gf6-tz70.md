# Results: Panasonic LUMIX GF6 / LF1 / TZ70 (mock)

Plan: [`../TEST-PLAN.md`](../TEST-PLAN.md). Result key: `P` pass · `F` fail · `UX` works, UX failure · `N/A` · `—` not run.

| | |
|---|---|
| Sheet | `panasonic-dmc-gf6-tz70` |
| Stands for | noISO bodies: GF6, LF1, TZ70/ZS50 |
| Flagship | no |
| Run type | Probes (GF6, TZ70) |
| Date | 2026-11-25 |
| Tester | Claude (Sonnet 5.5) |
| Build | test/plan worktree on main 5da84a8 (app code unchanged), Debug 1.1 (5), iPhone 17 simulator |
| Camera | Mock: `python3 -I -u mock_lumix.py --model DMC-GF6 / DMC-TZ70` |
| Self-test | `panasonic-DMC-GF6`: failures=not reached (probe); `panasonic-DMC-TZ70`: failures=not reached (probe) |

## Checks

| ID | Result | Note |
|---|---|---|
| ST-01 | P | SELFTEST PASS connect brand=panasonic name=LUMIX GF6 error=- |
| ST-02 | P | SELFTEST INFO profile=LUMIX GF6 support=Researched, not yet tried on this camera crop=2.0 note=- |
| ST-03 | P | SELFTEST PASS live view fps=15 frame=640x480 |
| ST-04–ST-20 | — | probe only: stopped after connect, live view and the first settings |
| Flag noISO | P | `isospeedvalue=auto(ro)`; no `set isospeedvalue` line on GF6 or TZ70 |
| TZ70 | P | SELFTEST INFO profile=LUMIX TZ70 / ZS50 support=Researched, not yet tried on this camera crop=2.0 note=- |

## Findings

| ID | Sev | Check | What happens | Suggested fix |
|---|---|---|---|---|
| panasonic-dmc-gf6-tz70-F1 | S3 | PRESET-06 | With ISO read-only the Astro/Moon/Landscape ISO steps cannot apply; the message must say "set ISO on the camera" (not seen on screen). | Check PRESET-06 text for noISO bodies. |

## Mockup record

Strip cells on the LUMIX mock (7): F-STOP, SHUT… (label truncated), ISO, EV, WB, DRIVE (icon only), QUALI… (truncated). On an iPhone 17 portrait the last two labels are cut with an ellipsis.

ISO cell read-only (auto).

## Value and pricing

Astro without ISO control is half a preset: **a stretch** for a GF6/TZ70 owner.

## Self-test output

```text
# panasonic-DMC-GF6
SELFTEST PASS connect brand=panasonic name=LUMIX GF6 error=-
SELFTEST INFO profile=LUMIX GF6 support=Researched, not yet tried on this camera crop=2.0 note=-
SELFTEST PASS live view fps=15 frame=640x480
SELFTEST PASS settings read afmode=1area[7] aspectratio=4:3[4] colormode=standard[8] colortemp=[76] creativectrl=pop(ro)[5] drivemode=normal[16] expcomp=0.0[31] filter_setting=noeffect[5] flash=forcedflashoff[3] focalvalue=2.8[21] isospeedvalue=auto(ro)[27] lightmetering=multi[3] peaking=off[3] quality=fine[5] shutspeedvalue=125[59] takemode=M(ro)[1] videoformat=mp4[2] videoquality=mp4_30p_100mbps
SELFTEST PASS set expcomp 0.0 → -5.0, now -5.0
SELFTEST PASS set focalvalue 2.8 → 1.7, now 1.7
SELFTEST PASS set shutspeedvalue 125 → 60", now 60"
SELFTEST PASS set wbvalue 0 → 18, now 18
SELFTEST PASS set drivemode normal → burst|sh, now burst|sh
SELFTEST PASS set colormode standard → vivid, now vivid
SELFTEST PASS set afmode 1area → facedetection, now facedetection
SELFTEST PASS set colortemp  → 2500, now 2500
SELFTEST PASS tap focus afState=0
# panasonic-DMC-TZ70
SELFTEST PASS connect brand=panasonic name=LUMIX TZ70 / ZS50 error=-
SELFTEST INFO profile=LUMIX TZ70 / ZS50 support=Researched, not yet tried on this camera crop=2.0 note=-
SELFTEST PASS live view fps=15 frame=640x480
SELFTEST PASS settings read afmode=1area[7] aspectratio=4:3[4] colormode=standard[8] colortemp=[76] creativectrl=pop(ro)[5] drivemode=normal[16] expcomp=0.0[31] filter_setting=noeffect[5] flash=forcedflashoff[3] focalvalue=2.8[21] isospeedvalue=auto(ro)[27] lightmetering=multi[3] peaking=off[3] quality=fine[5] shutspeedvalue=125[59] takemode=M(ro)[1] videoformat=mp4[2] videoquality=mp4_30p_100mbps
SELFTEST PASS set expcomp 0.0 → -5.0, now -5.0
SELFTEST PASS set focalvalue 2.8 → 1.7, now 1.7
SELFTEST PASS set shutspeedvalue 125 → 60", now 60"
SELFTEST PASS set wbvalue 0 → 18, now 18
SELFTEST PASS set drivemode normal → burst|sh, now burst|sh
SELFTEST PASS set colormode standard → vivid, now vivid
SELFTEST PASS set afmode 1area → facedetection, now facedetection
SELFTEST PASS set colortemp  → 2500, now 2500
SELFTEST PASS tap focus afState=0
```
