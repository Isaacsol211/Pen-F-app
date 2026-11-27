# Results: Panasonic LUMIX TZ-series / FT7 compacts (mock)

Plan: [`../TEST-PLAN.md`](../TEST-PLAN.md). Result key: `P` pass · `F` fail · `UX` works, UX failure · `N/A` · `—` not run.

| | |
|---|---|
| Sheet | `panasonic-dmc-tz60-tz55-ft7` |
| Stands for | fixedExposure compacts: TZ60/ZS40, TZ55/ZS35 (also noVideo), SZ8/SZ10 (noVideo), FT7/TS7 (note) |
| Flagship | no |
| Run type | Probes (TZ60, TZ55, FT7) |
| Date | 2026-11-25 |
| Tester | Claude (Sonnet 5.5) |
| Build | test/plan worktree on main 5da84a8 (app code unchanged), Debug 1.1 (5), iPhone 17 simulator |
| Camera | Mock: `python3 -I -u mock_lumix.py --model DMC-TZ60 / DMC-TZ55 / DC-FT7` |
| Self-test | `panasonic-DMC-TZ60`: failures=not reached (probe); `panasonic-DMC-TZ55`: failures=not reached (probe); `panasonic-DC-FT7`: failures=not reached (probe) |

## Checks

| ID | Result | Note |
|---|---|---|
| ST-01 | P | SELFTEST PASS connect brand=panasonic name=LUMIX TZ60 / ZS40 error=- |
| ST-02 | P | SELFTEST INFO profile=LUMIX TZ60 / ZS40 support=Researched, not yet tried on this camera crop=2.0 note=- |
| ST-03 | P | SELFTEST PASS live view fps=15 frame=640x480 |
| ST-04–ST-20 | — | probe only: stopped after connect, live view and the first settings |
| TZ55 no video | F | The TZ55 probe reached `bracket` and failed: "The shutter speed is locked in M. Use S or M, or bracket EV instead." (self-contradictory wording and Auto does not fall back to EV on a fixed-exposure body) |
| FT7 note | P | "4K recording is off while the camera's Wi-Fi is on." attached |
| TZ60 movie | P | `PASS movie` on TZ60; TZ55 has no movie line (noVideo): correct |

## Findings

| ID | Sev | Check | What happens | Suggested fix |
|---|---|---|---|---|
| panasonic-dmc-tz60-tz55-ft7-F1 | S2 | BRK-05 | On a fixed-exposure body (TZ55) Bracket Auto picks the shutter in M and fails with "The shutter speed is locked in M. Use S or M…": the message contradicts itself, and Auto should fall back to EV bracketing when shutter is read-only. | Make Auto choose EV when the shutter is read-only; fix the wording ("locked on this camera"). |

## Mockup record

Strip cells on the LUMIX mock (7): F-STOP, SHUT… (label truncated), ISO, EV, WB, DRIVE (icon only), QUALI… (truncated). On an iPhone 17 portrait the last two labels are cut with an ellipsis.

On these compacts F-STOP and SHUTTER are read-only; the strip should shrink them and keep ISO, EV, WB, Quality. The TZ55/SZ8 have no video: confirm the Video switch tile is hidden (profile noVideo; capabilities.movie false).

## Value and pricing

Compact owner: Pro adds little (Interval and Motion still work). **Poor value / a stretch.**

## Self-test output

```text
# panasonic-DMC-TZ60
SELFTEST PASS connect brand=panasonic name=LUMIX TZ60 / ZS40 error=-
SELFTEST INFO profile=LUMIX TZ60 / ZS40 support=Researched, not yet tried on this camera crop=2.0 note=-
SELFTEST PASS live view fps=15 frame=640x480
SELFTEST PASS settings read afmode=1area[7] aspectratio=4:3[4] colormode=standard[8] colortemp=[76] creativectrl=pop(ro)[5] drivemode=normal[16] expcomp=0.0[31] filter_setting=noeffect[5] flash=forcedflashoff[3] focalvalue=2.8(ro)[21] isospeedvalue=auto[27] lightmetering=multi[3] peaking=off[3] quality=fine[5] shutspeedvalue=125(ro)[59] takemode=M(ro)[1] videoformat=mp4[2] videoquality=mp4_30p_100
SELFTEST PASS set expcomp 0.0 → -5.0, now -5.0
SELFTEST PASS set isospeedvalue auto → i_iso, now i_iso
SELFTEST PASS set wbvalue 0 → 18, now 18
SELFTEST PASS set drivemode normal → burst|sh, now burst|sh
SELFTEST PASS set colormode standard → vivid, now vivid
SELFTEST PASS set afmode 1area → facedetection, now facedetection
SELFTEST PASS set colortemp  → 2500, now 2500
SELFTEST PASS tap focus afState=0
SELFTEST PASS shoot
SELFTEST PASS movie
# panasonic-DMC-TZ55
SELFTEST PASS connect brand=panasonic name=LUMIX TZ55 / ZS35 error=-
SELFTEST INFO profile=LUMIX TZ55 / ZS35 support=Researched, not yet tried on this camera crop=2.0 note=-
SELFTEST PASS live view fps=16 frame=640x480
SELFTEST PASS settings read afmode=1area[7] aspectratio=4:3[4] colormode=standard[8] colortemp=[76] creativectrl=pop(ro)[5] drivemode=normal[16] expcomp=0.0[31] filter_setting=noeffect[5] flash=forcedflashoff[3] focalvalue=2.8(ro)[21] isospeedvalue=auto[27] lightmetering=multi[3] peaking=off[3] quality=fine[5] shutspeedvalue=125(ro)[59] takemode=M(ro)[1] videoformat=mp4[2] videoquality=mp4_30p_100
SELFTEST PASS set expcomp 0.0 → -5.0, now -5.0
SELFTEST PASS set isospeedvalue auto → i_iso, now i_iso
SELFTEST PASS set wbvalue 0 → 18, now 18
SELFTEST PASS set drivemode normal → burst|sh, now burst|sh
SELFTEST PASS set colormode standard → vivid, now vivid
SELFTEST PASS set afmode 1area → facedetection, now facedetection
SELFTEST PASS set colortemp  → 2500, now 2500
SELFTEST PASS tap focus afState=0
SELFTEST PASS shoot
SELFTEST PASS interval shots=2
SELFTEST FAIL bracket The shutter speed is locked in M. Use S or M, or bracket EV instead.
# panasonic-DC-FT7
SELFTEST PASS connect brand=panasonic name=LUMIX FT7 / TS7 error=-
SELFTEST INFO profile=LUMIX FT7 / TS7 support=Researched, not yet tried on this camera crop=2.0 note=4K recording is off while the camera's Wi-Fi is on.
SELFTEST PASS live view fps=15 frame=640x480
SELFTEST PASS settings read afmode=1area[7] aspectratio=4:3[4] colormode=standard[8] colortemp=[76] creativectrl=pop(ro)[5] drivemode=normal[16] expcomp=0.0[31] filter_setting=noeffect[5] flash=forcedflashoff[3] focalvalue=2.8(ro)[21] isospeedvalue=auto[27] lightmetering=multi[3] peaking=off[3] quality=fine[5] shutspeedvalue=125(ro)[59] takemode=M(ro)[1] videoformat=mp4[2] videoquality=mp4_30p_100
SELFTEST PASS set expcomp 0.0 → -5.0, now -5.0
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
