import SwiftUI

/// Edita nome, tipo e andar de um cômodo.
struct EditarComodoView: View {
    let imovelID: UUID
    let comodo: Comodo

    @Environment(ImovelStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var nome: String
    @State private var tipo: TipoComodo
    @State private var andar: Int

    init(imovelID: UUID, comodo: Comodo) {
        self.imovelID = imovelID
        self.comodo = comodo
        _nome = State(initialValue: comodo.nome)
        _tipo = State(initialValue: comodo.tipo ?? .outro)
        _andar = State(initialValue: comodo.andarOuPadrao)
    }

    private var nomeSugerido: String {
        DetectorComodo.nomeSugerido(tipo, existentes: store.imovel(id: imovelID)?.comodos ?? [], ignorando: comodo.id)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Nome") {
                    TextField("Nome do cômodo", text: $nome)
                    if nomeSugerido != nome {
                        Button("Usar \"\(nomeSugerido)\"") { nome = nomeSugerido }
                    }
                }
                Section("Tipo") {
                    Picker("Tipo", selection: $tipo) {
                        ForEach(TipoComodo.allCases) { t in
                            Label(t.nome, systemImage: t.icone).tag(t)
                        }
                    }
                    .pickerStyle(.navigationLink)
                }
                Section("Andar") {
                    Stepper(Formato.andar(andar), value: $andar, in: 1...20)
                }
            }
            .navigationTitle("Editar cômodo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salvar") {
                        let limpo = nome.trimmingCharacters(in: .whitespacesAndNewlines)
                        store.atualizarComodo(
                            id: comodo.id,
                            nome: limpo.isEmpty ? nomeSugerido : limpo,
                            tipo: tipo,
                            andar: andar,
                            imovelID: imovelID
                        )
                        dismiss()
                    }
                }
            }
        }
    }
}
