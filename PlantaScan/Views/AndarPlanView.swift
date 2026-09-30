import SwiftUI
import RoomPlan

/// Planta de um andar inteiro: junta os cômodos escaneados na mesma sessão (mesmo referencial).
/// Cômodos de sessões diferentes aparecem lado a lado, pois não há como alinhá-los.
struct AndarPlanView: View {
    let imovelID: UUID
    let andar: Int

    @Environment(ImovelStore.self) private var store
    @State private var rooms: [UUID: CapturedRoom] = [:]
    @State private var carregado = false
    @State private var selecionado: ElementoPlano?
    @AppStorage("mostrarNomeComodo") private var mostrarNomeComodo = true
    @AppStorage("mostrarNomesObjetos") private var mostrarNomesObjetos = true

    private var comodos: [Comodo] {
        store.imovel(id: imovelID)?.comodos.filter { $0.andarOuPadrao == andar } ?? []
    }

    var body: some View {
        Group {
            if !carregado {
                ProgressView("Montando a planta…")
            } else {
                let montagem = montar()
                VStack(spacing: 0) {
                    FloorPlanCanvas(
                        plano: montagem.plano,
                        titulo: nil,
                        selecionado: $selecionado,
                        mostrarNomeComodo: mostrarNomeComodo,
                        mostrarNomesObjetos: mostrarNomesObjetos,
                        anguloNorte: montagem.norte
                    )
                    Divider()
                    painel(montagem)
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
                } label: {
                    Label("Opções", systemImage: "ellipsis.circle")
                }
            }
        }
        .task { carregar() }
    }

    private struct Montagem {
        var plano: FloorPlan2D
        var norte: Double?
        var separados: Bool
    }

    private func montar() -> Montagem {
        // Agrupa por sessão; cômodos antigos sem sessão ficam cada um no seu grupo.
        var ordem: [String] = []
        var grupos: [String: [FloorPlan2D]] = [:]
        var norte: Double?
        for c in comodos {
            guard let room = rooms[c.id] else { continue }
            var p = FloorPlanBuilder.construir(room, comodo: c)
            p.rotulos = [RotuloComodo(ponto: p.centroRotulo, nome: c.nome, area: p.area)]
            let chave = c.sessao?.uuidString ?? c.id.uuidString
            if grupos[chave] == nil {
                ordem.append(chave)
            }
            // O norte vale para o primeiro grupo (os outros podem estar em outro referencial).
            if ordem.first == chave, norte == nil {
                norte = c.anguloNorte
            }
            grupos[chave, default: []].append(p)
        }

        var partes: [FloorPlan2D] = []
        var proximoX: CGFloat = 0
        for chave in ordem {
            var g = FloorPlan2D.combinar(grupos[chave] ?? [])
            if !partes.isEmpty {
                g.deslocar(CGVector(dx: proximoX - g.limites.minX, dy: 0))
            }
            proximoX = g.limites.maxX + 1.5
            partes.append(g)
        }
        return Montagem(plano: FloorPlan2D.combinar(partes), norte: norte, separados: ordem.count > 1)
    }

    private func painel(_ m: Montagem) -> some View {
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
                    Text(contagem)
                        .font(.subheadline)
                }
                if m.separados {
                    Label("Alguns cômodos foram escaneados em sessões separadas e aparecem lado a lado, fora da posição real. Use \"Continuar scan\" para escanear conectado aos anteriores.", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
    }

    private func carregar() {
        guard !carregado else { return }
        var r: [UUID: CapturedRoom] = [:]
        for c in comodos {
            if let room = try? Storage.carregarScan(comodoID: c.id, imovelID: imovelID) {
                r[c.id] = room
            }
        }
        rooms = r
        carregado = true
    }
}
