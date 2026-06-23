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
