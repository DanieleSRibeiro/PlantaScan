import SwiftUI

@main
struct PlantaScanApp: App {
    @State private var store = ImovelStore()

    var body: some Scene {
        WindowGroup {
            ImoveisListView()
                .environment(store)
                .environment(\.locale, Locale(identifier: "pt_BR"))
        }
    }
}
