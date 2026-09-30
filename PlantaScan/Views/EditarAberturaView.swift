import SwiftUI

/// Editor de porta/janela/vão: tipo, modelo (com miniaturas), medidas, posição e lado de abertura.
struct EditarAberturaView: View {
    let abertura: Abertura2D
    let aoSalvar: (EdicaoAbertura?) -> Void
    let aoRemover: () -> Void

    @State private var edicao: EdicaoAbertura
    @Environment(\.dismiss) private var dismiss

    init(abertura: Abertura2D, edicao: EdicaoAbertura, aoSalvar: @escaping (EdicaoAbertura?) -> Void, aoRemover: @escaping () -> Void) {
        self.abertura = abertura
        self.aoSalvar = aoSalvar
        self.aoRemover = aoRemover
        _edicao = State(initialValue: edicao)
    }

    private var tipo: TipoAbertura { edicao.tipo ?? abertura.tipo }
    private var modeloPorta: ModeloPorta { edicao.modeloPorta ?? abertura.modeloPorta }
    private var modeloJanela: ModeloJanela { edicao.modeloJanela ?? abertura.modeloJanela }
    private var largura: Double { edicao.largura ?? abertura.dimensoes.largura }
    private var altura: Double { edicao.altura ?? abertura.dimensoes.altura }
    private var inverterLado: Bool { edicao.inverterLado ?? false }
    private var inverterDobradica: Bool { edicao.inverterDobradica ?? false }

    private let colunas = [GridItem(.adaptive(minimum: 96), spacing: 12)]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ModeloPreview(
                        tipo: tipo,
                        porta: modeloPorta,
                        janela: modeloJanela,
                        inverterLado: inverterLado,
                        inverterDobradica: inverterDobradica
                    )
                    .frame(height: 120)
                    .frame(maxWidth: .infinity)

                    Picker("Tipo", selection: Binding(get: { tipo }, set: { edicao.tipo = $0 })) {
                        ForEach(TipoAbertura.allCases) { t in
                            Text(t.nome).tag(t)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                if tipo == .porta {
                    Section("Modelo da porta") {
                        LazyVGrid(columns: colunas, spacing: 12) {
                            ForEach(ModeloPorta.allCases) { m in
                                CartaoModelo(nome: m.nome, selecionado: m == modeloPorta) {
                                    ModeloPreview(tipo: .porta, porta: m)
                                }
                                .onTapGesture { edicao.modeloPorta = m }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                } else if tipo == .janela {
                    Section("Modelo da janela") {
                        LazyVGrid(columns: colunas, spacing: 12) {
                            ForEach(ModeloJanela.allCases) { m in
                                CartaoModelo(nome: m.nome, selecionado: m == modeloJanela) {
                                    ModeloPreview(tipo: .janela, janela: m)
                                }
                                .onTapGesture { edicao.modeloJanela = m }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section("Medidas") {
                    Stepper(value: Binding(get: { largura }, set: { edicao.largura = $0 }), in: 0.3...5, step: 0.05) {
                        LabeledContent("Largura", value: Formato.metros(largura))
                    }
                    Stepper(value: Binding(get: { altura }, set: { edicao.altura = $0 }), in: 0.2...3.5, step: 0.05) {
                        LabeledContent("Altura", value: Formato.metros(altura))
                    }
                }

                Section("Posição") {
                    Stepper(value: Binding(get: { edicao.deslocamento ?? 0 }, set: { edicao.deslocamento = $0 }), in: -10...10, step: 0.05) {
                        LabeledContent("Mover na parede", value: Formato.metros(edicao.deslocamento ?? 0))
                    }
                    if tipo != .vao {
                        Toggle("Inverter lado de abertura", isOn: Binding(get: { inverterLado }, set: { edicao.inverterLado = $0 }))
                    }
                    if tipo == .porta && modeloPorta == .giro {
                        Toggle("Inverter lado da dobradiça", isOn: Binding(get: { inverterDobradica }, set: { edicao.inverterDobradica = $0 }))
                    }
                }

                Section {
                    if !abertura.manual {
                        Button("Restaurar como foi escaneado") {
                            aoSalvar(nil)
                            dismiss()
                        }
                    }
                    Button("Remover \(tipo.nome.lowercased())", role: .destructive) {
                        aoRemover()
                        dismiss()
                    }
                }
            }
            .navigationTitle("Editar \(tipo.nome.lowercased())")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salvar") {
                        aoSalvar(edicao)
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct CartaoModelo<Conteudo: View>: View {
    let nome: String
    let selecionado: Bool
    @ViewBuilder let conteudo: () -> Conteudo

    var body: some View {
        VStack(spacing: 6) {
            conteudo()
                .frame(height: 64)
            Text(nome)
                .font(.caption.weight(selecionado ? .semibold : .regular))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(8)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(selecionado ? Color.accentColor.opacity(0.12) : Color(uiColor: .secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(selecionado ? Color.accentColor : Color(uiColor: .separator), lineWidth: selecionado ? 2 : 0.5)
        )
        .contentShape(Rectangle())
        .accessibilityAddTraits(selecionado ? [.isButton, .isSelected] : .isButton)
    }
}
