# Results: OM System OM-1 Mark II (mock)

Plan: [`../TEST-PLAN.md`](../TEST-PLAN.md). Result key: `P` pass · `F` fail · `UX` works, UX failure · `N/A` · `—` not run.

| | |
|---|---|
| Sheet | `olympus-om-1-mark-ii` |
| Stands for | OM-1 Mark II (flagship, 2024) |
| Flagship | **yes** |
| Run type | Probe (connect, live view, first settings) + profile review; UI per group sheet |
| Date | 2026-11-25 |
| Tester | Claude (Sonnet 5.5) |
| Build | test/plan worktree on main 5da84a8 (app code unchanged), Debug 1.1 (5), iPhone 17 simulator |
| Camera | Mock: `python3 -I -u mock_penf.py --model OM-1MarkII` |
| Self-test | `olympus-OM-1MarkII`: failures=not reached (probe) |

## Checks

| ID | Result | Note |
|---|---|---|
| ST-01 | P | SELFTEST PASS connect brand=olympus name=OM System OM-1 Mark II error=- |
| ST-02 | P | SELFTEST INFO profile=OM System OM-1 Mark II support=Researched, not yet tried on this camera crop=2.0 note=OM System bodies: start Device Connection on the camera (Bluetooth can stay off). OM System says remote shooting is partly limited, and its app may speak a newer protocol: this body hasn't been tried with Shutterlink yet. |
| ST-03 | P | SELFTEST PASS live view fps=11 frame=640x480 |
| UI-ADD-08 | P | note text attached as listed |

## Findings

| ID | Sev | Check | What happens | Suggested fix |
|---|---|---|---|---|
| olympus-om-1-mark-ii-F1 | S3 | VAL-08 | Pro is sold before the body is known to work: the note is the only warning. | Warn before purchase on the Pro screen when the connected body is a "Researched" OM System model. |

## Mockup record

Strip cells (same on every Olympus mock): F-STOP, SHUTTER, ISO, EV, WB, DRIVE (see `olympus-pen-f.md` MODEL-06/07). No Quality cell: Olympus does not report picture quality over Wi-Fi.

**What this body can do over Wi-Fi that the app does not use (from the OPC command list on the PEN-F baseline; this body's own list is unknown):** Live ND, Live GND, Pro Capture, in-camera focus stacking and High Res (handheld 50 MP / tripod 80 MP) are camera-side; none has a known Wi-Fi command. Unused OPC commands: power zoom, share-order list, GPS push, half-press shutter, free card space.

**What its live screen should show:** mode, aperture, shutter, ISO, EV (4 Tier-1 cells + mode), WB and drive on the strip; High Res and Live ND/Live Composite state as read-only chips; Pro Capture would be the first Tier 2 cell if the camera ever exposes it.

## Value and pricing

**OM-1 Mark II owner.** Expectation: remote Live Composite, High Res Shot and Pro Capture from the phone, plus fast shooting. What the app gives: Presets (one-tap Astro/Moon/Fireworks), Interval, Bracket, ND calculator, Motion trigger; High Res is a guide. Overlap: the camera already has intervalometer, bracketing, focus stacking, Live ND and Live Composite, so Pro replaces fewer in-camera features than for an E-M10. **Verdict (VAL-10): a stretch at $9.99 until a real OM-1 II connects, then fair**: the Presets/Undo and Astro with the lens's focal length are the genuinely new things. What would help most: a note before purchase, a High Res start that works, and a Live Composite shortcut on the main screen.

## Self-test output

```text
# olympus-OM-1MarkII
SELFTEST PASS connect brand=olympus name=OM System OM-1 Mark II error=-
SELFTEST INFO profile=OM System OM-1 Mark II support=Researched, not yet tried on this camera crop=2.0 note=OM System bodies: start Device Connection on the camera (Bluetooth can stay off). OM System says remote shooting is partly limited, and its app may speak a newer protocol: this body hasn't been tried with Shutterlink yet.
SELFTEST PASS live view fps=11 frame=640x480
SELFTEST PASS settings read artfilter=popart(ro)[14] colortone=natural[9] drivemode=normal[12] expcomp=0.0[31] focalvalue=5.6(ro)[23] isospeedvalue=Auto[24] shutspeedvalue=250(ro)[61] takemode=P[7] wbvalue=0[13]
SELFTEST PASS set expcomp 0.0 → -5.0, now -5.0
SELFTEST PASS set isospeedvalue Auto → Low, now Low
SELFTEST PASS set wbvalue 0 → 18, now 18
SELFTEST PASS tap focus afState=1
SELFTEST PASS shoot
SELFTEST PASS last-shot review
SELFTEST PASS movie
```
