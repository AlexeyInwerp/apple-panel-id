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
