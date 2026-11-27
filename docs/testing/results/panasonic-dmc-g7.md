# Results: Panasonic LUMIX G7 / G70 (mock)

Plan: [`../TEST-PLAN.md`](../TEST-PLAN.md). Result key: `P` pass · `F` fail · `UX` works, UX failure · `N/A` · `—` not run.

| | |
|---|---|
| Sheet | `panasonic-dmc-g7` |
| Stands for | G7 / G70 and the plain-profile LUMIX interchangeable-lens bodies (G6, GX7, GM1, GM5, GF7, GX80/GX85, G80/G85, GX9, G90/G95, G100, GH5S, BGH1, S1/S1R/S1H, GH6, G97, G100D, FZ1000 and similar) |
| Flagship | no |
| Run type | Full self-test (normal and `--sticky-drive`) + UI pass on `--sticky-drive` |
| Date | 2026-11-25 |
| Tester | Claude (Sonnet 5.5) |
| Build | test/plan worktree on main 5da84a8 (app code unchanged), Debug 1.1 (5), iPhone 17 simulator |
| Camera | Mock: `python3 -I -u mock_lumix.py --model DMC-G7 [--sticky-drive]` |
| Self-test | `panasonic-g7`: failures=0; `panasonic-g7-sticky`: failures=8 |

## Checks

| ID | Result | Note |
|---|---|---|
| ST-01–ST-20 (normal) | P | failures=0. All presets passed with "Self-timer 2 s" as the drive step. |
| ST-01–ST-20 (`--sticky-drive`) | F | failures=8: `set drivemode` FAIL ("The camera said OK but stayed on Single. Change drive on the camera."), 6 of 7 presets FAIL on the drive step ("The camera refused Self-timer 2 s"), ND setup FAIL |
| UI-REMOTE-01 | UX | 7 cells fit but SHUTTER and QUALITY labels are truncated ("SHUT…", "QUALI…"); a scene-suggestion pill ("Movement in the frame … 1/500 s") covers the lower quarter of live view and re-wraps taller when a panel opens. remote-portrait.png, drive-panel.png |
| UI-STRIP-01 | UX | Cells: F-STOP, SHUT…, ISO, EV, WB, DRIVE, QUALI…; Quality is present (Olympus has none) |
| UI-STRIP-08 | F | Drive cell is a bare square; the Drive panel offers 22 options in 1.5 tiles of height; on a body whose drive is a physical dial every option except Single is refused. Tapping one gives a clear banner ("The camera said OK but stayed on Single. Change drive on the camera."), but the panel itself should not offer what cannot work. drive-panel.png, drive-refused-banner.png |
| UI-STRIP-09 | UX | Quality panel lists Fine, Standard, RAW+Fine, RAW+Standard, RAW, 3D+Fine… (7); RAW takes. The plan's real-G7 fact "RAW locks picture size" is **not reflected**: Picture size (L 16M) stays tappable under RAW in All camera settings. quality-panel.png, settings-bottom-quality-raw.png |
| UI-MODE-02 | UX | The mock reports the mode (M, locked), so the carousel is one letter "M"; on the real G7 (mode not readable) the app must show nothing or "turn the mode dial". Not reproducible on this mock. remote-portrait.png |
| UI-REMOTE-05 | UX | The red "stayed on Single" banner persisted over the live view for over a minute while other panels (Quality) were used; it never timed out. drive-refused-banner.png |
| MENU-01 | P | Live view size, Restart live view, Scene suggestions, Save new photos to Photos, Shutterlink Pro, All camera settings, Request log, Disconnect, Turn camera off. No Sync clock, no High Res: correct for LUMIX. All items fit on one screen. menu.png |
| SET-01 | UX | Raw names again ("focalvalue · 21 options", "afmode · 11 options"). AF mode, Metering, Flash, Photo Style and Peaking live only here (3 taps from the remote screen). settings-top.png |
| PRESET-06 | F | On `--sticky-drive`: Landscape, Macro, Action show `takemode:skip` and the drive step FAILED with "The camera refused Self-timer 2 s": a refusal, not an instruction. The preset is reported as failed overall. |
| PRESET-07 | F | See PRESET-06: a preset where one step the camera cannot take ends as "failed" rather than "applied with N camera-side steps" |
| HW-04/HW-05 | — | needs the real G7 (mode dial, drive dial, EV dial) |

