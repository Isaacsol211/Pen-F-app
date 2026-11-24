# Results: Olympus AIR A01 and TG-Tracker (mock)

Plan: [`../TEST-PLAN.md`](../TEST-PLAN.md). Result key: `P` pass · `F` fail · `UX` works, UX failure · `N/A` · `—` not run.

| | |
|---|---|
| Sheet | `olympus-air-a01` |
| Stands for | Unsupported bodies: AIR A01, TG-Tracker |
| Flagship | no |
| Run type | Self-test connect only |
| Date | 2026-11-25 |
| Tester | Claude (Sonnet 5.5) |
| Build | test/plan worktree on main 5da84a8 (app code unchanged), Debug 1.1 (5), iPhone 17 simulator |
| Camera | Mock: `python3 -I -u mock_penf.py --model AIR-A01  /  --model TG-Tracker` |
| Self-test | `olympus-AIR-A01`: failures=not reached (probe); `olympus-TG-Tracker`: failures=1 |

## Checks

| ID | Result | Note |
|---|---|---|
| UI-ADD-07 AIR A01 | — |  |
| UI-ADD-07 TG-Tracker | UX | SELFTEST FAIL connect brand=olympus name=TG-Tracker error=The TG-Tracker works with OI.Track, not remote shooting. |
| ST-21 | — | not run (needs the real-address refusal check) |

## Findings

| ID | Sev | Check | What happens | Suggested fix |
|---|---|---|---|---|
| olympus-air-a01-F1 | S3 | UI-ADD-07 | The AIR A01 reason names protocol calls ("switch_cameramode, newstarttake"). A user cannot act on that; the TG-Tracker reason is better but offers no alternative. | Reword to: "The AIR A01 works with the Olympus Air app only. Shutterlink can't control it." and add a link to the maker's app. |
| olympus-air-a01-F2 | S3 | UI-ADD-07 | The refusal is thrown after the app has already contacted the camera and started connecting; the camera is probably saved as "last used" before the refusal (not confirmed on screen). | Check the profile before saving the camera. |

## Mockup record

No remote screen: the app stops at connect with the profile's reason.

## Value and pricing

Not applicable: nobody pays for Pro on these bodies. The Pro screen should not be reachable before a successful connect on an unsupported body.

## Self-test output

```text
# olympus-AIR-A01
# olympus-TG-Tracker
SELFTEST FAIL connect brand=olympus name=TG-Tracker error=The TG-Tracker works with OI.Track, not remote shooting.
SELFTEST DONE failures=1
```
