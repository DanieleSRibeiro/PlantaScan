import SwiftUI

/// Correção manual da direção do norte na planta.
struct AjusteNorteView: View {
    /// Norte medido pela bússola no scan (radianos), se houver.
    let medido: Double?
    let aoSalvar: (Double) -> Void

    @State private var ajuste: Double
    @Environment(\.dismiss) private var dismiss

    init(medido: Double?, ajusteInicial: Double, aoSalvar: @escaping (Double) -> Void) {
        self.medido = medido
        self.aoSalvar = aoSalvar
        _ajuste = State(initialValue: ajusteInicial)
    }

    private var angulo: Double {
        (medido ?? -Double.pi / 2) + ajuste * Double.pi / 180
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text(medido == nil
                     ? "O norte não foi medido neste scan. Gire a seta até apontar para o norte."
                     : "O norte foi medido pela bússola durante o scan. Se estiver errado (interferência de metal), corrija aqui.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                ZStack {
                    Circle()
                        .stroke(Color(uiColor: .separator), lineWidth: 1)
                    Image(systemName: "location.north.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.tint)
                        .rotationEffect(.radians(angulo + .pi / 2))
                }
                .frame(width: 120, height: 120)

                VStack {
                    Slider(value: $ajuste, in: -180...180, step: 1)
                    Text("Correção: \(Int(ajuste))°")
                        .font(.subheadline.monospacedDigit())
                }

                if ajuste != 0 {
                    Button("Voltar ao medido") { ajuste = 0 }
                }
            }
            .padding()
            .navigationTitle("Ajustar norte")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salvar") {
                        aoSalvar(ajuste)
                        dismiss()
                    }
                }
            }
        }
    }
}
