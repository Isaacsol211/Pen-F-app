# Results: Olympus body not in the table (mock "E-XYZ9")

Plan: [`../TEST-PLAN.md`](../TEST-PLAN.md). Result key: `P` pass · `F` fail · `UX` works, UX failure · `N/A` · `—` not run.

| | |
|---|---|
| Sheet | `olympus-unknown` |
| Stands for | Bodies absent from ModelProfiles.swift (e.g. a future OM System model, an Air-less model alias) |
| Flagship | no |
| Run type | Probe |
| Date | 2026-11-25 |
| Tester | Claude (Sonnet 5.5) |
| Build | test/plan worktree on main 5da84a8 (app code unchanged), Debug 1.1 (5), iPhone 17 simulator |
| Camera | Mock: `python3 -I -u mock_penf.py --model E-XYZ9` |
| Self-test | `olympus-E-XYZ9`: failures=not reached (probe) |

## Checks

| ID | Result | Note |
|---|---|---|
| ST-01 | P | SELFTEST PASS connect brand=olympus name=E-XYZ9 (mock) error=- |
| ST-02 | UX | SELFTEST INFO profile=none support=- crop=2.0 note=- The name shows "E-XYZ9 (mock)" with the mock suffix; a real camera would show its own name. |

## Findings

| ID | Sev | Check | What happens | Suggested fix |
|---|---|---|---|---|
| olympus-unknown-F1 | S4 | ST-01 | An unknown body connects with brand defaults and no message that it is unknown or untried: "Tested / Researched" label is blank (support=-). | Show "Not in the supported list: try it and send the request log" once. |

## Mockup record

Strip cells (same on every Olympus mock): F-STOP, SHUTTER, ISO, EV, WB, DRIVE (see `olympus-pen-f.md` MODEL-06/07). No Quality cell: Olympus does not report picture quality over Wi-Fi.

## Value and pricing

An owner of an unlisted body has no way to tell what to expect: show "Unknown body" and open the trial before purchase.

## Self-test output

```text
# olympus-E-XYZ9
SELFTEST PASS connect brand=olympus name=E-XYZ9 (mock) error=-
SELFTEST INFO profile=none support=- crop=2.0 note=-
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
