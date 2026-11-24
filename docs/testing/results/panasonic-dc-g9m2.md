# Results: Panasonic LUMIX G9 II (mock)

Plan: [`../TEST-PLAN.md`](../TEST-PLAN.md). Result key: `P` pass · `F` fail · `UX` works, UX failure · `N/A` · `—` not run.

| | |
|---|---|
| Sheet | `panasonic-dc-g9m2` |
| Stands for | G9 II (2023, stills flagship, newer pairing) |
| Flagship | **yes** |
| Run type | Probe with `--encrypted` + profile review; full self-test for S5 IIX |
| Date | 2026-11-25 |
| Tester | Claude (Sonnet 5.5) |
| Build | test/plan worktree on main 5da84a8 (app code unchanged), Debug 1.1 (5), iPhone 17 simulator |
| Camera | Mock: `python3 -I -u mock_lumix.py --model DC-G9M2 --encrypted` |
| Self-test | `panasonic-DC-G9M2-enc`: failures=not reached (probe) |

## Checks

| ID | Result | Note |
|---|---|---|
| ST-01 | P | SELFTEST PASS connect brand=panasonic name=LUMIX G9 II error=- |
| ST-02 | P | SELFTEST INFO profile=LUMIX G9 II support=Researched, not yet tried on this camera crop=2.0 note=This body may use the newer LUMIX pairing, which is newer in Shutterlink. Since the 2025 firmware the camera's Wi-Fi always has a password, shown on the camera. |
| ST-03 | P | SELFTEST PASS live view fps=16 frame=640x480 |
| Newer pairing | P | app switched to `req_acc_g`/`req_acc_e`; connected |

## Findings

| ID | Sev | Check | What happens | Suggested fix |
|---|---|---|---|---|
| panasonic-dc-g9m2-F1 | S4 | UI-ADD-08 | Note wording "the newer LUMIX pairing, which is newer in Shutterlink" is circular, and for GH7/S5 II/S9 the profile says pairing standard while the app switches to the encrypted path by itself when the camera asks: the user is told "may use" after it already did. | Reword to "This body uses a newer LUMIX pairing that Shutterlink has not tried on a real camera." |
| panasonic-dc-g9m2-F2 | S4 (test infra) | ST-03 | The mock sends 640x480 for every model; the S5 profile promises 16:9 (640x360), so aspect-ratio handling for S5/S5 II is untested. | Make the mock send 640x360 for S5-family models. |

## Mockup record

Strip cells on the LUMIX mock (7): F-STOP, SHUT… (label truncated), ISO, EV, WB, DRIVE (icon only), QUALI… (truncated). On an iPhone 17 portrait the last two labels are cut with an ellipsis.

As G9 (High Resolution Mode cannot be started from the app) plus newer pairing. AF mode (subject detection) and Metering are in All camera settings only. Not exposed: Live View Composite, Pre-burst, High Resolution Mode.

**Live screen for this owner:** F-STOP, SHUTTER, ISO, EV, WB, QUALITY plus AF area/subject as the seventh cell; Drive read-only text (dial); a High Res chip.

## Value and pricing

**G9 II owner (stills flagship, 2023).** Closest to the user's G7 audience. Pro's Astro, Interval, Bracket, Focus stack, ND and Motion are all stills tools and genuinely useful; overlap is moderate (the G9 II has interval, focus bracketing and Live Composite). **Verdict: fair** if pairing works; the two things that sell it are Astro and Motion trigger. Missing from the app: High Resolution Mode start, subject-detect AF choice on the main screen.

## Self-test output

```text
# panasonic-DC-G9M2-enc
SELFTEST PASS connect brand=panasonic name=LUMIX G9 II error=-
SELFTEST INFO profile=LUMIX G9 II support=Researched, not yet tried on this camera crop=2.0 note=This body may use the newer LUMIX pairing, which is newer in Shutterlink. Since the 2025 firmware the camera's Wi-Fi always has a password, shown on the camera.
SELFTEST PASS live view fps=16 frame=640x480
SELFTEST PASS settings read afmode=1area[7] aspectratio=4:3[4] colormode=standard[8] colortemp=[76] creativectrl=pop(ro)[5] drivemode=normal[16] expcomp=0.0[31] filter_setting=noeffect[5] flash=forcedflashoff[3] focalvalue=2.8[21] isospeedvalue=auto[27] lightmetering=multi[3] peaking=off[3] quality=fine[5] shutspeedvalue=125[59] takemode=M(ro)[1] videoformat=mp4[2] videoquality=mp4_30p_100mbps_4k[
SELFTEST PASS set expcomp 0.0 → -5.0, now -5.0
SELFTEST PASS set focalvalue 2.8 → 1.7, now 1.7
SELFTEST PASS set shutspeedvalue 125 → 60", now 60"
SELFTEST PASS set isospeedvalue auto → i_iso, now i_iso
SELFTEST PASS set wbvalue 0 → 18, now 18
SELFTEST PASS set drivemode normal → burst|sh, now burst|sh
SELFTEST PASS set colormode standard → vivid, now vivid
SELFTEST PASS set afmode 1area → facedetection, now facedetection
SELFTEST PASS set colortemp  → 2500, now 2500
SELFTEST PASS tap focus afState=0
```
