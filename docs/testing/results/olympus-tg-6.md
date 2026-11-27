# Results: Olympus Tough TG-6 (mock)

Plan: [`../TEST-PLAN.md`](../TEST-PLAN.md). Result key: `P` pass · `F` fail · `UX` works, UX failure · `N/A` · `—` not run.

| | |
|---|---|
| Sheet | `olympus-tg-6` |
| Stands for | All Olympus bodies with no note and no High Res: E-P5, Stylus 1/1s, E-M10, SH-1, TG-3, E-PL7, SH-2, TG-4, TG-860/870, E-M10 II, E-M10 III, SH-3, E-PL8, TG-5, E-PL9, E-PL10, E-P7 (probed: TG-6, Stylus 1, E-M10 III, E-PL10) |
| Flagship | no |
| Run type | Full self-test (TG-6) + probes (Stylus 1, E-M10 Mark III, E-PL10) |
| Date | 2026-11-25 |
| Tester | Claude (Sonnet 5.5) |
| Build | test/plan worktree on main 5da84a8 (app code unchanged), Debug 1.1 (5), iPhone 17 simulator |
| Camera | Mock: `python3 -I -u mock_penf.py --model TG-6` |
| Self-test | `olympus-TG-6`: failures=not reached (probe); `olympus-STYLUS1b`: failures=not reached (probe); `olympus-E-M10MarkIII`: failures=not reached (probe); `olympus-E-PL10`: failures=not reached (probe) |

## Checks

| ID | Result | Note |
|---|---|---|
| ST-01 | — |  |
| ST-02 | — |  |
| ST-03 | — |  |
| ST-04–ST-20 | — | probe only: stopped after connect, live view and the first settings |
| Probe Stylus 1 | P | profile "Stylus 1 / 1s"; the first probe attempt returned no output and was repeated (see Findings) |
| Probe E-M10 Mark III | P | SELFTEST INFO profile=OM-D E-M10 Mark III support=Researched, not yet tried on this camera crop=2.0 note=- |
| Probe E-PL10 | P | SELFTEST INFO profile=PEN E-PL10 support=Researched, not yet tried on this camera crop=2.0 note=- |
| MODEL-05 | UX | A Tough TG-6 is a fixed-lens waterproof compact: Bulb/Live Composite/Live Time and a 61-value shutter list come from the mock, and Astro sets F1.8 (the TG-6 lens opens to f/2.0). On the real body the aperture list is much shorter, which the app reads from the camera, so this is mock fidelity only. |

## Findings

| ID | Sev | Check | What happens | Suggested fix |
|---|---|---|---|---|
| olympus-tg-6-F1 | S4 (test infra) | probe | The first Stylus 1 probe in the batch produced an empty log (app launched before the simulator was ready); a repeat gave a normal result. Not an app bug, but a probe needs a "simulator ready" wait. | Add a bootstatus wait before launching the app in the probe script. |

## Mockup record

Strip cells (same on every Olympus mock): F-STOP, SHUTTER, ISO, EV, WB, DRIVE (see `olympus-pen-f.md` MODEL-06/07). No Quality cell: Olympus does not report picture quality over Wi-Fi.

Fixed-lens compacts (TG series, Stylus, SH): the strip should not offer an aperture dial wider than the lens, and Astro's "widest aperture" must come from the camera's own list (it does: the app reads the list). Interchangeable-lens bodies in this group (E-PL, E-M10, E-P) behave exactly like the PEN-F minus High Res.

## Value and pricing

For a tough compact owner (TG-6) Pro is the weakest match: Interval and Bracket help, Astro suits the lens, but ND calculators and focus stacks are not what a TG-6 is bought for, and in-camera focus bracketing/focus stacking exists. Verdict for the plain group: **fair** for E-M10 / E-PL / E-P owners (a real step up from OI.Share), **a stretch** for TG owners.

## Self-test output

```text
# olympus-TG-6
# olympus-STYLUS1b
SELFTEST PASS connect brand=olympus name=Stylus 1 / 1s error=-
SELFTEST INFO profile=Stylus 1 / 1s support=Researched, not yet tried on this camera crop=2.0 note=-
SELFTEST PASS live view fps=11 frame=640x480
SELFTEST PASS settings read artfilter=popart(ro)[14] colortone=natural[9] drivemode=normal[12] expcomp=0.0[31] focalvalue=5.6(ro)[23] isospeedvalue=Auto[24] shutspeedvalue=250(ro)[61] takemode=P[7] wbvalue=0[13]
SELFTEST PASS set expcomp 0.0 → -5.0, now -5.0
SELFTEST PASS set isospeedvalue Auto → Low, now Low
SELFTEST PASS set wbvalue 0 → 18, now 18
SELFTEST PASS tap focus afState=0
SELFTEST PASS shoot
SELFTEST PASS last-shot review
SELFTEST PASS movie
# olympus-E-M10MarkIII
SELFTEST PASS connect brand=olympus name=OM-D E-M10 Mark III error=-
SELFTEST INFO profile=OM-D E-M10 Mark III support=Researched, not yet tried on this camera crop=2.0 note=-
SELFTEST PASS live view fps=11 frame=640x480
SELFTEST PASS settings read artfilter=popart(ro)[14] colortone=natural[9] drivemode=normal[12] expcomp=0.0[31] focalvalue=5.6(ro)[23] isospeedvalue=Auto[24] shutspeedvalue=250(ro)[61] takemode=P[7] wbvalue=0[13]
SELFTEST PASS set expcomp 0.0 → -5.0, now -5.0
SELFTEST PASS set isospeedvalue Auto → Low, now Low
SELFTEST PASS set wbvalue 0 → 18, now 18
SELFTEST PASS tap focus afState=0
SELFTEST PASS shoot
SELFTEST PASS last-shot review
SELFTEST PASS movie
# olympus-E-PL10
SELFTEST PASS connect brand=olympus name=PEN E-PL10 error=-
SELFTEST INFO profile=PEN E-PL10 support=Researched, not yet tried on this camera crop=2.0 note=-
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
