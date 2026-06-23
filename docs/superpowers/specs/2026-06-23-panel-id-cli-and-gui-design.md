# Panel ID — compiled CLI + native GUI

**Date:** 2026-06-23
**Status:** Approved design, pre-implementation
**Repo:** `apple-panel-id` (https://github.com/AlexeyInwerp/apple-panel-id)

## Summary

Add a compiled, native macOS toolset to the existing `apple-panel-id` project:

1. **`panelid`** — a compiled CLI binary that becomes the canonical tool, replacing the
   `panelid.sh` / `panelmap.py` scripts (which move into `research/` as reference
   implementations).
2. **`PanelID.app`** — a small SwiftUI GUI with two views: panel **Identity** (verdict) and
   **TCON Map** (on-panel memory components).

Both are produced from one Swift Package Manager package, share a single tested core, are built
locally for Apple Silicon (arm64), ad-hoc signed (unsigned for distribution), and shipped as a
**v0.1.0** GitHub Release.

## Goals

- One shared, unit-tested core for the panel-identity parse + verdict and the TCON-map parse.
- A compiled CLI that reproduces the behavior of `panelid.sh` and `panelmap.py`, plus `--json`
  output and scriptable exit codes.
- A minimal native GUI surfacing the same two capabilities.
- A self-contained `build.sh` (no external dependencies, no full Xcode required) that produces
  both distributable artifacts.
- A v0.1.0 release with both artifacts and clear install/first-launch instructions.

## Non-goals (v1)

- Notarization / Developer ID signing (distribution is unsigned + ad-hoc signed).
- Universal/Intel binary — arm64 only (all target machines are Apple Silicon).
- Custom app icon (default app icon for v1; trivial to add later).
- Baseline save/compare workflow in the GUI.
- GitHub Actions CI release workflow (local build only for v1).
- In-process IOKit reads (continue shelling to `ioreg`; IOKit is a possible future refinement).
- Any write/modify path — the tool is strictly read-only.

## Architecture

A single Swift Package Manager package with `Package.swift` at the repo root, layered so logic is
written and tested once and reused by both executables.

```
PanelKit (pure, no I/O)  ←── unit tested
   ▲
PanelIO (shells to ioreg, returns parsed models)
   ▲                 ▲
panelid (CLI)     PanelID (SwiftUI GUI)
```

### `PanelKit` — pure library (the only tested target)

No I/O, no `Process`, no IOKit — pure functions over `String`/`Data` so it is fully unit-testable.

- `PanelIdentity` model: `raw: String`, `fields: [String]`, `serial: String` (field 0),
  `status: String` (field 2), `verdict: Verdict`.
- `Verdict` enum: `.likelyGenuine`, `.suspect(reason: String)`, `.absent`.
- `parsePanelID(_ raw: String?) -> PanelIdentity` — splits `raw` on `"+"`, extracts fields,
  computes the verdict (heuristic below). `nil`/empty raw → `.absent`.
- `TCONComponent` model: `name`, `bus` (`SPI`/`I2C`/`if<N>`), `deviceType`, `addr: UInt32`,
  `size: UInt32`, `protection: UInt32`, `verify: UInt32`.
- `parseTCON(_ plist: Data) throws -> [TCONComponent]` — decodes the `AppleTCONComponent` plist
  array (logic below).
- `version` constant (`"0.1.0"`) — used by `panelid --version` and the GUI About string.

#### Verdict heuristic (exact port of `panelid.sh`)

Fields are the `"+"`-split components of the raw string. `serial = fields[0]`,
`status = fields[2]` (guarded for short arrays). Checks are applied in this order, each
overwriting the previous — the **last** matching check wins (faithful to the script's sequential
reassignment):

1. start: `.likelyGenuine`
2. if `status` does not start with `"PROD"` → `.suspect("status field is not PROD")`
3. if `serial` is all zeros (contains no non-`0` character; empty counts) →
   `.suspect("serial field is all zeros")`
4. if `serial.count < 8` → `.suspect("serial field too short")`

Absent (`Panel_ID` not present) is determined at the `PanelIO` layer and maps to `.absent`.

#### TCON parse (exact port of `panelmap.py`)

Input is the plist emitted by `ioreg -arw0 -c AppleTCONComponent` (an array of dicts). For each
dict:

- `reg` (`Data`): `addr = UInt32(littleEndian)` from bytes `0..<4`, `size` from bytes `4..<8`
  (both `0` if `reg` shorter than 8 bytes).
- `interface` (`Data`, first 4 bytes LE): `0 → "SPI"`, `3 → "I2C"`, else `"if<N>"`.
- `protection`, `verify` (`Data`, first 4 bytes LE → `UInt32`, default `0`).
- `name`, `device_type`: decoded ASCII (trailing NULs stripped).
- Display bus/type string = `bus + "/" + device_type`.

### `PanelIO` — I/O library

The single place that runs `ioreg` (via `Foundation.Process`, executable `/usr/sbin/ioreg`) and
hands raw output to `PanelKit`. Returns ready-to-render models; surfaces errors as thrown
errors / typed results.

- `readPanelIdentity() throws -> PanelIdentity` — runs `ioreg -arw0 -r -n disp0`, parses stdout
  as a plist, reads the `Panel_ID` string property from the `disp0` node (more robust than text
  grep). Missing property → `parsePanelID(nil)` → `.absent`.
- `readTCONComponents() throws -> [TCONComponent]` — runs `ioreg -arw0 -c AppleTCONComponent`,
  passes stdout `Data` to `PanelKit.parseTCON`. Empty array if none published.

### `panelid` — CLI executable

Depends on `PanelIO` + `PanelKit`. Hand-rolled argument parsing (no external dependency).

Commands / flags:

- `panelid` — print the identity report (raw string + char count, `"+"`-split fields with
  index/length, serial, status, verdict). Mirrors `panelid.sh` output.
- `panelid map` — print the TCON component table. Mirrors `panelmap.py` output.
- `--json` — on either command, print machine-readable JSON instead of the human table.
- `-h` / `--help` — usage. `--version` — prints `PanelKit.version`.

Exit codes (identity command; scriptable):

- `0` — verdict likely genuine
- `1` — verdict suspect
- `2` — `Panel_ID` absent

`panelid map` exits `0` on success (even with zero components), non-zero only on `ioreg` failure.

### `PanelID` — SwiftUI GUI executable

Depends on `PanelIO` + `PanelKit`. One window, a segmented control switching two views. Reads on
launch and on **Re-scan**.

- **Identity view:** a colored verdict badge — green *Likely genuine*, orange/red
  *Suspect (reason)*, red *Absent*; Serial (field 0) and Status (field 2) rows; a disclosure
  listing all `"+"`-split fields with index + length; the raw string with char count
  (collapsible); **Re-scan** and **Copy report** buttons (Copy produces the same text as the CLI
  human report).
- **TCON Map view:** a table of components — name, bus/type, address (`0x..`), size (`0x..`),
  prot, verify; empty-state text when none are published.

Deployment target macOS 13.0 (Apple Silicon only). Regular app (not an agent/menubar item).

## Data flow

`ioreg` (subprocess) → `PanelIO` parses stdout plist → `PanelKit` pure parse/verdict → rendered
by CLI (stdout text/JSON) or GUI (SwiftUI views). The GUI and CLI never parse `ioreg` output
themselves; all parsing lives in `PanelKit`, all process invocation in `PanelIO`.

## Error handling

- `ioreg` non-zero exit / spawn failure → thrown error; CLI prints a diagnostic to stderr and
  exits non-zero; GUI shows an error state with the message.
- Missing `Panel_ID` → `.absent` (not an error): CLI exit `2`, GUI red Absent badge.
- Malformed plist (TCON) → thrown parse error handled as above; the identity path degrades to
  `.absent` rather than crashing.
- Short/garbled field arrays → guarded indexing; verdict still computed from whatever fields
  exist.

## Build & packaging — `build.sh`

Self-contained, requires only the installed Command Line Tools (Swift 6.2, `swiftc`, `codesign`,
`ditto`, `tar`). No full Xcode, no network.

1. `VERSION=0.1.0` (kept in sync with `PanelKit.version`).
2. Clean and recreate `dist/`.
3. `swift build -c release --arch arm64` (builds `panelid` and `PanelID`).
4. **CLI:** copy `.build/release/panelid` → `dist/panelid`; `codesign --force --sign - dist/panelid`.
5. **GUI:** assemble `dist/PanelID.app/Contents/`:
   - `MacOS/PanelID` (copied from `.build/release/PanelID`)
   - generated `Info.plist`: `CFBundleIdentifier=com.alexeyinwerp.apple-panel-id`,
     `CFBundleName=Panel ID`, `CFBundleExecutable=PanelID`, `CFBundleShortVersionString=0.1.0`,
     `CFBundleVersion=1`, `CFBundlePackageType=APPL`, `LSMinimumSystemVersion=13.0`,
     `NSHighResolutionCapable=true`
   - `codesign --force --deep --sign - dist/PanelID.app`
6. Package artifacts:
   - `ditto -c -k --keepParent dist/PanelID.app dist/PanelID-v0.1.0-arm64.zip`
   - `tar -czf dist/panelid-v0.1.0-arm64.tar.gz -C dist panelid`

## Distribution

- Run `build.sh` locally on this Apple Silicon Mac.
- Cut GitHub Release **v0.1.0** (tag `v0.1.0`) with both assets attached:
  `PanelID-v0.1.0-arm64.zip` and `panelid-v0.1.0-arm64.tar.gz`.
- README gets an **Install** section:
  - CLI: download, extract, `xattr -dr com.apple.quarantine panelid`, move to a `PATH` dir.
  - GUI: download, unzip, first launch via right-click → **Open** (or
    `xattr -dr com.apple.quarantine PanelID.app`), because the build is unsigned.
- The raw `ioreg -lw0 -r -n disp0 | grep Panel_ID` one-liner stays in the README as the
  zero-install path.

## Repo layout changes

```
Package.swift                 (new, at repo root)
Sources/
  PanelKit/                   (new — pure parse + verdict + TCON)
  PanelIO/                    (new — ioreg invocation)
  panelid/                    (new — CLI)
  PanelID/                    (new — SwiftUI app)
Tests/PanelKitTests/          (new)
build.sh                      (new)
dist/                         (new, gitignored)
research/
  panelid.sh                  (moved here from root)
  panelmap.py                 (moved here from root)
  README.md                   (updated: note these are the reference scripts)
  holder.m, objcdump.m, probe.c, tcontool.m
README.md                     (updated: Install section, scripts relocated)
.gitignore                    (add /dist/ and /.build/)
LICENSE                       (unchanged)
```

## Testing strategy

`swift test` runs `PanelKitTests` (XCTest), covering the pure core with fixtures:

- **Verdict branches:** likely-genuine (PROD status, long serial); status-not-PROD;
  serial-all-zeros; serial-too-short; verify the last-match-wins precedence (e.g. a short
  all-zeros serial reports "too short").
- **Absent:** `parsePanelID(nil)` and `parsePanelID("")` → `.absent`.
- **Field splitting:** correct count, indices, and per-field lengths for a representative raw
  string.
- **TCON parse:** a small constructed plist `Data` fixture → expected rows, including
  little-endian `addr`/`size` decoding and the `0→SPI`, `3→I2C`, other→`if<N>` bus mapping, and
  short-`reg` defaulting to `0`.

`PanelIO` and the executables are exercised manually on the dev Mac (real `ioreg`); only the pure
core is unit-tested, matching the module boundaries.

## Decisions (resolved during brainstorming)

- GUI scope: Identity + TCON Map (not baseline-compare).
- CLI replaces the scripts as canonical; scripts move to `research/`.
- Signing: unsigned, ad-hoc signed; documented first-launch step.
- Build/ship: local build now + `build.sh`, v0.1.0 release.
- Root-level `Package.swift`; no external CLI-args dependency; bundle id
  `com.alexeyinwerp.apple-panel-id`; no custom icon in v1.
