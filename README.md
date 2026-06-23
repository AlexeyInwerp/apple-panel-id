# apple-panel-id

Read the **internal display panel identity** of an Apple Silicon Mac — including the panel
serial number and a genuine/aftermarket indicator — straight from the I/O Registry. No root,
no entitlements, no disassembly, no hardware.

On Apple Silicon, the built-in display is driven through a display coprocessor (DCP) and an
on-panel timing controller (TCON) that carries a small non-volatile memory. At boot the DCP
reads that memory and republishes the panel's identity record in the I/O Registry as the
`Panel_ID` property of the `disp0` node. This tool reads and parses it.

Useful for repair/refurb work: a genuine, factory-serialized Apple panel exposes a full,
well-formed identity record; a non-serialized or aftermarket panel typically does not.

## Install

Pre-compiled for Apple Silicon (arm64). Downloads are **unsigned**, so macOS quarantines them on
first run — clear it once as shown.

**CLI (`panelid`):**

```bash
# download panelid-v0.1.0-arm64.tar.gz from Releases, then:
tar -xzf panelid-v0.1.0-arm64.tar.gz
xattr -dr com.apple.quarantine panelid
./panelid          # identity + verdict
./panelid map      # on-panel TCON memory map
./panelid --json   # machine-readable
# optionally: sudo mv panelid /usr/local/bin/
```

**GUI (`PanelID.app`):** download `PanelID-v0.1.0-arm64.zip`, unzip, then **right-click → Open**
the app the first time (or `xattr -dr com.apple.quarantine PanelID.app`).

**Zero-install (no download):** read the raw record straight from the I/O Registry:

```bash
ioreg -lw0 -r -n disp0 | grep Panel_ID
```

## Quick start

```bash
./panelid
```

Example output (serial masked):

```
Panel_ID (raw, 170 chars):
  F0Y20########609B+000000004M22F2+PROD+B000000000000+0000…0000+PA07N0108Y21011214+…

Fields (split on '+'):
  [0] len=17  F0Y20########609B
  [1] len=14  000000004M22F2
  [2] len=4   PROD
  [3] len=13  B000000000000
  [4] len=26  0000000000000000000000000
  [5] len=18  PA07N0108Y21011214
  [6] len=33  ………
  [7] len=38  ………

Serial-number field [0] : F0Y20########609B
Build/status field  [2] : PROD
Heuristic verdict       : LIKELY GENUINE
```

## Determining if a panel is genuine

Run `panelid` on a **known-genuine** Mac to establish a baseline, then on the **suspect**
Mac and compare. A non-serialized / aftermarket / refurbished panel commonly shows one of:

- `Panel_ID` **absent** entirely,
- field `[0]` (serial) **all zeros** or generic,
- field `[2]` (build/status) **not `PROD`** (empty, or an engineering marker),
- or the whole record zeroed / malformed.

Any of those, measured against your genuine baseline, is strong evidence of a non-genuine panel.
The check is non-invasive and works on any Mac that boots.

## Field meanings — read this

The **bytes are read live** from the I/O Registry and are accurate. The **meaning of each
`+`-delimited field is inferred** from observation, not from any official specification — Apple
does not publish this record's layout. Field `[0]` is the panel serial; field `[2]` (`PROD`) is
a manufacturing build-status marker. Treat the rest as opaque unless you've corroborated it
yourself across multiple panels. Don't make irreversible decisions on an inferred field.

## Tools

| Tool | What it does |
|------|--------------|
| `panelid` (CLI) | Reads `Panel_ID`, splits the fields, prints a genuine/suspect verdict. `panelid map` lists the on-panel TCON memories (I²C/SPI bus + address); `--json` emits machine-readable output. |
| `PanelID.app` (GUI) | The same two capabilities in a small native window — an **Identity** view (verdict) and a **TCON Map** view. |
| `research/` | The original `panelid.sh` / `panelmap.py` reference scripts, plus exploration of the *gated* programmatic paths (private framework + IOKit user client). See `research/README.md`. |

## Build from source

Requires the Xcode Command Line Tools (Swift 6+) — no full Xcode needed.

```bash
swift run paneltests   # run the PanelKit unit-test harness
./build.sh             # produces dist/panelid + dist/PanelID.app and release archives
```

## Requirements

- Apple Silicon Mac with a built-in display, macOS 13+.
- The pre-built binaries are arm64 and use only stock `ioreg`. Building from source needs the
  Swift toolchain (Command Line Tools). The reference scripts in `research/` use `zsh` / `python3`.

## Caveats

- Tested on an M1 Pro (14"/16"-class panel). The `Panel_ID` record format may vary across panel
  generations and vendors; the parser splits on `+` and makes no assumptions beyond that.
- The genuine/suspect verdict is a **heuristic**, not an authoritative authentication. It is a
  triage aid, not proof. Corroborate before acting.

## License

MIT — see [LICENSE](LICENSE).
