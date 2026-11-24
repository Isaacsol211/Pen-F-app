# Results: Canon EOS R5 / R3 / R6 Mark II / R1 (mock)

Plan: [`../TEST-PLAN.md`](../TEST-PLAN.md). Result key: `P` pass · `F` fail · `UX` works, UX failure · `N/A` · `—` not run.

| | |
|---|---|
| Sheet | `canon-eos-r5-r3-r6m2` |
| Stands for | Canon flagships ★ |
| Flagship | **yes** |
| Run type | Probes |
| Date | 2026-11-25 |
| Tester | Claude (Sonnet 5.5) |
| Build | test/plan worktree on main 5da84a8 (app code unchanged), Debug 1.1 (5), iPhone 17 simulator |
| Camera | Mock: `scratch mock_canon.py MOCKMODEL=<name>` |
| Self-test | `canon-CanonEOSR5`: failures=not reached (probe); `canon-CanonEOSR3`: failures=not reached (probe); `canon-CanonEOSR6MarkII`: failures=not reached (probe); `canon-CanonEOSR6m2`: failures=not reached (probe); `canon-CanonEOSR5m2`: failures=not reached (probe); `canon-CanonEOSR1`: failures=not reached (probe) |

## Checks

| ID | Result | Note |
|---|---|---|
| ST-01 | P | SELFTEST PASS connect brand=canon name=EOS R5 error=- |
| ST-02 | P | SELFTEST INFO profile=none support=- crop=1.0 note=- |
| ST-03 | P | SELFTEST PASS live view fps=23 frame=640x480 |
| ST-04–ST-20 | — | probe only |
| R3 | P | SELFTEST INFO profile=none support=- crop=1.0 note=- |
| R6 Mark II | P | SELFTEST INFO profile=none support=- crop=1.0 note=- |
| R6m2 | P | SELFTEST INFO profile=none support=- crop=1.6 note=- crop 1.6: wrong |
| R5m2 | P | SELFTEST INFO profile=none support=- crop=1.6 note=- crop 1.6: wrong |

## Findings

| ID | Sev | Check | What happens | Suggested fix |
|---|---|---|---|---|
| canon-eos-r5-r3-r6m2-F1 | S2 | ST-02 | If a Mark II body reports its model as "EOS R6m2"/"R5m2" (the form Canon uses internally), the crop factor falls through to APS-C (1.6), and Astro/Star-trails shutter speeds are ~60% too long on a full-frame body. | Add "R6M2", "R5M2", "R1", "R3" spellings to the Canon full-frame list (or key off the sensor size reported by CCAPI). |

## Mockup record

Strip as the R6 (5 cells). Flagships (R5, R3, R1) also have Pre-Capture / RAW burst, subject-tracking AF, 8K (R5) and a Bulb timer: none exposed. R1/R5 II have CCAPI built in; the others need the activation tool.

## Value and pricing

**VAL-08 (is it clear before paying that this brand is beta / mock-only?): No.** The Connect screen shows a small flask line ("Newer in Shutterlink… please tell us") under the brand's steps, but the Add a camera list has no Beta tag, the Pro screen does not mention beta or mock-only status, and the Pro trial is offered before any connect. A user can buy Pro for a body that has only ever been tested against a mock. (`img/nikon-z6ii/add-camera-brands-no-beta-mark.png`, `pro-screen-no-beta-mention.png`)

**R5 / R3 / R6 II owner.** A CCAPI flagship owner has already done the one-time developer-account activation, so they are the most committed buyers and the most likely to be disappointed by a mock-only driver. The app's Pro tools (Astro, intervals, bracket, ND) overlap what the R5/R3 do natively (intervalometer, bracketing, bulb timer). **Verdict: a stretch to poor.**

## Self-test output

