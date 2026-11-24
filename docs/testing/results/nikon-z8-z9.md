# Results: Nikon Z 8 / Z 9 / Z 6III / Z f (mock)

Plan: [`../TEST-PLAN.md`](../TEST-PLAN.md). Result key: `P` pass · `F` fail · `UX` works, UX failure · `N/A` · `—` not run.

| | |
|---|---|
| Sheet | `nikon-z8-z9` |
| Stands for | Flagship Nikon Z bodies ★ and the Zf |
| Flagship | **yes** |
| Run type | Probes (connect, live view, first settings) |
| Date | 2026-11-25 |
| Tester | Claude (Sonnet 5.5) |
| Build | test/plan worktree on main 5da84a8 (app code unchanged), Debug 1.1 (5), iPhone 17 simulator |
| Camera | Mock: `scratch mock_nikon.py with MOCKMODEL=<name>` |
| Self-test | `nikon-Z8`: failures=not reached (probe); `nikon-Z9`: failures=not reached (probe); `nikon-Z6_3`: failures=not reached (probe); `nikon-Zf`: failures=not reached (probe) |

## Checks

| ID | Result | Note |
|---|---|---|
| ST-01 | P | SELFTEST PASS connect brand=nikon name=Z 8 error=- |
| ST-02 | P | SELFTEST INFO profile=none support=- crop=1.0 note=- |
| ST-03 | P | SELFTEST PASS live view fps=32 frame=640x480 |
| ST-04–ST-20 | — | probe only |
| Z 9 | P | SELFTEST INFO profile=none support=- crop=1.0 note=- |
| Z 6 III | P | SELFTEST INFO profile=none support=- crop=1.0 note=- |
| Z f | P | SELFTEST INFO profile=none support=- crop=1.0 note=- |

## Findings

| ID | Sev | Check | What happens | Suggested fix |
|---|---|---|---|---|
| nikon-z8-z9-F1 | S3 | VAL-08 | Flagship owners (Z 8, Z 9, Z 6III) are the likeliest to pay and the least likely to have a camera whose Wi-Fi remote works with a third-party PTP/IP client; the app has no real-body evidence for any of them. | Mark them "unconfirmed" in the connect step and in the trial prompt. |

## Mockup record

Same strip as the Z 6II (5 cells). Flagship-specific expectations: Z 9/Z 8 have Pre-Release Capture, subject detection, 4 Z bodies with Bulb/Time and focus shift shooting. None is exposed. The app's own Bulb/Time is absent for Nikon (PTP), so Astro and ND long exposures on a Z 8/Z 9 can't start Bulb.

## Value and pricing

**VAL-08 (is it clear before paying that this brand is beta / mock-only?): No.** The Connect screen shows a small flask line ("Newer in Shutterlink… please tell us") under the brand's steps, but the Add a camera list has no Beta tag, the Pro screen does not mention beta or mock-only status, and the Pro trial is offered before any connect. A user can buy Pro for a body that has only ever been tested against a mock. (`img/nikon-z6ii/add-camera-brands-no-beta-mark.png`, `pro-screen-no-beta-mention.png`)

**Z 8 / Z 9 / Z 6III owner.** These bodies already have an intervalometer, time-lapse movie, focus shift shooting, Pre-Release Capture and bracketing. Pro overlaps almost everything the app can do on Nikon, and the one thing the app lacks that a flagship owner needs (Bulb/Time, Drive, subject AF choice) isn't there. **Verdict: poor value at $9.99 for a Z 8/Z 9 owner.** What would make it worth it: a working Bulb, drive/release mode on the strip, and a real-body test.

## Self-test output

```text
# nikon-Z8
SELFTEST PASS connect brand=nikon name=Z 8 error=-
SELFTEST INFO profile=none support=- crop=1.0 note=-
SELFTEST PASS live view fps=32 frame=640x480
SELFTEST PASS settings read expcomp=0.0[31] focalvalue=4.0[20] isospeedvalue=400[25] shutspeedvalue=125[57] takemode=M(ro)[1] wbvalue=0[9]
SELFTEST PASS set expcomp 0.0 → -5.0, now -5.0
SELFTEST PASS set focalvalue 4.0 → 1.8, now 1.8
SELFTEST PASS set shutspeedvalue 125 → 30", now 30"
SELFTEST PASS set isospeedvalue 400 → 100, now 100
SELFTEST PASS set wbvalue 0 → 18, now 18
SELFTEST PASS tap focus afState=1
# nikon-Z9
SELFTEST PASS connect brand=nikon name=Z 9 error=-
SELFTEST INFO profile=none support=- crop=1.0 note=-
SELFTEST PASS live view fps=31 frame=640x480
SELFTEST PASS settings read expcomp=0.0[31] focalvalue=4.0[20] isospeedvalue=400[25] shutspeedvalue=125[57] takemode=M(ro)[1] wbvalue=0[9]
SELFTEST PASS set expcomp 0.0 → -5.0, now -5.0
SELFTEST PASS set focalvalue 4.0 → 1.8, now 1.8
SELFTEST PASS set shutspeedvalue 125 → 30", now 30"
SELFTEST PASS set isospeedvalue 400 → 100, now 100
SELFTEST PASS set wbvalue 0 → 18, now 18
SELFTEST PASS tap focus afState=1
# nikon-Z6_3
SELFTEST PASS connect brand=nikon name=Z 6 III error=-
SELFTEST INFO profile=none support=- crop=1.0 note=-
SELFTEST PASS live view fps=30 frame=640x480
SELFTEST PASS settings read expcomp=0.0[31] focalvalue=4.0[20] isospeedvalue=400[25] shutspeedvalue=125[57] takemode=M(ro)[1] wbvalue=0[9]
SELFTEST PASS set expcomp 0.0 → -5.0, now -5.0
SELFTEST PASS set focalvalue 4.0 → 1.8, now 1.8
SELFTEST PASS set shutspeedvalue 125 → 30", now 30"
SELFTEST PASS set isospeedvalue 400 → 100, now 100
SELFTEST PASS set wbvalue 0 → 18, now 18
SELFTEST PASS tap focus afState=1
# nikon-Zf
SELFTEST PASS connect brand=nikon name=Z f error=-
SELFTEST INFO profile=none support=- crop=1.0 note=-
SELFTEST PASS live view fps=32 frame=640x480
SELFTEST PASS settings read expcomp=0.0[31] focalvalue=4.0[20] isospeedvalue=400[25] shutspeedvalue=125[57] takemode=M(ro)[1] wbvalue=0[9]
SELFTEST PASS set expcomp 0.0 → -5.0, now -5.0
SELFTEST PASS set focalvalue 4.0 → 1.8, now 1.8
SELFTEST PASS set shutspeedvalue 125 → 30", now 30"
SELFTEST PASS set isospeedvalue 400 → 100, now 100
SELFTEST PASS set wbvalue 0 → 18, now 18
SELFTEST PASS tap focus afState=1
```
