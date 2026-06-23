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
