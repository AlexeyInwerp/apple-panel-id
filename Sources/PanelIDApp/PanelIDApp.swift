import SwiftUI

@main
struct PanelIDApp: App {
    @StateObject private var model = PanelViewModel()

    var body: some Scene {
        WindowGroup("Panel ID") {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 480, minHeight: 440)
                .onAppear { model.scan() }
        }
        .windowResizability(.contentSize)
    }
}
