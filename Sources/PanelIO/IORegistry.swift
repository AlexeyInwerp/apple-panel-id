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

/// Read the built-in display panel identity from the `Panel_ID` property of the
/// disp0 (AppleCLCD2) node. Parsed from `ioreg` text output: the `-a` archived
/// plist omits this particular property, so we scan text like research/panelid.sh.
public func readPanelIdentity() throws -> PanelIdentity {
    let data = try runIoreg(["-lw0", "-r", "-n", "disp0"])
    let text = String(decoding: data, as: UTF8.self)
    return parsePanelID(panelIDFromText(text))
}

/// Extract the first `"Panel_ID" = "VALUE"` value from ioreg text output.
/// Mirrors panelid.sh's sed: s/.*"Panel_ID" = "([^"]*)".*/\1/
private func panelIDFromText(_ text: String) -> String? {
    for line in text.split(separator: "\n") where line.contains("\"Panel_ID\"") {
        guard let marker = line.range(of: "= \"") else { continue }
        let after = line[marker.upperBound...]
        guard let endQuote = after.firstIndex(of: "\"") else { continue }
        return String(after[..<endQuote])
    }
    return nil
}

/// Read the on-panel TCON memory components (empty if none published).
public func readTCONComponents() throws -> [TCONComponent] {
    let data = try runIoreg(["-arw0", "-c", "AppleTCONComponent"])
    return (try? parseTCON(data)) ?? []
}
