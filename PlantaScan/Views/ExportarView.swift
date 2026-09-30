import QuickLook
import SwiftUI

/// Exportação do imóvel: PDF profissional, PNG da planta por andar e modelos 3D (USDZ).
/// Os arquivos abrem no Quick Look, que tem o botão de compartilhar (WhatsApp, e-mail, Arquivos…).
struct ExportarView: View {
    let imovelID: UUID

    @Environment(ImovelStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var incluirCortes = true
    @State private var incluirQuadros = true
    @State private var mostrarMobiliario = true
    @State private var gerando = false
    @State private var arquivo: URL?
    @State private var erro: String?

    private var imovel: Imovel? { store.imovel(id: imovelID) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Cortes AA e BB", isOn: $incluirCortes)
                    Toggle("Quadros de áreas e esquadrias", isOn: $incluirQuadros)
                    Toggle("Mobiliário na planta", isOn: $mostrarMobiliario)
                    Button {
                        gerar { imovel, montagens in
                            try PDFExporter.gerarPDF(
                                imovel: imovel,
                                montagens: montagens,
                                opcoes: .init(incluirCortes: incluirCortes, incluirQuadros: incluirQuadros, mostrarMobiliario: mostrarMobiliario)
                            )
                        }
                    } label: {
                        Label("Gerar PDF", systemImage: "doc.richtext")
                    }
                } header: {
                    Text("PDF profissional (A4)")
                } footer: {
                    Text("Planta de cada andar em escala, com cotas, legenda, norte, escala gráfica e carimbo.")
                }

                if let imovel, !imovel.andares.isEmpty {
                    Section("Imagem da planta (PNG)") {
                        ForEach(imovel.andares, id: \.self) { andar in
                            Button {
                                gerar { imovel, montagens in
                                    guard let m = montagens.first(where: { $0.andar == andar }) else {
                                        throw CocoaError(.fileNoSuchFile)
                                    }
                                    return try PDFExporter.gerarPNG(imovel: imovel, montagem: m)
                                }
                            } label: {
                                Label("Planta do \(Formato.andar(andar))", systemImage: "photo")
                            }
                        }
                    }

                    Section {
                        ForEach(imovel.comodos) { c in
                            Button {
                                arquivo = Storage.urlModelo(comodoID: c.id, imovelID: imovelID)
                            } label: {
                                Label(c.nome, systemImage: "cube")
                            }
                        }
                    } header: {
                        Text("Modelo 3D (USDZ)")
                    } footer: {
                        Text("Abre o modelo 3D do cômodo; dá para ver em realidade aumentada e compartilhar.")
                    }
                }
            }
            .navigationTitle("Exportar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fechar") { dismiss() }
                }
            }
            .disabled(gerando)
            .overlay {
                if gerando {
                    ProgressView("Gerando…")
                        .padding(20)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                }
            }
            .quickLookPreview($arquivo)
            .alert(
                "Erro",
                isPresented: Binding(get: { erro != nil }, set: { if !$0 { erro = nil } })
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(erro ?? "")
            }
        }
    }

    private func gerar(_ acao: @escaping (Imovel, [MontagemAndar]) throws -> URL) {
        guard let imovel else { return }
        gerando = true
        Task { @MainActor in
            // Deixa o indicador aparecer antes do trabalho pesado.
            try? await Task.sleep(nanoseconds: 80_000_000)
            do {
                let rooms = MontadorPlanta.carregarRooms(imovel.comodos, imovelID: imovelID)
                let montagens = imovel.andares.map {
                    MontadorPlanta.montar(andar: $0, comodos: imovel.comodos, rooms: rooms)
                }
                arquivo = try acao(imovel, montagens)
            } catch {
                erro = "Não foi possível gerar o arquivo: \(error.localizedDescription)"
            }
            gerando = false
        }
    }
}
