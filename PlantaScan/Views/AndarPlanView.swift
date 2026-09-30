import SwiftUI
import RoomPlan

/// Planta de um andar inteiro: junta os cômodos por grupo (mesma sessão ou encaixados).
/// No modo "Encaixar", um cômodo escaneado separado pode ser encaixado pela porta,
/// arrastado com o dedo e girado.
struct AndarPlanView: View {
    let imovelID: UUID
    let andar: Int

    @Environment(ImovelStore.self) private var store
    @State private var rooms: [UUID: CapturedRoom] = [:]
    @State private var carregado = false
    @State private var selecionado: ElementoPlano?
    @AppStorage("mostrarNomeComodo") private var mostrarNomeComodo = true
    @AppStorage("mostrarNomesObjetos") private var mostrarNomesObjetos = true

    // Modo encaixe.
    @State private var encaixando = false
    @State private var grupoAtivo: String?
    @State private var temporario: Alinhamento?
    @State private var limitesFixos: CGRect?
    @State private var aviso: String?

    private var comodos: [Comodo] {
        store.imovel(id: imovelID)?.comodos.filter { $0.andarOuPadrao == andar } ?? []
    }

    /// Cômodos com o encaixe provisório aplicado ao grupo que está sendo movido.
    private var comodosExibidos: [Comodo] {
        guard let grupoAtivo, let temporario else { return comodos }
        return comodos.map { c in
            var c = c
            if c.chaveSessaoPropria == grupoAtivo { c.alinhamento = temporario }
            return c
        }
    }

