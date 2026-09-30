import SwiftUI
import UniformTypeIdentifiers

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
    @Environment(Sincronizador.self) private var sinc
    @State private var editor: ImovelEditorAlvo?
    @State private var mostrandoConta = false
    @State private var paginaPro: LinkWeb?
    @State private var paraApagar: Imovel?
    @State private var busca = ""
    @State private var importando = false
    @State private var resultadoImportacao: String?

    private static let tiposPlanilha: [UTType] =
        [UTType.commaSeparatedText, UTType.tabSeparatedText, UTType.plainText]
        + [UTType("org.openxmlformats.spreadsheetml.sheet")].compactMap { $0 }

    private var filtrados: [Imovel] {
        let termo = busca.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !termo.isEmpty else { return store.imoveis }
        let palavras = normalizar(termo).split(separator: " ").map(String.init)
        return store.imoveis.filter { imovel in
            let texto = normalizar([imovel.nome, imovel.endereco, imovel.eircode ?? ""].joined(separator: " "))
            let eircodeCompacto = normalizar(imovel.eircode ?? "").replacingOccurrences(of: " ", with: "")
            let termoCompacto = normalizar(termo).replacingOccurrences(of: " ", with: "")
            if !eircodeCompacto.isEmpty && eircodeCompacto.contains(termoCompacto) { return true }
            return palavras.allSatisfy { texto.contains($0) }
        }
    }

    private func normalizar(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "pt_BR"))
    }

    var body: some View {
        NavigationStack {
            Group {
                if store.imoveis.isEmpty {
                    ContentUnavailableView {
                        Label("Nenhum imóvel", systemImage: "house")
                    } description: {
                        Text("Cadastre um imóvel ou importe uma planilha (CSV ou Excel) com várias casas.")
                    } actions: {
                        Button("Novo imóvel") { editor = .novo }
                            .buttonStyle(.borderedProminent)
                        Button("Importar planilha") { importando = true }
                    }
                } else if filtrados.isEmpty {
                    ContentUnavailableView.search(text: busca)
                } else {
                    lista
                }
            }
            .navigationTitle("Imóveis")
            .searchable(text: $busca, prompt: "Nome, endereço ou Eircode")
            .navigationDestination(for: UUID.self) { id in
                ImovelDetailView(imovelID: id)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        mostrandoConta = true
                    } label: {
                        if sinc.sincronizando {
                            ProgressView()
                        } else {
                            Label(
                                "Conta e sincronização",
                                systemImage: sinc.logado
                                    ? (sinc.ultimoErro == nil ? "checkmark.icloud" : "exclamationmark.icloud")
                                    : "icloud.slash"
                            )
                        }
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        paginaPro = .pro()
                    } label: {
                        Label("Inspeções (Pro)", systemImage: "checklist")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            editor = .novo
                        } label: {
                            Label("Novo imóvel", systemImage: "plus")
                        }
                        Button {
                            importando = true
                        } label: {
                            Label("Importar planilha (CSV/Excel)", systemImage: "square.and.arrow.down")
                        }
                    } label: {
                        Label("Adicionar", systemImage: "plus")
                    }
                }
            }
            .sheet(item: $editor) { alvo in
                ImovelFormView(alvo: alvo)
            }
            .sheet(isPresented: $mostrandoConta) {
                ContaView()
            }
            .paginaWeb($paginaPro)
            .fileImporter(isPresented: $importando, allowedContentTypes: Self.tiposPlanilha) { resultado in
                importar(resultado)
            }
            .alert(
                "Importação",
                isPresented: Binding(get: { resultadoImportacao != nil }, set: { if !$0 { resultadoImportacao = nil } })
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(resultadoImportacao ?? "")
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
            if !sinc.logado {
                Button {
                    mostrandoConta = true
                } label: {
                    Label("Entre na sua conta para sincronizar com o computador", systemImage: "icloud")
                        .font(.subheadline)
                }
            }
            ForEach(filtrados) { imovel in
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
                        Label("Editar", systemImage: "pencil")
                    }
                    .tint(.orange)
                }
                .contextMenu {
                    Button {
                        editor = .editar(imovel)
                    } label: {
                        Label("Editar", systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        paraApagar = imovel
                    } label: {
                        Label("Apagar", systemImage: "trash")
                    }
                }
            }
        }
        .refreshable {
            await sinc.sincronizar()
        }
    }

    private func importar(_ resultado: Result<URL, Error>) {
        do {
            let url = try resultado.get()
            let itens = try ImportadorPlanilha.ler(url: url)
            let r = store.importar(itens)
            var msg = "\(r.importados) imóvel(is) importado(s)."
            if r.ignorados > 0 {
                msg += " \(r.ignorados) ignorado(s) por já existirem."
            }
            resultadoImportacao = msg
        } catch {
            resultadoImportacao = error.localizedDescription
        }
    }
}

private struct ImovelRow: View {
    let imovel: Imovel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(imovel.nome)
                    .font(.headline)
                Spacer()
                if let eircode = imovel.eircode, !eircode.isEmpty {
                    Text(eircode)
                        .font(.caption.monospaced().weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.12), in: Capsule())
                }
            }
            if !imovel.endereco.isEmpty {
                Text(imovel.endereco)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            HStack(spacing: 12) {
                Label("\(imovel.comodos.count) cômodo(s)", systemImage: "square.split.2x2")
                if imovel.areaTotal > 0 {
                    Label(Formato.area(imovel.areaTotal), systemImage: "ruler")
                }
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
    @State private var eircode = ""

    private var nomeLimpo: String { nome.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                Section("Nome") {
                    TextField("Ex.: Casa Rua das Flores", text: $nome)
                }
                Section("Endereço") {
                    TextField("Rua, número, bairro, cidade", text: $endereco, axis: .vertical)
                        .lineLimit(1...4)
                    TextField("Eircode (ex.: D02 X285)", text: $eircode)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
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
                    eircode = imovel.eircode ?? ""
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
        let eircodeLimpo = eircode.trimmingCharacters(in: .whitespacesAndNewlines)
        switch alvo {
        case .novo:
            store.criarImovel(nome: nomeLimpo, endereco: enderecoLimpo, eircode: eircodeLimpo)
        case .editar(let original):
            guard var atual = store.imovel(id: original.id) else { break }
            atual.nome = nomeLimpo
            atual.endereco = enderecoLimpo
            atual.eircode = eircodeLimpo.isEmpty ? nil : ImportadorPlanilha.formatarEircode(eircodeLimpo)
            store.atualizar(atual)
        }
        dismiss()
    }
}
