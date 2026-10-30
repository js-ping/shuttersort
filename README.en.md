<div align="center">

# ShutterSort

**Rename your phone photos to the time they were actually taken.**

Afterwards the folder sorts itself chronologically — exactly the order you see in your camera roll.

*(Chinese name: 拍摄时间改名器)*

[![License: MIT](https://img.shields.io/badge/License-MIT-8a63d2.svg)](LICENSE)
[![macOS](https://img.shields.io/badge/macOS-14%2B%20native%20SwiftUI-000000.svg)]()
[![Python](https://img.shields.io/badge/Python-3.8%2B-3776ab.svg)](https://www.python.org/)
[![Dependencies](https://img.shields.io/badge/dependencies-0-brightgreen.svg)]()
[![Platform](https://img.shields.io/badge/platform-Windows%20%7C%20macOS%20%7C%20Linux-lightgrey.svg)]()
[![Tests](https://img.shields.io/badge/self--test-72%20pass-brightgreen.svg)](#for-developers)

[中文说明](README.md) · English

</div>

---

## Before and after

Photos come off a phone as a bare serial number. Three files, and nothing says when they were taken:

```
IMG_8734.HEIC
IMG_8734.MOV
IMG_8741.HEIC
```

After:

```
IMG_20240506_153008.HEIC
IMG_20240506_153012.MOV
IMG_20240506_154421.HEIC
```

That's 6 May 2024, just past 3 pm. Sorting by name is now sorting by time, so search, backup and transferring to another drive all just work.

**It never touches your photos.** Renames only — not a single byte of file content changes. And it can be undone in one click.

> **Good fit:** photo libraries that have grown beyond finding things by filename; bulk exports from WhatsApp, WeChat or Google Photos; a whole batch shot with a camera clock that was set wrong.
>
> **Not a fit:** auto-sorting by faces, places or events; editing the metadata inside photos; cloud sync. This does one thing — renaming — and tries to do it properly.

## Three steps

**1. Download**

| Your computer | File | Install |
| --- | --- | --- |
| Windows 10 / 11 | `ShutterSort.exe` | Double-click. Nothing to install. |
| macOS 14 or newer | `ShutterSort-x.x.x-macOS-universal.dmg` | Double-click to mount, drag the icon into *Applications* |

Get them from [Releases](https://github.com/js-ping/shuttersort/releases).

**2. Drop the folder onto the window**

Or use *Choose folder*, or hand-pick a few files.

**3. Check the preview, click *Rename***

The preview lists what every file will be called. If it looks wrong, don't click — nothing has changed yet.

> First time? Copy the folder you want to tidy and practise on the copy. Undo works, but a copy is cheaper than trusting anything.

> ⚠️ **The first launch gets blocked by the OS**, because there's no paid code-signing certificate
> (US$99/year from Apple, more from Microsoft).
> Windows: *More info* → *Run anyway*.
> macOS: **right-click the app → Open → Open**.
> That's a one-time approval; double-clicking works from then on.

## What it handles

Phone shots, videos, files forwarded through messaging apps, Google Photos exports, camera and drone footage — if the name carries no time, it digs the real one out.

| Your situation | What it does |
| --- | --- |
| `IMG_8734.HEIC` straight off an iPhone | Reads the capture time stored inside the photo |
| `IMG_8734.MOV` recorded on the phone | Reads the creation time stored in the video container |
| Forwarded through WeChat or WhatsApp, metadata stripped | Recovers the time from the filename |
| A pile exported from Google Photos | Reads the `.json` sidecar that came with the export |
| Continuous burst, several frames in the same second | Reads sub-second precision; numbering follows the shutter |
| Camera clock was off by 8 hours | Shifts every name; filenames only, EXIF untouched |
| Names cluttered with `_edited`, stray digits, extra underscores | Cleans them up with rename rules |

**It tells you where each timestamp came from.** Every row carries a small coloured tag —
`embedded·EXIF`, `filename`, `Takeout JSON` and so on. You can check each one instead of
trusting a black box.

**It only touches what you tick.** Everything is checked after a scan; untick a row and it stays put.

**Re-running is safe.** Scan an already-renamed folder again and it reports "no change needed"
instead of appending another `_1`.

**No timestamp, no guess.** Those files are skipped and labelled, never given a made-up time.

## Screenshots

**Inspect everything before anything moves:**

![Main window](screenshots/01-main.png)

**Click any row to see where its time came from and the raw metadata:**

![File detail](screenshots/02-detail.png)

**One more confirmation — how many files, what naming, any collisions:**

![Confirm](screenshots/03-confirm.png)

**Every run is recorded; undo survives a restart:**

![History](screenshots/04-history.png)

**Wrong camera clock? Shift the batch — filenames only, metadata untouched:**

![Time correction](screenshots/05-correction.png)

## Naming

Default output is `IMG_20240506_153008.jpg` — prefix `IMG_` plus `%Y%m%d_%H%M%S`. Both are editable in the sidebar; clear the prefix and you get `20240506_153008.jpg`.

How the date combines with the original name:

| Pattern | Result |
| --- | --- |
| Date only (default) | `20240506_153008.jpg` |
| Date_original | `20240506_153008_IMG_8734.jpg` |
| Original_date | `IMG_8734_20240506_153008.jpg` |
| Original only | `IMG_8734.jpg` (prefix/suffix only, no date) |

Custom strftime-style formats work too (e.g. `%Y年%m月%d日`), and there's optional **archiving into date subfolders** like `2024/2024-05/`.

**Name collisions** get `_1` / `_2` appended. Existing files are never overwritten.

### Rename rules (macOS only)

Prefix and suffix can only add text at the ends, but the annoying part is usually in the middle:
the `IMG_` a camera adds, an `_edited` appended by an editor, redundant seconds, a long ID
stamped by an import tool.

Rename rules run **after** the name is assembled, and there are five:

| Rule | What it does | Example |
| --- | --- | --- |
| Insert | After character N, or before / after a piece of text | `20240506_153008` → `20240506-_153008` |
| Delete | From character N, a number of characters — or all the way to the end | `IMG_20240506_153008` → `20240506_153008` |
| Replace | Swap text; leave the replacement empty to delete | `IMG_` → `photo_` |
| Strip | Remove every occurrence of a character class | all underscores, spaces, brackets |
| Case | lower / UPPER / Title Case / Sentence case | `DSC` → `dsc` |

- Rules run top to bottom; each one's output is the next one's input. Toggle any rule off, or reorder them
- **No counting required:** a strip of clickable characters sits under every position-based rule.
  Click a character and the position is set to it. The strip shows the name *as that rule sees it*,
  so if an earlier rule changed the length, you still click the right character
- Spaces render as `·` and tabs as `→`, so invisible characters can't be miscounted

**Two guarantees:** the extension is never damaged (rules act on the stem, before `.jpg`);
and if a rule deletes everything, the name reverts to the unedited version instead of leaving
a bare `.jpg`.

<details>
<summary>Why there's no auto-numbering and no regex</summary>

The rule set was modelled on [ReNamer](https://www.den4b.com/products/renamer), deliberately minus three things:

- **Auto-numbering** breaks the promise that re-scanning changes nothing. Number files only partially
  selected and the numbers drift, which destroys the property the whole tool is built around.
  Bursts are already ordered by sub-second timestamps and collisions already get `_1`/`_2`
- **Regex and scripting** raise the bar far too high and invite mistakes — the opposite of what this is for
- **Changing extensions, randomising, transliterating** have nothing to do with capture times,
  and rewriting extensions on photos is a risk not worth taking

The Windows / Linux build doesn't have rename rules yet; its code is identical to v1.5.0.

</details>

### Bursts in the same second

Several frames land in one second. The app reads the sub-second part of the timestamp and orders
within that second by it, so `_1`, `_2` … follow the actual shutter order — not the order the
directory happened to be read in. Three small digits under the timestamp show that precision.

When sub-second data is missing (some Android cameras omit it), file mtime is the fallback, then
the filename: a three-level sort key that always produces the same answer.

### Wrong camera clock

Time zone set wrong, forgot to change the clock while travelling, or an old batch with broken
timestamps — the filenames inherit the error. Enable **time correction**, enter `days / hours / minutes`
(negative shifts backwards), and every name is generated from the corrected time.

Not sure by how much? Select a suspicious row, click *derive from selected row…*, type the photo's
**actual** capture time, and the offset is computed for you.

> Correction only affects generated filenames — **EXIF is never rewritten**. The original values stay,
> so you can set the offset back to zero and redo at any time. Corrected rows carry an orange badge
> (e.g. `+8h`); hover to see the original timestamp.

## Where the time comes from

The app walks a fixed list and **stops at the first usable timestamp**, then tells you which layer it used:

1. **Stored in the photo** — EXIF, XMP, PNG time chunks. Most reliable, tried first
2. **Stored in the video container** — MP4 / MOV / HEIC creation time, with UTC converted to your local time
3. **Stored in a sidecar** — the `.json` from a Google Photos export, or an `.xmp` written by an editor
4. **Written in the filename** — DJI, WhatsApp, screenshots, Chinese dates and six more patterns
5. **The file's own timestamp** — note this is when the file landed on your disk, *not* when the photo was taken. Off by default; you have to enable it

If none of the five hits, the file is skipped and tagged "no timestamp". **It will not invent a time for you.**

<details>
<summary>Full precedence table and "do I need exiftool?"</summary>

| # | Source | Notes |
| :-: | --- | --- |
| 1 | exiftool (if installed) | Highest-coverage standard extraction |
| 2 | Container time (MP4/MOV/HEIC) | `com.apple.quicktime.creationdate` → `mvhd` → `mdhd`, UTC to local |
| 3 | Embedded XMP (JPEG/PNG/WebP) | `xmp:CreateDate`, `photoshop:DateCreated` |
| 4 | EXIF (JPEG/TIFF/RAW/WebP) | `DateTimeOriginal` → `DateTimeDigitized` → `DateTime`, incl. `OffsetTime*` and `SubSecTime*` |
| 5 | PNG `tIME` chunk | The lifesaver for phone screenshots |
| 6 | Google Takeout `.json` sidecar | Accurate capture time from the export |
| 7 | `.xmp` sidecar | Written by editors next to the image |
| 8 | Filename parsing | 10 patterns, see below |
| 9 | Filesystem time (opt-in) | Clearly labelled as *not* a capture time |
| 10 | Nothing | Skipped, tagged "no timestamp" |

**exiftool is entirely optional.** The core formats are parsed in-house, pure standard library:

- **JPEG / TIFF / RAW EXIF** — own TIFF IFD walker, covering ARW / NEF / CR2 / DNG / RW2 / ORF / SRW
- **MP4 / MOV / HEIC / AVIF** — own ISOBMFF box parser, `keys` + `ilst` for QuickTime creation time, falling back to `mvhd` / `mdhd`
- **HEIC / HEIF** — `meta` → `iinf` / `iloc` to locate the Exif item, plus a TIFF magic-number scan as backup
- **PNG / WebP** — own chunk parser (`tIME` / `eXIf` / EXIF / XMP)

</details>

<details>
<summary>Filename patterns it recognises</summary>

| Pattern | Example |
| --- | --- |
| DJI Fly | `dji_fly_20251108_164116_0042_D.MP4` |
| DJI | `DJI_20251108_164116_0042_D.MP4` |
| IMG_ / VID_ | `IMG_20250418_193012.jpg` |
| 14 consecutive digits | `IMG_20200101000000_0001.jpg` |
| Generic | `20251111_184839.png` / `2025-11-08_16-41-16.mp4` |
| WhatsApp | `IMG-20240125-WA0001.jpg` |
| Screenshots | `Screenshot 2024-09-15 at 10.20.30.jpg` |
| Chinese dates | `2024年5月6日 活动.jpg` |
| WeChat / Pixel | `PXL_20240506_153008123.jpg` |

**Purely numeric names aren't mistaken for dates.** `1000000034.jpg` doesn't form a valid date and is
skipped; so are UUIDs and long hashes, with an extra year-plausibility check on top.

</details>

## FAQ

**Will it damage my photos?**

No. It only changes filenames. File content is untouched byte for byte, and the metadata inside
photos is never rewritten. If you get it wrong, one click in the history restores everything.

**Does renaming break my phone's photo library?**

This works on files already copied to a computer. It renames files on your disk or external drive;
your phone's camera roll is not involved.

**Why do some files show "no timestamp"?**

Their metadata was stripped — forwarded through WeChat / WhatsApp, re-saved by a screenshot tool,
exported through an online editor. You can enable the filesystem-time fallback (but that's when the
file landed on disk, not necessarily when it was shot), or just leave them skipped.

**The time is off by a few hours.**

EXIF timestamps carry no time zone, so the app can't infer where you were. Sources that *do* carry
one (container creation time, EXIF with `OffsetTime`) are converted automatically and won't drift.

**Video times are exactly 8 hours early or late.**

Check the source tag in that column:

- `embedded·mvhd creation time` — the built-in parser reads the UTC seconds from the container and
  converts to local time. Correct
- `exiftool·QuickTime:CreateDate` — this goes through exiftool. **Before v1.3.1** there was a time-zone
  bug: QuickTime stores UTC, exiftool interpreted it as local, so everything was off by one time zone
  (+08:00 meant 8 hours early). Fixed in v1.3.1; it now matches the built-in parser

Worth noting: the same file differing by 8 hours depending on whether exiftool is installed is exactly
why this is easy to miss.

**Windows: nothing happens when I double-click, or SmartScreen blocks it.**

Being blocked is normal for an unsigned binary — *More info* → *Run anyway*. If nothing happens at all,
run from source with `start.bat`, which prints the actual error.

**Windows: HEIC thumbnails don't show.**

HEIC needs an external decoder. macOS has one built in; Windows / Linux need ImageMagick
(`winget install ImageMagick`) or ffmpeg. Renaming is unaffected — you just see a placeholder icon.

**Does it support Windows / Linux?**

Yes. One codebase, same features, and the self-test runs on all three platforms. On Windows the
folder picker uses the native dialog, so non-ASCII paths are safe.

## Privacy

- ❌ **No network access.** The native macOS build doesn't even open a local port; the Python build binds `127.0.0.1` only
- ❌ **No uploads** of files, filenames or metadata
- ❌ **No content modification** — renaming only (plus an optional move when archiving)
- ✅ Existing files are never overwritten, in either direction
- ✅ Every self-test runs in a temp directory and never touches your real files
- ✅ The Windows exe is built by public GitHub Actions; the build is auditable

## For developers

<details>
<summary>Run from source</summary>

**Windows** (Python 3.8+; tick `Add python.exe to PATH` during install):

```bat
git clone https://github.com/js-ping/shuttersort.git
cd shuttersort
start.bat
```

**macOS / Linux** (Python 3.8+, built in on macOS):

```bash
git clone https://github.com/js-ping/shuttersort.git
cd shuttersort
./start.command
```

No `pip install`, no venv, no config file — pure standard library.

</details>

<details>
<summary>Build it yourself</summary>

**Windows:** double-click `build_exe.bat`. It installs PyInstaller, generates the icon and produces
`dist\ShutterSort.exe`.

**macOS native app** (needs only `swiftc` — `xcode-select --install`, **Xcode is not required**):

```bash
cd native
./build.sh --universal --zip --dmg
```

You get `native/dist/ShutterSort.app` plus a shareable `ShutterSort-<version>-macOS-universal.dmg`
and `.zip`.

**CI:** push a `v*` tag and GitHub Actions builds the exe and the `.app` on real Windows and macOS
runners and attaches them to the release. The Actions page also has a manual "Run workflow" that
builds without releasing.

</details>

<details>
<summary>Tests</summary>

```bash
python3 tests/selftest.py           # 72 regression checks
python3 native/tests/run_parity.py  # native vs Python, 14 scenarios, field by field
```

The native build is a rewrite, and the dangerous failure isn't an ugly window — it's reading the
wrong time. So `run_parity.py` builds a corpus covering 9 formats (HEIC, WebP, big-endian TIFF,
EXIF with time-zone offsets, same-second collisions in subfolders), compares timestamps,
sub-seconds, source labels, target names and conflict markers field by field, and exits non-zero
on any difference. It then really renames six files, re-scans to prove idempotency, exports the CSV
and undoes the batch — so the two riskiest paths are gated as well.

Rename-rule boundaries get their own gate, because an off-by-one here is invisible to the eye:

```bash
swiftc -O native/Sources/Core/*.swift native/Sources/CLI/main.swift -o /tmp/ss-cli
/tmp/ss-cli edit-test        # 38 checks: five rule types + zero/negative/overflow/anchor/stacking/disabled/CJK/extension
```

The UI can be inspected without looking at a screen:

```bash
native/tests/snapshots.sh            # light
native/tests/snapshots.sh --dark     # dark
```

It renders the sidebar, table cells, the detail pane and all sheets to PNGs
(`$TMPDIR/shuttersort-snapshots/out`) — handy for checking column widths, clipped text and contrast.

The 72 checks cover the parsers (9 formats → expected time), filename rules, the naming engine, the
full HTTP flow (scan → preview → rename → idempotent re-scan → undo), selective renaming (only the
selected rows, paths outside the scan rejected), file-list scanning (dedup, common parent, invalid
paths) and API security (path traversal). Everything runs in a temp directory and cleans up after itself.

</details>

<details>
<summary>Optional extras (all optional)</summary>

| Tool | Purpose | Without it |
| --- | --- | --- |
| `exiftool` | Highest-coverage metadata extraction | Falls back to built-in parsers, fully functional |
| `ffmpeg` | Video thumbnails (and a HEIC fallback) | Shows a 🎬 icon; renaming unaffected |
| `magick` (ImageMagick) | HEIC thumbnails on Windows / Linux | Placeholder icon; renaming unaffected |

```bash
brew install exiftool ffmpeg                                    # macOS
winget install exiftool ffmpeg                                  # Windows
sudo apt install libimage-exiftool-perl ffmpeg imagemagick      # Debian / Ubuntu
```

**The native macOS build needs none of them.** Thumbnails go through system ImageIO
(HEIC / HEIF / RAW / TIFF) and AVFoundation (a frame at 0.5 s for videos).

</details>

<details>
<summary>How it compares to a generic batch renamer</summary>

| Capability | Generic batch renamer | ShutterSort |
| --- | :---: | :---: |
| Reads capture time from photos (EXIF / XMP / PNG / HEIC / RAW) | Partial | ✅ |
| Reads capture time from video containers (MP4 / MOV) | Usually not | ✅ |
| Recovers time from filenames of messaging-app exports | Rarely | ✅ |
| Reads Google Takeout `.json` sidecars | No | ✅ |
| **Tells you where each timestamp came from** | No | ✅ Tagged per file |
| **Renames only the rows you pick** | Rarely | ✅ |
| Undo | Usually session-only | ✅ Persisted, survives restart |
| Re-running is stable | Often breaks | ✅ |
| **Sub-second ordering for bursts** | Directory order | ✅ Follows the shutter |
| **Time correction** | Rare | ✅ ±days/hours/minutes, or derived from a reference file |
| Dependencies | A pile of packages | ✅ Zero third-party deps |
| Platforms | Usually one | ✅ Windows / macOS / Linux, native on macOS |

</details>

## Project layout

```
ShutterSort/
├── native/                    ← macOS native app (SwiftUI, since v1.5.0)
│   ├── build.sh               ← one command → .app + zip + dmg
│   ├── Sources/Core/          ← parsing engine, rewritten in Swift (TIFF/EXIF/ISOBMFF)
│   ├── Sources/UI/            ← SwiftUI interface
│   ├── Sources/CLI/           ← CLI entry used by the parity and rule tests
│   └── tests/                 ← run_parity.py, snapshots.sh
├── start.command / start.bat  ← double-click launcher (macOS·Linux / Windows, Python build)
├── build_exe.bat              ← double-click: build the Windows standalone exe
├── src/
│   ├── media_time.py          ← timestamp parsing engine (Python build: Windows / Linux)
│   ├── server.py              ← local server + all endpoints
│   ├── app_main.py            ← window entry point (Windows .exe)
│   └── static/index.html      ← UI (single file, no build step)
├── tests/selftest.py          ← 72 regression checks
├── packaging/                 ← Windows packaging + icons
│   ├── version_info.txt       ← version resource embedded in the exe
│   └── ci/RELEASE_NOTES.md    ← release body (edit this one before a release)
├── .github/workflows/         ← tag a release → exe + .app built and attached
├── screenshots/               ← README images
└── rename-history/            ← created at runtime: undo records (don't delete)
```

## Performance

| Workload | Time |
| --- | --- |
| 100 photos | < 1 s |
| 10 000 files | 20–60 s (disk-bound) |
| One 4 GB 4K video | Milliseconds — only the header boxes are read |

Parallel scanning scales with CPU cores; videos are read header-only, never loaded whole.
The table renders at most 1500 rows to stay responsive; renaming still applies to every file.

## License

[MIT](LICENSE)