    var body: some View {
        Group {
            if !carregado {
                ProgressView("Montando a planta…")
            } else {
                let montagem = MontadorPlanta.montar(andar: andar, comodos: comodosExibidos, rooms: rooms)
                let tocar: ((CGPoint) -> Void)? = encaixando ? { p in escolherGrupo(em: p, montagem: montagem) } : nil
                let arrastar: ((CGVector) -> Void)? = (encaixando && grupoAtivo != nil) ? { d in mover(d) } : nil
                VStack(spacing: 0) {
                    FloorPlanCanvas(
                        plano: montagem.plano,
                        titulo: nil,
                        selecionado: $selecionado,
                        mostrarNomeComodo: mostrarNomeComodo,
                        mostrarNomesObjetos: mostrarNomesObjetos,
                        anguloNorte: montagem.norte,
                        limites: encaixando ? limitesFixos : nil,
                        aoTocar: tocar,
                        aoArrastar: arrastar
                    )
                    Divider()
                    if encaixando {
                        painelEncaixe(montagem)
                    } else {
                        painel(montagem)
                    }
                }
            }
        }
        .navigationTitle("Planta · \(Formato.andar(andar))")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Section("Exibir na planta") {
                        Toggle("Nomes dos cômodos", isOn: $mostrarNomeComodo)
                        Toggle("Nomes dos objetos", isOn: $mostrarNomesObjetos)
                    }
                    if comodos.count > 1 && !encaixando {
                        Button {
                            iniciarEncaixe()
                        } label: {
                            Label("Encaixar cômodos", systemImage: "square.on.square.dashed")
                        }
                    }
                } label: {
                    Label("Opções", systemImage: "ellipsis.circle")
                }
            }
        }
        .task { carregar() }
    }

    // MARK: Painéis

    private func painel(_ m: MontagemAndar) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let sel = selecionado {
                HStack {
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
                Text("Para editar portas, janelas e móveis, abra o cômodo na lista.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Área do andar").font(.caption).foregroundStyle(.secondary)
                        Text(Formato.area(m.plano.area)).font(.headline.monospacedDigit())
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Cômodos").font(.caption).foregroundStyle(.secondary)
                        Text("\(comodos.count)").font(.headline.monospacedDigit())
                    }
                }
                let contagem = Formato.contagem(comodos)
                if !contagem.isEmpty {
                    Text(contagem).font(.subheadline)
                }
                if m.separados {
                    Button {
                        iniciarEncaixe()
                    } label: {
                        Label("Há cômodos fora do lugar. Toque para encaixar.", systemImage: "square.on.square.dashed")
                            .font(.subheadline)
                    }
                    .tint(.orange)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
    }

    private func painelEncaixe(_ m: MontagemAndar) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let grupoAtivo {
                let nomes = comodos.filter { $0.chaveSessaoPropria == grupoAtivo }.map(\.nome).joined(separator: ", ")
                Text("Movendo: \(nomes)").font(.headline).lineLimit(2)
                Text("Arraste com o dedo para mover. Use os botões para girar.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button {
                    encaixarPelaPorta(grupoAtivo)
                } label: {
                    Label("Encaixar pela porta (automático)", systemImage: "door.left.hand.open")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                HStack {
                    botaoGirar("−90°", -Double.pi / 2, m)
                    botaoGirar("−5°", -Double.pi / 36, m)
                    botaoGirar("−1°", -Double.pi / 180, m)
                    botaoGirar("+1°", Double.pi / 180, m)
                    botaoGirar("+5°", Double.pi / 36, m)
                    botaoGirar("+90°", Double.pi / 2, m)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else {
                Text("Toque no cômodo que está fora do lugar.").font(.headline)
            }

            if let aviso {
                Text(aviso).font(.caption).foregroundStyle(.orange)
            }

            HStack {
                Button("Cancelar") { sairDoEncaixe() }
                    .buttonStyle(.bordered)
                if grupoAtivo != nil {
                    Button("Soltar") {
                        if let g = grupoAtivo {
                            store.definirAlinhamento(nil, grupo: g, imovelID: imovelID)
                        }
                        sairDoEncaixe()
                    }
                    .buttonStyle(.bordered)
                    Spacer()
                    Button("Salvar posição") {
                        if let g = grupoAtivo {
                            store.definirAlinhamento(temporario, grupo: g, imovelID: imovelID)
                        }
                        sairDoEncaixe()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
    }

    private func botaoGirar(_ titulo: String, _ delta: Double, _ m: MontagemAndar) -> some View {
        Button(titulo) {
            guard let grupoAtivo, let atual = temporario else { return }
            let planos = comodosExibidos
                .filter { $0.chaveSessaoPropria == grupoAtivo }
                .compactMap { m.planosPorComodo[$0.id] }
            let centro = FloorPlan2D.combinar(planos).centroRotulo
            temporario = Encaixe.girar(atual, por: delta, em: centro)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Encaixe

    private func iniciarEncaixe() {
        let m = MontadorPlanta.montar(andar: andar, comodos: comodos, rooms: rooms)
        limitesFixos = m.plano.limites.insetBy(dx: -2, dy: -2)
        selecionado = nil
        grupoAtivo = nil
        temporario = nil
        aviso = nil
        encaixando = true
    }

    private func sairDoEncaixe() {
        encaixando = false
        grupoAtivo = nil
        temporario = nil
        limitesFixos = nil
        aviso = nil
    }

    private func escolherGrupo(em p: CGPoint, montagem m: MontagemAndar) {
        guard let c = comodosExibidos.first(where: { c in
            m.planosPorComodo[c.id]?.pisos.contains { Geometria.contem($0, p) } ?? false
        }) else { return }
        let grupo = c.chaveSessaoPropria
        if grupo == m.chavePrincipal && c.alinhamento == nil {
            aviso = "\"\(c.nome)\" é a referência da planta. Toque num cômodo escaneado separado."
            return
        }
        aviso = nil
        grupoAtivo = grupo
        if let a = c.alinhamento, a.referencia == m.chavePrincipal {
            temporario = a
        } else if let room = rooms[c.id], let exibido = m.planosPorComodo[c.id] {
            // Começa onde o cômodo está sendo mostrado (ao lado da planta).
            let bruto = MontadorPlanta.planoBruto(c, room: room)
            let d = exibido.centro - bruto.centro
            temporario = Alinhamento(referencia: m.chavePrincipal, rotacao: 0, dx: Double(d.dx), dy: Double(d.dy))
        }
    }

    private func mover(_ d: CGVector) {
        guard var a = temporario else { return }
        a.dx += Double(d.dx)
        a.dy += Double(d.dy)
        temporario = a
    }

    private func encaixarPelaPorta(_ grupo: String) {
        let doGrupo = comodos.filter { $0.chaveSessaoPropria == grupo }
        let outros = comodos.filter { $0.chaveSessaoPropria != grupo }
        let fixo = MontadorPlanta.montar(andar: andar, comodos: outros, rooms: rooms)
        guard let chave = fixo.chavePrincipal else { return }
        let movel = FloorPlan2D.combinar(doGrupo.compactMap { c in rooms[c.id].map { MontadorPlanta.planoBruto(c, room: $0) } })
        if let a = Encaixe.porPorta(movel: movel, fixo: fixo.planoPrincipal, referencia: chave) {
            temporario = a
            aviso = nil
        } else {
            aviso = "Não encontrei uma porta em comum com a mesma largura. Arraste e gire à mão."
        }
    }

    private func carregar() {
        guard !carregado else { return }
        rooms = MontadorPlanta.carregarRooms(comodos, imovelID: imovelID)
        carregado = true
    }
}
