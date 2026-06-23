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
