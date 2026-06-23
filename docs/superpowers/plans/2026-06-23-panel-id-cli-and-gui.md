# Panel ID CLI + GUI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a compiled `panelid` CLI and a small SwiftUI `PanelID.app` from one Swift package, sharing a tested `PanelKit` core, and ship them as a v0.1.0 GitHub Release.

**Architecture:** `PanelKit` (pure parse + verdict + report formatting, unit-tested) ← `PanelIO` (shells to `ioreg`) ← two executables (`panelid` CLI, `PanelID` SwiftUI app). The CLI replaces the `panelid.sh`/`panelmap.py` scripts, which move to `research/`.

**Tech Stack:** Swift 6.2 (Command Line Tools, no Xcode), Swift Package Manager, SwiftUI, `Foundation.Process` + `PropertyListSerialization`, `codesign`/`ditto`/`tar`, `gh`.

## Global Constraints

- Deployment target: **macOS 13.0**, **arm64 only**.
- **No external SPM dependencies** (hand-rolled CLI arg parsing).
- Bundle identifier: `com.alexeyinwerp.apple-panel-id`. App display name: `Panel ID`.
- Version `0.1.0` — keep `PanelKit.panelIDVersion` and `build.sh`'s `VERSION` in sync.
- Distribution is **unsigned / ad-hoc signed** (`codesign --sign -`).
- Strictly **read-only**: only ever runs `/usr/sbin/ioreg`; never writes to hardware.
- Verdict heuristic is an exact port of `research/panelid.sh`: sequential checks, **last match wins** (status≠PROD → all-zeros serial → serial<8 chars), `.absent` when `Panel_ID` missing.
- TCON decode is an exact port of `research/panelmap.py`: `reg` bytes `0..<4`/`4..<8` little-endian for addr/size (both 0 if `reg`<8 bytes); `interface`/`protection`/`verify` little-endian over available bytes; bus `0→SPI`, `3→I2C`, else `if<N>`.
- All branches on `main`: this work lives on branch `cli-and-gui`; Task 8 merges it.

---

### Task 1: Package scaffold + PanelKit identity parser

**Files:**
- Create: `Package.swift`
- Create: `Sources/PanelKit/PanelIdentity.swift`
- Test: `Tests/PanelKitTests/PanelIdentityTests.swift`

**Interfaces:**
- Produces: `public let panelIDVersion: String`; `public enum Verdict: Equatable { case likelyGenuine; case suspect(reason: String); case absent }` with `var label: String` and `var exitCode: Int32`; `public struct PanelIdentity: Equatable` with `raw: String`, `fields: [String]`, `verdict: Verdict`, computed `serial: String` (field 0), `status: String` (field 2); `public func parsePanelID(_ raw: String?) -> PanelIdentity`.

- [ ] **Step 1: Create the package manifest and an empty PanelKit source**

`Package.swift`:
```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PanelID",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "panelid", targets: ["panelid"]),
        .executable(name: "PanelID", targets: ["PanelID"]),
        .library(name: "PanelKit", targets: ["PanelKit"]),
    ],
    targets: [
        .target(name: "PanelKit"),
        .target(name: "PanelIO", dependencies: ["PanelKit"]),
        .executableTarget(name: "panelid", dependencies: ["PanelKit", "PanelIO"]),
        .executableTarget(name: "PanelID", dependencies: ["PanelKit", "PanelIO"]),
        .testTarget(name: "PanelKitTests", dependencies: ["PanelKit"]),
    ],
    swiftLanguageModes: [.v5]
)
```

Create placeholder sources so the package compiles before later tasks fill them in:
- `Sources/PanelKit/PanelKit.swift` → `public let panelIDVersion = "0.1.0"`
- `Sources/PanelIO/PanelIO.swift` → `// filled in Task 4`
- `Sources/panelid/main.swift` → `// filled in Task 4` followed by `print("")`
- `Sources/PanelID/Placeholder.swift` → `// filled in Task 5`

> Note: `Sources/PanelID/` will get its real `@main` entrypoint in Task 5; the placeholder file just lets the package resolve. Delete `Placeholder.swift` in Task 5.

- [ ] **Step 2: Write the failing test**

`Tests/PanelKitTests/PanelIdentityTests.swift`:
```swift
import XCTest
@testable import PanelKit

final class PanelIdentityTests: XCTestCase {
    // A genuine-shaped record: long serial, PROD status.
    let genuine = "F0Y20ABCDEF609B+000000004M22F2+PROD+B000000000000+0000000000000000000000000+PA07N0108Y21011214"

    func testLikelyGenuine() {
        let id = parsePanelID(genuine)
        XCTAssertEqual(id.verdict, .likelyGenuine)
        XCTAssertEqual(id.serial, "F0Y20ABCDEF609B")
        XCTAssertEqual(id.status, "PROD")
        XCTAssertEqual(id.fields.count, 6)
    }

    func testStatusNotProd() {
        let raw = "F0Y20ABCDEF609B+000000004M22F2+ENGR+x"
        XCTAssertEqual(parsePanelID(raw).verdict, .suspect(reason: "status field is not PROD"))
    }

    func testSerialAllZeros() {
        // 16-char all-zero serial, PROD status -> all-zeros wins (length ok).
        let raw = "0000000000000000+000000004M22F2+PROD+x"
        XCTAssertEqual(parsePanelID(raw).verdict, .suspect(reason: "serial field is all zeros"))
    }

    func testSerialTooShort() {
        // Short all-zeros serial -> "too short" wins (last check).
        let raw = "0000+000000004M22F2+PROD+x"
        XCTAssertEqual(parsePanelID(raw).verdict, .suspect(reason: "serial field too short"))
    }

    func testAbsent() {
        XCTAssertEqual(parsePanelID(nil).verdict, .absent)
        XCTAssertEqual(parsePanelID("").verdict, .absent)
    }

    func testExitCodes() {
        XCTAssertEqual(Verdict.likelyGenuine.exitCode, 0)
        XCTAssertEqual(Verdict.suspect(reason: "x").exitCode, 1)
        XCTAssertEqual(Verdict.absent.exitCode, 2)
    }
}
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `swift test --filter PanelIdentityTests`
Expected: FAIL — compile error, `cannot find 'parsePanelID' in scope` / `Verdict`/`PanelIdentity` undefined.

- [ ] **Step 4: Implement the parser**

`Sources/PanelKit/PanelIdentity.swift`:
```swift
import Foundation

