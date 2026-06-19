import SwiftUI

@main
struct ImmichDriveApp: App {
    var body: some Scene {
        Window("Immich", id: "main") {
            ContentView()
        }
        .windowResizability(.contentSize)
    }
}
