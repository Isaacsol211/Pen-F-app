# Results: Olympus OM-D E-M1X (mock)

Plan: [`../TEST-PLAN.md`](../TEST-PLAN.md). Result key: `P` pass · `F` fail · `UX` works, UX failure · `N/A` · `—` not run.

| | |
|---|---|
| Sheet | `olympus-e-m1x` |
| Stands for | E-M1X (flagship, 2019) and, by profile, E-M1 Mark III |
| Flagship | **yes** |
| Run type | Probe (connect, live view, first settings) + profile review; UI per group sheet |
| Date | 2026-11-25 |
| Tester | Claude (Sonnet 5.5) |
| Build | test/plan worktree on main 5da84a8 (app code unchanged), Debug 1.1 (5), iPhone 17 simulator |
| Camera | Mock: `python3 -I -u mock_penf.py --model E-M1X  (and E-M1MarkIII)` |
| Self-test | `olympus-E-M1X`: failures=not reached (probe); `olympus-E-M1MarkIII`: failures=not reached (probe) |

## Checks

| ID | Result | Note |
|---|---|---|
| ST-01 | P | SELFTEST PASS connect brand=olympus name=OM-D E-M1X error=- |
| ST-02 | P | SELFTEST INFO profile=OM-D E-M1X support=Researched, not yet tried on this camera crop=2.0 note=Olympus may restrict remote shooting from other apps on this body (other apps only offer downloads). If controls are refused, use OI.Share. |
| ST-03 | P | SELFTEST PASS live view fps=11 frame=640x480 |
| UI-ADD-08 | P | note text attached as listed |

## Findings

| ID | Sev | Check | What happens | Suggested fix |
|---|---|---|---|---|
| olympus-e-m1x-F1 | S3 | VAL-08 | The note says other apps may be limited to downloads on this body; if so, remote shooting is refused and Pro is useless. The app learns this only when a control is refused. | On the first refused setting show "This body restricts other apps: use OI.Share for control" once, with the Pro trial pinned to the connect step so the user can test before buying. |

## Mockup record

Strip cells (same on every Olympus mock): F-STOP, SHUTTER, ISO, EV, WB, DRIVE (see `olympus-pen-f.md` MODEL-06/07). No Quality cell: Olympus does not report picture quality over Wi-Fi.

**What this body can do over Wi-Fi that the app does not use (from the OPC command list on the PEN-F baseline; this body's own list is unknown):** Pro Capture, Live ND, Handheld High Res, Focus Stacking, Intelligent Subject Detection and a portrait grip with dual dials are camera-side. The app has no Wi-Fi way to start any of these. Unused OPC commands as in the PEN-F list.

**What its live screen should show:** Mode, aperture, shutter, ISO, EV, WB, drive on the strip; a read-only chip for High Res and Live Composite state; the High Res tile is kept (profile highResShot).

## Value and pricing

**E-M1X / E-M1 Mark III owner (pro body).** Expectation: reliable remote for wildlife and sports, High Res, Pro Capture, in-camera focus stacking. The profile note warns that Olympus may restrict other apps. If that happens the trial shows Pro is of no use on this body, which is why the trial must be easy to start before purchase (it is: 7 days, free). Overlap with in-camera features is the highest here. **Verdict: a stretch for a pro, fair for an enthusiast**: Motion trigger and Presets are the genuinely new things; what's missing is a remote half-press AF (`exec_shutter` is unused).

## Self-test output

```text
# olympus-E-M1X
SELFTEST PASS connect brand=olympus name=OM-D E-M1X error=-
SELFTEST INFO profile=OM-D E-M1X support=Researched, not yet tried on this camera crop=2.0 note=Olympus may restrict remote shooting from other apps on this body (other apps only offer downloads). If controls are refused, use OI.Share.
SELFTEST PASS live view fps=11 frame=640x480
SELFTEST PASS settings read artfilter=popart(ro)[14] colortone=natural[9] drivemode=normal[12] expcomp=0.0[31] focalvalue=5.6(ro)[23] isospeedvalue=Auto[24] shutspeedvalue=250(ro)[61] takemode=P[7] wbvalue=0[13]
SELFTEST PASS set expcomp 0.0 → -5.0, now -5.0
SELFTEST PASS set isospeedvalue Auto → Low, now Low
SELFTEST PASS set wbvalue 0 → 18, now 18
SELFTEST PASS tap focus afState=0
SELFTEST PASS shoot
SELFTEST PASS last-shot review
SELFTEST PASS movie
# olympus-E-M1MarkIII
SELFTEST PASS connect brand=olympus name=OM-D E-M1 Mark III error=-
SELFTEST INFO profile=OM-D E-M1 Mark III support=Researched, not yet tried on this camera crop=2.0 note=Olympus may restrict remote shooting from other apps on this body (other apps only offer downloads). If controls are refused, use OI.Share.
SELFTEST PASS live view fps=12 frame=640x480
SELFTEST PASS settings read artfilter=popart(ro)[14] colortone=natural[9] drivemode=normal[12] expcomp=0.0[31] focalvalue=5.6(ro)[23] isospeedvalue=Auto[24] shutspeedvalue=250(ro)[61] takemode=P[7] wbvalue=0[13]
SELFTEST PASS set expcomp 0.0 → -5.0, now -5.0
SELFTEST PASS set isospeedvalue Auto → Low, now Low
SELFTEST PASS set wbvalue 0 → 18, now 18
SELFTEST PASS tap focus afState=1
SELFTEST PASS shoot
SELFTEST PASS last-shot review
SELFTEST PASS movie
```