public enum Verdict: Equatable {
    case likelyGenuine
    case suspect(reason: String)
    case absent

    public var label: String {
        switch self {
        case .likelyGenuine: return "LIKELY GENUINE"
        case .suspect(let reason): return "SUSPECT (\(reason))"
        case .absent: return "ABSENT"
        }
    }

    /// Process exit code: 0 genuine, 1 suspect, 2 absent.
    public var exitCode: Int32 {
        switch self {
        case .likelyGenuine: return 0
        case .suspect: return 1
        case .absent: return 2
        }
    }
}

public struct PanelIdentity: Equatable {
    public let raw: String
    public let fields: [String]
    public let verdict: Verdict

    public init(raw: String, fields: [String], verdict: Verdict) {
        self.raw = raw
        self.fields = fields
        self.verdict = verdict
    }

    public var serial: String { fields.indices.contains(0) ? fields[0] : "" }
    public var status: String { fields.indices.contains(2) ? fields[2] : "" }
}

/// Parse a raw Panel_ID string into fields + a heuristic verdict.
/// Exact port of research/panelid.sh: sequential checks, last match wins.
public func parsePanelID(_ raw: String?) -> PanelIdentity {
    guard let raw, !raw.isEmpty else {
        return PanelIdentity(raw: "", fields: [], verdict: .absent)
    }
    let fields = raw.components(separatedBy: "+")
    let serial = fields.indices.contains(0) ? fields[0] : ""
    let status = fields.indices.contains(2) ? fields[2] : ""

    var verdict: Verdict = .likelyGenuine
    if !status.hasPrefix("PROD") {
        verdict = .suspect(reason: "status field is not PROD")
    }
    if serial.allSatisfy({ $0 == "0" }) {   // empty string also satisfies (all-zeros)
        verdict = .suspect(reason: "serial field is all zeros")
    }
    if serial.count < 8 {
        verdict = .suspect(reason: "serial field too short")
    }
    return PanelIdentity(raw: raw, fields: fields, verdict: verdict)
}
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `swift test --filter PanelIdentityTests`
Expected: PASS (6 tests).

- [ ] **Step 6: Commit**

```bash
git add Package.swift Sources Tests
git commit -m "feat: Swift package scaffold + PanelKit identity parser"
```

---

### Task 2: PanelKit TCON parser

**Files:**
- Create: `Sources/PanelKit/TCONComponent.swift`
- Test: `Tests/PanelKitTests/TCONTests.swift`

**Interfaces:**
- Produces: `public struct TCONComponent: Equatable` with `name`, `bus`, `deviceType: String`, `addr`, `size`, `protection`, `verify: UInt32`, computed `busType: String` (`"<bus>/<deviceType>"`); `public func parseTCON(_ plist: Data) throws -> [TCONComponent]`; `public enum TCONParseError: Error { case notAnArray }`.

- [ ] **Step 1: Write the failing test**

`Tests/PanelKitTests/TCONTests.swift`:
```swift
import XCTest
@testable import PanelKit

final class TCONTests: XCTestCase {
    func testParseI2CComponent() throws {
        let comp: [String: Any] = [
            "name": Data("tcon0\u{0}".utf8),
            "device_type": Data("eeprom\u{0}".utf8),
            "reg": Data([0x50, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00]), // addr 0x50, size 0x100
            "interface": Data([0x03, 0x00, 0x00, 0x00]),                    // I2C
            "protection": Data([0x01, 0x00, 0x00, 0x00]),
            "verify": Data([0x00, 0x00, 0x00, 0x00]),
        ]
        let data = try PropertyListSerialization.data(
            fromPropertyList: [comp] as [Any], format: .xml, options: 0)
        let rows = try parseTCON(data)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].name, "tcon0")
        XCTAssertEqual(rows[0].deviceType, "eeprom")
        XCTAssertEqual(rows[0].bus, "I2C")
        XCTAssertEqual(rows[0].busType, "I2C/eeprom")
        XCTAssertEqual(rows[0].addr, 0x50)
        XCTAssertEqual(rows[0].size, 0x100)
        XCTAssertEqual(rows[0].protection, 1)
        XCTAssertEqual(rows[0].verify, 0)
    }

    func testSpiAndShortRegAndStringNames() throws {
        let comp: [String: Any] = [
            "name": "spi0",              // String form
            "device_type": "flash",
            "reg": Data([0x01, 0x02]),   // < 8 bytes -> addr/size 0
            "interface": Data([0x00]),   // SPI, single byte
        ]
        let data = try PropertyListSerialization.data(
            fromPropertyList: [comp] as [Any], format: .binary, options: 0)
        let rows = try parseTCON(data)
        XCTAssertEqual(rows[0].bus, "SPI")
        XCTAssertEqual(rows[0].name, "spi0")
        XCTAssertEqual(rows[0].addr, 0)
        XCTAssertEqual(rows[0].size, 0)
        XCTAssertEqual(rows[0].protection, 0) // missing key -> 0
    }

    func testEmptyArray() throws {
        let data = try PropertyListSerialization.data(
            fromPropertyList: [] as [Any], format: .xml, options: 0)
        XCTAssertEqual(try parseTCON(data).count, 0)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter TCONTests`
