# Results: Sony modern bodies (mock): a7 III/IV, a7R V, a1 ★, a9 III ★, a7S III, ZV-E10, ZV-E1, a6400, a6700, a7C II, RX100 VII

Plan: [`../TEST-PLAN.md`](../TEST-PLAN.md). Result key: `P` pass · `F` fail · `UX` works, UX failure · `N/A` · `—` not run.

| | |
|---|---|
| Sheet | `sony-ilce-modern` |
| Stands for | Sony bodies from 2020 on and other model names |
| Flagship | **yes** |
| Run type | Probes |
| Date | 2026-11-25 |
| Tester | Claude (Sonnet 5.5) |
| Build | test/plan worktree on main 5da84a8 (app code unchanged), Debug 1.1 (5), iPhone 17 simulator |
| Camera | Mock: `scratch mock_sony.py MOCKMODEL=<name>` |
| Self-test | `sony-ILCE-1`: failures=not reached (probe); `sony-ILCE-9M3`: failures=not reached (probe); `sony-ILCE-7M4`: failures=not reached (probe); `sony-ILCE-7RM5`: failures=not reached (probe); `sony-ILCE-7M3`: failures=not reached (probe); `sony-ILCE-7SM3`: failures=not reached (probe); `sony-ILCE-6400`: failures=not reached (probe); `sony-ILCE-6700`: failures=not reached (probe); `sony-ZV-E10`: failures=not reached (probe); `sony-ZV-E1`: failures=not reached (probe); `sony-DSC-RX100M7`: failures=not reached (probe); `sony-ILCE-7CM2`: failures=not reached (probe) |

## Checks

| ID | Result | Note |
|---|---|---|
| ST-01 | P | SELFTEST PASS connect brand=sony name=ILCE-1 error=- |
| ST-02 | P | SELFTEST INFO profile=none support=- crop=1.0 note=- |
| ST-03 | P | SELFTEST PASS live view fps=15 frame=640x480 |
| ST-04–ST-20 | — | probe only |
| ILCE-9M3 | P | SELFTEST INFO profile=none support=- crop=1.0 note=- |
| ILCE-7M4 | P | SELFTEST INFO profile=none support=- crop=1.0 note=- |
| ILCE-7RM5 | P | SELFTEST INFO profile=none support=- crop=1.0 note=- |
| ILCE-7M3 | P | SELFTEST INFO profile=none support=- crop=1.0 note=- |
| ILCE-7SM3 | P | SELFTEST INFO profile=none support=- crop=1.0 note=- |
| ILCE-6400 | P | SELFTEST INFO profile=none support=- crop=1.5 note=- |
| ILCE-6700 | P | SELFTEST INFO profile=none support=- crop=1.5 note=- |
| ZV-E10 | P | SELFTEST INFO profile=none support=- crop=1.5 note=- |
| ZV-E1 | P | SELFTEST INFO profile=none support=- crop=1.5 note=- |
| DSC-RX100M7 | P | SELFTEST INFO profile=none support=- crop=2.7 note=- |
| ILCE-7CM2 | P | SELFTEST INFO profile=none support=- crop=1.0 note=- |

## Findings

| ID | Sev | Check | What happens | Suggested fix |
|---|---|---|---|---|
| sony-ilce-modern-F1 | S2 | VAL-08 | The app (and README) say a7 IV, a7S III, a1, ZV-E10, a6700 and later do not offer Smart Remote to other apps, yet the app connects to any model name on a mock and has no body table: a real a1/a7 IV owner gets no up-front refusal and can start the Pro trial. | Add a Sony table with `unsupported` for 2020+ bodies (like AIR A01 for Olympus) and refuse at connect with a clear reason. |
| sony-ilce-modern-F2 | S2 | ST-02 | **ZV-E1 (full frame) gets crop 1.5**: its name starts "ZV-E", not "ILCE-7". Astro shutter is 50% too long for it. (a7C II, ILCE-7CM2, is correct at 1.0.) | Add ZV-E1 (and ZV-1, which is 1-inch) to the crop table. |

## Mockup record

No per-model screen can be recorded: the app treats any Sony as the a6000 mock. Flagship owners (a1, a9 III, a7R V) would see no live screen at all because their cameras don't offer Smart Remote; modern bodies use Creators' App / Imaging Edge Mobile.

## Value and pricing

**VAL-08 (is it clear before paying that this brand is beta / mock-only?): No.** The Connect screen shows a small flask line ("Newer in Shutterlink… please tell us") under the brand's steps, but the Add a camera list has no Beta tag, the Pro screen does not mention beta or mock-only status, and the Pro trial is offered before any connect. A user can buy Pro for a body that has only ever been tested against a mock. (`img/nikon-z6ii/add-camera-brands-no-beta-mark.png`, `pro-screen-no-beta-mention.png`)

**a1 / a9 III / a7R V owners.** The most expensive Sony bodies are exactly the ones this driver does not support. They'd read 'Sony' on the Add a camera list, start the trial and fail to connect. **Verdict: no value; a refusal is needed before the Pro screen.**

## Self-test output

