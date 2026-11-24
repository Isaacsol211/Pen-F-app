# Test results: Olympus / OM System, Panasonic LUMIX, Nikon, Canon, Sony

Mock-camera runs of [`../TEST-PLAN.md`](../TEST-PLAN.md) on the iPhone 17 simulator, 2026-11-25, against `main` 5da84a8 (app code unchanged). **Nothing here was run on a real camera**; "tested" means the app's side against a mock, with the mock's `--model` choosing which `ModelProfiles.swift` entry applies.

Flagship bodies (the likeliest paying customers) are marked **★**. Their sheets carry the extra weight on value (`VAL-01`…`VAL-10`).

How to read the sheets: `olympus-pen-f.md` and `panasonic-dmc-g7.md` are the two deep runs (UI driven by hand, screenshots in `img/`). Every other sheet is a short run (connect, profile, live view and, where marked, the full self-test) plus the model's value and mockup record.

## Olympus / OM System (35 bodies in the table)

A "group" is every body whose profile (notes, High Res flag, support level) is the same.

| Group | Bodies in the table | Tested as | Sheet |
|---|---|---|---|
| Tried on hardware, High Res | PEN-F | PEN-F (full self-test + UI) | [olympus-pen-f](olympus-pen-f.md) |
| High Res, no note | E-M5 Mark II, E-M5 Mark III, E-M1 Mark II | E-M1 Mark II (full), E-M5 Mark II (probe) | [olympus-e-m1-mark-ii](olympus-e-m1-mark-ii.md) |
| Note: Private Wi-Fi, no movie | E-M1 | E-M1 (probe) | [olympus-e-m1](olympus-e-m1.md) |
| ★ Note: other apps may be limited | E-M1X ★, E-M1 Mark III ★ | E-M1X, E-M1 Mark III (probes) | [olympus-e-m1x](olympus-e-m1x.md) |
| Note: limited Wi-Fi settings | E-M10 Mark IV | E-M10 Mark IV (full) | [olympus-e-m10-mark-iv](olympus-e-m10-mark-iv.md) |
| OM System note + High Res | OM-1, OM-5, OM-1 Mark II ★, OM-3 ★, OM-5 Mark II | OM-1 (full); OM-1 Mark II, OM-3 (probes) | [olympus-om-1](olympus-om-1.md), [olympus-om-1-mark-ii](olympus-om-1-mark-ii.md), [olympus-om-3](olympus-om-3.md) |
| OM System note, no High Res | TG-7 | TG-7 (probe) | [olympus-om-1](olympus-om-1.md) |
| Plain (no note, no High Res) | E-P5, Stylus 1/1s, E-M10, SH-1, TG-3, E-PL7, SH-2, TG-4, TG-860/870, E-M10 Mark II, E-M10 Mark III, SH-3, E-PL8, TG-5, E-PL9, TG-6, E-PL10, E-P7 | TG-6 (full); Stylus 1, E-M10 Mark III, E-PL10 (probes) | [olympus-tg-6](olympus-tg-6.md) |
| Unsupported | AIR A01, TG-Tracker | both (connect) | [olympus-air-a01](olympus-air-a01.md) |
| Not in the table | any other body | "E-XYZ9" | [olympus-unknown](olympus-unknown.md) |

Olympus bodies in the table that were **not** run themselves: E-P5, E-M10, E-M10 Mark II, E-PL7/8/9/7 (E-P7), SH-1/2/3, TG-3/4/5, TG-860/870, E-M5 Mark III, OM-5, OM-5 Mark II: each stands for its group above, because the mock gives every Olympus name the same camera and only the profile differs.

## Panasonic LUMIX (about 60 bodies in the table)

