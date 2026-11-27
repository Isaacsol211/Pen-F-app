# Results: OM System OM-3 (mock)

Plan: [`../TEST-PLAN.md`](../TEST-PLAN.md). Result key: `P` pass · `F` fail · `UX` works, UX failure · `N/A` · `—` not run.

| | |
|---|---|
| Sheet | `olympus-om-3` |
| Stands for | OM-3 (flagship-class, 2025) |
| Flagship | **yes** |
| Run type | Probe (connect, live view, first settings) + profile review; UI per group sheet |
| Date | 2026-11-25 |
| Tester | Claude (Sonnet 5.5) |
| Build | test/plan worktree on main 5da84a8 (app code unchanged), Debug 1.1 (5), iPhone 17 simulator |
| Camera | Mock: `python3 -I -u mock_penf.py --model OM-3` |
| Self-test | `olympus-OM-3`: failures=not reached (probe) |

## Checks

| ID | Result | Note |
|---|---|---|
| ST-01 | P | SELFTEST PASS connect brand=olympus name=OM System OM-3 error=- |
| ST-02 | P | SELFTEST INFO profile=OM System OM-3 support=Researched, not yet tried on this camera crop=2.0 note=OM System bodies: start Device Connection on the camera (Bluetooth can stay off). OM System says remote shooting is partly limited, and its app may speak a newer protocol: this body hasn't been tried with Shutterlink yet. |
| ST-03 | P | SELFTEST PASS live view fps=11 frame=640x480 |
| UI-ADD-08 | P | note text attached as listed |

## Findings

| ID | Sev | Check | What happens | Suggested fix |
|---|---|---|---|---|
| olympus-om-3-F1 | S3 | VAL-08 | Pro is sold before the body is known to work (see OM-1 Mark II). | Same as OM-1 Mark II. |

## Mockup record

Strip cells (same on every Olympus mock): F-STOP, SHUTTER, ISO, EV, WB, DRIVE (see `olympus-pen-f.md` MODEL-06/07). No Quality cell: Olympus does not report picture quality over Wi-Fi.

**What this body can do over Wi-Fi that the app does not use (from the OPC command list on the PEN-F baseline; this body's own list is unknown):** OM-3 adds Computational Photography modes (Live ND, High Res, Focus Stacking, HDR) in a retro body; none of these is exposed over the OPC command list the app knows. Unused OPC commands as for the OM-1 Mark II.

**What its live screen should show:** Same strip as the OM-1 Mark II. The OM-3 owner is a stills photographer, so Drive (with anti-shock/silent) and WB deserve full text labels rather than icons.

## Value and pricing

**OM-3 owner.** Brand-new body (2025), the likeliest owner to be a paying photography enthusiast and also the likeliest to hit an unsupported protocol. On the mock everything works; the profile says "newer protocol unconfirmed". Value is **a stretch until proven on a real OM-3**: the app's strengths (presets, ND, astro) overlap with Live ND and Computational modes the OM-3 sells. Missing: Live ND control, High Res start, Pro Capture. Would be worth it for: Astro setup and Interval with Live Composite star trails.

## Self-test output

```text
# olympus-OM-3
SELFTEST PASS connect brand=olympus name=OM System OM-3 error=-
SELFTEST INFO profile=OM System OM-3 support=Researched, not yet tried on this camera crop=2.0 note=OM System bodies: start Device Connection on the camera (Bluetooth can stay off). OM System says remote shooting is partly limited, and its app may speak a newer protocol: this body hasn't been tried with Shutterlink yet.
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
