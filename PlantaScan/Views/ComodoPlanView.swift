import SwiftUI
import RoomPlan

/// Planta 2D de um cômodo, com medidas ao tocar e edição de portas/janelas.
struct ComodoPlanView: View {
    let imovelID: UUID
    let comodoID: UUID

    @Environment(ImovelStore.self) private var store
    @Environment(\.dismiss) private var sairDaTela
    @State private var room: CapturedRoom?
    @State private var erro: String?
    @State private var selecionado: ElementoPlano?
    @State private var editando: AlvoEdicao?
    @State private var renomeandoObjeto: ElementoPlano?
    @State private var renomeandoComodo = false
    @State private var ajustandoNorte = false
    @State private var novoNome = ""
    @AppStorage("mostrarNomeComodo") private var mostrarNomeComodo = true
    @AppStorage("mostrarNomesObjetos") private var mostrarNomesObjetos = true

    private struct AlvoEdicao: Identifiable {
        let id: UUID
    }

    private var comodo: Comodo? {
        store.imovel(id: imovelID)?.comodos.first { $0.id == comodoID }
    }

    var body: some View {
        Group {
            if let room, let comodo {
                let plano = FloorPlanBuilder.construir(room, comodo: comodo)
                conteudo(plano, comodo: comodo)
            } else if let erro {
                ContentUnavailableView("Não foi possível abrir", systemImage: "exclamationmark.triangle", description: Text(erro))
            } else {
                ProgressView("Carregando planta…")
            }
        }
        .navigationTitle(comodo?.nome ?? "Cômodo")
        .navigationBarTitleDisplayMode(.inline)
        .task { carregar() }
    }