| Group (profile flag) | Bodies | Tested as | Sheet |
|---|---|---|---|
| Plain, interchangeable lens | G6, GX7, GM1/GM1S, GM5, G7/G70, GF7, GX80/GX85/GX7 II, G80/G85/G81, GF8, GF9/GX800/GX850, GH5S, GX9/GX7 III, GF10/GF90, G90/G95/G91, G100/G110, BGH1, G97, G100D, FZ1000, FZ1000 II, FZ2000/FZ2500, FZ300/FZ330 | **G7** (full + `--sticky-drive` + UI) | [panasonic-dmc-g7](panasonic-dmc-g7.md) |
| Plain, "tested on this camera" label (mismatch) | GH5 | GH5 (full) | [panasonic-dc-gh5](panasonic-dc-gh5.md) |
| Note: High Resolution Mode | G9 | G9 (full) | [panasonic-dc-g9](panasonic-dc-g9.md) |
| No pairing step | GH3, GH4 | GH3, GH4 (probes) | [panasonic-dmc-gh3-gh4](panasonic-dmc-gh3-gh4.md) |
| Physical EV dial (`noExposureComp`) | GX8 | GX8 (probe) | [panasonic-dmc-gx8](panasonic-dmc-gx8.md) |
| Physical aperture, shutter and EV (`fixedExposure`+`noExposureComp`) | LX100 (LX100 II, LX10/LX15 have no flags) | LX100 (probe) | [panasonic-dmc-lx100](panasonic-dmc-lx100.md) |
| Fixed exposure compacts | TZ60/ZS40, TZ55/ZS35 (no video), SZ8 (no video), SZ10 (no video), FT7/TS7 (note) | TZ60, TZ55, FT7 (probes) | [panasonic-dmc-tz60-tz55-ft7](panasonic-dmc-tz60-tz55-ft7.md) |
| No ISO from the phone | GF6, LF1, TZ70/ZS50 | GF6, TZ70 (probes) | [panasonic-dmc-gf6-tz70](panasonic-dmc-gf6-tz70.md) |
| 16:9 live view / plain full frame | S5, S1/S1R/S1H | S5, S1 (probes) | [panasonic-dc-s5](panasonic-dc-s5.md) |
| Password note | GH5 II | GH5 II (probe) | [panasonic-dc-gh5m2](panasonic-dc-gh5m2.md) |
| ★ Newer pairing (profile `.newer`) | S5 IIX ★, G9 II ★ | S5 IIX (full, `--encrypted`), G9 II (probe) | [panasonic-dc-s5m2x](panasonic-dc-s5m2x.md), [panasonic-dc-g9m2](panasonic-dc-g9m2.md) |
| ★ Newer-pairing note, profile standard | S5 II ★, GH7 ★, S9 | all three (probes, `--encrypted`; GH7 also plain) | [panasonic-dc-s5m2x](panasonic-dc-s5m2x.md), [panasonic-dc-gh7](panasonic-dc-gh7.md) |
| Plain flagship video | GH6 ★ | GH6 (probe) | [panasonic-dc-gh7](panasonic-dc-gh7.md) |
| Lab/Flow era | S1 II, S1R II, L10 | S1 II (probe, `--encrypted`) | [panasonic-dc-s1m2](panasonic-dc-s1m2.md) |
| Not tested | TS5/FT5, TZ40/ZS30, FZ70/FZ72, TZ57/ZS45, TZ80/ZS60, TZ90/ZS70, TZ95/ZS80, TZ99/ZS99, TZ100/ZS100, TZ200/ZS200, FZ80/FZ82, LX100 II, LX10/LX15, GH5 II etc. | each is in the "Plain compact" or flagged group above; the mock gives every LUMIX the same menu, so only the profile flag differs | – |

## Nikon, Canon, Sony (beta brands, no model table in the app)

`ModelProfiles.swift` has no Nikon/Canon/Sony entries, so the only per-model logic is the crop factor worked out from the reported name. The repo mocks always report one body (Z 6II or D750, EOS R6, ILCE-6000); to test other names I ran **scratch copies** of the mocks that read the reported name from an environment variable (repo mocks unchanged). Probes check connect, live view and crop factor only.

| Brand | Group | Bodies | Tested as | Sheet |
|---|---|---|---|---|
| Nikon | Z mirrorless | Z 5, Z 6/6II, Z 7/7II, Z 50, Z fc, Z 30 | Z 6II (full + UI), Z 5, Z 50, Z fc, Z 7II (probes) | [nikon-z6ii](nikon-z6ii.md) |
| Nikon | ★ flagship Z | Z 8 ★, Z 9 ★, Z 6III ★, Z f ★ | all four (probes) | [nikon-z8-z9](nikon-z8-z9.md) |
| Nikon | DSLR | D750, D850, D7200 | D750 (full), D850, D7200 (probes) | [nikon-d750](nikon-d750.md) |
| Canon | CCAPI mirrorless | R, RP, R6, R7, R8, R10, R50, 90D | R6 (full + UI), R7, R10, R50, R8, RP, 90D (probes) | [canon-eos-r6](canon-eos-r6.md) |
| Canon | ★ flagship | R5 ★, R3 ★, R6 II ★, R1 ★, R5 II ★ | all (probes, incl. "R6m2"/"R5m2" spellings) | [canon-eos-r5-r3-r6m2](canon-eos-r5-r3-r6m2.md) |
| Sony | Smart Remote era | a6000, a6300, a7 II, a9, RX100 | a6000 (full + UI) | [sony-a6000](sony-a6000.md) |
| Sony | modern / ★ flagship | a7 III/IV, a7R V, a1 ★, a9 III ★, a7S III, ZV-E10, ZV-E1, a6400, a6700, a7C II, RX100 VII | all (probes) | [sony-ilce-modern](sony-ilce-modern.md) |

