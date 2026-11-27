# Results: Panasonic LUMIX S5 (mock)

Plan: [`../TEST-PLAN.md`](../TEST-PLAN.md). Result key: `P` pass · `F` fail · `UX` works, UX failure · `N/A` · `—` not run.

| | |
|---|---|
| Sheet | `panasonic-dc-s5` |
| Stands for | S5 (2020, 16:9 live view note); S1/S1R/S1H plain |
| Flagship | no |
| Run type | Probe (S5, S1) |
| Date | 2026-11-25 |
| Tester | Claude (Sonnet 5.5) |
| Build | test/plan worktree on main 5da84a8 (app code unchanged), Debug 1.1 (5), iPhone 17 simulator |
| Camera | Mock: `python3 -I -u mock_lumix.py --model DC-S5 (and DC-S1)` |
| Self-test | `panasonic-DC-S5`: failures=not reached (probe); `panasonic-DC-S1`: failures=not reached (probe) |

## Checks

| ID | Result | Note |
|---|---|---|
| ST-01 | P | SELFTEST PASS connect brand=panasonic name=LUMIX S5 error=- |
| ST-02 | P | SELFTEST INFO profile=LUMIX S5 support=Researched, not yet tried on this camera crop=2.0 note=The S5 sends 16:9 live view (640×360). |
| ST-03 | — | SELFTEST INFO profile=LUMIX S5 support=Researched, not yet tried on this camera crop=2.0 note=The S5 |
| ST-04–ST-20 | — | probe only: stopped after connect, live view and the first settings |
| S1 | P | SELFTEST INFO profile=LUMIX S1 / S1R / S1H support=Researched, not yet tried on this camera crop=2.0 note=- |
| 16:9 live view | — | mock sends 640x480, so the S5's 16:9 handling is not exercised |

## Findings

| ID | Sev | Check | What happens | Suggested fix |
|---|---|---|---|---|
| panasonic-dc-s5-F1 | S4 (test infra) | ST-03 | The mock sends 640x480 for every model; the S5 profile promises 16:9 (640x360), so aspect-ratio handling for S5/S5 II is untested. | Make the mock send 640x360 for S5-family models. |

## Mockup record

Strip cells on the LUMIX mock (7): F-STOP, SHUT… (label truncated), ISO, EV, WB, DRIVE (icon only), QUALI… (truncated). On an iPhone 17 portrait the last two labels are cut with an ellipsis.

## Value and pricing

S5 owner: full-frame hybrid; same value picture as S5 II without the pairing risk: **fair**.

## Self-test output

```text
# panasonic-DC-S5
SELFTEST PASS connect brand=panasonic name=LUMIX S5 error=-
SELFTEST INFO profile=LUMIX S5 support=Researched, not yet tried on this camera crop=2.0 note=The S5 sends 16:9 live view (640×360).
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
# panasonic-DC-S1
SELFTEST PASS connect brand=panasonic name=LUMIX S1 / S1R / S1H error=-
SELFTEST INFO profile=LUMIX S1 / S1R / S1H support=Researched, not yet tried on this camera crop=2.0 note=-
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
