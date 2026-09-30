import SwiftUI
import RoomPlan

struct ImovelDetailView: View {
    let imovelID: UUID

    @Environment(ImovelStore.self) private var store
    @State private var escaneando = false
    @State private var renomeando: Comodo?
    @State private var novoNome = ""
    @State private var andarAtual = 1

    var body: some View {
        if let imovel = store.imovel(id: imovelID) {
            conteudo(imovel)
        } else {
            ContentUnavailableView("Imóvel não encontrado", systemImage: "questionmark.folder")
        }
    }

    private func conteudo(_ imovel: Imovel) -> some View {
        let andares = imovel.andares
        let limiteAndar = max((andares.max() ?? 1) + 1, andarAtual, 2)

        return List {
            Section {
                if !imovel.endereco.isEmpty || imovel.eircode != nil {
                    let textoEndereco = [imovel.endereco, imovel.eircode ?? ""]
                        .filter { !$0.isEmpty }
                        .joined(separator: " · ")
                    if let url = urlMapa(imovel) {
                        Link(destination: url) {
                            Label(textoEndereco, systemImage: "mappin.and.ellipse")
                        }
                    } else {
                        Label(textoEndereco, systemImage: "mappin.and.ellipse")
                    }
                }
                if !imovel.comodos.isEmpty {
                    LabeledContent("Área total", value: Formato.area(imovel.areaTotal))
                    LabeledContent("Cômodos", value: "\(imovel.comodos.count)")
                }
            }

            Section {
                Picker("Andar do próximo scan", selection: $andarAtual) {
                    ForEach(1...limiteAndar, id: \.self) { n in
                        Text(Formato.andar(n)).tag(n)
                    }
                }
            } footer: {
                Text("Escolha o andar em que você está antes de escanear.")
            }

            if imovel.comodos.isEmpty {
                Section("Cômodos") {
                    Text("Nenhum cômodo escaneado ainda. Toque em \"Escanear cômodo\".")
                        .foregroundStyle(.secondary)
                }
            }

            ForEach(andares, id: \.self) { andar in
                let comodos = imovel.comodos.filter { $0.andarOuPadrao == andar }
                let area = comodos.reduce(0) { $0 + ($1.area ?? 0) }
                Section {
                    ForEach(comodos) { comodo in
                        NavigationLink {
                            ComodoPlanView(imovelID: imovelID, comodoID: comodo.id)
                        } label: {
                            ComodoRow(comodo: comodo)
                        }
                        .contextMenu {
                            Button {
                                iniciarRenomear(comodo)
                            } label: {
                                Label("Renomear", systemImage: "pencil")
                            }
                            Menu {
                                ForEach(1...limiteAndar, id: \.self) { n in
                                    Button(Formato.andar(n)) {
                                        store.moverComodo(id: comodo.id, paraAndar: n, imovelID: imovelID)
                                    }
                                }
                            } label: {
                                Label("Mover para andar", systemImage: "arrow.up.arrow.down")
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
                        store.apagarComodos(ids: offsets.map { comodos[$0].id }, imovelID: imovelID)
                    }
                } header: {
                    HStack {
                        Text(Formato.andar(andar))
                        Spacer()
                        if area > 0 {
                            Text(Formato.area(area))
                        }
                    }
                }
            }
        }
        .navigationTitle(imovel.nome)
        .safeAreaInset(edge: .bottom) {
            Button {
                escaneando = true
            } label: {
                Label("Escanear cômodo · \(Formato.andar(andarAtual))", systemImage: "camera.viewfinder")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding()
            .background(.bar)
        }
        .onAppear {
            if let ultimo = imovel.comodos.last {
                andarAtual = ultimo.andarOuPadrao
            }
        }
        .fullScreenCover(isPresented: $escaneando) {
            RoomScanView { nome, room, norte in
                try store.adicionarComodo(nome: nome, room: room, imovelID: imovelID, andar: andarAtual, norte: norte)
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

    /// Abre o endereço (com Eircode) no app Mapas.
    private func urlMapa(_ imovel: Imovel) -> URL? {
        let consulta = [imovel.endereco, imovel.eircode ?? ""]
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
        guard !consulta.isEmpty else { return nil }
        var c = URLComponents(string: "https://maps.apple.com/")
        c?.queryItems = [URLQueryItem(name: "q", value: consulta)]
        return c?.url
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
                HStack(spacing: 8) {
                    if let area = comodo.area, area > 0 {
                        Text(Formato.area(area))
                            .fontWeight(.medium)
                    }
                    Text(comodo.dataScan.formatted(date: .abbreviated, time: .shortened))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