Not run: Nikon Z 30, D3xxx/D5xxx; Canon M-series, G-series, 250D/850D, PowerShot; Sony a6100/a6300/RX10; each falls into the nearest group above.

### Worst problems per beta brand

- **Nikon:** nothing before Pro says it is beta or mock-only (Pro screen, Add a camera list have no Beta tag); no Drive/Quality cell, so burst and RAW can't be chosen from the phone; every preset skips Drive without telling the user what to set on the camera. A Z 8/Z 9 owner gets almost no new value.
- **Canon:** switching brand in Add a camera keeps the previous brand's address (Canon tried the Nikon port); the resulting 12-line error banner covers the sheet's brand list and address field, survives Cancel and shows on the home screen; WB shows the raw code `awb_white`; if the camera reports "R6m2"/"R5m2" the crop factor is wrong (1.6) and Astro shutters come out ~60% too long.
- **Sony:** the Action preset FAILS ("camera refused 1/1000 … mode dial on S?"), the same pattern as the LUMIX G7 drive failure; the app connects to any Sony model name and gives modern bodies (a1, a7 IV, a9 III, a7R V, ZV-E10, a6700) no refusal before Pro; ZV-E1 (full frame) gets crop 1.5.
- **All three (VAL-08):** it is **not** clear before paying that these brands are beta and mock-only. The Connect screen has a small flask line; the Pro screen and trial prompt say nothing.

## Worst problems across Olympus and LUMIX

1. **LUMIX G7 presets report FAILED when the drive dial cannot be changed.** On `--sticky-drive` six of seven presets and the ND setup end as failed with "The camera refused Self-timer 2 s": a refusal, not an instruction (`panasonic-dmc-g7` F1). This is the real G7's situation and the first thing a G7 owner sees.
2. **Bracketing on fixed-exposure compacts (TZ55 and friends) fails with a self-contradictory message** "The shutter speed is locked in M. Use S or M…" instead of falling back to EV (`panasonic-dmc-tz60-tz55-ft7` F1).
3. **The Olympus and LUMIX Drive panel crops 12 to 22 options into 1.5 rows**, and the Drive cell is a bare icon on every body (`olympus-pen-f` F3/F4, `panasonic-dmc-g7` F2).
4. **Presets that are "on" are invisible on the remote screen and are forgotten if the app restarts** (`olympus-pen-f` F5).
5. **One unreproduced hang/termination** while a sheet was opening after Astro (`olympus-pen-f` F1).
6. Several body-specific warnings (OM System, E-M1X/III, S1 II, S5 II/IIX/GH7 pairing) appear only after connecting, i.e. after a user may already have started the trial or bought Pro.
7. **GH5 says "Tested on this camera"** while the README says mock only (`panasonic-dc-gh5` F1).

## Value, flagships

| Flagship | Pro verdict at $9.99 | Why |
|---|---|---|
| OM-1 Mark II ★, OM-3 ★ | a stretch until a real body connects, then fair | camera already has intervalometer, Live ND, focus stacking, Live Composite; newer protocol unconfirmed |
| E-M1X ★, E-M1 Mark III ★ | a stretch for pros, fair for enthusiasts | "other apps may be limited" note; highest overlap with in-camera features |
| S5 II / S5 IIX ★ | a stretch | hybrid bodies with in-camera interval/focus bracketing; video setup buried |
| GH7 ★ / GH6 ★ | poor | video bodies, Pro is a stills package |
| G9 II ★ | fair | stills flagship; Astro, Motion and Focus stack are new to them; High Res not startable |
| G7 (own body) | fair, once FAILED presets are fixed | best demo of focus stack and interval |

None of these verdicts is confirmed on a real body.
