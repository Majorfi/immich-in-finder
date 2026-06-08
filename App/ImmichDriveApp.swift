import SwiftUI

@main
struct ImmichDriveApp: App {
    var body: some Scene {
        Window("Immich Drive", id: "main") {
            ContentView()
                .frame(minWidth: 440, minHeight: 380)
        }
        .windowResizability(.contentSize)
    }
}