## Findings

| ID | Sev | Check | What happens | Suggested fix |
|---|---|---|---|---|
| panasonic-dmc-g7-F1 | S2 | PRESET-06 / ST-13 | On a body where drive cannot be changed from the phone (mock `--sticky-drive`; the real G7's physical drive dial), 6 of 7 presets and the ND setup report FAILED because one step ("The camera refused Self-timer 2 s") fails. The user sees a failure and the app suggests nothing, although every other step applied. | Detect a drive step the camera ignores (read-back differs) and turn it into a skipped step with "Turn the drive dial to the self-timer"; count the preset as applied. |
| panasonic-dmc-g7-F2 | S3 | UI-STRIP-08 | The Drive panel shows 22 options in 1.5 rows (cropped tiles, no scroll cue), and offers every option although none can take. The strip cell is a bare square. | Show Drive read-only (current value + "turn the dial") when the camera ignores changes; otherwise give the panel full height. |
| panasonic-dmc-g7-F3 | S3 | UI-STRIP-09 | Picture size stays settable while quality is RAW. The real G7 locks picture size under RAW, so the user can change a setting the camera ignores or refuses. (The mock does not model the lock either.) | Lock Picture size under RAW and say "RAW ignores picture size"; model it in the mock. |
| panasonic-dmc-g7-F4 | S4 | UI-REMOTE-01 | "SHUT…" and "QUALI…" are truncated on an iPhone 17 portrait strip of 7 cells. | Shorten to SHTR and QUAL, or use two-line labels. |
| panasonic-dmc-g7-F5 | S3 | SET-01 / MODEL-06 | AF mode, Metering, Photo Style and Flash are shot-to-shot settings for a G7 user but live 3 taps deep in All camera settings. | Promote AF mode and Metering to a Tier 2 cell or a Tools tile. |
| panasonic-dmc-g7-F6 | S4 | UI-REMOTE-05 | Error banner never dismisses itself and stays through other actions. | Auto-dismiss after ~8 s or on the next successful action. |

## Mockup record

Strip cells on the LUMIX mock (7): F-STOP, SHUT… (label truncated), ISO, EV, WB, DRIVE (icon only), QUALI… (truncated). On an iPhone 17 portrait the last two labels are cut with an ellipsis.

**Real G7 facts (from the brief, not the mock):** the mode dial (P/A/S/M) and the drive dial cannot be read or changed over Wi-Fi; quality RAW locks picture size. The mock (`DMC-G7`) serves the real G7's menu, so settings are real; it reports a mode (M) that the real camera would not.

| Camera setting (mock list) | Where in the app |
|---|---|
| focalvalue, shutspeedvalue, isospeedvalue, expcomp, wbvalue | strip |
| drivemode (22) | strip (icon only) |
| quality (7) | strip |
| afmode (11), lightmetering (3), colormode/Photo Style (9), filter_setting (23), creativectrl (22, read-only), flash (6), peaking (3), aspectratio (4), pictsize (11), colortemp (76 Kelvin steps), videoformat (2), videoquality (18) | All camera settings only |
| takemode | read-only indicator (mock) |

**Should be on the live screen for this model:** F-STOP, SHUTTER, ISO, EV, WB, QUALITY, plus AF mode or Metering as a seventh cell; DRIVE shown read-only with a one-word label (the dial is physical); the mode as a read-only chip "Mode: turn the dial" when the camera does not report it.

**Gaps (camera can, app doesn't):** the G7 menu lists Photo Style, Filter, Creative Control, flash, aspect ratio, picture size and video format: all are reachable (All camera settings) but none is promoted. Not exposed: Focus peaking colour, 4K photo mode via the drive list is available only through Drive (22 options).

## Value and pricing

**Pro on a G7** (inferred from the mock): Presets Part (any preset with a drive or mode step needs camera-side action and currently reports FAILED, see F1), Astro Part (mode dial), Star trails Full (interval series of 30 s frames), Interval Full, Bracket Full in EV, Focus stack Full (camera in MF), ND filter Full (Bulb), Expose to the right Part, Motion trigger Full, High Res N/A, Watch remote not run. **Full ≈ 6, Part ≈ 3, None 0.**

**Verdict: fair, but the first impression is rough.** The G7 is the user's own body: the most convincing demo (focus stacking and intervals on a camera that has neither on its own menus) sits next to a Presets screen that shows red failures because of a physical dial. Fix F1 and the $9.99 reads as clearly worth it; as it is a G7 owner starts the trial, taps Astro, and sees "refused".

## Self-test output

```text
# panasonic-g7
SELFTEST PASS connect brand=panasonic name=LUMIX G7 / G70 error=-
SELFTEST INFO profile=LUMIX G7 / G70 support=Researched, not yet tried on this camera crop=2.0 note=-
SELFTEST PASS live view fps=15 frame=640x480
SELFTEST PASS settings read afmode=1area[11] aspectratio=4:3[4] colormode=standard[9] colortemp=[76] creativectrl=pop(ro)[22] drivemode=normal[22] expcomp=0.0[31] filter_setting=noeffect[23] flash=forcedflashoff[6] focalvalue=2.8[21] isospeedvalue=auto[27] lightmetering=multi[3] peaking=off[3] pictsize=16m[11] quality=fine[7] shutspeedvalue=125[59] takemode=M(ro)[1] videoformat=mp4[2] videoquality
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
SELFTEST PASS shoot
SELFTEST PASS movie
SELFTEST PASS interval shots=2
SELFTEST PASS bracket shots=3
SELFTEST PASS focus stack shots=3
SELFTEST PASS sky positions sun 62.0° (≈62), full 1.00, new 0.00
SELFTEST PASS scene rules night=astro moon=moon water=water-nd bird=bird clipping=["clipping"]
SELFTEST PASS scene analysis  suggestion=-
SELFTEST PASS preset astro takemode=M focalvalue=F1.7 shutspeedvalue=8" isospeedvalue=1600 wbvalue=Incandescent drivemode=Self-timer 2 s
SELFTEST PASS preset moon takemode=M focalvalue=F8.0 shutspeedvalue=1/250 isospeedvalue=200 wbvalue=Sunny drivemode=Self-timer 2 s
SELFTEST PASS preset fireworks takemode=M focalvalue=F8.0 shutspeedvalue=4" isospeedvalue=100 wbvalue=Sunny drivemode=Self-timer 2 s
SELFTEST PASS preset landscape takemode:skip focalvalue=F8.0 isospeedvalue=100 expcomp=±0.0 drivemode=Self-timer 2 s
SELFTEST PASS preset action takemode:skip shutspeedvalue=1/1000 isospeedvalue=Auto expcomp=±0.0 drivemode:skip
SELFTEST PASS preset macro takemode:skip focalvalue=F8.0 isospeedvalue=100 expcomp=±0.0 drivemode=Self-timer 2 s
SELFTEST PASS preset trails takemode=M focalvalue=F11 shutspeedvalue=15" isospeedvalue=100 drivemode=Self-timer 2 s
SELFTEST PASS saved preset 6 values: focalvalue=F11 shutspeedvalue=15" isospeedvalue=100 expcomp=±0.0 wbvalue=Sunny drivemode=Self-timer 2 s
SELFTEST PASS nd setup metered 15.0s → 960.0s, shutter now bulb
SELFTEST PASS motion trigger shots=1 peak=0.0195 threshold=0.01
SELFTEST PASS ettr ev 0.0 → 0.0 Live view doesn't get brighter with the exposure, so the highlights can't be judged. Turn off Live View Boost (or exposure preview) on the camera and try again.
SELFTEST PASS battery 100%
SELFTEST PASS card list 102 files in ["LUMIX G7 / G70"]
SELFTEST PASS thumbnail P0001060.JPG
SELFTEST PASS preview 640x480
SELFTEST PASS download P0001060.JPG 25246 bytes
SELFTEST PASS download RAW P0001060.RW2 4000000 bytes
SELFTEST PASS live view after card fps=15
SELFTEST DONE failures=0
# panasonic-g7-sticky
SELFTEST PASS connect brand=panasonic name=LUMIX G7 / G70 error=-
SELFTEST INFO profile=LUMIX G7 / G70 support=Researched, not yet tried on this camera crop=2.0 note=-
SELFTEST PASS live view fps=15 frame=640x480
SELFTEST PASS settings read afmode=1area[11] aspectratio=4:3[4] colormode=standard[9] colortemp=[76] creativectrl=pop(ro)[22] drivemode=normal[22] expcomp=0.0[31] filter_setting=noeffect[23] flash=forcedflashoff[6] focalvalue=2.8[21] isospeedvalue=auto[27] lightmetering=multi[3] peaking=off[3] pictsize=16m[11] quality=fine[7] shutspeedvalue=125[59] takemode=M(ro)[1] videoformat=mp4[2] videoquality
SELFTEST PASS set expcomp 0.0 → -5.0, now -5.0
SELFTEST PASS set focalvalue 2.8 → 1.7, now 1.7
SELFTEST PASS set shutspeedvalue 125 → 60", now 60"
SELFTEST PASS set isospeedvalue auto → i_iso, now i_iso
SELFTEST PASS set wbvalue 0 → 18, now 18
SELFTEST FAIL set drivemode normal → burst|sh, now normal The camera said OK but stayed on Single. Change drive on the camera.
SELFTEST PASS set colormode standard → vivid, now vivid
SELFTEST PASS set afmode 1area → facedetection, now facedetection
SELFTEST PASS set colortemp  → 2500, now 2500
SELFTEST PASS tap focus afState=0
SELFTEST PASS shoot
SELFTEST PASS movie
SELFTEST PASS interval shots=2
SELFTEST PASS bracket shots=3
SELFTEST PASS focus stack shots=3
SELFTEST PASS sky positions sun 62.0° (≈62), full 1.00, new 0.00
SELFTEST PASS scene rules night=astro moon=moon water=water-nd bird=bird clipping=["clipping"]
SELFTEST PASS scene analysis  suggestion=-
SELFTEST FAIL preset astro takemode=M focalvalue=F1.7 shutspeedvalue=8" isospeedvalue=1600 wbvalue=Incandescent drivemode:FAILED(The camera refused Self-timer 2 s)
SELFTEST FAIL preset moon takemode=M focalvalue=F8.0 shutspeedvalue=1/250 isospeedvalue=200 wbvalue=Sunny drivemode:FAILED(The camera refused Self-timer 2 s)
SELFTEST FAIL preset fireworks takemode=M focalvalue=F8.0 shutspeedvalue=4" isospeedvalue=100 wbvalue=Sunny drivemode:FAILED(The camera refused Self-timer 2 s)
SELFTEST FAIL preset landscape takemode:skip focalvalue=F8.0 isospeedvalue=100 expcomp=±0.0 drivemode:FAILED(The camera refused Self-timer 2 s)
SELFTEST PASS preset action takemode:skip shutspeedvalue=1/1000 isospeedvalue=Auto expcomp=±0.0 drivemode:skip
SELFTEST FAIL preset macro takemode:skip focalvalue=F8.0 isospeedvalue=100 expcomp=±0.0 drivemode:FAILED(The camera refused Self-timer 2 s)
SELFTEST FAIL preset trails takemode=M focalvalue=F11 shutspeedvalue=15" isospeedvalue=100 drivemode:FAILED(The camera refused Self-timer 2 s)
SELFTEST PASS saved preset 6 values: focalvalue=F11 shutspeedvalue=15" isospeedvalue=100 expcomp=±0.0 wbvalue=Sunny drivemode=Single
SELFTEST FAIL nd setup metered 15.0s → 960.0s, shutter now bulb
SELFTEST PASS motion trigger shots=1 peak=0.0208 threshold=0.01
SELFTEST PASS ettr ev 0.0 → 0.0 Live view doesn't get brighter with the exposure, so the highlights can't be judged. Turn off Live View Boost (or exposure preview) on the camera and try again.
SELFTEST PASS battery 100%
SELFTEST PASS card list 102 files in ["LUMIX G7 / G70"]
SELFTEST PASS thumbnail P0001060.JPG
SELFTEST PASS preview 640x480
SELFTEST PASS download P0001060.JPG 25246 bytes
SELFTEST PASS download RAW P0001060.RW2 4000000 bytes
SELFTEST PASS live view after card fps=15
SELFTEST DONE failures=8
```
