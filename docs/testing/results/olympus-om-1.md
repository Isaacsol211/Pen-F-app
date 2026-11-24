# Results: OM System OM-1 (mock)

Plan: [`../TEST-PLAN.md`](../TEST-PLAN.md). Result key: `P` pass · `F` fail · `UX` works, UX failure · `N/A` · `—` not run.

| | |
|---|---|
| Sheet | `olympus-om-1` |
| Stands for | OM System bodies with the Device Connection note: OM-1, OM-5, OM-1 Mark II, OM-3, OM-5 Mark II, TG-7 (no High Res). Probed: OM-1, OM-1 Mark II, OM-3, TG-7 |
| Flagship | no |
| Run type | Full self-test (OM-1) + probes (OM-1 Mark II, OM-3, TG-7) |
| Date | 2026-11-25 |
| Tester | Claude (Sonnet 5.5) |
| Build | test/plan worktree on main 5da84a8 (app code unchanged), Debug 1.1 (5), iPhone 17 simulator |
| Camera | Mock: `python3 -I -u mock_penf.py --model OM-1` |
| Self-test | `olympus-OM-1`: failures=not reached (probe); `olympus-OM-1MarkII`: failures=not reached (probe); `olympus-OM-3`: failures=not reached (probe); `olympus-TG-7`: failures=not reached (probe) |

## Checks

| ID | Result | Note |
|---|---|---|
| ST-01 | — |  |
| ST-02 | — |  |
| ST-03 | — |  |
| ST-04–ST-20 | — | probe only: stopped after connect, live view and the first settings |
| UI-ADD-08 | P | The OM System note text is attached ("start Device Connection ... Bluetooth can stay off ... hasn't been tried with Shutterlink yet"); not seen on screen |
| Probe OM-1 Mark II | P | same note |
| Probe OM-3 | P | same note |
| Probe TG-7 | P | same note, no High Res |

## Findings

| ID | Sev | Check | What happens | Suggested fix |
|---|---|---|---|---|
| olympus-om-1-F1 | S3 | UI-ADD-08 | The note is shown to the user only after connecting, so an OM System owner pays for Pro (or starts the trial) before learning that the body may not be fully supported. | Show the OM System caveat on the Add a camera sheet for the OM brand and on the Pro screen when the connected body is "Researched". |

## Mockup record

Strip cells (same on every Olympus mock): F-STOP, SHUTTER, ISO, EV, WB, DRIVE (see `olympus-pen-f.md` MODEL-06/07). No Quality cell: Olympus does not report picture quality over Wi-Fi.

**Note risk.** The OM System note says the body is only partly open to remote shooting and that its app may speak a newer protocol that Shutterlink has not seen. On the mock the app connects normally, so that risk is **not testable here** and is the biggest unknown for every OM System owner.

## Value and pricing

See the flagship sheets (`olympus-om-1-mark-ii.md`, `olympus-om-3.md`) for the value analysis of these bodies. For OM-1 and OM-5 owners: **a stretch** until a real body proves the newer protocol.

## Self-test output

```text
# olympus-OM-1
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
# olympus-TG-7
SELFTEST PASS connect brand=olympus name=OM System TG-7 error=-
SELFTEST INFO profile=OM System TG-7 support=Researched, not yet tried on this camera crop=2.0 note=OM System bodies: start Device Connection on the camera (Bluetooth can stay off). OM System says remote shooting is partly limited, and its app may speak a newer protocol: this body hasn't been tried with Shutterlink yet.
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
