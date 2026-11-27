# Results: Panasonic LUMIX GH7 and GH6 (mock)

Plan: [`../TEST-PLAN.md`](../TEST-PLAN.md). Result key: `P` pass · `F` fail · `UX` works, UX failure · `N/A` · `—` not run.

| | |
|---|---|
| Sheet | `panasonic-dc-gh7` |
| Stands for | GH7 (2024, flagship video); GH6 (2022) probed as plain |
| Flagship | **yes** |
| Run type | Probe with `--encrypted` + profile review; full self-test for S5 IIX |
| Date | 2026-11-25 |
| Tester | Claude (Sonnet 5.5) |
| Build | test/plan worktree on main 5da84a8 (app code unchanged), Debug 1.1 (5), iPhone 17 simulator |
| Camera | Mock: `python3 -I -u mock_lumix.py --model DC-GH7 --encrypted (and DC-GH6)` |
| Self-test | `panasonic-DC-GH7-enc`: failures=not reached (probe); `panasonic-DC-GH7-plain`: failures=not reached (probe); `panasonic-DC-GH6`: failures=not reached (probe) |

## Checks

| ID | Result | Note |
|---|---|---|
| ST-01 | P | SELFTEST PASS connect brand=panasonic name=LUMIX GH7 error=- |
| ST-02 | P | SELFTEST INFO profile=LUMIX GH7 support=Researched, not yet tried on this camera crop=2.0 note=This body may use the newer LUMIX pairing, which is newer in Shutterlink. Since the 2025 firmware the camera's Wi-Fi always has a password, shown on the camera. |
| ST-03 | P | SELFTEST PASS live view fps=16 frame=640x480 |
| Newer pairing | P | app switched to `req_acc_g`/`req_acc_e`; connected |

## Findings

| ID | Sev | Check | What happens | Suggested fix |
|---|---|---|---|---|
| panasonic-dc-gh7-F1 | S4 | UI-ADD-08 | Note wording "the newer LUMIX pairing, which is newer in Shutterlink" is circular, and for GH7/S5 II/S9 the profile says pairing standard while the app switches to the encrypted path by itself when the camera asks: the user is told "may use" after it already did. | Reword to "This body uses a newer LUMIX pairing that Shutterlink has not tried on a real camera." |
| panasonic-dc-gh7-F2 | S4 (test infra) | ST-03 | The mock sends 640x480 for every model; the S5 profile promises 16:9 (640x360), so aspect-ratio handling for S5/S5 II is untested. | Make the mock send 640x360 for S5-family models. |

## Mockup record

Strip cells on the LUMIX mock (7): F-STOP, SHUT… (label truncated), ISO, EV, WB, DRIVE (icon only), QUALI… (truncated). On an iPhone 17 portrait the last two labels are cut with an ellipsis.

Video format and Video quality are in All camera settings only; no recording timer/format chip on the remote screen; shutter angle and ISO dual-native are not in the strip. GH6/GH7 are video bodies: the Video switch is a Tools tile (2 taps) rather than a mode on the carousel.

**Live screen for this owner:** in video mode replace SHUTTER with shutter angle, show a REC chip with time left on the card and the format chip; hide Drive and Quality (stills) behind the photo switch.

## Value and pricing

**GH7 / GH6 owner (video flagship).** The owner shoots video: the app's remote is useful, but Pro (Astro, Interval, Bracket, ND, Motion, High Res) is a **stills** package. The GH7 has in-camera interval/time-lapse, Live View Composite and 32-bit float, none of which the app drives. **Verdict: poor value ($9.99 buys almost nothing for a video shooter)** unless the Apple Watch remote and the free tier's video start/stop are what they need, in which case Pro is not needed. What would make it worth it: video-specific Pro tools (shot presets by codec, rec-length timer, auto-record on motion).

## Self-test output

```text
# panasonic-DC-GH7-enc
SELFTEST PASS connect brand=panasonic name=LUMIX GH7 error=-
SELFTEST INFO profile=LUMIX GH7 support=Researched, not yet tried on this camera crop=2.0 note=This body may use the newer LUMIX pairing, which is newer in Shutterlink. Since the 2025 firmware the camera's Wi-Fi always has a password, shown on the camera.
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
# panasonic-DC-GH7-plain
SELFTEST PASS connect brand=panasonic name=LUMIX GH7 error=-
SELFTEST INFO profile=LUMIX GH7 support=Researched, not yet tried on this camera crop=2.0 note=This body may use the newer LUMIX pairing, which is newer in Shutterlink. Since the 2025 firmware the camera's Wi-Fi always has a password, shown on the camera.
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
# panasonic-DC-GH6
SELFTEST PASS connect brand=panasonic name=LUMIX GH6 error=-
SELFTEST INFO profile=LUMIX GH6 support=Researched, not yet tried on this camera crop=2.0 note=-
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
