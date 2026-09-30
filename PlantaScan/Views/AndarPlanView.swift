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

    private func montar() -> MontagemAndar {
        MontadorPlanta.montar(andar: andar, comodos: comodos, rooms: rooms)
    }

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
        rooms = MontadorPlanta.carregarRooms(comodos, imovelID: imovelID)
        carregado = true
    }
}