Expected: FAIL — `cannot find 'parseTCON'` / `TCONComponent` undefined.

- [ ] **Step 3: Implement the TCON parser**

`Sources/PanelKit/TCONComponent.swift`:
```swift
import Foundation

public struct TCONComponent: Equatable {
    public let name: String
    public let bus: String          // "SPI", "I2C", or "if<N>"
    public let deviceType: String
    public let addr: UInt32
    public let size: UInt32
    public let protection: UInt32
    public let verify: UInt32

    public init(name: String, bus: String, deviceType: String,
                addr: UInt32, size: UInt32, protection: UInt32, verify: UInt32) {
        self.name = name; self.bus = bus; self.deviceType = deviceType
        self.addr = addr; self.size = size; self.protection = protection; self.verify = verify
    }

    public var busType: String { "\(bus)/\(deviceType)" }
}

public enum TCONParseError: Error { case notAnArray }

/// Parse the plist emitted by `ioreg -arw0 -c AppleTCONComponent` (array of dicts).
/// Exact port of research/panelmap.py.
public func parseTCON(_ plist: Data) throws -> [TCONComponent] {
    let obj = try PropertyListSerialization.propertyList(from: plist, format: nil)
    guard let array = obj as? [Any] else { throw TCONParseError.notAnArray }
    return array.compactMap { $0 as? [String: Any] }.map { dict in
        let reg = dataValue(dict["reg"])
        let addr = reg.count >= 8 ? leUInt32(reg, offset: 0) : 0
        let size = reg.count >= 8 ? leUInt32(reg, offset: 4) : 0
        let iface = leUInt32(dataValue(dict["interface"]))
        let bus: String
        switch iface {
        case 0: bus = "SPI"
        case 3: bus = "I2C"
        default: bus = "if\(iface)"
        }
        return TCONComponent(
            name: asciiString(dict["name"]),
            bus: bus,
            deviceType: asciiString(dict["device_type"]),
            addr: addr,
            size: size,
            protection: leUInt32(dataValue(dict["protection"])),
            verify: leUInt32(dataValue(dict["verify"]))
        )
    }
}

private func dataValue(_ value: Any?) -> Data { (value as? Data) ?? Data() }

/// Little-endian UInt32 from up to 4 bytes at `offset` (missing bytes treated as 0).
private func leUInt32(_ data: Data, offset: Int = 0) -> UInt32 {
    var result: UInt32 = 0
    for i in 0..<4 {
        let idx = data.startIndex + offset + i
        if idx < data.endIndex { result |= UInt32(data[idx]) << (8 * i) }
    }
    return result
}

/// Decode an ioreg value (Data or String) to ASCII, stripping trailing NULs.
private func asciiString(_ value: Any?) -> String {
    if let d = value as? Data {
        var bytes = [UInt8](d)
        while bytes.last == 0 { bytes.removeLast() }
        return String(decoding: bytes, as: UTF8.self)
    }
    if let s = value as? String { return s }
    if let n = value as? NSNumber { return n.stringValue }
    return ""
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `swift test --filter TCONTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/PanelKit/TCONComponent.swift Tests/PanelKitTests/TCONTests.swift
git commit -m "feat: PanelKit TCON component parser"
```

---

### Task 3: PanelKit report formatters (human + JSON)

**Files:**
- Create: `Sources/PanelKit/Report.swift`
- Test: `Tests/PanelKitTests/ReportTests.swift`

**Interfaces:**
- Produces: `public func identityReport(_ id: PanelIdentity) -> String`; `public func tconReport(_ comps: [TCONComponent]) -> String`; `public func identityJSON(_ id: PanelIdentity) -> String`; `public func tconJSON(_ comps: [TCONComponent]) -> String`.

- [ ] **Step 1: Write the failing test**

`Tests/PanelKitTests/ReportTests.swift`:
```swift
import XCTest
@testable import PanelKit

final class ReportTests: XCTestCase {
    let genuine = "F0Y20ABCDEF609B+000000004M22F2+PROD+B000000000000"

    func testIdentityReportHuman() {
        let r = identityReport(parsePanelID(genuine))
        XCTAssertTrue(r.contains("Panel_ID (raw, \(genuine.count) chars):"))
        XCTAssertTrue(r.contains("[0] len=15"))
        XCTAssertTrue(r.contains("Serial-number field [0] : F0Y20ABCDEF609B"))
        XCTAssertTrue(r.contains("Heuristic verdict       : LIKELY GENUINE"))
    }

