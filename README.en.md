<div align="center">

# ShutterSort

**Write the iPhone capture time back into the filename.**

[![License: MIT](https://img.shields.io/badge/License-MIT-8a63d2.svg)](LICENSE)
[![Python](https://img.shields.io/badge/Python-3.8%2B-3776ab.svg)](https://www.python.org/)
[![Dependencies](https://img.shields.io/badge/dependencies-0-brightgreen.svg)]()
[![Platform](https://img.shields.io/badge/platform-macOS-lightgrey.svg)]()
[![Tests](https://img.shields.io/badge/self--test-49%20pass-brightgreen.svg)](#development--testing)

[中文说明](README.md) · English

</div>

---

Photos and videos shot on an iPhone come off the camera as a bare serial number ——
once exported to a computer, a drive or the cloud, nothing in the filename says *when* it was taken:

```
IMG_8734.HEIC
IMG_8734.MOV
IMG_8741.HEIC
```

ShutterSort does one thing: **replace those names with the real capture time** read back
from the file's embedded metadata.

```
IMG_8734.HEIC   →  IMG_20240506_153008.HEIC
IMG_8734.MOV    →  IMG_20240506_153012.MOV
IMG_8741.HEIC   →  IMG_20240506_154421.HEIC
```

Afterwards the folder sorts chronologically by itself, matching what you see in your photo app ——
and the filename *is* the timestamp, so search, backup and sync all just work.

## Highlights

- **Auditable timestamps** — every file is tagged with *where* its time came from. No black boxes.
- **Zero dependencies** — pure Python standard library. No `pip install`, no venv, no config.
- **Self-contained parsers** — TIFF/EXIF, XMP, PNG chunks, WebP and ISOBMFF (MP4/MOV/HEIC) are all parsed in-house, so nothing breaks when external tools are missing.
- **Deterministic & idempotent** — re-running on an already-renamed folder reports "no change" instead of appending `_1`.
- **Persistent undo** — every run writes a JSON history file; undo works across sessions.
- **Safe by default** — conflict handling with `_1`/`_2` suffixes, overwrite protection in both rename and undo directions, and no-timestamp files are skipped rather than guessed.

## Screenshots

**Preview before touching anything** — note the colored timestamp-source tags:

![Main window](screenshots/01-main.png)

**Click any row to inspect the source and raw embedded metadata:**

![File detail](screenshots/02-detail.png)

**Confirmation dialog before the actual rename:**

![Confirm](screenshots/03-confirm.png)

**Persistent, cross-session undo:**

![History](screenshots/04-history.png)

## Quick start

### Run from source (recommended)

macOS with Python 3.8+ (built in on macOS):

```bash
git clone https://github.com/js-ping/shuttersort.git
cd shuttersort
./start.command
```

A terminal window opens, then your browser opens the UI. There is nothing to install.

### Package as a standalone .app

```bash
python3 -m pip install pyinstaller pywebview   # once
cd packaging
./build_app.command
```

Produces `packaging/dist/ShutterSort.app` — a native window, no Python required on the machine.

### Optional extras

| Tool | Purpose | Without it |
| --- | --- | --- |
| `exiftool` | Highest-coverage metadata extraction | Falls back to built-in parsers, fully functional |
| `ffmpeg` | Video thumbnails | Shows a 🎬 icon; renaming unaffected |

## Timestamp precedence

For every file the first usable timestamp wins, and the UI shows which layer was used:

1. **exiftool** (if installed)
2. **Container time** — MP4/MOV/HEIC: `com.apple.quicktime.creationdate` → `mvhd` → `mdhd`, UTC converted to local time
3. **Embedded XMP** (JPEG/PNG/WebP)
4. **EXIF** — `DateTimeOriginal` → `DateTimeDigitized` → `DateTime`, incl. `OffsetTime*` time zones and `SubSecTime*` milliseconds
5. **PNG `tIME` chunk**
6. **Google Takeout `.json` sidecar**
7. **`.xmp` sidecar**
8. **Filename parsing** — 10 patterns (DJI, IMG/VID, WhatsApp, screenshots, Chinese dates, `PXL_`, 14-digit stamps, …)
9. **Filesystem time** (opt-in fallback, clearly labelled as *not* a capture time)
10. Nothing → skipped, tagged "no timestamp". **Never guessed.**

Purely numeric names such as `1000000034.jpg`, UUIDs and long hashes are recognized and skipped,
with an extra year-plausibility check on top.

## Naming

**Default output: `IMG_20261012_122123.jpg`** — prefix `IMG_` plus format `%Y%m%d_%H%M%S`.
Both are editable in the UI (clear the prefix and you get `20261012_122123.jpg`).

Patterns: `Date only` (default), `Date_original`, `Original_date`, `Original only`.
Custom strftime-style formats and optional **archiving into date subfolders** (`2024/2024-05/`) are supported too.

## Privacy

- No network access — the server binds to `127.0.0.1` only
- No uploads of files, names or metadata
- No content modification — renaming (plus an optional move for archiving)
- Overwrite protection in both rename and undo directions

## Performance

| Workload | Time |
| --- | --- |
| 100 photos | < 1 s |
| 10 000 files | 20–60 s |
| One 4 GB 4K video | Milliseconds — only the header boxes are read |

Parallel scanning scales with CPU cores; videos are read header-only, never loaded whole.

## Development & testing

```bash
python3 tests/selftest.py
```

49 regression checks cover the parsers, filename rules, the naming engine, the full HTTP flow
(scan → preview → rename → idempotent re-scan → undo) and API security (path traversal protection).
Everything runs in a temp directory and cleans itself up.

## License

[MIT](LICENSE)
