# research/ — exploration of the gated paths

These are the dead ends I walked before finding that `Panel_ID` in the I/O Registry already
exposes everything needed. They're kept because they document *why* the simple method is the
right one, and they're small, self-contained examples of poking at private display interfaces.

**None of these return panel data on a normally-booted Mac.** Use the compiled `panelid` CLI.

> `panelid.sh` and `panelmap.py` also live in this directory. They are the original shell / Python
> reference implementations of the method that works. The shipping tool is the compiled **`panelid`**
> CLI (built from `../Sources/`), which reproduces their behavior; the scripts remain as readable,
> dependency-free documentation. `panelid.sh` reads and parses `Panel_ID`; `panelmap.py` lists the
> on-panel TCON memories.

| File | What it probes | Result |
|------|----------------|--------|
| `probe.c` | Opens the `IOAVDisplayMemoryConcreteUserClient` IOKit user client on each on-panel memory node. | `IOServiceOpen` returns `kIOReturnBadArgument` — the user client needs a specific connection type and (almost certainly) a private entitlement. |
| `objcdump.m` | Loads `AppleDisplayTCONControl.framework` and enumerates its Objective-C classes/methods at runtime. | Reveals `ADIOReportingInterface` with `-getSerialNumber`, `-getDeviceInfo`, etc. |
| `holder.m` | Loads that framework and parks the process so a debugger can attach for static inspection. | Helper only. |
| `tcontool.m` | Calls `ADIOReportingInterface -getSerialNumber` / `-getDeviceInfo` for several container IDs. | Returns `nil`: the methods proxy to an XPC service (`com.apple.AppleDisplayTCONControl.IOReporting`) that is **not registered** on a normal Mac — it's part of an external-display / diagnostic facility. |

## Build & run

```bash
clang probe.c    -o probe    -framework IOKit -framework CoreFoundation
clang objcdump.m -o objcdump -framework Foundation -fobjc-arc
clang holder.m   -o holder   -framework Foundation
clang tcontool.m -o tcontool -framework Foundation -fobjc-arc
```

## Takeaway

The clean APIs exist but are reserved for Apple-signed/entitled callers and an XPC service that
isn't present in normal operation. Meanwhile the DCP already publishes the parsed panel identity
as `disp0`'s `Panel_ID` property, readable by anyone. That's the whole tool.
