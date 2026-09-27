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
3. Choose **"Generate Mobile App Icons"** and pick **Android + iOS**, **Android only**
   or **iOS only** from its submenu, or choose one of the **"Resize Screenshot - ..."**
   commands.
4. A console window shows progress, then Explorer opens to the output.

> **Windows 11 caveat (by design):** this entry appears in the **classic** ("Show more
> options" / Shift+F10) menu, **not** the new compact Windows 11 menu. Adding items to the
> new menu requires a packaged **MSIX shell extension (`IExplorerCommand`)**, which is out
> of scope for a lightweight per-user script tool. The classic menu is 100% functional and
> needs no administrator rights.

### From the command line

```powershell
.\Make-MobileIcons.ps1 -Path "C:\path\to\logo.png"
.\Make-MobileIcons.ps1 -Path "C:\path\to\logo.png" -Platform Android   # or iOS

# Screenshot orientation follows the source automatically.
.\Resize-StoreScreenshot.ps1 -Path "C:\path\to\screenshot.png" -Preset Apple-iPhone-1284x2778
.\Resize-StoreScreenshot.ps1 -Path "C:\path\to\screenshot.png" -Preset GooglePlay-1080x1920
```

- Both scripts require `-Path <string>` and support `-NoInteractive` for automation
  (no Explorer window, no "Press Enter" prompt).
- `Make-MobileIcons.ps1` takes an optional `-Platform All|Android|iOS` (default `All`).
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

Output goes to a sibling folder named `<basename>-icons` next to the source PNG
(`<basename>-icons-android` / `<basename>-icons-ios` for the single-platform commands). If
that folder already exists, `-2`, `-3`, … is appended instead (nothing is overwritten). The
folder layout inside is the same in every mode, so paths into `Android/` or `iOS/` stay
stable.

- If the source is **not square**, it is padded to a square canvas with **transparent**
  pixels (centered) before generating; this is noted in the run summary.
- For Android, the image is **analysed** to find where its visible content is and what
  background sits behind it (see [How the Android artwork is fitted](#how-the-android-artwork-is-fitted)).
  The resulting **background color** is used for the adaptive background layer, and the
  legacy and Play Store icons are rendered from the same framing.

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
      ├─ mipmap-mdpi/    ic_launcher.png + ic_launcher_round.png (48)    ic_launcher_foreground.png + ic_launcher_monochrome.png (108)
      ├─ mipmap-hdpi/    ic_launcher.png + ic_launcher_round.png (72)    ic_launcher_foreground.png + ic_launcher_monochrome.png (162)
      ├─ mipmap-xhdpi/   ic_launcher.png + ic_launcher_round.png (96)    ic_launcher_foreground.png + ic_launcher_monochrome.png (216)
      ├─ mipmap-xxhdpi/  ic_launcher.png + ic_launcher_round.png (144)   ic_launcher_foreground.png + ic_launcher_monochrome.png (324)
      ├─ mipmap-xxxhdpi/ ic_launcher.png + ic_launcher_round.png (192)   ic_launcher_foreground.png + ic_launcher_monochrome.png (432)
      ├─ mipmap-anydpi-v26/ic_launcher.xml         adaptive-icon: background + foreground + monochrome
      ├─ mipmap-anydpi-v26/ic_launcher_round.xml   same layers, for android:roundIcon
      └─ values/ic_launcher_background.xml         <color name="ic_launcher_background"> (sampled)
```

### How each layer is derived (from one flat PNG)

| Output | Treatment |
| --- | --- |
| iOS `icon_1024.png` / `AppStore-1024.png` | Scaled to 1024², **flattened onto white**, alpha channel removed (App Store icons must be fully opaque). |
| iOS `icon_1024_dark.png` | Content brightness reduced (~90%) and **flattened onto black** — an automatic, recognizable dark-mode treatment. Judgment call (see notes). |
| iOS `icon_1024_tinted.png` | **Grayscale, alpha preserved.** iOS applies the system tint to the luminance; transparency keeps the tint on the artwork only. |
| Android `ic_launcher_foreground.png` | Image scaled so its **farthest visible pixel lies on the 66dp safe-zone circle**, centered on a transparent 108dp canvas (see below). |
| Android `ic_launcher_monochrome.png` | Same placement, grayscale. The system keeps only the alpha and tints it. For a logo on transparency, the alpha is the silhouette. For art on a plain tile, only what stands out from the tile is kept (e.g. the white mark and lines), so the themed icon is a real glyph rather than a solid square. |
| Android `ic_launcher.png` / `ic_launcher_round.png` (legacy) | What a launcher shows: background + foreground, cropped to the 72dp viewport. Square is opaque; round is circle-masked with transparency. |
| Android `PlayStore-512.png` | The same 72dp framing at 512², opaque (Play requires a non-transparent icon and rounds the corners itself). |

Both input shapes are handled and tested: **flat PNGs with transparency** (logo on a
transparent background) and **fully-opaque full-bleed PNGs** (no alpha channel at all).

### How the Android artwork is fitted

Launchers show only the inner 72dp of the 108dp adaptive layers and cut it to an OEM shape
(circle, squircle, rounded square, …). The **circle is the tightest mask**. Scaling a
full-bleed square to 66dp therefore still loses its corners, and on a squircle anything
near the edges (e.g. a frame or waves along the bottom). To avoid that, the generator looks
at the image before placing it:

| Source | Background layer | What counts as content |
| --- | --- | --- |
| Has transparency | Average color of the image (falls back to white) | Non-transparent pixels |
| Opaque, plain border (art on a flat tile) | The **border color** itself, so there is no visible seam | Pixels that differ from the border color. The outer 1% is ignored and repainted with the border color, which also removes stray export slivers along the edges |
| Opaque, varied border (gradient, photo) | Average border color | The whole square. Edges are feathered into the background |

The artwork is then scaled until the farthest content pixel sits on the **66dp safe-zone
circle** (radius 33dp). Nothing is cropped under any mask shape, including parallax/pulse
effects. Art whose content stays inside the inscribed circle is drawn larger than 66dp, and a
square filled edge to edge ends up at 46.7dp. The run prints the result, e.g.
`content reaches 1.21x its half-width -> drawn at 54.7dp of the 108dp layer`.

---

## Install / Uninstall (per-user, no admin)

```powershell
# Add the right-click icon and screenshot commands
.\install.ps1

# Remove it
.\uninstall.ps1
```

`install.ps1` creates per-user shell keys (no elevation needed). The icon generator is a
cascading submenu. The parent has only `MUIVerb` and an empty `SubCommands` value, and its
entries live in its own `shell` subkey:

```
HKCU:\Software\Classes\SystemFileAssociations\.png\shell\MakeMobileIcons
    MUIVerb     = "Generate Mobile App Icons"
    SubCommands = ""
    Icon        = <powershell.exe>,0
    \shell
        \01All      (default) = "Android + iOS"   \command = ... Make-MobileIcons.ps1" -Path "%1" -Platform All
        \02Android  (default) = "Android only"    \command = ... Make-MobileIcons.ps1" -Path "%1" -Platform Android
        \03iOS      (default) = "iOS only"        \command = ... Make-MobileIcons.ps1" -Path "%1" -Platform iOS
```

The installer deletes and recreates `MakeMobileIcons` each time. A leftover `(default)`
value or `command` subkey from the older single-command install would otherwise turn the
parent back into a plain verb.

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

*(Adaptive icon and Play Store icon pages re-verified 2026-09-27.)*

- **Adaptive icon layers are 108×108 dp.** Android's docs: "Use a logo that's at least
  48x48 dp. It must not exceed 66x66 dp, because the inner 66x66 dp of the icon appears
  within the masked viewport." The outer 18 dp per edge is "reserved for masking and to
  create visual effects such as parallax or pulsing".
- **The 66 dp limit is for a logo, not a full square.** Masks are OEM-defined, and a circle
  (e.g. Pixel's default) cuts off the corners of a 66 dp square. This tool therefore fits
  the artwork's farthest visible pixel to the **66 dp circle**. See
  [How the Android artwork is fitted](#how-the-android-artwork-is-fitted).
- **Adaptive layer pixel sizes:** mdpi 108, hdpi 162, xhdpi 216, xxhdpi 324, xxxhdpi 432.
- **Legacy `ic_launcher` pixel sizes:** mdpi 48, hdpi 72, xhdpi 96, xxhdpi 144, xxxhdpi 192.
- **`android:roundIcon`:** launchers that use it apply a circular mask to it. Android Studio's
  template manifest points it at `@mipmap/ic_launcher_round`, so this tool writes a matching
  `ic_launcher_round.xml` (same adaptive layers) and legacy `ic_launcher_round.png`.
  Without them, a template project would keep showing its old round icon.
- **Themed / monochrome icons (Android 13+, API 33):** provide a single `<monochrome>`
  layer; the system recolors it from the wallpaper/theme. Android 16 QPR2-era releases can
  auto-generate a monochrome layer for apps that lack one, but shipping your own is still
  recommended. Declared in `res/mipmap-anydpi-v26/ic_launcher.xml`.
- **Google Play Store listing icon:** 512×512 px, 32-bit PNG, sRGB, under 1024 KB, full
  square, and preferably **not transparent** (transparent areas show Play's UI color).
  Play applies masking with a **corner radius of 30% of the icon size**, plus a shadow.
  Don't bake either in. This tool renders the Play icon with the same framing as the
  launcher icon, so the 30% corners never reach the artwork.
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
- **Background color** is the border color for art on a plain tile, the average border
  color for other opaque images, and the alpha-weighted average for transparent sources
  (falls back to white). For a specific brand background, edit
  `res/values/ic_launcher_background.xml`. If you override it (e.g. an Expo
  `adaptiveIcon.backgroundColor`), use the exported value: a different color shows as a
  ring around art on a plain tile.
- **Opaque images with a varied border** (gradients, photos) can't be separated into
  content and background, so the whole square is fitted inside the safe-zone circle. It is
  then visible as a square on the average border color. Supply a transparent-background
  logo if you want the art larger.
- **Monochrome from an opaque image with a varied border** is a feathered grayscale square
  (there's no silhouette to cut out), so the system tints the whole square. Supply a
  dedicated alpha silhouette if you want a specific themed shape.
- The tool never overwrites: repeated runs create `-icons-2`, `-icons-3`, …