```text
# canon-CanonEOSR5
SELFTEST PASS connect brand=canon name=EOS R5 error=-
SELFTEST INFO profile=none support=- crop=1.0 note=-
SELFTEST PASS live view fps=23 frame=640x480
SELFTEST PASS settings read expcomp=0.0[19] focalvalue=4.0[23] isospeedvalue=auto[26] shutspeedvalue=125[56] takemode=M(ro)[1] wbvalue=0[10]
SELFTEST PASS set expcomp 0.0 → -3.0, now -3.0
SELFTEST PASS set focalvalue 4.0 → 1.8, now 1.8
SELFTEST PASS set shutspeedvalue 125 → 30", now 30"
SELFTEST PASS set isospeedvalue auto → 100, now 100
SELFTEST PASS set wbvalue 0 → awb_white, now awb_white
SELFTEST PASS tap focus afState=0
# canon-CanonEOSR3
SELFTEST PASS connect brand=canon name=EOS R3 error=-
SELFTEST INFO profile=none support=- crop=1.0 note=-
SELFTEST PASS live view fps=21 frame=640x480
SELFTEST PASS settings read expcomp=0.0[19] focalvalue=4.0[23] isospeedvalue=auto[26] shutspeedvalue=125[56] takemode=M(ro)[1] wbvalue=0[10]
SELFTEST PASS set expcomp 0.0 → -3.0, now -3.0
SELFTEST PASS set focalvalue 4.0 → 1.8, now 1.8
SELFTEST PASS set shutspeedvalue 125 → 30", now 30"
SELFTEST PASS set isospeedvalue auto → 100, now 100
SELFTEST PASS set wbvalue 0 → awb_white, now awb_white
SELFTEST PASS tap focus afState=0
# canon-CanonEOSR6MarkII
SELFTEST PASS connect brand=canon name=EOS R6 Mark II error=-
SELFTEST INFO profile=none support=- crop=1.0 note=-
SELFTEST PASS live view fps=23 frame=640x480
SELFTEST PASS settings read expcomp=0.0[19] focalvalue=4.0[23] isospeedvalue=auto[26] shutspeedvalue=125[56] takemode=M(ro)[1] wbvalue=0[10]
SELFTEST PASS set expcomp 0.0 → -3.0, now -3.0
SELFTEST PASS set focalvalue 4.0 → 1.8, now 1.8
SELFTEST PASS set shutspeedvalue 125 → 30", now 30"
SELFTEST PASS set isospeedvalue auto → 100, now 100
SELFTEST PASS set wbvalue 0 → awb_white, now awb_white
SELFTEST PASS tap focus afState=0
# canon-CanonEOSR6m2
SELFTEST PASS connect brand=canon name=EOS R6m2 error=-
SELFTEST INFO profile=none support=- crop=1.6 note=-
SELFTEST PASS live view fps=23 frame=640x480
SELFTEST PASS settings read expcomp=0.0[19] focalvalue=4.0[23] isospeedvalue=auto[26] shutspeedvalue=125[56] takemode=M(ro)[1] wbvalue=0[10]
SELFTEST PASS set expcomp 0.0 → -3.0, now -3.0
SELFTEST PASS set focalvalue 4.0 → 1.8, now 1.8
SELFTEST PASS set shutspeedvalue 125 → 30", now 30"
SELFTEST PASS set isospeedvalue auto → 100, now 100
SELFTEST PASS set wbvalue 0 → awb_white, now awb_white
SELFTEST PASS tap focus afState=0
# canon-CanonEOSR5m2
SELFTEST PASS connect brand=canon name=EOS R5m2 error=-
SELFTEST INFO profile=none support=- crop=1.6 note=-
SELFTEST PASS live view fps=22 frame=640x480
SELFTEST PASS settings read expcomp=0.0[19] focalvalue=4.0[23] isospeedvalue=auto[26] shutspeedvalue=125[56] takemode=M(ro)[1] wbvalue=0[10]
SELFTEST PASS set expcomp 0.0 → -3.0, now -3.0
SELFTEST PASS set focalvalue 4.0 → 1.8, now 1.8
SELFTEST PASS set shutspeedvalue 125 → 30", now 30"
SELFTEST PASS set isospeedvalue auto → 100, now 100
SELFTEST PASS set wbvalue 0 → awb_white, now awb_white
SELFTEST PASS tap focus afState=0
# canon-CanonEOSR1
SELFTEST PASS connect brand=canon name=EOS R1 error=-
SELFTEST INFO profile=none support=- crop=1.0 note=-
SELFTEST PASS live view fps=23 frame=640x480
SELFTEST PASS settings read expcomp=0.0[19] focalvalue=4.0[23] isospeedvalue=auto[26] shutspeedvalue=125[56] takemode=M(ro)[1] wbvalue=0[10]
SELFTEST PASS set expcomp 0.0 → -3.0, now -3.0
SELFTEST PASS set focalvalue 4.0 → 1.8, now 1.8
SELFTEST PASS set shutspeedvalue 125 → 30", now 30"
SELFTEST PASS set isospeedvalue auto → 100, now 100
SELFTEST PASS set wbvalue 0 → awb_white, now awb_white
SELFTEST PASS tap focus afState=0
```
