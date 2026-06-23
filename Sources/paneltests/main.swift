// Dependency-free unit-test harness for PanelKit's pure logic.
// Command Line Tools ship no XCTest / Swift Testing module, so we roll a tiny
// runner: each check records failures; the process exits non-zero if any fail.
// Run with:  swift run paneltests
import Foundation
import PanelKit

var failures = 0
var checks = 0

func eq<T: Equatable>(_ got: T, _ want: T, _ what: String, line: UInt = #line) {
    checks += 1
    if got != want {
        failures += 1
        print("FAIL [\(line)] \(what): got \(got), expected \(want)")
    }
}

func ok(_ cond: Bool, _ what: String, line: UInt = #line) {
    checks += 1
    if !cond {
        failures += 1
        print("FAIL [\(line)] \(what)")
    }
}

// MARK: - Identity parsing & verdict (Task 1)

func testIdentity() {
    let genuine = "F0Y20ABCDEF609B+000000004M22F2+PROD+B000000000000+0000000000000000000000000+PA07N0108Y21011214"
    let id = parsePanelID(genuine)
    eq(id.verdict, .likelyGenuine, "genuine verdict")
    eq(id.serial, "F0Y20ABCDEF609B", "genuine serial")
    eq(id.status, "PROD", "genuine status")
    eq(id.fields.count, 6, "genuine field count")

    eq(parsePanelID("F0Y20ABCDEF609B+000000004M22F2+ENGR+x").verdict,
       .suspect(reason: "status field is not PROD"), "status not PROD")
    eq(parsePanelID("0000000000000000+000000004M22F2+PROD+x").verdict,
       .suspect(reason: "serial field is all zeros"), "serial all zeros")
    eq(parsePanelID("0000+000000004M22F2+PROD+x").verdict,
       .suspect(reason: "serial field too short"), "serial too short")
    eq(parsePanelID(nil).verdict, .absent, "nil absent")
    eq(parsePanelID("").verdict, .absent, "empty absent")

    eq(Verdict.likelyGenuine.exitCode, 0, "exit genuine")
    eq(Verdict.suspect(reason: "x").exitCode, 1, "exit suspect")
    eq(Verdict.absent.exitCode, 2, "exit absent")
}

// MARK: - TCON parsing (Task 2)

func testTCON() {
    // I2C component with full reg (addr 0x50, size 0x100), Data-typed name/device_type.
    let i2c: [String: Any] = [
        "name": Data("tcon0\u{0}".utf8),
        "device_type": Data("eeprom\u{0}".utf8),
        "reg": Data([0x50, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00]),
        "interface": Data([0x03, 0x00, 0x00, 0x00]),
        "protection": Data([0x01, 0x00, 0x00, 0x00]),
        "verify": Data([0x00, 0x00, 0x00, 0x00]),
    ]
    guard let data = try? PropertyListSerialization.data(
        fromPropertyList: [i2c] as [Any], format: .xml, options: 0),
          let rows = try? parseTCON(data) else {
        failures += 1; print("FAIL: I2C plist did not parse"); return
    }
    eq(rows.count, 1, "i2c count")
    if let r = rows.first {
        eq(r.name, "tcon0", "i2c name")
        eq(r.deviceType, "eeprom", "i2c device_type")
        eq(r.bus, "I2C", "i2c bus")
        eq(r.busType, "I2C/eeprom", "i2c busType")
        eq(r.addr, 0x50, "i2c addr")
        eq(r.size, 0x100, "i2c size")
        eq(r.protection, 1, "i2c protection")
        eq(r.verify, 0, "i2c verify")
    }

    // SPI, short reg (< 8 bytes -> addr/size 0), String-typed name, missing protection/verify.
    let spi: [String: Any] = [
        "name": "spi0",
        "device_type": "flash",
        "reg": Data([0x01, 0x02]),
        "interface": Data([0x00]),
    ]
    if let data = try? PropertyListSerialization.data(
        fromPropertyList: [spi] as [Any], format: .binary, options: 0),
       let rows = try? parseTCON(data), let r = rows.first {
        eq(r.bus, "SPI", "spi bus")
        eq(r.name, "spi0", "spi name (string)")
        eq(r.addr, 0, "spi addr (short reg)")
        eq(r.size, 0, "spi size (short reg)")
        eq(r.protection, 0, "spi protection (missing key)")
    } else {
        failures += 1; print("FAIL: SPI plist did not parse")
    }

    // Empty array is valid.
    if let data = try? PropertyListSerialization.data(
        fromPropertyList: [] as [Any], format: .xml, options: 0),
       let rows = try? parseTCON(data) {
        eq(rows.count, 0, "empty tcon array")
    } else {
        failures += 1; print("FAIL: empty plist did not parse")
    }
}

// MARK: - Runner

testIdentity()
testTCON()

print("\nchecks: \(checks)   failures: \(failures)")
exit(failures == 0 ? 0 : 1)
