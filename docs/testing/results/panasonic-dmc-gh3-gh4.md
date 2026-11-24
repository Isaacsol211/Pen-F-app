# Results: Panasonic LUMIX GH3 / GH4 (mock)

Plan: [`../TEST-PLAN.md`](../TEST-PLAN.md). Result key: `P` pass · `F` fail · `UX` works, UX failure · `N/A` · `—` not run.

| | |
|---|---|
| Sheet | `panasonic-dmc-gh3-gh4` |
| Stands for | Bodies with no pairing step: GH3, GH4 |
| Flagship | no |
| Run type | Probe |
| Date | 2026-11-25 |
| Tester | Claude (Sonnet 5.5) |
| Build | test/plan worktree on main 5da84a8 (app code unchanged), Debug 1.1 (5), iPhone 17 simulator |
| Camera | Mock: `python3 -I -u mock_lumix.py --model DMC-GH4 (and DMC-GH3)` |
| Self-test | `panasonic-DMC-GH3`: failures=not reached (probe); `panasonic-DMC-GH4`: failures=not reached (probe) |

## Checks

| ID | Result | Note |
|---|---|---|
| ST-01 | P | SELFTEST PASS connect brand=panasonic name=LUMIX GH3 error=- |
| ST-02 | P | SELFTEST INFO profile=LUMIX GH3 support=Researched, not yet tried on this camera crop=2.0 note=- |
| ST-03 | P | SELFTEST PASS live view fps=16 frame=640x480 |
| ST-04–ST-20 | — | probe only: stopped after connect, live view and the first settings |
| Pairing | P | mock log shows no `req_acc` call at all for either body (`pairing: .none`), as the profile promises |
| GH4 | P | SELFTEST INFO profile=LUMIX GH4 support=Researched, not yet tried on this camera crop=2.0 note=- |

## Findings

None beyond those already recorded for the group's first sheet.

## Mockup record

Strip cells on the LUMIX mock (7): F-STOP, SHUT… (label truncated), ISO, EV, WB, DRIVE (icon only), QUALI… (truncated). On an iPhone 17 portrait the last two labels are cut with an ellipsis.

## Value and pricing

Older flagship video bodies (2012/2014) with a free remote already better than Panasonic's old app; Pro's stills tools suit a GH4 astro shooter. **Fair**.

## Self-test output

```text
# panasonic-DMC-GH3
SELFTEST PASS connect brand=panasonic name=LUMIX GH3 error=-
SELFTEST INFO profile=LUMIX GH3 support=Researched, not yet tried on this camera crop=2.0 note=-
SELFTEST PASS live view fps=16 frame=640x480
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
# panasonic-DMC-GH4
SELFTEST PASS connect brand=panasonic name=LUMIX GH4 error=-
SELFTEST INFO profile=LUMIX GH4 support=Researched, not yet tried on this camera crop=2.0 note=-
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
