# Conjoyn — App Icon Handoff

Final macOS app icon for **Conjoyn** ("Split recordings, made whole").
Chosen concept: **Molten weld joint — molten bridge + sparks**, Orange → Amber palette.
Two cold metal segment-ends bridged by a hot, glowing solder bead = split clips fused back into one.

---

## What's in this folder

```
export/
├─ Conjoyn-Icon-Master.svg     # 1024×1024 vector source — single source of truth, re-render any size
├─ AppIcon.appiconset/         # drop-in Xcode asset catalog (SwiftUI / AppKit)
│  ├─ Contents.json
│  └─ icon_16x16.png … icon_512x512@2x.png   (10 PNGs)
├─ Conjoyn.iconset/            # iconutil-ready set → build a .icns
│  └─ icon_16x16.png … icon_512x512@2x.png   (10 PNGs)
└─ README.md
```

All PNGs are RGBA with transparent corners outside the squircle (the standard macOS
"full-bleed 1024 canvas, 824 squircle" format). A subtle contact shadow is baked in;
the Dock adds its own drop shadow on top, as normal.

---

## Option A — Xcode / SwiftUI (recommended)

1. Copy `AppIcon.appiconset/` into your app's `Assets.xcassets/`
   (replace the existing `AppIcon.appiconset` if present).
2. In the target's **General → App Icons and Launch Screen**, set **App Icon** to `AppIcon`.
3. Build. Done.

`Contents.json` maps each filename to its `mac` idiom + scale, so the `@2x` filenames
are not load-bearing here — Xcode reads the catalog, not the names.

## Option B — Build a standalone `.icns`

From this folder:

```sh
iconutil -c icns Conjoyn.iconset
# → produces Conjoyn.icns
```

Drop `Conjoyn.icns` into your bundle and reference it via `CFBundleIconFile` in Info.plist.
(For this route the exact `icon_NxN@2x.png` names **are** required — they're preserved here.)

## Option C — Re-render from the vector master

`Conjoyn-Icon-Master.svg` is the authoritative artwork. To regenerate any size:

```sh
# requires librsvg
rsvg-convert -w 1024 -h 1024 Conjoyn-Icon-Master.svg -o icon_1024.png
```

---

## Size set (macOS)

| Catalog slot | 1x | 2x |
|---|---|---|
| 16pt  | 16   | 32   |
| 32pt  | 32   | 64   |
| 128pt | 128  | 256  |
| 256pt | 256  | 512  |
| 512pt | 512  | 1024 |

## Design spec

- **Format:** rounded-square (superellipse, n≈5) on the Big Sur grid — 824px squircle centered in 1024.
- **Background:** vertical gradient `#1B2233 → #10141F` with a radial vignette + warm halo.
- **Metal segments:** slate gradient `#3C4862 → #28303F` (the two clips being joined).
- **Molten bead / glow / sparks:** Orange → Amber `#FFC56E → #FF9A3D → #FF5E2A`, glow `#FF9646`, white-hot core.
- **Finish:** soft top-down light, inner edge shadow, faint top gloss.

## Notes / easy tweaks

- At **16–32px** the spark flecks soften (expected). If you want a crisper small end, I can
  ship simplified 16/32 variants (sparks dropped, bead fattened) and wire them into the same
  catalog slots — just ask.
- Palette is swappable: the master is parametric in the design project (cyan→blue, violet→magenta,
  teal→cyan also available) if branding shifts.