    private func conteudo(_ plano: FloorPlan2D, comodo: Comodo) -> some View {
        VStack(spacing: 0) {
            if plano.vazio {
                ContentUnavailableView("Planta vazia", systemImage: "square.dashed", description: Text("O scan não detectou paredes."))
            } else {
                FloorPlanCanvas(
                    plano: plano, titulo: comodo.nome, selecionado: $selecionado,
                    mostrarNomeComodo: mostrarNomeComodo, mostrarNomesObjetos: mostrarNomesObjetos,
                    anguloNorte: comodo.anguloNorte
                )
            }
            Divider()
            painel(plano)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Section("Exibir na planta") {
                        Toggle("Nome do cômodo", isOn: $mostrarNomeComodo)
                        Toggle("Nomes dos objetos", isOn: $mostrarNomesObjetos)
                    }
                    Button {
                        renomeandoComodo = true
                    } label: {
                        Label("Editar nome, tipo, andar ou apagar", systemImage: "pencil")
                    }
                    Button {
                        ajustandoNorte = true
                    } label: {
                        Label("Ajustar norte…", systemImage: "location.north.line")
                    }
                    if plano.quantidadeRemovidos > 0 {
                        Button {
                            store.restaurarRemovidos(comodoID: comodoID, imovelID: imovelID)
                        } label: {
                            Label("Restaurar removidos (\(plano.quantidadeRemovidos))", systemImage: "arrow.uturn.backward")
                        }
                    }
                } label: {
                    Label("Opções", systemImage: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $ajustandoNorte) {
            AjusteNorteView(medido: comodo.norte, ajusteInicial: comodo.ajusteNorte ?? 0) { graus in
                store.ajustarNorte(graus, comodoID: comodoID, imovelID: imovelID)
            }
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $renomeandoComodo) {
            EditarComodoView(imovelID: imovelID, comodo: comodo) {
                sairDaTela()
            }
        }
        .alert(
            "Renomear objeto",
            isPresented: Binding(get: { renomeandoObjeto != nil }, set: { if !$0 { renomeandoObjeto = nil } }),
            presenting: renomeandoObjeto
        ) { obj in
            TextField("Nome do objeto", text: $novoNome)
            Button("Salvar") {
                store.renomearObjeto(id: obj.id, para: novoNome.trimmingCharacters(in: .whitespacesAndNewlines),
                                     comodoID: comodoID, imovelID: imovelID)
                selecionado = nil
            }
            Button("Cancelar", role: .cancel) {}
        } message: { _ in
            Text("Deixe em branco para voltar ao nome detectado.")
        }
        .sheet(item: $editando) { alvo in
            if let ab = plano.aberturas.first(where: { $0.id == alvo.id }) {
                EditarAberturaView(
                    abertura: ab,
                    edicao: comodo.edicoes?[ab.id.uuidString] ?? EdicaoAbertura(),
                    aoSalvar: { e in
                        store.salvarEdicao(e, elementoID: ab.id, comodoID: comodoID, imovelID: imovelID)
                        selecionado = nil
                    },
                    aoRemover: {
                        if ab.manual {
                            store.removerAberturaManual(id: ab.id, comodoID: comodoID, imovelID: imovelID)
                        } else {
                            var e = comodo.edicoes?[ab.id.uuidString] ?? EdicaoAbertura()
                            e.removido = true
                            store.salvarEdicao(e, elementoID: ab.id, comodoID: comodoID, imovelID: imovelID)
                        }
                        selecionado = nil
                    }
                )
            }
        }
    }

    @ViewBuilder
    private func painel(_ plano: FloorPlan2D) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let sel = selecionado {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(sel.nome).font(.headline)
                        Text(Formato.dimensoes(sel.dimensoes))
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        selecionado = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel("Fechar")
                }
                acoes(para: sel, plano: plano)
            } else {
                HStack(spacing: 0) {
                    resumo("Área", Formato.area(plano.area))
                    resumo("Portas", "\(plano.contar(.porta))")
                    resumo("Janelas", "\(plano.contar(.janela))")
                    resumo("Objetos", "\(plano.objetos.count)")
                }
                Text("Toque numa parede, porta, janela ou móvel para ver as medidas e editar.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
    }

    @ViewBuilder
    private func acoes(para sel: ElementoPlano, plano: FloorPlan2D) -> some View {
        switch sel.tipo {
        case .abertura:
            Button {
                editando = AlvoEdicao(id: sel.id)
            } label: {
                Label("Editar modelo e medidas", systemImage: "slider.horizontal.3")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        case .parede:
            HStack {
                ForEach(TipoAbertura.allCases) { tipo in
                    Button {
                        adicionar(tipo, na: sel.id, plano: plano)
                    } label: {
                        Label(tipo.nome, systemImage: "plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }
            Button(role: .destructive) {
                store.removerParede(id: sel.id, comodoID: comodoID, imovelID: imovelID)
                selecionado = nil
            } label: {
                Label("Apagar parede (n\u{e3}o \u{e9} deste c\u{f4}modo)", systemImage: "trash")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        case .objeto:
            HStack {
                Button {
                    novoNome = sel.nome
                    renomeandoObjeto = sel
                } label: {
                    Label("Renomear", systemImage: "pencil")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                Button(role: .destructive) {
                    store.removerObjeto(id: sel.id, comodoID: comodoID, imovelID: imovelID)
                    selecionado = nil
                } label: {
                    Label("Remover", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func resumo(_ titulo: String, _ valor: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(titulo).font(.caption).foregroundStyle(.secondary)
            Text(valor).font(.headline.monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func adicionar(_ tipo: TipoAbertura, na paredeID: UUID, plano: FloorPlan2D) {
        guard let parede = plano.paredes.first(where: { $0.id == paredeID }) else { return }
        let comprimento = Double(parede.a.distancia(parede.b))
        let padrao: (largura: Double, altura: Double)
        switch tipo {
        case .porta: padrao = (0.80, 2.10)
        case .janela: padrao = (1.20, 1.20)
        case .vao: padrao = (0.90, 2.10)
        }
        let nova = AberturaManual(
            paredeID: paredeID,
            tipo: tipo,
            posicao: comprimento / 2,
            largura: min(padrao.largura, comprimento * 0.9),
            altura: padrao.altura
        )
        store.adicionarAbertura(nova, comodoID: comodoID, imovelID: imovelID)
        selecionado = nil
        editando = AlvoEdicao(id: nova.id)
    }

    private func carregar() {
        guard room == nil else { return }
        do {
            let r = try Storage.carregarScan(comodoID: comodoID, imovelID: imovelID)
            room = r
            let area = FloorPlanBuilder.construir(r, comodo: comodo).area
            store.definirArea(area, comodoID: comodoID, imovelID: imovelID)
        } catch {
            erro = error.localizedDescription
        }
    }
}
