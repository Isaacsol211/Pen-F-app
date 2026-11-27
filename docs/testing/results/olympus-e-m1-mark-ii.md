# Results: Olympus OM-D E-M1 Mark II (mock)

Plan: [`../TEST-PLAN.md`](../TEST-PLAN.md). Result key: `P` pass · `F` fail · `UX` works, UX failure · `N/A` · `—` not run.

| | |
|---|---|
| Sheet | `olympus-e-m1-mark-ii` |
| Stands for | High Res Shot bodies without a note: E-M5 Mark II, E-M5 Mark III, E-M1 Mark II, PEN-F (tested on hardware) |
| Flagship | no |
| Run type | Full self-test (+ probe of E-M5 Mark II) |
| Date | 2026-11-25 |
| Tester | Claude (Sonnet 5.5) |
| Build | test/plan worktree on main 5da84a8 (app code unchanged), Debug 1.1 (5), iPhone 17 simulator |
| Camera | Mock: `python3 -I -u mock_penf.py --model E-M1MarkII` |
| Self-test | `olympus-E-M1MarkII`: failures=not reached (probe); `olympus-E-M5MarkII`: failures=not reached (probe) |

## Checks

| ID | Result | Note |
|---|---|---|
| ST-01 | — |  |
| ST-02 | — |  |
| ST-03 | — |  |
| ST-04–ST-20 | — | probe only: stopped after connect, live view and the first settings |
| HIRES-01 | — | High Res tile expected (profile highResShot true); not looked at on screen |
| UI-ADD-08 | P | No note expected, and `note=-` in the INFO line |
| Probe E-M5 Mark II | P | SELFTEST INFO profile=OM-D E-M5 Mark II support=Researched, not yet tried on this camera crop=2.0 note=- |

## Findings

None beyond those already recorded for the group's first sheet.

## Mockup record

Strip cells (same on every Olympus mock): F-STOP, SHUTTER, ISO, EV, WB, DRIVE (see `olympus-pen-f.md` MODEL-06/07). No Quality cell: Olympus does not report picture quality over Wi-Fi.

Identical to the PEN-F sheet: same properties on the mock, High Res Shot helper available.

## Value and pricing

Same as PEN-F (`olympus-pen-f.md` Pro scorecard): 10 Full, 3 Part, 2 Guide. The E-M1 Mark II is a 2016 flagship, so its owners expect remote High Res Shot and Pro Capture: the app's High Res tool is a guide only (the camera must be set by hand), which is the one place this body's owner may feel short-changed.

## Self-test output

```text
# olympus-E-M1MarkII
# olympus-E-M5MarkII
SELFTEST PASS connect brand=olympus name=OM-D E-M5 Mark II error=-
SELFTEST INFO profile=OM-D E-M5 Mark II support=Researched, not yet tried on this camera crop=2.0 note=-
SELFTEST PASS live view fps=11 frame=640x480
SELFTEST PASS settings read artfilter=popart(ro)[14] colortone=natural[9] drivemode=normal[12] expcomp=0.0[31] focalvalue=5.6(ro)[23] isospeedvalue=Auto[24] shutspeedvalue=250(ro)[61] takemode=P[7] wbvalue=0[13]
SELFTEST PASS set expcomp 0.0 → -5.0, now -5.0
SELFTEST PASS set isospeedvalue Auto → Low, now Low
SELFTEST PASS set wbvalue 0 → 18, now 18
SELFTEST PASS tap focus afState=0
SELFTEST PASS shoot
SELFTEST PASS last-shot review
SELFTEST PASS movie
```
