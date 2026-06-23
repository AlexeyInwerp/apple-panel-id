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

// MARK: - Runner

testIdentity()

print("\nchecks: \(checks)   failures: \(failures)")
exit(failures == 0 ? 0 : 1)
