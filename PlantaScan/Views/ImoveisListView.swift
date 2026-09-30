import SwiftUI

enum ImovelEditorAlvo: Identifiable {
    case novo
    case editar(Imovel)

    var id: String {
        switch self {
        case .novo: return "novo"
        case .editar(let imovel): return imovel.id.uuidString
        }
    }
}

struct ImoveisListView: View {
    @Environment(ImovelStore.self) private var store
    @State private var editor: ImovelEditorAlvo?
    @State private var paraApagar: Imovel?

    var body: some View {
        NavigationStack {
            Group {
                if store.imoveis.isEmpty {
                    ContentUnavailableView(
                        "Nenhum imóvel",
                        systemImage: "house",
                        description: Text("Toque em + para cadastrar o primeiro imóvel.")
                    )
                } else {
                    lista
                }
            }
            .navigationTitle("Imóveis")
            .navigationDestination(for: UUID.self) { id in
                ImovelDetailView(imovelID: id)
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        editor = .novo
                    } label: {
                        Label("Novo imóvel", systemImage: "plus")
                    }
                }
            }
            .sheet(item: $editor) { alvo in
                ImovelFormView(alvo: alvo)
            }
            .confirmationDialog(
                "Apagar imóvel?",
                isPresented: Binding(get: { paraApagar != nil }, set: { if !$0 { paraApagar = nil } }),
                titleVisibility: .visible,
                presenting: paraApagar
            ) { imovel in
                Button("Apagar \"\(imovel.nome)\"", role: .destructive) {
                    store.apagarImovel(id: imovel.id)
                }
            } message: { _ in
                Text("Todos os cômodos escaneados deste imóvel serão apagados.")
            }
            .alert(
                "Erro",
                isPresented: Binding(get: { store.mensagemErro != nil }, set: { if !$0 { store.mensagemErro = nil } })
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(store.mensagemErro ?? "")
            }
        }
    }

    private var lista: some View {
        List {
            ForEach(store.imoveis) { imovel in
                NavigationLink(value: imovel.id) {
                    ImovelRow(imovel: imovel)
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        paraApagar = imovel
                    } label: {
                        Label("Apagar", systemImage: "trash")
                    }
                    Button {
                        editor = .editar(imovel)
                    } label: {
                        Label("Renomear", systemImage: "pencil")
                    }
                    .tint(.orange)
                }
                .contextMenu {
                    Button {
                        editor = .editar(imovel)
                    } label: {
                        Label("Renomear", systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        paraApagar = imovel
                    } label: {
                        Label("Apagar", systemImage: "trash")
                    }
                }
            }
        }
    }
}

private struct ImovelRow: View {
    let imovel: Imovel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(imovel.nome)
                .font(.headline)
            if !imovel.endereco.isEmpty {
                Text(imovel.endereco)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            HStack(spacing: 12) {
                Label(imovel.dataCriacao.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
                Label("\(imovel.comodos.count) cômodo(s)", systemImage: "square.split.2x2")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

struct ImovelFormView: View {
    let alvo: ImovelEditorAlvo

    @Environment(ImovelStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var nome = ""
    @State private var endereco = ""

    private var nomeLimpo: String { nome.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                Section("Nome") {
                    TextField("Ex.: Apartamento Centro", text: $nome)
                }
                Section("Endereço") {
                    TextField("Rua, número, bairro, cidade", text: $endereco, axis: .vertical)
                        .lineLimit(1...4)
                }
            }
            .navigationTitle(tituloTela)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salvar") { salvar() }
                        .disabled(nomeLimpo.isEmpty)
                }
            }
            .onAppear {
                if case .editar(let imovel) = alvo {
                    nome = imovel.nome
                    endereco = imovel.endereco
                }
            }
        }
    }

    private var tituloTela: String {
        switch alvo {
        case .novo: return "Novo imóvel"
        case .editar: return "Editar imóvel"
        }
    }

    private func salvar() {
        let enderecoLimpo = endereco.trimmingCharacters(in: .whitespacesAndNewlines)
        switch alvo {
        case .novo:
            store.criarImovel(nome: nomeLimpo, endereco: enderecoLimpo)
        case .editar(let original):
            guard var atual = store.imovel(id: original.id) else { break }
            atual.nome = nomeLimpo
            atual.endereco = enderecoLimpo
            store.atualizar(atual)
        }
        dismiss()
    }
}
