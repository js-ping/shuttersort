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
- Rename rule chains: insert / delete / replace / strip / case
- Fully offline. Nothing is uploaded.

## Install

1. Download the `.dmg`, drag the app into Applications.
2. First launch is blocked by Gatekeeper (no paid developer certificate): **right-click the app → Open → Open**.
3. Drop a folder into the window, check the preview, hit rename.

## Build from source

Command Line Tools only, no Xcode:

```bash
cd native
./build.sh --universal --zip --dmg
```

The version comes from the `VERSION` file in the repo root.

## Notes

- Chinese UI, macOS only. Windows / Linux builds were dropped in 1.8.0 and stay in the Release history.
- See [CHANGELOG.md](CHANGELOG.md) for version history.

## License

MIT
