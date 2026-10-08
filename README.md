# IconRightClick — Prepare Mobile Store Images from a PNG, JPG or HEIC

Right-click any `.png`, `.jpg`/`.jpeg` or `.heic`/`.heif` in Windows Explorer and generate
**Android-** and **iOS-compliant** app icon sets or resize screenshots for **App Store
Connect** and **Google Play Console** (phones and tablets), following current (2026) Google
and Apple guidance. Select one image or a whole batch: every selected file is processed in
a single run. Every output file is a **PNG**, whatever the source format (see
[Source formats](#source-formats-png-jpg-heic)).

The tool works from a **single flat image** — an exported logo, a full-bleed image or a
phone photo/screenshot.
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
  HEIC sources need an ImageMagick build with HEIC support; the Windows release includes it.
  To check, run `magick -list format | findstr HEIC` and look for an `r` in the mode column.

---

## Usage

### From the right-click menu (after installing — see below)

1. Select one or more `.png`, `.jpg`/`.jpeg` or `.heic`/`.heif` files in Explorer (up to
   100) and right-click.
2. On **Windows 11**, click **"Show more options"** (or press **Shift+F10**) to open the
   classic context menu.
3. Choose **"Generate Mobile App Icons"** and pick **Android + iOS**, **Android only**
   or **iOS only**, or choose **"Resize Store Screenshot"** and pick a store size.
4. One console window shows progress for the whole selection, then Explorer opens to the
   output.

With several files selected, a console window briefly opens and closes for each extra file
before the batch starts in the first one (see [Batch processing](#batch-processing)).

> **Windows 11 caveat (by design):** this entry appears in the **classic** ("Show more
> options" / Shift+F10) menu, **not** the new compact Windows 11 menu. Adding items to the
> new menu requires a packaged **MSIX shell extension (`IExplorerCommand`)**, which is out
> of scope for a lightweight per-user script tool. The classic menu is 100% functional and
> needs no administrator rights.

### From the command line

```powershell
.\Make-MobileIcons.ps1 -Path "C:\path\to\logo.png"
.\Make-MobileIcons.ps1 -Path "C:\path\to\logo.png", "C:\path\to\logo-beta.png" -Platform Android   # or iOS

# Screenshot orientation follows each source automatically.
.\Resize-StoreScreenshot.ps1 -Path "C:\path\to\screenshot.png" -Preset Apple-iPhone-1320x2868

# A batch: every .png in a folder, written at two sizes each.
.\Resize-StoreScreenshot.ps1 -Path "C:\path\to\tablet-shots" -Preset Apple-iPad-2064x2752, GooglePlay-Tablet-1440x2560

# Wildcards work too.
.\Resize-StoreScreenshot.ps1 -Path "C:\path\to\shots\home-*.png" -Preset GooglePlay-1080x1920

# JPG and HEIC sources (e.g. straight from a phone); the output is PNG.
.\Resize-StoreScreenshot.ps1 -Path "C:\path\to\IMG_0042.HEIC" -Preset Apple-iPhone-1206x2622
.\Make-MobileIcons.ps1 -Path "C:\path\to\logo.jpg"
```

- Both scripts take `-Path` with one or more entries. Each entry can be a `.png`, `.jpg`,
  `.jpeg`, `.heic` or `.heif` file, a folder (every such file directly inside it) or a
  wildcard. When a folder is given, `Resize-StoreScreenshot.ps1` skips files it wrote on an
  earlier run.
- Both support `-NoInteractive` for automation (no Explorer window, no "Press Enter"
  prompt).
- `Make-MobileIcons.ps1` takes an optional `-Platform All|Android|iOS` (default `All`).
- `Resize-StoreScreenshot.ps1` also requires one or more of the documented `-Preset` values.
- A file that fails (e.g. not a readable PNG, JPEG or HEIC image) is reported, and the rest
  of the batch still runs. The exit code is `1` if anything failed.

### Batch processing

For a command-line menu entry, Explorer starts **one process per selected file**. Each
process would otherwise open its own window, Explorer view and "Press Enter" prompt. By
default Explorer also hides such entries entirely once more than 15 files are selected.

The installer registers every entry with `MultiSelectModel = Player`, which raises
Explorer's limit to **100 files**, and adds `-FromExplorer` to the command line. With that
switch, the first process to start collects the paths of all the others. They hand over
their file and exit, and the batch runs in that one window. Different menu entries never
share a batch. A new selection started while an earlier batch is still running gets its own
window.

For more than 100 files, run either script from the command line with a folder or wildcard
as `-Path`.

### Source formats (PNG, JPG, HEIC)

| Extension | Typical source |
| --- | --- |
| `.png` | Exported artwork, screenshots |
| `.jpg`, `.jpeg` | Photos, screenshots saved by other tools |
| `.heic`, `.heif` | iPhone/iPad photos (the default camera format) |

Every source is normalized the same way before anything else happens, so both tools treat
the three formats alike:

- **Checked by content, not by name.** A file is accepted when ImageMagick reads it as PNG,
  JPEG or HEIC, so a `.jpg` that is really a PNG works. Other formats (GIF, WebP, …) are
  rejected with a message.
- **Turned upright.** Phones often store a portrait photo sideways and record the rotation
  in its EXIF data. That rotation is applied first, so the screenshot resizer picks the
  right orientation and icons aren't sideways. (HEIC files are already decoded upright.)
- **Converted to sRGB.** iPhone photos (and often screenshots) carry a Display P3 color
  profile. An embedded profile is converted to sRGB (the color space both stores expect)
  using the sRGB profile that ships with Windows
  (`%SystemRoot%\System32\spool\drivers\color\sRGB Color Space Profile.icm`). Without that
  conversion the colors would look washed out. CMYK and grayscale JPEGs are converted too.
- **Metadata removed.** EXIF data (camera details and **GPS location**), XMP and color
  profiles are not copied into any output file.
- **First image only.** If a HEIC holds several images, only the first is used.

JPG images and HEIC photos have no transparency, so they are treated like an opaque PNG (see
[How the Android artwork is fitted](#how-the-android-artwork-is-fitted)). For the largest
Android icon, a logo PNG with a transparent background still works best.

---

## Screenshot resize presets

The **"Resize Store Screenshot"** submenu provides these presets. Each label shows its
portrait canvas; a landscape source automatically receives the reversed dimensions.

| Menu entry | `-Preset` | Portrait output | Landscape output | Store slot |
| --- | --- | ---: | ---: | --- |
| Apple iPhone 6.9" — 1320 x 2868 | `Apple-iPhone-1320x2868` | 1320 x 2868 | 2868 x 1320 | iPhone with Dynamic Island (large display) |
| Apple iPhone 6.3" — 1206 x 2622 | `Apple-iPhone-1206x2622` | 1206 x 2622 | 2622 x 1206 | iPhone with Dynamic Island (medium display) |
| Apple iPhone 6.5" — 1284 x 2778 | `Apple-iPhone-1284x2778` | 1284 x 2778 | 2778 x 1284 | iPhone with Face ID (large display) |
| Apple iPhone 6.5" — 1242 x 2688 | `Apple-iPhone-1242x2688` | 1242 x 2688 | 2688 x 1242 | iPhone with Face ID (large display) |
| Apple iPad 13" — 2064 x 2752 | `Apple-iPad-2064x2752` | 2064 x 2752 | 2752 x 2064 | iPad 13" display |
| Apple iPad 13" — 2048 x 2732 | `Apple-iPad-2048x2732` | 2048 x 2732 | 2732 x 2048 | iPad 13" display |
| Google Play phone — 1080 x 1920 | `GooglePlay-1080x1920` | 1080 x 1920 | 1920 x 1080 | Phone |
| Google Play tablet (7" and 10") — 1440 x 2560 | `GooglePlay-Tablet-1440x2560` | 1440 x 2560 | 2560 x 1440 | 7-inch and 10-inch tablet |

Which to use:

- **iPhone:** 6.9" is the largest accepted size. App Store Connect scales it down for the
  smaller iPhone slots if you don't upload those. Apple's page currently lists the 6.3"
  (Dynamic Island, medium) slot as the required one, so use that preset if App Store
  Connect asks for 6.3" screenshots specifically. The two 6.5" presets remain accepted.
- **iPad:** 13" is required if the app runs on iPad. Smaller iPads use scaled 13" shots.
- **Google Play phone:** 1080 x 1920 is Google's minimum for apps to be eligible for
  screenshot-based recommendation surfaces.
- **Google Play tablet:** the same 9:16 / 16:9 file suits both the 7-inch and 10-inch
  slots. 1440 x 2560 is within both Google's large-screen range (1,080–7,680 px) and the
  general 3,840 px cap.

The result is written beside the source as an opaque 24-bit PNG named
`<name>-<store>-<width>x<height>.png`. The source aspect ratio is preserved—there is no
stretching. If it does not match the target canvas, the script centers it and adds white
padding. Existing files are never overwritten; later runs add `-2`, `-3`, and so on (as does
a second source with the same base name, e.g. `shot.jpg` next to `shot.heic`).

---

## What the icon generator produces

Output goes to a sibling folder named `<basename>-icons` next to the source image
(`<basename>-icons-android` / `<basename>-icons-ios` for the single-platform commands); in a
batch, each source gets its own folder. If
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

### How each layer is derived (from one flat image)

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
transparent background) and **fully-opaque full-bleed images** (no alpha channel at all,
which includes every JPG and HEIC).

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

`install.ps1` creates per-user shell keys (no elevation needed). Both tools are cascading
submenus, registered identically for each supported extension (`.png`, `.jpg`, `.jpeg`,
`.heic`, `.heif`). Each parent has only `MUIVerb` and an empty `SubCommands` value, and its
entries live in its own `shell` subkey. Every key also carries `MultiSelectModel = Player`
(see [Batch processing](#batch-processing)). Shown for `.png`; the other extensions get the
same keys:

```
HKCU:\Software\Classes\SystemFileAssociations\.png\shell\MakeMobileIcons
    MUIVerb     = "Generate Mobile App Icons"
    SubCommands = ""
    \shell
        \01All      (default) = "Android + iOS"   \command = ... Make-MobileIcons.ps1" -Path "%1" -Platform All -FromExplorer
        \02Android  (default) = "Android only"    \command = ... Make-MobileIcons.ps1" -Path "%1" -Platform Android -FromExplorer
        \03iOS      (default) = "iOS only"        \command = ... Make-MobileIcons.ps1" -Path "%1" -Platform iOS -FromExplorer

HKCU:\Software\Classes\SystemFileAssociations\.png\shell\ResizeStoreScreenshot
    MUIVerb     = "Resize Store Screenshot"
    SubCommands = ""
    \shell
        \01 ... \08  (default) = "<preset label>" \command = ... Resize-StoreScreenshot.ps1" -Path "%1" -Preset <preset> -FromExplorer
```

The installer deletes and recreates both parent keys each time. A leftover `(default)` value
or `command` subkey from an older single-command install would otherwise turn a parent back
into a plain verb. It also removes the direct `ResizeStoreScreenshot01`–`05` verbs that
earlier versions registered. Re-run `install.ps1` after updating the project so Explorer
receives the new entries (an install from before JPG/HEIC support only covers `.png`).

The commands are the same for every extension, and a batch is keyed on the menu entry, not
the file type, so a selection that mixes PNG, JPG and HEIC files runs as one batch.

`uninstall.ps1` removes both the icon and screenshot commands from every file type.

---

## Screenshot specifications followed (verified 2026-10-08)

### Apple — App Store Connect

Apple's page now names display classes instead of inch sizes. The inch labels in the menu
are the conventional names for those classes.

| Display class | Accepted portrait sizes (landscape = reversed) | Apple's requirement note |
| --- | --- | --- |
| iPhone with Dynamic Island (large) — 6.9" | 1260 x 2736, 1290 x 2796, **1320 x 2868** | Falls back to scaled Face ID (large) shots |
| iPhone with Face ID (large) — 6.5" | **1284 x 2778**, **1242 x 2688** | Required if the app runs on iPhone and Dynamic Island (large) shots aren't provided |
| iPhone with Dynamic Island (medium) — 6.3" | 1179 x 2556, **1206 x 2622** | Listed under "Required device sizes" for iPhone |
| iPad 13" | **2064 x 2752**, **2048 x 2732** | Required if the app runs on iPad |
| iPad 11" and smaller | (various) | Falls back to scaled 13" shots |

Bold sizes have a preset.

- "If your app's user interface is consistent across multiple device sizes … you only need
  to provide screenshots for the highest required resolution. App Store Connect
  automatically scales them down for smaller device sizes."
- 1–10 screenshots per device size, in `.jpeg`, `.jpg` or `.png`. Images can't include
  alpha channels or transparency, so the resizer writes opaque 24-bit PNGs.
- Source: Apple App Store Connect Help — Screenshot specifications:
  https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications

### Google — Play Console screenshots

- Format: JPEG or 24-bit PNG without alpha. Up to 8 screenshots per device type, and at
  least 2 across device types to publish.
- Dimensions (all screenshots): minimum 320 px, maximum 3,840 px, and the long side can't
  be more than twice the short side.
- **Phones:** for apps to be eligible for recommendation formats that use screenshots,
  provide at least four screenshots at 1080 px or more: 9:16 at 1080 x 1920 or larger
  (portrait), or 16:9 at 1920 x 1080 or larger (landscape).
- **Tablets (7-inch and 10-inch) and Chromebooks:** at least 4 screenshots, each side
  between 1,080 and 7,680 px, at 16:9 (landscape) or 9:16 (portrait). Common third-party
  sizes such as 1200 x 1920 or 1600 x 2560 are 10:16 and don't meet this.
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

---

## Third-party software and licenses

This repository contains only its own scripts and documentation, released under the MIT
License (see [License](#license)). It does **not** include, bundle or modify any third-party
code, library or data file. At run time the scripts call
ImageMagick, which you install yourself, and read one color profile that ships with Windows.
Those components stay under their own licenses:

| Component | What this project uses it for | License |
| --- | --- | --- |
| [ImageMagick](https://imagemagick.org/) — © 1999 ImageMagick Studio LLC | Every read, conversion and resize (`magick`) | [ImageMagick License](https://imagemagick.org/license/) (derived from Apache 2.0) |
| [libheif](https://github.com/strukturag/libheif) | HEIC/HEIF decoding, inside ImageMagick | [LGPL-3.0](https://github.com/strukturag/libheif/blob/master/COPYING) |
| [libde265](https://github.com/strukturag/libde265) | HEVC decoding for libheif, inside ImageMagick | [LGPL-3.0](https://github.com/strukturag/libde265/blob/master/COPYING) |
| [Little CMS](https://www.littlecms.com/) | Color-profile conversion to sRGB, inside ImageMagick | [MIT](https://github.com/mm2/Little-CMS/blob/master/LICENSE) |
| [libjpeg-turbo](https://libjpeg-turbo.org/) | JPEG decoding, inside ImageMagick | [IJG License and BSD-3-Clause](https://github.com/libjpeg-turbo/libjpeg-turbo/blob/main/LICENSE.md) |
| [libpng](http://www.libpng.org/pub/png/libpng.html) | PNG reading and writing, inside ImageMagick | [PNG Reference Library License v2](http://www.libpng.org/pub/png/src/libpng-LICENSE.txt) |
| Windows sRGB color profile (`sRGB Color Space Profile.icm`) | Target profile for the sRGB conversion; read in place, never copied | Part of Windows, under the Windows license terms |

The libraries are the ones the official Windows build of ImageMagick compiles in, per
ImageMagick's Windows dependency list:
https://github.com/ImageMagick/Dependencies/blob/main/clone-dependencies.sh

If you redistribute ImageMagick together with these scripts (for example in a packaged
installer), that distribution must follow ImageMagick's license and those of the libraries
it contains, including the LGPL-3.0 terms of libheif and libde265.

---

## License

IconRightClick is released under the [MIT License](LICENSE), © 2026 fTr0ut. The
third-party software listed above is not covered by it and keeps its own licenses.
