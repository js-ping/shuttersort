# ShutterSort

Rename phone photos to their real capture time. **Renames only — file contents are never touched.**

macOS 14+ · universal (Apple silicon / Intel) · MIT

**Download**: the latest `.dmg` from [Releases](../../releases)

---

## What it does

```
IMG_8734.HEIC   →   IMG_20240506_153008.HEIC
```

After renaming, sorting by filename equals sorting by capture time.

- Undo anything, any time (records persist across launches)
- Batch a whole folder, or pick individual files
- Time correction for a camera with a wrong clock
- Sub-second ordering for bursts
- **Six rename rule types**: insert / delete / replace / strip / clean up / change case
  - No counting positions by hand — a clickable strip of characters sits under each position rule; spaces show as `·`, tabs as `→`
  - "Clean up" handles whatever an export tool bolted on: `photo(1)` → `photo`, plus stray spaces, underscores, and emoji
- **Presets**: save the date format, prefix/suffix, archiving, and the whole rule chain as one named setup
- Fully offline. Nothing is uploaded.

## Install

1. Download the `.dmg`, drag the app into Applications.
2. First launch is blocked by Gatekeeper (no paid developer certificate): **right-click the app → Open → Open**.
3. A three-step guide appears on first launch. Drop a folder into the window, check the preview, hit rename.

## FAQ

| Symptom | Cause / fix |
|---|---|
| The time shown is when the file arrived | No capture-time metadata inside (common for files forwarded through chat apps). It falls back to the filesystem time and labels the source |
| I want the filesystem-time fallback | Switch "Timestamp source" to file modified / created time — the list recalculates **immediately**, no rescan needed |
| Video times are 8 hours off | Fixed in 1.3.1 (QuickTime stores UTC; older builds read it as local time) |
| MKV / AVI show no time | Those containers have no standard creation-time field; filename or filesystem time only |
| Will re-running the same batch change anything? | No. Collision detection excludes the file itself and names vacated in the same run |
| How do I drop `(1)` or `[copy]` from names | Add a "Clean up" rule with "brackets" ticked — handles full-width brackets and nesting |

## Build from source

Command Line Tools only, no Xcode:

```bash
cd native
./build.sh --universal --zip --dmg
```

The version comes from the `VERSION` file in the repo root.

## Tests

```bash
cd native
python3 tests/run_parity.py                 # field-by-field vs the old Python build, 3878 checks

swiftc -O Sources/Core/*.swift Sources/CLI/main.swift -o /tmp/ss-cli
/tmp/ss-cli edit-test                       # 53 rename-rule assertions

swiftc -O Sources/Core/*.swift tests/preset-test.swift -o /tmp/ss-preset
/tmp/ss-preset /tmp/ss-preset-dir           # 14 preset read/write assertions
```

Two more gates cover UI behaviour (build a corpus first: `python3 tests/mkcorpus.py --out /tmp/corpus`):

```bash
# Timestamp-source switching: 9 assertions across skip → modified → created → skip
swiftc -O Sources/Core/*.swift Sources/UI/AppState.swift tests/fallback-test.swift \
    -o /tmp/ss-fb -framework SwiftUI -framework AppKit
/tmp/ss-fb /tmp/corpus

# Offscreen UI snapshots, for column widths, clipped text, light/dark
tests/snapshots.sh          # light
tests/snapshots.sh --dark   # dark
```

## Notes

- Chinese UI, macOS only. Windows / Linux builds were dropped in 1.8.0 and stay in the Release history.
- Presets live in `~/Library/Application Support/ShutterSort/presets.json`.
- See [CHANGELOG.md](CHANGELOG.md) for version history.

## License

MIT
