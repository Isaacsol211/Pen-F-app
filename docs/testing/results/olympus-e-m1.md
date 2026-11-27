# Results: Olympus OM-D E-M1 (mock)

Plan: [`../TEST-PLAN.md`](../TEST-PLAN.md). Result key: `P` pass · `F` fail · `UX` works, UX failure · `N/A` · `—` not run.

| | |
|---|---|
| Sheet | `olympus-e-m1` |
| Stands for | E-M1 (Mark I, 2013): note "Wi-Fi must be Private; no movie mode over Wi-Fi" |
| Flagship | no |
| Run type | Probe |
| Date | 2026-11-25 |
| Tester | Claude (Sonnet 5.5) |
| Build | test/plan worktree on main 5da84a8 (app code unchanged), Debug 1.1 (5), iPhone 17 simulator |
| Camera | Mock: `python3 -I -u mock_penf.py --model E-M1` |
| Self-test | `olympus-E-M1`: failures=not reached (probe) |

## Checks

| ID | Result | Note |
|---|---|---|
| ST-01 | P | SELFTEST PASS connect brand=olympus name=OM-D E-M1 error=- |
| ST-02 | P | SELFTEST INFO profile=OM-D E-M1 support=Researched, not yet tried on this camera crop=2.0 note=Remote control only works with the camera's Wi-Fi set to Private, not One-Time. Movie mode isn't available over Wi-Fi. |
| Movie mode | UX | The profile says movie mode is not available over Wi-Fi; the probe shows `PASS movie` on the mock because the mock offers it, and the app's carousel would still show VIDEO. Check on screen that the app hides it (not done). |

## Findings

| ID | Sev | Check | What happens | Suggested fix |
|---|---|---|---|---|
| olympus-e-m1-F1 | S3 | UI-STRIP-01 | The note says no movie mode over Wi-Fi but the app has no profile flag to hide the VIDEO option for the E-M1 (the Olympus `ModelProfile` has `noVideo` only as a LUMIX flag). | Add a `noMovie` flag for Olympus and hide VIDEO on the E-M1. |

## Mockup record

Same strip as the PEN-F sheet.

## Value and pricing

E-M1 (2013) owner: Pro is **fair** for stills, VIDEO shown but unusable.

## Self-test output

```text
# olympus-E-M1
SELFTEST PASS connect brand=olympus name=OM-D E-M1 error=-
SELFTEST INFO profile=OM-D E-M1 support=Researched, not yet tried on this camera crop=2.0 note=Remote control only works with the camera's Wi-Fi set to Private, not One-Time. Movie mode isn't available over Wi-Fi.
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