    func testIdentityReportAbsent() {
        XCTAssertTrue(identityReport(parsePanelID(nil)).contains("<ABSENT>"))
    }

    func testIdentityJSON() throws {
        let json = identityJSON(parsePanelID(genuine))
        let obj = try JSONSerialization.jsonObject(with: Data(json.utf8)) as! [String: Any]
        XCTAssertEqual(obj["present"] as? Bool, true)
        XCTAssertEqual(obj["verdict"] as? String, "likely_genuine")
        XCTAssertEqual(obj["serial"] as? String, "F0Y20ABCDEF609B")
        XCTAssertEqual(obj["charCount"] as? Int, genuine.count)
    }

    func testTconReportAndJSON() throws {
        let c = TCONComponent(name: "tcon0", bus: "I2C", deviceType: "eeprom",
                              addr: 0x50, size: 0x100, protection: 1, verify: 0)
        let human = tconReport([c])
        XCTAssertTrue(human.contains("I2C/eeprom"))
        XCTAssertTrue(human.contains("0x50"))

        let json = tconJSON([c])
        let arr = try JSONSerialization.jsonObject(with: Data(json.utf8)) as! [[String: Any]]
        XCTAssertEqual(arr.count, 1)
        XCTAssertEqual(arr[0]["bus"] as? String, "I2C")
        XCTAssertEqual(arr[0]["addr"] as? Int, 0x50)
    }