```text
# sony-ILCE-1
SELFTEST PASS connect brand=sony name=ILCE-1 error=-
SELFTEST INFO profile=none support=- crop=1.0 note=-
SELFTEST PASS live view fps=15 frame=640x480
SELFTEST PASS settings read expcomp=0.0[19] focalvalue=4.0[19] isospeedvalue=auto[25] shutspeedvalue=125[53] takemode=M(ro)[1] wbvalue=0[10]
SELFTEST PASS set expcomp 0.0 → -3.0, now -3.0
SELFTEST PASS set focalvalue 4.0 → 2.8, now 2.8
SELFTEST PASS set shutspeedvalue 125 → 30", now 30"
SELFTEST PASS set isospeedvalue auto → 100, now 100
SELFTEST PASS set wbvalue 0 → 18, now 18
SELFTEST PASS tap focus afState=1
# sony-ILCE-9M3
SELFTEST PASS connect brand=sony name=ILCE-9M3 error=-
SELFTEST INFO profile=none support=- crop=1.0 note=-
SELFTEST PASS live view fps=16 frame=640x480
SELFTEST PASS settings read expcomp=0.0[19] focalvalue=4.0[19] isospeedvalue=auto[25] shutspeedvalue=125[53] takemode=M(ro)[1] wbvalue=0[10]
SELFTEST PASS set expcomp 0.0 → -3.0, now -3.0
SELFTEST PASS set focalvalue 4.0 → 2.8, now 2.8
SELFTEST PASS set shutspeedvalue 125 → 30", now 30"
SELFTEST PASS set isospeedvalue auto → 100, now 100
SELFTEST PASS set wbvalue 0 → 18, now 18
SELFTEST PASS tap focus afState=1
# sony-ILCE-7M4
SELFTEST PASS connect brand=sony name=ILCE-7M4 error=-
SELFTEST INFO profile=none support=- crop=1.0 note=-
SELFTEST PASS live view fps=15 frame=640x480
SELFTEST PASS settings read expcomp=0.0[19] focalvalue=4.0[19] isospeedvalue=auto[25] shutspeedvalue=125[53] takemode=M(ro)[1] wbvalue=0[10]
SELFTEST PASS set expcomp 0.0 → -3.0, now -3.0
SELFTEST PASS set focalvalue 4.0 → 2.8, now 2.8
SELFTEST PASS set shutspeedvalue 125 → 30", now 30"
SELFTEST PASS set isospeedvalue auto → 100, now 100
SELFTEST PASS set wbvalue 0 → 18, now 18
SELFTEST PASS tap focus afState=1
# sony-ILCE-7RM5
SELFTEST PASS connect brand=sony name=ILCE-7RM5 error=-
SELFTEST INFO profile=none support=- crop=1.0 note=-
SELFTEST PASS live view fps=15 frame=640x480
SELFTEST PASS settings read expcomp=0.0[19] focalvalue=4.0[19] isospeedvalue=auto[25] shutspeedvalue=125[53] takemode=M(ro)[1] wbvalue=0[10]
SELFTEST PASS set expcomp 0.0 → -3.0, now -3.0
SELFTEST PASS set focalvalue 4.0 → 2.8, now 2.8
SELFTEST PASS set shutspeedvalue 125 → 30", now 30"
SELFTEST PASS set isospeedvalue auto → 100, now 100
SELFTEST PASS set wbvalue 0 → 18, now 18
SELFTEST PASS tap focus afState=1
# sony-ILCE-7M3
SELFTEST PASS connect brand=sony name=ILCE-7M3 error=-
SELFTEST INFO profile=none support=- crop=1.0 note=-
SELFTEST PASS live view fps=15 frame=640x480
SELFTEST PASS settings read expcomp=0.0[19] focalvalue=4.0[19] isospeedvalue=auto[25] shutspeedvalue=125[53] takemode=M(ro)[1] wbvalue=0[10]
SELFTEST PASS set expcomp 0.0 → -3.0, now -3.0
SELFTEST PASS set focalvalue 4.0 → 2.8, now 2.8
SELFTEST PASS set shutspeedvalue 125 → 30", now 30"
SELFTEST PASS set isospeedvalue auto → 100, now 100
SELFTEST PASS set wbvalue 0 → 18, now 18
SELFTEST PASS tap focus afState=1
# sony-ILCE-7SM3
SELFTEST PASS connect brand=sony name=ILCE-7SM3 error=-
SELFTEST INFO profile=none support=- crop=1.0 note=-
SELFTEST PASS live view fps=15 frame=640x480
SELFTEST PASS settings read expcomp=0.0[19] focalvalue=4.0[19] isospeedvalue=auto[25] shutspeedvalue=125[53] takemode=M(ro)[1] wbvalue=0[10]
SELFTEST PASS set expcomp 0.0 → -3.0, now -3.0
SELFTEST PASS set focalvalue 4.0 → 2.8, now 2.8
SELFTEST PASS set shutspeedvalue 125 → 30", now 30"
SELFTEST PASS set isospeedvalue auto → 100, now 100
SELFTEST PASS set wbvalue 0 → 18, now 18
SELFTEST PASS tap focus afState=1
# sony-ILCE-6400
SELFTEST PASS connect brand=sony name=ILCE-6400 error=-
SELFTEST INFO profile=none support=- crop=1.5 note=-
SELFTEST PASS live view fps=15 frame=640x480
SELFTEST PASS settings read expcomp=0.0[19] focalvalue=4.0[19] isospeedvalue=auto[25] shutspeedvalue=125[53] takemode=M(ro)[1] wbvalue=0[10]
SELFTEST PASS set expcomp 0.0 → -3.0, now -3.0
SELFTEST PASS set focalvalue 4.0 → 2.8, now 2.8
SELFTEST PASS set shutspeedvalue 125 → 30", now 30"
SELFTEST PASS set isospeedvalue auto → 100, now 100
SELFTEST PASS set wbvalue 0 → 18, now 18
SELFTEST PASS tap focus afState=1
# sony-ILCE-6700
SELFTEST PASS connect brand=sony name=ILCE-6700 error=-
SELFTEST INFO profile=none support=- crop=1.5 note=-
SELFTEST PASS live view fps=15 frame=640x480
SELFTEST PASS settings read expcomp=0.0[19] focalvalue=4.0[19] isospeedvalue=auto[25] shutspeedvalue=125[53] takemode=M(ro)[1] wbvalue=0[10]
SELFTEST PASS set expcomp 0.0 → -3.0, now -3.0
SELFTEST PASS set focalvalue 4.0 → 2.8, now 2.8
SELFTEST PASS set shutspeedvalue 125 → 30", now 30"
SELFTEST PASS set isospeedvalue auto → 100, now 100
SELFTEST PASS set wbvalue 0 → 18, now 18
SELFTEST PASS tap focus afState=1
# sony-ZV-E10
SELFTEST PASS connect brand=sony name=ZV-E10 error=-
SELFTEST INFO profile=none support=- crop=1.5 note=-
SELFTEST PASS live view fps=15 frame=640x480
SELFTEST PASS settings read expcomp=0.0[19] focalvalue=4.0[19] isospeedvalue=auto[25] shutspeedvalue=125[53] takemode=M(ro)[1] wbvalue=0[10]
SELFTEST PASS set expcomp 0.0 → -3.0, now -3.0
SELFTEST PASS set focalvalue 4.0 → 2.8, now 2.8
SELFTEST PASS set shutspeedvalue 125 → 30", now 30"
SELFTEST PASS set isospeedvalue auto → 100, now 100
SELFTEST PASS set wbvalue 0 → 18, now 18
SELFTEST PASS tap focus afState=1
# sony-ZV-E1
SELFTEST PASS connect brand=sony name=ZV-E1 error=-
SELFTEST INFO profile=none support=- crop=1.5 note=-
SELFTEST PASS live view fps=16 frame=640x480
SELFTEST PASS settings read expcomp=0.0[19] focalvalue=4.0[19] isospeedvalue=auto[25] shutspeedvalue=125[53] takemode=M(ro)[1] wbvalue=0[10]
SELFTEST PASS set expcomp 0.0 → -3.0, now -3.0
SELFTEST PASS set focalvalue 4.0 → 2.8, now 2.8
SELFTEST PASS set shutspeedvalue 125 → 30", now 30"
SELFTEST PASS set isospeedvalue auto → 100, now 100
SELFTEST PASS set wbvalue 0 → 18, now 18
SELFTEST PASS tap focus afState=1
# sony-DSC-RX100M7
SELFTEST PASS connect brand=sony name=DSC-RX100M7 error=-
SELFTEST INFO profile=none support=- crop=2.7 note=-
SELFTEST PASS live view fps=15 frame=640x480
SELFTEST PASS settings read expcomp=0.0[19] focalvalue=4.0[19] isospeedvalue=auto[25] shutspeedvalue=125[53] takemode=M(ro)[1] wbvalue=0[10]
SELFTEST PASS set expcomp 0.0 → -3.0, now -3.0
SELFTEST PASS set focalvalue 4.0 → 2.8, now 2.8
SELFTEST PASS set shutspeedvalue 125 → 30", now 30"
SELFTEST PASS set isospeedvalue auto → 100, now 100
SELFTEST PASS set wbvalue 0 → 18, now 18
SELFTEST PASS tap focus afState=1
# sony-ILCE-7CM2
SELFTEST PASS connect brand=sony name=ILCE-7CM2 error=-
SELFTEST INFO profile=none support=- crop=1.0 note=-
SELFTEST PASS live view fps=15 frame=640x480
SELFTEST PASS settings read expcomp=0.0[19] focalvalue=4.0[19] isospeedvalue=auto[25] shutspeedvalue=125[53] takemode=M(ro)[1] wbvalue=0[10]
SELFTEST PASS set expcomp 0.0 → -3.0, now -3.0
SELFTEST PASS set focalvalue 4.0 → 2.8, now 2.8
SELFTEST PASS set shutspeedvalue 125 → 30", now 30"
SELFTEST PASS set isospeedvalue auto → 100, now 100
SELFTEST PASS set wbvalue 0 → 18, now 18
SELFTEST PASS tap focus afState=1
```
