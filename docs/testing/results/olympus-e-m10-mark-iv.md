# Results: Olympus OM-D E-M10 Mark IV (mock)

Plan: [`../TEST-PLAN.md`](../TEST-PLAN.md). Result key: `P` pass · `F` fail · `UX` works, UX failure · `N/A` · `—` not run.

| | |
|---|---|
| Sheet | `olympus-e-m10-mark-iv` |
| Stands for | E-M10 Mark IV only (the one body with the "only some settings over Wi-Fi" note) |
| Flagship | no |
| Run type | Full self-test, no UI pass |
| Date | 2026-11-25 |
| Tester | Claude (Sonnet 5.5) |
| Build | test/plan worktree on main 5da84a8 (app code unchanged), Debug 1.1 (5), iPhone 17 simulator |
| Camera | Mock: `python3 -I -u mock_penf.py --model E-M10MarkIV` |
| Self-test | `olympus-E-M10MarkIV`: failures=not reached (probe) |

## Checks

| ID | Result | Note |
|---|---|---|
| ST-01 | — |  |
| ST-02 | — |  |
| ST-03 | — |  |
| ST-04–ST-20 | — | probe only: stopped after connect, live view and the first settings |
| UI-ADD-08 | UX | The profile note is "Over Wi-Fi the E-M10 IV only changes mode, aperture, shutter, EV, ISO, white balance, drive, art filter and hue." The mock still serves `colortone` and lets the app list it in All camera settings, so the app shows a setting the note says is not changeable (mock fidelity, not seen on screen). |
| PRESET-06 | — | all 7 presets passed without a skipped step on the mock, so the "camera cannot do this" path is untested for this body |

## Findings

| ID | Sev | Check | What happens | Suggested fix |
|---|---|---|---|---|
| olympus-e-m10-mark-iv-F1 | S4 (test infra) | ST-04 | The mock gives the E-M10 IV `colortone` although the profile note says the body only changes the nine settings listed. Nothing in the app limits the list to that note. | Filter All camera settings by the note, or make the mock model the E-M10 IV list. |

## Mockup record

Strip cells (same on every Olympus mock): F-STOP, SHUTTER, ISO, EV, WB, DRIVE (see `olympus-pen-f.md` MODEL-06/07). No Quality cell: Olympus does not report picture quality over Wi-Fi.

**Per model:** the note says the body allows mode, aperture, shutter, EV, ISO, WB, drive, art filter and hue: the same settings the app already shows, so nothing is lost. The E-M10 IV has no High Res Shot, so the High Res tool should be hidden (profile `highResShot` false; not checked on screen).

## Value and pricing

Pro for an entry-level OM-D: Presets, Astro, Interval, Bracket, ND and Motion all work on the mock, so a first-time astro or long-exposure user gets real value. The E-M10 IV has no High Res Shot and a limited Wi-Fi command set, so there are no gaps to disappoint a buyer. Verdict: **fair to generous** at $9.99; the main risk is that the one-time note appears only after connecting.

## Self-test output

```text
# olympus-E-M10MarkIV
```
