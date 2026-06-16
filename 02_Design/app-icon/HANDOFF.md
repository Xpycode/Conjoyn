# Conjoyn — App Icon Handoff

Final macOS app icon for **Conjoyn** ("Split recordings, made whole").
Concept: **Molten weld joint** — two cold slate segment-ends bridged by a hot, glowing
solder bead = split clips fused back into one. Orange → Amber palette.

Ships in **two appearances** that share identical geometry — only the surround changes,
so the molten seam reads as the same object in both:

| | Background | Join tiles | Seam / sparks |
|---|---|---|---|
| **Dark** (default) | navy `#1B2233 → #10141F` | slate `#3C4862 → #28303F` | Orange→Amber `#FFC56E → #FF5E2A` |
| **Light** (reverse) | cool white `#FCFDFF → #E6EBF4` | light slate `#DEE4EF → #C3CCDC` | *unchanged* — the brand constant |

---

## What's in this folder

```
export/
├─ Conjoyn-Icon-Master.svg          # DARK  — 1024×1024 vector source (single source of truth)
├─ Conjoyn-Icon-Master-Light.svg    # LIGHT — 1024×1024 vector source
│
├─ AppIcon.appiconset/              # DARK  — drop-in Xcode asset catalog
│  ├─ Contents.json
│  └─ icon_16x16.png … icon_512x512@2x.png      (10 PNGs)
├─ AppIcon-Light.appiconset/        # LIGHT — drop-in Xcode asset catalog
│  ├─ Contents.json
│  └─ icon_16x16.png … icon_512x512@2x.png      (10 PNGs)
│
├─ Conjoyn.iconset/                 # DARK  — iconutil-ready → .icns
├─ Conjoyn-Light.iconset/           # LIGHT — iconutil-ready → .icns
│
├─ icon-lightmode-preview.html      # side-by-side comparison (open in a browser)
└─ HANDOFF.md                       # this file
```

All PNGs are RGBA with transparent corners outside the squircle (the standard macOS
"full-bleed 1024 canvas, 824 squircle" format). A subtle contact shadow is baked in; the
Dock adds its own drop shadow on top, as normal.

---

## Option A — Xcode / SwiftUI (recommended)

**Single appearance:** copy the appiconset you want into `Assets.xcassets/`, then set the
target's **App Icon** to it in **General → App Icons and Launch Screen**.

**Both appearances (light + dark) in one catalog:** in Xcode, select the `AppIcon` image
set → Attributes inspector → **Appearances: Any, Dark**. Drop the **Light** PNGs in the
"Any Appearance" wells and the **Dark** PNGs in the "Dark" wells. macOS then swaps
automatically with the system theme. (Each appiconset here is already a complete set for
its appearance — you're just filling the two columns from the two folders.)

`Contents.json` maps each filename to its `mac` idiom + scale, so the `@2x` filenames are
not load-bearing on this route — Xcode reads the catalog, not the names.

## Option B — Build a standalone `.icns`

```sh
iconutil -c icns Conjoyn.iconset        # → Conjoyn.icns        (dark)
iconutil -c icns Conjoyn-Light.iconset  # → Conjoyn-Light.icns  (light)
```

Drop the `.icns` into your bundle and reference it via `CFBundleIconFile` in Info.plist.
(For this route the exact `icon_NxN@2x.png` names **are** required — they're preserved here.)

## Option C — Re-render from the vector masters

The two `*.svg` files are the authoritative artwork. To regenerate any size:

```sh
# requires librsvg
rsvg-convert -w 1024 -h 1024 Conjoyn-Icon-Master.svg       -o icon_dark_1024.png
rsvg-convert -w 1024 -h 1024 Conjoyn-Icon-Master-Light.svg -o icon_light_1024.png
```

---

## Size set (macOS, both appearances)

| Catalog slot | 1x | 2x |
|---|---|---|
| 16pt  | 16   | 32   |
| 32pt  | 32   | 64   |
| 128pt | 128  | 256  |
| 256pt | 256  | 512  |
| 512pt | 512  | 1024 |

## Design spec

- **Format:** rounded-square (superellipse, n≈5) on the Big Sur grid — 824px squircle centered in 1024.
- **Geometry is identical across both appearances** — only background, tiles, shadow and vignette change.
- **Molten bead / glow / sparks (shared):** Orange → Amber `#FFC56E → #FF9A3D → #FF5E2A`, glow `#FF9646`, white-hot core.
- **Dark finish:** soft top-down light, dark radial vignette, faint white top gloss, deep contact shadow (`#000 @ 45%`).
- **Light finish:** brighter white top gloss, soft cool vignette (`#6B7488 @ 14%`), light contact shadow (`#3A445C @ 18%`).

## Notes

- At **16–32px** the spark flecks soften in both appearances (expected). I can ship simplified
  16/32 variants (sparks dropped, bead fattened) wired into the same catalog slots if you want a
  crisper small end — just ask.
- The molten seam stays constant by design: it's the identity. If branding ever shifts, both
  masters are parametric in the design project (cyan→blue, violet→magenta, teal→cyan available).
