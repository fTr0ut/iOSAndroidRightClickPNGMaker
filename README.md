# IconRightClick — Prepare Mobile Store Images from a PNG

Right-click any `.png` in Windows Explorer and generate **Android-** and **iOS-compliant**
app icon sets or resize screenshots for **App Store Connect** and **Google Play Console**,
following current (2026) Google and Apple guidance.

The tool works from a **single flat PNG** — an exported logo or a full-bleed image.
You do **not** need layered artwork or separate foreground/background files. Everything
(iOS light/dark/tinted, the Android adaptive foreground, background color, and the
monochrome/themed layer) is derived automatically from that one image. Layered authoring
(Apple's Icon Composer, hand-built adaptive layers) is optional polish, not a requirement
for this tool.

---

## Requirements

- **Windows 10/11**, Windows PowerShell 5.1 (built in).
- **ImageMagick** (`magick`). Install with:
  ```powershell
  winget install --id ImageMagick.ImageMagick -e --accept-source-agreements --accept-package-agreements
  ```
  The generator finds `magick` on `PATH`, and if it isn't there it falls back to
  `C:\Program Files\ImageMagick*\magick.exe`.

---

## Usage

### From the right-click menu (after installing — see below)

1. Right-click a `.png` file in Explorer.
2. On **Windows 11**, click **"Show more options"** (or press **Shift+F10**) to open the
   classic context menu.
3. Choose either **"Generate Mobile App Icons"** or one of the
   **"Resize Screenshot - ..."** commands.
4. A console window shows progress, then Explorer opens to the output.

> **Windows 11 caveat (by design):** this entry appears in the **classic** ("Show more
> options" / Shift+F10) menu, **not** the new compact Windows 11 menu. Adding items to the
> new menu requires a packaged **MSIX shell extension (`IExplorerCommand`)**, which is out
> of scope for a lightweight per-user script tool. The classic menu is 100% functional and
> needs no administrator rights.

### From the command line

```powershell
.\Make-MobileIcons.ps1 -Path "C:\path\to\logo.png"

# Screenshot orientation follows the source automatically.
.\Resize-StoreScreenshot.ps1 -Path "C:\path\to\screenshot.png" -Preset Apple-iPhone-1284x2778
.\Resize-StoreScreenshot.ps1 -Path "C:\path\to\screenshot.png" -Preset GooglePlay-1080x1920
```

- Both scripts require `-Path <string>` and support `-NoInteractive` for automation.
- `Resize-StoreScreenshot.ps1` also requires one of the documented `-Preset` values.

---

## Screenshot resize presets

The classic right-click menu provides these resize commands. Each label shows its portrait
canvas; a landscape source automatically receives the reversed dimensions.

| Menu preset | Portrait output | Landscape output |
| --- | ---: | ---: |
| Apple iPhone — 1242 x 2688 | 1242 x 2688 | 2688 x 1242 |
| Apple iPhone — 1284 x 2778 | 1284 x 2778 | 2778 x 1284 |
| Apple iPad — 2064 x 2752 | 2064 x 2752 | 2752 x 2064 |
| Apple iPad — 2048 x 2732 | 2048 x 2732 | 2732 x 2048 |
| Google Play — 1080 x 1920 | 1080 x 1920 | 1920 x 1080 |

The result is written beside the source as an opaque 24-bit PNG. The source aspect ratio
is preserved—there is no stretching. If it does not match the target canvas, the script
centers it and adds white padding. Existing files are never overwritten; later runs add
`-2`, `-3`, and so on.

The Google Play preset uses Google's current recommendation for apps that want to be
eligible for screenshot-based recommendation surfaces. Play Console accepts other phone
screenshot sizes too; see the verified requirements below.

---

## What the icon generator produces

Output goes to a sibling folder named `<basename>-icons` next to the source PNG. If that
folder already exists, `<basename>-icons-2`, `-3`, … is used instead (nothing is
overwritten).

- If the source is **not square**, it is padded to a square canvas with **transparent**
  pixels (centered) before generating; this is noted in the run summary.
- A **background color** is sampled automatically from the image (alpha-weighted average;
  falls back to white). It is used for the Android adaptive background, the opaque legacy
  launcher icons, and the Play Store icon.

```
<basename>-icons/
├─ iOS/
│  ├─ AppStore-1024.png                     1024x1024, opaque (App Store Connect upload)
│  └─ AppIcon.appiconset/
│     ├─ Contents.json                      single-size, with dark + tinted appearances
│     ├─ icon_1024.png                      1024x1024, light/default, opaque (no alpha)
│     ├─ icon_1024_dark.png                 1024x1024, dark variant, opaque
│     └─ icon_1024_tinted.png               1024x1024, grayscale, alpha preserved
└─ Android/
   ├─ PlayStore-512.png                     512x512, opaque (Play Store listing)
   └─ res/
      ├─ mipmap-mdpi/    ic_launcher.png (48)   ic_launcher_foreground.png (108)   ic_launcher_monochrome.png (108)
      ├─ mipmap-hdpi/    ic_launcher.png (72)   ic_launcher_foreground.png (162)   ic_launcher_monochrome.png (162)
      ├─ mipmap-xhdpi/   ic_launcher.png (96)   ic_launcher_foreground.png (216)   ic_launcher_monochrome.png (216)
      ├─ mipmap-xxhdpi/  ic_launcher.png (144)  ic_launcher_foreground.png (324)   ic_launcher_monochrome.png (324)
      ├─ mipmap-xxxhdpi/ ic_launcher.png (192)  ic_launcher_foreground.png (432)   ic_launcher_monochrome.png (432)
      ├─ mipmap-anydpi-v26/ic_launcher.xml   adaptive-icon: background + foreground + monochrome
      └─ values/ic_launcher_background.xml   <color name="ic_launcher_background"> (sampled)
```

### How each layer is derived (from one flat PNG)

| Output | Treatment |
| --- | --- |
| iOS `icon_1024.png` / `AppStore-1024.png` | Scaled to 1024², **flattened onto white**, alpha channel removed (App Store icons must be fully opaque). |
| iOS `icon_1024_dark.png` | Content brightness reduced (~90%) and **flattened onto black** — an automatic, recognizable dark-mode treatment. Judgment call (see notes). |
| iOS `icon_1024_tinted.png` | **Grayscale, alpha preserved.** iOS applies the system tint to the luminance; transparency keeps the tint on the artwork only. |
| Android `ic_launcher.png` (legacy) | Full-bleed square, scaled per density, flattened onto the sampled background color (opaque). |
| Android `ic_launcher_foreground.png` | Whole image scaled into the **adaptive safe zone (66/108 of the canvas)**, centered on a transparent canvas of the full adaptive size. |
| Android `ic_launcher_monochrome.png` | Same safe-zone scaling, **alpha-preserving grayscale.** For a logo on transparency, the alpha becomes the tinted silhouette. For a fully-opaque full-bleed image (no alpha), the whole safe-zone square is opaque, so the system tints the full tile — still valid, just less "cut-out". Author a dedicated monochrome asset if you want a specific silhouette. |
| Android `PlayStore-512.png` | Scaled to 512², flattened onto the sampled background color (opaque — Play requires a non-transparent icon). |

Both input shapes are handled and tested: **flat PNGs with transparency** (logo on a
transparent background) and **fully-opaque full-bleed PNGs** (no alpha channel at all).

---

## Install / Uninstall (per-user, no admin)

```powershell
# Add the right-click icon and screenshot commands
.\install.ps1

# Remove it
.\uninstall.ps1
```

`install.ps1` creates per-user shell keys (no elevation needed). The icon generator keeps
its existing key:

```
HKCU:\Software\Classes\SystemFileAssociations\.png\shell\MakeMobileIcons
    (default) = "Generate Mobile App Icons"
    Icon      = <powershell.exe>,0
    \command
        (default) = powershell.exe -NoProfile -ExecutionPolicy Bypass -File "<...>\Make-MobileIcons.ps1" -Path "%1"
```

Each screenshot preset is registered as a direct verb under the same `.png\shell`
location. Re-run `install.ps1` after updating the project so Explorer receives the new
entries.

`uninstall.ps1` removes both the icon and screenshot commands.

---

## Screenshot specifications followed (verified 2026-09-20)

### Apple — App Store Connect

- The iPhone presets produce all four requested 6.5-inch accepted sizes: 1242 x 2688,
  2688 x 1242, 1284 x 2778, and 2778 x 1284.
- The iPad presets produce all four accepted 13-inch sizes: 2064 x 2752, 2752 x 2064,
  2048 x 2732, and 2732 x 2048.
- App Store Connect accepts PNG, JPEG, and JPG screenshots, but screenshots cannot contain
  transparency or an alpha channel. The resizer therefore writes opaque 24-bit PNGs.
- Source: Apple App Store Connect Help — Screenshot specifications:
  https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications

### Google — Play Console screenshots

- Required format: JPEG or 24-bit PNG without alpha.
- Required dimensions: the short side must be at least 320 px, the long side at most
  3840 px, and the long side cannot exceed twice the short side.
- For apps to be eligible for recommendation formats that use screenshots, Google asks
  for at least four screenshots with at least 1080 px resolution: 1080 x 1920 or larger
  at 9:16 for portrait, or 1920 x 1080 or larger at 16:9 for landscape.
- For tablets and Chromebooks, Google asks for at least four large-screen screenshots,
  dimensions between 1080 and 7680 px, and a 9:16 or 16:9 aspect ratio.
- Source: Google Play Console Help — Add preview assets to showcase your app:
  https://support.google.com/googleplay/android-developer/answer/9866151

---

## App icon specifications followed (verified 2026-07-20)

### Apple — iOS / iPadOS (iOS 26 "Liquid Glass")

- **Master size 1024×1024 px.** A single 1024 master is submitted to App Store Connect; the
  system generates the smaller sizes.
- **No transparency / no alpha on the App Store icon.** All pixels must be opaque;
  transparent areas can render as black. This tool flattens the 1024 (and Play) icons onto
  a solid background.
- **Do not pre-round corners** — the system applies its own mask.
- **Appearance variants: Default (light), Dark, Tinted.** Introduced in iOS 18 and
  expanded with iOS 26's Liquid Glass. The Xcode asset catalog expresses them with
  `"appearances": [{ "appearance": "luminosity", "value": "dark" | "tinted" }]` entries in
  `Contents.json` (this tool writes exactly that). Dark and tinted variants may keep an
  alpha channel; only the primary/App Store icon must be opaque.
- **iOS 26 Liquid Glass icons are ideally authored in Apple's Icon Composer** (macOS,
  ships with Xcode 26), which produces a layered `.icon` bundle with system glass/lighting.
  This tool produces the **standard flat PNG fallbacks** that remain fully valid; run them
  through Icon Composer later if you want the layered glass treatment.
- Sources:
  - Apple HIG — App icons: https://developer.apple.com/design/human-interface-guidelines/app-icons
  - Apple HIG — Icon Composer / Liquid Glass overview (iOS 26): https://developer.apple.com/design/human-interface-guidelines/app-icons
  - iOS App Icon Guidelines 2026 (transparency/rounded-corner rules): https://theapplaunchpad.com/blog/ios-app-icon-guidelines/
  - iOS 26 Liquid Glass redesign overview: https://www.mobileaction.co/blog/apple-liquid-glass-design/

### Google — Android

- **Adaptive icon layers are 108×108 dp**; the **inner 66 dp** is the safe zone (the outer
  18 dp per edge may be clipped by the launcher's mask). Key artwork must stay inside the
  safe zone. This tool scales the whole flat image to **66/108** of each canvas, centered.
- **Adaptive layer pixel sizes:** mdpi 108, hdpi 162, xhdpi 216, xxhdpi 324, xxxhdpi 432.
- **Legacy `ic_launcher` pixel sizes:** mdpi 48, hdpi 72, xhdpi 96, xxhdpi 144, xxxhdpi 192.
- **Themed / monochrome icons (Android 13+, API 33):** provide a single `<monochrome>`
  layer; the system recolors it from the wallpaper/theme. Android 16 QPR2-era releases can
  auto-generate a monochrome layer for apps that lack one, but shipping your own is still
  recommended. Declared in `res/mipmap-anydpi-v26/ic_launcher.xml`.
- **Google Play Store listing icon:** 512×512 px, 32-bit PNG, sRGB, under 1024 KB, and
  **not transparent** (use a solid background). Play applies rounded corners, shadow, and
  masking dynamically — don't bake them in. From **March 31, 2026** Play renders icons with
  a **30% corner radius**, so keep key elements within ~15–18% internal padding.
- Sources:
  - Android — Adaptive icons: https://developer.android.com/develop/ui/compose/system/icon_design_adaptive
  - Android — Create app icons (Image Asset Studio, density sizes): https://developer.android.com/studio/write/create-app-icons
  - Google Play — Icon design specifications: https://developer.android.com/distribute/google-play/resources/icon-design-specifications
  - Android app icon sizes 2026 (density ladder reference): https://www.iconikai.com/blog/android-app-icon-sizes-design-guide-2026

---

## Notes & judgment calls

- **Dark iOS variant** is generated automatically (darken + flatten onto black). Apple
  expects a hand-designed dark icon; this is a reasonable, recognizable fallback. Replace
  `icon_1024_dark.png` with a bespoke dark design for production if desired.
- **Tinted iOS variant** is grayscale with alpha, which is what the system expects to apply
  its tint to.
- **Background color** is an alpha-weighted average of the source (falls back to white).
  For a specific brand background, edit `res/values/ic_launcher_background.xml` and
  re-flatten as needed.
- **Monochrome from an opaque full-bleed image** tints the whole safe-zone tile (there's no
  alpha silhouette to cut out). This is valid; supply a dedicated alpha silhouette if you
  want a specific themed shape.
- The tool never overwrites: repeated runs create `-icons-2`, `-icons-3`, …
