import SwiftUI

@main
struct PlantaScanApp: App {
    @State private var store = ImovelStore()
    @State private var sincronizador = Sincronizador()
    @Environment(\.scenePhase) private var fase

    var body: some Scene {
        WindowGroup {
            ImoveisListView()
                .environment(store)
                .environment(sincronizador)
                .environment(\.locale, Locale(identifier: "pt_BR"))
                .task {
                    sincronizador.conectar(store)
                    await sincronizador.sincronizar()
                }
                .onChange(of: fase) { _, nova in
                    if nova == .active {
                        Task { await sincronizador.sincronizar() }
                    }
                }
        }
    }
}
