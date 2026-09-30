import SwiftUI
import RoomPlan

struct ImovelDetailView: View {
    let imovelID: UUID

    @Environment(ImovelStore.self) private var store
    @State private var escaneando = false
    @State private var renomeando: Comodo?
    @State private var novoNome = ""

    var body: some View {
        if let imovel = store.imovel(id: imovelID) {
            conteudo(imovel)
        } else {
            ContentUnavailableView("Imóvel não encontrado", systemImage: "questionmark.folder")
        }
    }

    private func conteudo(_ imovel: Imovel) -> some View {
        List {
            Section {
                if !imovel.endereco.isEmpty {
                    Label(imovel.endereco, systemImage: "mappin.and.ellipse")
                }
                Label(imovel.dataCriacao.formatted(date: .long, time: .omitted), systemImage: "calendar")
            }

            Section("Cômodos") {
                if imovel.comodos.isEmpty {
                    Text("Nenhum cômodo escaneado ainda. Toque em \"Escanear cômodo\".")
                        .foregroundStyle(.secondary)
                }
                ForEach(imovel.comodos) { comodo in
                    ComodoRow(comodo: comodo)
                        .contextMenu {
                            Button {
                                iniciarRenomear(comodo)
                            } label: {
                                Label("Renomear", systemImage: "pencil")
                            }
                        }
                        .swipeActions(edge: .leading) {
                            Button {
                                iniciarRenomear(comodo)
                            } label: {
                                Label("Renomear", systemImage: "pencil")
                            }
                            .tint(.orange)
                        }
                }
                .onDelete { offsets in
                    store.apagarComodos(at: offsets, imovelID: imovelID)
                }
            }
        }
        .navigationTitle(imovel.nome)
        .safeAreaInset(edge: .bottom) {
            Button {
                escaneando = true
            } label: {
                Label("Escanear cômodo", systemImage: "camera.viewfinder")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding()
            .background(.bar)
        }
        .fullScreenCover(isPresented: $escaneando) {
            RoomScanView { nome, room in
                try store.adicionarComodo(nome: nome, room: room, imovelID: imovelID)
            }
        }
        .alert(
            "Renomear cômodo",
            isPresented: Binding(get: { renomeando != nil }, set: { if !$0 { renomeando = nil } }),
            presenting: renomeando
        ) { comodo in
            TextField("Nome do cômodo", text: $novoNome)
            Button("Salvar") {
                let nome = novoNome.trimmingCharacters(in: .whitespacesAndNewlines)
                if !nome.isEmpty {
                    store.renomearComodo(id: comodo.id, para: nome, imovelID: imovelID)
                }
            }
            Button("Cancelar", role: .cancel) {}
        }
    }

    private func iniciarRenomear(_ comodo: Comodo) {
        novoNome = comodo.nome
        renomeando = comodo
    }
}

private struct ComodoRow: View {
    let comodo: Comodo

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "square.dashed")
                .font(.title2)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(comodo.nome)
                    .font(.headline)
                Text("Escaneado em \(comodo.dataScan.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
