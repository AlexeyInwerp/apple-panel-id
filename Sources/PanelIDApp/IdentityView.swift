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

    private func verdictBadge(_ verdict: Verdict) -> some View {
        let text: String
        let color: Color
        switch verdict {
        case .likelyGenuine: text = "● LIKELY GENUINE"; color = .green
        case .suspect(let r): text = "● SUSPECT — \(r)"; color = .orange
        case .absent: text = "● Panel_ID ABSENT"; color = .red
        }
        return Text(text).font(.headline).foregroundStyle(color)
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label).foregroundStyle(.secondary).frame(width: 130, alignment: .leading)
            Text(value).font(.system(.body, design: .monospaced)).textSelection(.enabled)
        }
    }
}
