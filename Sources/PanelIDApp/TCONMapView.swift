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
