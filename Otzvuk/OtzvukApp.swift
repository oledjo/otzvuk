import SwiftUI

@main
struct OtzvukApp: App {
    @StateObject private var app = AppModel()

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environmentObject(app)
                .environmentObject(app.library)
                .environmentObject(app.music)
                .environmentObject(app.wishlist)
                .environmentObject(app.settings)
                .environmentObject(app.session)
                .environmentObject(app.recorder)
        }
    }
}
