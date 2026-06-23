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
