import Foundation
import PanelKit
import PanelIO

@MainActor
final class PanelViewModel: ObservableObject {
    @Published var identity: PanelIdentity?
    @Published var components: [TCONComponent] = []
    @Published var errorMessage: String?

    func scan() {
        errorMessage = nil
        do {
            identity = try readPanelIdentity()
            components = try readTCONComponents()
        } catch let e as IORegistryError {
            errorMessage = e.description
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    var reportText: String {
        guard let identity else { return "" }
        return identityReport(identity) + "\n\n" + tconReport(components)
    }
}