    func testTconReportEmpty() {
        XCTAssertTrue(tconReport([]).lowercased().contains("no "))
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter ReportTests`
Expected: FAIL — `cannot find 'identityReport'` etc.

- [ ] **Step 3: Implement the formatters**

`Sources/PanelKit/Report.swift`:
```swift
import Foundation

// MARK: - Human-readable

public func identityReport(_ id: PanelIdentity) -> String {
    if id.verdict == .absent {
        return "Panel_ID : <ABSENT>   <-- no panel identity published (strong SUSPECT signal)"
    }
    var lines: [String] = []
    lines.append("Panel_ID (raw, \(id.raw.count) chars):")
    lines.append("  \(id.raw)")
    lines.append("")
    lines.append("Fields (split on '+'):")
    for (i, f) in id.fields.enumerated() {
        lines.append("  [\(i)] len=\(rpad(String(f.count), 3)) \(f)")
    }
    lines.append("")
    lines.append("Serial-number field [0] : \(id.serial)")
    lines.append("Build/status field  [2] : \(id.status)")
    lines.append("Heuristic verdict       : \(id.verdict.label)")
    return lines.joined(separator: "\n")
}

public func tconReport(_ comps: [TCONComponent]) -> String {
    guard !comps.isEmpty else {
        return "No TCON memory components published by this Mac."
    }
    var lines: [String] = []
    lines.append("\(rpad("COMPONENT", 16)) \(rpad("BUS/TYPE", 24)) \(rpad("ADDR", 6)) \(rpad("SIZE", 8)) prot verify")
    for c in comps {
        let addr = String(format: "0x%02x", c.addr)
        let size = String(format: "0x%x", c.size)
        lines.append("\(rpad(c.name, 16)) \(rpad(c.busType, 24)) \(rpad(addr, 6)) \(rpad(size, 8)) \(rpad(String(c.protection), 4)) \(c.verify)")
    }
    return lines.joined(separator: "\n")
}

private func rpad(_ s: String, _ width: Int) -> String {
    s.count >= width ? s : s + String(repeating: " ", count: width - s.count)
}

// MARK: - JSON

private struct IdentityDTO: Encodable {
    let present: Bool
    let raw: String
    let charCount: Int
    let fields: [String]
    let serial: String
    let status: String
    let verdict: String
    let verdictReason: String?
    let verdictLabel: String
}

private struct TCONDTO: Encodable {
    let name: String
    let bus: String
    let deviceType: String
    let busType: String
    let addr: UInt32
    let size: UInt32
    let protection: UInt32
    let verify: UInt32
}

public func identityJSON(_ id: PanelIdentity) -> String {
    let code: String
    let reason: String?
    switch id.verdict {
    case .likelyGenuine: code = "likely_genuine"; reason = nil
    case .suspect(let r): code = "suspect"; reason = r
    case .absent: code = "absent"; reason = nil
    }
    let dto = IdentityDTO(
        present: id.verdict != .absent,
        raw: id.raw, charCount: id.raw.count, fields: id.fields,
        serial: id.serial, status: id.status,
        verdict: code, verdictReason: reason, verdictLabel: id.verdict.label)
    return encodeJSON(dto)
}

public func tconJSON(_ comps: [TCONComponent]) -> String {
    let dtos = comps.map {
        TCONDTO(name: $0.name, bus: $0.bus, deviceType: $0.deviceType, busType: $0.busType,
                addr: $0.addr, size: $0.size, protection: $0.protection, verify: $0.verify)
    }
    return encodeJSON(dtos)
}

private func encodeJSON<T: Encodable>(_ value: T) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    guard let data = try? encoder.encode(value),
          let s = String(data: data, encoding: .utf8) else { return "{}" }
    return s
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `swift test --filter ReportTests`
Expected: PASS (5 tests). Then run the whole suite: `swift test` → all green.

- [ ] **Step 5: Commit**

```bash
git add Sources/PanelKit/Report.swift Tests/PanelKitTests/ReportTests.swift
git commit -m "feat: PanelKit human + JSON report formatters"
```

---

### Task 4: PanelIO + `panelid` CLI

**Files:**
- Create: `Sources/PanelIO/IORegistry.swift` (replaces `Sources/PanelIO/PanelIO.swift` placeholder — delete the placeholder)
- Create: `Sources/panelid/main.swift` (replaces the placeholder content)

**Interfaces:**
- Produces (PanelIO): `public func readPanelIdentity() throws -> PanelIdentity`; `public func readTCONComponents() throws -> [TCONComponent]`; `public enum IORegistryError: Error, CustomStringConvertible`.
- Consumes: all `PanelKit` symbols from Tasks 1–3.

- [ ] **Step 1: Implement PanelIO**

Delete `Sources/PanelIO/PanelIO.swift`. Create `Sources/PanelIO/IORegistry.swift`:
```swift
import Foundation
import PanelKit

public enum IORegistryError: Error, CustomStringConvertible {
    case launchFailed(String)
    case ioregFailed(status: Int32, stderr: String)

    public var description: String {
        switch self {
        case .launchFailed(let m): return "failed to launch ioreg: \(m)"
        case .ioregFailed(let s, let e):
            return "ioreg exited with status \(s)" + (e.isEmpty ? "" : ": \(e)")
        }
    }
}

private func runIoreg(_ args: [String]) throws -> Data {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/sbin/ioreg")
    p.arguments = args
    let out = Pipe(), err = Pipe()
    p.standardOutput = out
    p.standardError = err
    do { try p.run() } catch { throw IORegistryError.launchFailed(error.localizedDescription) }
    let outData = out.fileHandleForReading.readDataToEndOfFile()
    let errData = err.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    guard p.terminationStatus == 0 else {
        throw IORegistryError.ioregFailed(status: p.terminationStatus,
                                          stderr: String(decoding: errData, as: UTF8.self))
    }
    return outData
}

/// Read the built-in display panel identity (disp0's Panel_ID property).
public func readPanelIdentity() throws -> PanelIdentity {
    let data = try runIoreg(["-arw0", "-r", "-n", "disp0"])
    let raw = findPanelID(in: (try? PropertyListSerialization.propertyList(from: data, format: nil)) ?? [:])
    return parsePanelID(raw)
}

/// Recursively search an ioreg plist subtree for the first Panel_ID value.
private func findPanelID(in obj: Any) -> String? {
    if let dict = obj as? [String: Any] {
        if let s = dict["Panel_ID"] as? String { return s }
        if let d = dict["Panel_ID"] as? Data { return String(decoding: d, as: UTF8.self) }
        if let children = dict["IORegistryEntryChildren"], let f = findPanelID(in: children) { return f }
        return nil
    }
    if let array = obj as? [Any] {
        for el in array { if let f = findPanelID(in: el) { return f } }
    }
    return nil
}

/// Read the on-panel TCON memory components (empty if none published).
public func readTCONComponents() throws -> [TCONComponent] {
    let data = try runIoreg(["-arw0", "-c", "AppleTCONComponent"])
    return (try? parseTCON(data)) ?? []
}
```

- [ ] **Step 2: Implement the CLI**

Replace `Sources/panelid/main.swift` with:
```swift
import Foundation
import PanelKit
import PanelIO

let args = Array(CommandLine.arguments.dropFirst())
let flags = args.filter { $0.hasPrefix("-") }
let positional = args.filter { !$0.hasPrefix("-") }
let wantsJSON = flags.contains("--json")

func printUsage() {
    print("""
    panelid \(panelIDVersion) — read the Apple Silicon internal display panel identity.

    USAGE:
      panelid [--json]        Show the panel identity + genuine/suspect verdict.
      panelid map [--json]    List the on-panel TCON memory components.
      panelid --version       Print version.
      panelid --help          Show this help.

    EXIT CODES (identity):
      0  likely genuine    1  suspect    2  Panel_ID absent
    """)
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("panelid: \(message)\n".utf8))
    exit(64)
}

if flags.contains("-h") || flags.contains("--help") { printUsage(); exit(0) }
if flags.contains("--version") { print(panelIDVersion); exit(0) }
for f in flags where f != "--json" { fail("unknown option '\(f)'. Try 'panelid --help'.") }

do {
    if positional.isEmpty {
        let id = try readPanelIdentity()
        print(wantsJSON ? identityJSON(id) : identityReport(id))
        exit(id.verdict.exitCode)
    } else if positional == ["map"] {
        let comps = try readTCONComponents()
        print(wantsJSON ? tconJSON(comps) : tconReport(comps))
        exit(0)
    } else {
        fail("unknown command '\(positional.joined(separator: " "))'. Try 'panelid --help'.")
    }
} catch let e as IORegistryError {
    fail(e.description)
} catch {
    fail(error.localizedDescription)
}
```

- [ ] **Step 3: Build and smoke-test on this Mac**

Run each and eyeball the output (this is the I/O boundary — verified against real hardware):
```bash
swift build
swift run panelid
echo "exit: $?"
swift run panelid --json
swift run panelid map
swift run panelid map --json
swift run panelid --help
swift run panelid --version
swift run panelid --bogus    # expect: error to stderr, exit 64
```
Expected: `panelid` prints the raw Panel_ID, fields, serial/status, and a verdict; exit code 0/1/2 matching the verdict. `map` prints the component table (or the "No TCON…" line). `--json` prints valid JSON. If `panelid` shows `<ABSENT>` on a Mac with a built-in display, inspect `ioreg -arw0 -r -n disp0` and confirm `findPanelID` reaches the `Panel_ID` key.

- [ ] **Step 4: Commit**

```bash
git rm Sources/PanelIO/PanelIO.swift
git add Sources/PanelIO/IORegistry.swift Sources/panelid/main.swift
git commit -m "feat: PanelIO ioreg reader + panelid CLI"
```

---

### Task 5: PanelID SwiftUI GUI

**Files:**
- Delete: `Sources/PanelID/Placeholder.swift`
- Create: `Sources/PanelID/PanelIDApp.swift`, `Sources/PanelID/PanelViewModel.swift`, `Sources/PanelID/ContentView.swift`, `Sources/PanelID/IdentityView.swift`, `Sources/PanelID/TCONMapView.swift`

**Interfaces:**
- Consumes: `PanelKit` (`PanelIdentity`, `Verdict`, `TCONComponent`, `identityReport`, `tconReport`) and `PanelIO` (`readPanelIdentity`, `readTCONComponents`, `IORegistryError`).

- [ ] **Step 1: View model**

Delete `Sources/PanelID/Placeholder.swift`. Create `Sources/PanelID/PanelViewModel.swift`:
```swift
import Foundation
import PanelKit
import PanelIO

@MainActor
final class PanelViewModel: ObservableObject {
    @Published var identity: PanelIdentity?
    @Published var components: [TCONComponent] = []
    @Published var errorMessage: String?

    func scan() {
        errorMessage = nil
        do {
            identity = try readPanelIdentity()
            components = try readTCONComponents()
        } catch let e as IORegistryError {
            errorMessage = e.description
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    var reportText: String {
        guard let identity else { return "" }
        return identityReport(identity) + "\n\n" + tconReport(components)
    }
}
```

- [ ] **Step 2: App entrypoint**

`Sources/PanelID/PanelIDApp.swift`:
```swift
import SwiftUI

@main
struct PanelIDApp: App {
    @StateObject private var model = PanelViewModel()
    var body: some Scene {
        WindowGroup("Panel ID") {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 480, minHeight: 440)
                .onAppear { model.scan() }
        }
        .windowResizability(.contentSize)
    }
}
```

- [ ] **Step 3: Container view**

`Sources/PanelID/ContentView.swift`:
```swift
import SwiftUI

struct ContentView: View {
    @EnvironmentObject var model: PanelViewModel
    @State private var tab = 0

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                Text("Identity").tag(0)
                Text("TCON Map").tag(1)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding()

            Divider()

            if let error = model.errorMessage {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle).foregroundStyle(.orange)
                    Text("Couldn't read the I/O Registry").font(.headline)
                    Text(error).font(.caption).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Retry") { model.scan() }
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if tab == 0 {
                IdentityView()
            } else {
                TCONMapView()
            }
        }
    }
}
```

- [ ] **Step 4: Identity view**

`Sources/PanelID/IdentityView.swift`:
```swift
import SwiftUI
import AppKit
import PanelKit

struct IdentityView: View {
    @EnvironmentObject var model: PanelViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let id = model.identity {
                    verdictBadge(id.verdict)
                    if id.verdict != .absent {
                        infoRow("Serial (field 0)", id.serial)
                        infoRow("Status (field 2)", id.status.isEmpty ? "—" : id.status)
                        DisclosureGroup("Fields (\(id.fields.count))") {
                            VStack(alignment: .leading, spacing: 2) {
                                ForEach(Array(id.fields.enumerated()), id: \.offset) { idx, f in
                                    Text("[\(idx)] len=\(f.count)  \(f)")
                                        .font(.system(.caption, design: .monospaced))
                                        .textSelection(.enabled)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        DisclosureGroup("Raw (\(id.raw.count) chars)") {
                            Text(id.raw)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    } else {
                        Text("No Panel_ID is published for the built-in display.")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("Reading…").foregroundStyle(.secondary)
                }

                HStack {
                    Button("Re-scan") { model.scan() }
                    Button("Copy report") {
                        let pb = NSPasteboard.general
                        pb.clearContents()
                        pb.setString(model.reportText, forType: .string)
                    }
                    .disabled(model.identity == nil)
                }
                .padding(.top, 4)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func verdictBadge(_ verdict: Verdict) -> some View {
        let text: String
        let color: Color
        switch verdict {
        case .likelyGenuine: text = "● LIKELY GENUINE"; color = .green
        case .suspect(let r): text = "● SUSPECT — \(r)"; color = .orange
        case .absent: text = "● Panel_ID ABSENT"; color = .red
        }
        Text(text).font(.headline).foregroundStyle(color)
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label).foregroundStyle(.secondary).frame(width: 130, alignment: .leading)
            Text(value).font(.system(.body, design: .monospaced)).textSelection(.enabled)
        }
    }
}
```

- [ ] **Step 5: TCON map view**

`Sources/PanelID/TCONMapView.swift`:
```swift
import SwiftUI
import PanelKit

struct TCONMapView: View {
    @EnvironmentObject var model: PanelViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                if model.components.isEmpty {
                    Text("No TCON memory components published by this Mac.")
                        .foregroundStyle(.secondary).padding()
                } else {
                    header
                    Divider()
                    ForEach(Array(model.components.enumerated()), id: \.offset) { _, c in
                        row(c)
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            cell("COMPONENT", 120); cell("BUS/TYPE", 150); cell("ADDR", 64)
            cell("SIZE", 72); cell("PROT", 48); cell("VFY", 48)
        }
        .font(.system(.caption, design: .monospaced).weight(.bold))
    }

    private func row(_ c: TCONComponent) -> some View {
        HStack(spacing: 8) {
            cell(c.name, 120); cell(c.busType, 150)
            cell(String(format: "0x%02x", c.addr), 64)
            cell(String(format: "0x%x", c.size), 72)
            cell("\(c.protection)", 48); cell("\(c.verify)", 48)
        }
        .font(.system(.caption, design: .monospaced))
        .textSelection(.enabled)
    }

    private func cell(_ s: String, _ w: CGFloat) -> some View {
        Text(s).frame(width: w, alignment: .leading)
    }
}
```

- [ ] **Step 6: Build and smoke-test the GUI**

```bash
swift build
swift run PanelID
```
Expected: a window opens with an Identity / TCON Map segmented control; Identity shows the verdict badge + serial/status + disclosures; TCON Map shows the component table or the empty-state line; Re-scan re-reads; Copy report puts text on the clipboard. Close the window to end `swift run`. (Definitive check is the bundled app in Task 6.)

- [ ] **Step 7: Commit**

```bash
git rm Sources/PanelID/Placeholder.swift
git add Sources/PanelID
git commit -m "feat: PanelID SwiftUI GUI (Identity + TCON Map)"
```

---

### Task 6: build.sh — bundle, sign, package artifacts

**Files:**
- Create: `build.sh` (executable)
- Modify: `.gitignore` (add `/dist/`, `/.build/`, `.swiftpm/`)

- [ ] **Step 1: Write build.sh**

`build.sh`:
```bash
#!/bin/zsh
set -euo pipefail

VERSION="0.1.0"
ARCH="arm64"
ROOT="${0:A:h}"
cd "$ROOT"

DIST="$ROOT/dist"
rm -rf "$DIST"; mkdir -p "$DIST"

echo "==> swift build (release, $ARCH)"
swift build -c release --arch "$ARCH"
BIN="$(swift build -c release --arch "$ARCH" --show-bin-path)"

echo "==> packaging panelid CLI"
cp "$BIN/panelid" "$DIST/panelid"
codesign --force --sign - "$DIST/panelid"
tar -czf "$DIST/panelid-v${VERSION}-${ARCH}.tar.gz" -C "$DIST" panelid

echo "==> assembling PanelID.app"
APP="$DIST/PanelID.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/PanelID" "$APP/Contents/MacOS/PanelID"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Panel ID</string>
  <key>CFBundleDisplayName</key><string>Panel ID</string>
  <key>CFBundleIdentifier</key><string>com.alexeyinwerp.apple-panel-id</string>
  <key>CFBundleExecutable</key><string>PanelID</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP"
( cd "$DIST" && ditto -c -k --keepParent "PanelID.app" "PanelID-v${VERSION}-${ARCH}.zip" )

echo "==> artifacts in $DIST:"
ls -1 "$DIST"
```

- [ ] **Step 2: Update .gitignore**

Append to `.gitignore`:
```
# Swift build output
/.build/
/dist/
.swiftpm/
```

- [ ] **Step 3: Run the build and verify artifacts**

```bash
chmod +x build.sh
./build.sh
ls -1 dist
```
Expected `dist/` contains: `PanelID.app`, `PanelID-v0.1.0-arm64.zip`, `panelid`, `panelid-v0.1.0-arm64.tar.gz`.

- [ ] **Step 4: Verify the bundled artifacts actually run**

```bash
xattr -dr com.apple.quarantine dist/PanelID.app 2>/dev/null || true
open dist/PanelID.app          # window should open
codesign -dv dist/PanelID.app 2>&1 | head -3   # shows "Signature=adhoc"
dist/panelid --version         # -> 0.1.0
dist/panelid --help
dist/panelid; echo "exit: $?"
```
Expected: app launches; CLI prints help/version/identity with the right exit code.

- [ ] **Step 5: Commit**

```bash
git add build.sh .gitignore
git commit -m "build: build.sh assembles + ad-hoc-signs CLI and app bundle"
```

---

### Task 7: Relocate scripts; update README + research/README

**Files:**
- Move: `panelid.sh` → `research/panelid.sh`; `panelmap.py` → `research/panelmap.py`
- Modify: `README.md`, `research/README.md`

- [ ] **Step 1: Move the scripts**

```bash
git mv panelid.sh research/panelid.sh
git mv panelmap.py research/panelmap.py
```

- [ ] **Step 2: Update the research/ .gitignore references and README note**

In `research/README.md`, change the opening line `# research/ — exploration of the gated paths` block by inserting, immediately after the first paragraph, this note (verbatim):
```markdown
> `panelid.sh` and `panelmap.py` also live here now: they are the original shell/Python
> reference implementations. The shipping tool is the compiled **`panelid`** CLI (built from
> `Sources/`), which reproduces their behavior. The scripts remain as readable, dependency-free
> documentation of the method.
```
Also update the build paths in `research/README.md` that referenced sibling files if any (the `clang` block is unaffected; the `.c`/`.m` files stay in `research/`). Note the gitignore at repo root already ignores `research/probe` etc.

- [ ] **Step 3: Rewrite README.md**

Replace the **Quick start** section and **Tools** table, and add an **Install** section. Apply these edits:

Replace the block from `## Quick start` through the end of its example output (the fenced verdict block) with:
````markdown
## Install

Pre-compiled for Apple Silicon. Downloads are **unsigned**, so macOS quarantines them on first
run — clear it once as shown.

**CLI (`panelid`):**
```bash
# download panelid-v0.1.0-arm64.tar.gz from Releases, then:
tar -xzf panelid-v0.1.0-arm64.tar.gz
xattr -dr com.apple.quarantine panelid
./panelid          # identity + verdict
./panelid map      # TCON memory map
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
  [2] len=4   PROD
  ...

Serial-number field [0] : F0Y20########609B
Build/status field  [2] : PROD
Heuristic verdict       : LIKELY GENUINE
```
````

Replace the **Tools** table with:
```markdown
## Tools

| Tool | What it does |
|------|--------------|
| `panelid` (CLI) | Reads `Panel_ID`, splits the fields, prints a genuine/suspect verdict. `panelid map` lists the on-panel TCON memories. `--json` for scripting. |
| `PanelID.app` (GUI) | Same two capabilities in a small native window: Identity (verdict) and TCON Map. |
| `research/` | The original `panelid.sh` / `panelmap.py` reference scripts plus exploration of the *gated* programmatic paths. See `research/README.md`. |

## Build from source

Requires the Xcode Command Line Tools (Swift 6+). No full Xcode needed.

```bash
swift test     # run the PanelKit unit tests
./build.sh     # produces dist/panelid + dist/PanelID.app and release archives
```
```

Update the **Requirements** section line that lists script interpreters to:
```markdown
- macOS 13+ on Apple Silicon. The pre-built binaries are arm64. Building from source needs the
  Swift toolchain (Command Line Tools). The compiled tools only run stock `ioreg`.
```

- [ ] **Step 4: Verify the scripts still work from their new home and docs are consistent**

```bash
zsh research/panelid.sh | head -3      # still runs
grep -n "panelid.sh" README.md         # expect: only under research/ context, no root path
```
Expected: script runs; README no longer tells users to run `./panelid.sh` from the root.

- [ ] **Step 5: Commit**

```bash
git add README.md research/
git commit -m "docs: relocate reference scripts to research/, document compiled CLI + GUI"
```

---

### Task 8: Release v0.1.0

**Files:** none (git + GitHub operations).

- [ ] **Step 1: Final verification on the branch**

```bash
swift test                 # all PanelKit tests pass
./build.sh                 # artifacts rebuilt fresh from current source
ls -1 dist
```
Expected: tests green; `dist/` has both archives + `PanelID.app` + `panelid`.

- [ ] **Step 2: Merge the feature branch to main**

```bash
git checkout main
git merge --no-ff cli-and-gui -m "feat: compiled panelid CLI + PanelID GUI (v0.1.0)"
git push origin main
```

- [ ] **Step 3: Tag and push**

```bash
git tag -a v0.1.0 -m "v0.1.0 — panelid CLI + PanelID GUI"
git push origin v0.1.0
```

- [ ] **Step 4: Create the GitHub Release with both artifacts**

```bash
gh release create v0.1.0 \
  dist/PanelID-v0.1.0-arm64.zip \
  dist/panelid-v0.1.0-arm64.tar.gz \
  --title "v0.1.0 — panelid CLI + PanelID GUI" \
  --notes "First compiled release for Apple Silicon (arm64).

- \`panelid\` CLI: \`panelid\` (identity + verdict), \`panelid map\` (TCON memory), \`--json\`.
- \`PanelID.app\`: small native GUI (Identity + TCON Map).

Both are **unsigned** — clear quarantine on first run:
\`xattr -dr com.apple.quarantine panelid\` / right-click → Open the app. See README → Install."
```

- [ ] **Step 5: Verify the release is live**

```bash
gh release view v0.1.0
```
Expected: release `v0.1.0` is published with two assets attached.

---

## Self-Review

**Spec coverage:**
- GUI Identity + TCON Map → Tasks 5; verdict/fields/raw/copy all present. ✓
- CLI identity + `map` + `--json` + exit codes + help/version → Task 4. ✓
- Shared tested core (verdict heuristic, TCON decode, formatters) → Tasks 1–3. ✓
- `PanelIO` single ioreg boundary → Task 4. ✓
- Unsigned/ad-hoc build, arm64, macOS 13, bundle id, no external deps → Tasks 1 (manifest) + 6 (build.sh). ✓
- Scripts move to `research/`; raw one-liner stays in README; Install section → Task 7. ✓
- Local build + v0.1.0 release with both assets → Tasks 6, 8. ✓
- Non-goals (notarization, icon, baseline-compare, CI, IOKit) correctly absent. ✓

**Placeholder scan:** Task 1 intentionally creates throwaway placeholder source files so the package resolves before later tasks; each is explicitly deleted/replaced in Tasks 4–5. No `TBD`/"add error handling"/uncoded steps remain.

**Type consistency:** `parsePanelID`/`parseTCON`/`identityReport`/`tconReport`/`identityJSON`/`tconJSON` (PanelKit), `readPanelIdentity`/`readTCONComponents`/`IORegistryError` (PanelIO), `PanelViewModel.scan()`/`reportText` (GUI) — names/signatures match across producing and consuming tasks. `Verdict.exitCode`/`.label` used consistently by CLI and GUI.
