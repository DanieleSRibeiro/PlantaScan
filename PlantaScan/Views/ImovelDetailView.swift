import SwiftUI
import RoomPlan

struct ImovelDetailView: View {
    let imovelID: UUID

    @Environment(ImovelStore.self) private var store
    @State private var scan: ConfigScan?
    @State private var editando: Comodo?
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
        let continuar = store.sessaoParaContinuar(imovelID: imovelID)

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
                    let contagem = Formato.contagem(imovel.comodos)
                    if !contagem.isEmpty {
                        Text(contagem)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
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
                    Text("Nenhum cômodo escaneado ainda. Toque em \"Escanear\" e escolha um cômodo ou a casa toda.")
                        .foregroundStyle(.secondary)
                }
            }

            ForEach(andares, id: \.self) { andar in
                let comodos = imovel.comodos.filter { $0.andarOuPadrao == andar }
                let area = comodos.reduce(0) { $0 + ($1.area ?? 0) }
                Section {
                    NavigationLink {
                        AndarPlanView(imovelID: imovelID, andar: andar)
                    } label: {
                        Label("Planta do \(Formato.andar(andar))", systemImage: "map")
                            .fontWeight(.medium)
                    }
                    ForEach(comodos) { comodo in
                        NavigationLink {
                            ComodoPlanView(imovelID: imovelID, comodoID: comodo.id)
                        } label: {
                            ComodoRow(comodo: comodo)
                        }
                        .contextMenu {
                            Button {
                                editando = comodo
                            } label: {
                                Label("Editar nome, tipo e andar", systemImage: "pencil")
                            }
                        }
                        .swipeActions(edge: .leading) {
                            Button {
                                editando = comodo
                            } label: {
                                Label("Editar", systemImage: "pencil")
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
            Menu {
                Section("Novo scan · \(Formato.andar(andarAtual))") {
                    Button {
                        scan = ConfigScan(modo: .umComodo, sessao: UUID(), mapa: nil, andar: andarAtual)
                    } label: {
                        Label("Um cômodo", systemImage: "square")
                    }
                    Button {
                        scan = ConfigScan(modo: .casaToda, sessao: UUID(), mapa: nil, andar: andarAtual)
                    } label: {
                        Label("Casa toda (vários cômodos)", systemImage: "square.grid.2x2")
                    }
                }
                if let continuar {
                    Section("Continuar de onde parou") {
                        Button {
                            iniciarContinuacao(sessao: continuar.sessao)
                        } label: {
                            Label("Continuar scan (depois de \(continuar.comodo.nome))", systemImage: "arrow.forward.circle")
                        }
                    }
                }
            } label: {
                Label("Escanear · \(Formato.andar(andarAtual))", systemImage: "camera.viewfinder")
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
        .fullScreenCover(item: $scan) { config in
            RoomScanView(config: config) { room, mapa, norte, andar, sessao in
                try store.adicionarComodo(
                    room: room, imovelID: imovelID, andar: andar,
                    norte: norte, sessao: sessao, mapa: mapa
                ).nome
            }
        }
        .sheet(item: $editando) { comodo in
            EditarComodoView(imovelID: imovelID, comodo: comodo)
        }
    }

    private func iniciarContinuacao(sessao: UUID) {
        let mapa = Storage.carregarMapa(sessao: sessao, imovelID: imovelID)
        scan = ConfigScan(modo: .casaToda, sessao: mapa == nil ? UUID() : sessao, mapa: mapa, andar: andarAtual)
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
}

private struct ComodoRow: View {
    let comodo: Comodo

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: (comodo.tipo ?? .outro).icone)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 30)
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
