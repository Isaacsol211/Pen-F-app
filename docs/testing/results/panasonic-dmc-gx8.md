# Results: Panasonic LUMIX GX8 (mock)

Plan: [`../TEST-PLAN.md`](../TEST-PLAN.md). Result key: `P` pass · `F` fail · `UX` works, UX failure · `N/A` · `—` not run.

| | |
|---|---|
| Sheet | `panasonic-dmc-gx8` |
| Stands for | noExposureComp bodies: GX8 (physical EV dial) |
| Flagship | no |
| Run type | Probe |
| Date | 2026-11-25 |
| Tester | Claude (Sonnet 5.5) |
| Build | test/plan worktree on main 5da84a8 (app code unchanged), Debug 1.1 (5), iPhone 17 simulator |
| Camera | Mock: `python3 -I -u mock_lumix.py --model DMC-GX8` |
| Self-test | `panasonic-DMC-GX8`: failures=not reached (probe) |

## Checks

| ID | Result | Note |
|---|---|---|
| ST-01 | P | SELFTEST PASS connect brand=panasonic name=LUMIX GX8 error=- |
| ST-02 | P | SELFTEST INFO profile=LUMIX GX8 support=Researched, not yet tried on this camera crop=2.0 note=The GX8's exposure compensation dial is physical, so EV can't be changed from the phone. |
| ST-03 | P | SELFTEST PASS live view fps=16 frame=640x480 |
| ST-04–ST-20 | — | probe only: stopped after connect, live view and the first settings |
| Flag noExposureComp | P | settings read shows `expcomp=0.0(ro)`; no `set expcomp` line |
| UI-ADD-08 | P | "The GX8's exposure compensation dial is physical..." attached |

## Findings

| ID | Sev | Check | What happens | Suggested fix |
|---|---|---|---|---|
| panasonic-dmc-gx8-F1 | S3 | UI-STRIP-10 | With EV read-only the strip still has an EV cell; tapping it must say "turn the EV dial", and Bracket "Auto" must use shutter in M (it does for the self-test) but EV bracketing in P/A/S is impossible: a GX8 owner sees Bracket offer EV with no explanation (not seen on screen). | Check BRK with a read-only EV body; hide EV as a bracket choice. |

## Mockup record

Strip cells on the LUMIX mock (7): F-STOP, SHUT… (label truncated), ISO, EV, WB, DRIVE (icon only), QUALI… (truncated). On an iPhone 17 portrait the last two labels are cut with an ellipsis.

EV cell is read-only: show the value with a dial icon and keep the cell narrow.

## Value and pricing

Fine for a GX8 owner; the missing EV control costs Expose to the right and Presets' EV step (both rely on EV): **Part**. Verdict: fair.

## Self-test output

```text
# panasonic-DMC-GX8
SELFTEST PASS connect brand=panasonic name=LUMIX GX8 error=-
SELFTEST INFO profile=LUMIX GX8 support=Researched, not yet tried on this camera crop=2.0 note=The GX8's exposure compensation dial is physical, so EV can't be changed from the phone.
SELFTEST PASS live view fps=16 frame=640x480
SELFTEST PASS settings read afmode=1area[7] aspectratio=4:3[4] colormode=standard[8] colortemp=[76] creativectrl=pop(ro)[5] drivemode=normal[16] expcomp=0.0(ro)[31] filter_setting=noeffect[5] flash=forcedflashoff[3] focalvalue=2.8[21] isospeedvalue=auto[27] lightmetering=multi[3] peaking=off[3] quality=fine[5] shutspeedvalue=125[59] takemode=M(ro)[1] videoformat=mp4[2] videoquality=mp4_30p_100mbps
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
