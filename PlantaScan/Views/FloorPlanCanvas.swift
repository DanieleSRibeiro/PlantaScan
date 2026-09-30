import SwiftUI

/// Planta desenhada com Canvas: pinça para zoom, arrasto para mover, toque para selecionar.
struct FloorPlanCanvas: View {
    let plano: FloorPlan2D
    var titulo: String?
    @Binding var selecionado: ElementoPlano?
    var mostrarNomeComodo = true
    var mostrarNomesObjetos = true
    var anguloNorte: Double?

    @State private var zoom: CGFloat = 1
    @State private var zoomBase: CGFloat = 1
    @State private var desloc: CGSize = .zero
    @State private var deslocBase: CGSize = .zero

    var body: some View {
        GeometryReader { geo in
            let t = PlanoTransform.ajustar(plano.limites, em: geo.size, zoom: zoom, deslocamento: desloc)
            Canvas { ctx, size in
                FloorPlanRenderer(
                    plano: plano, t: t, selecionado: selecionado?.id, titulo: titulo,
                    mostrarNomeComodo: mostrarNomeComodo, mostrarNomesObjetos: mostrarNomesObjetos,
                    anguloNorte: anguloNorte
                )
                .desenhar(ctx, tamanho: size)
            }
            .background(Color(uiColor: .systemBackground))
            .contentShape(Rectangle())
            .gesture(
                MagnifyGesture()
                    .onChanged { v in zoom = min(max(zoomBase * v.magnification, 0.3), 12) }
                    .onEnded { _ in zoomBase = zoom }
                    .simultaneously(with:
                        DragGesture()
                            .onChanged { v in
                                desloc = CGSize(width: deslocBase.width + v.translation.width,
                                                height: deslocBase.height + v.translation.height)
                            }
                            .onEnded { _ in deslocBase = desloc }
                    )
            )
            .simultaneousGesture(
                SpatialTapGesture().onEnded { v in
                    let p = t.plano(v.location)
                    selecionado = plano.elemento(em: p, tolerancia: 12 / t.escala)
                }
            )
            .overlay(alignment: .topLeading) {
                if zoom != 1 || desloc != .zero {
                    Button {
                        withAnimation(.snappy) {
                            zoom = 1; zoomBase = 1
                            desloc = .zero; deslocBase = .zero
                        }
                    } label: {
                        Label("Centralizar", systemImage: "arrow.up.left.and.down.right.magnifyingglass")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .padding(10)
                }
            }
        }
    }
}

/// Miniatura de um modelo de porta/janela, usando o mesmo desenho da planta.
struct ModeloPreview: View {
    let tipo: TipoAbertura
    var porta: ModeloPorta = .giro
    var janela: ModeloJanela = .correr
    var inverterLado = false
    var inverterDobradica = false
    var fundo: Color = Color(uiColor: .secondarySystemGroupedBackground)

    var body: some View {
        Canvas { ctx, size in
            var plano = FloorPlan2D()
            plano.paredes = [
                Parede2D(id: UUID(), a: CGPoint(x: -1.1, y: 0), b: CGPoint(x: 1.1, y: 0),
                         dimensoes: Dimensoes(largura: 2.2, altura: 2.5, profundidade: 0))
            ]
            var ab = Abertura2D(
                id: UUID(), tipo: tipo,
                a: CGPoint(x: -0.45, y: 0), b: CGPoint(x: 0.45, y: 0),
                ladoInterno: CGVector(dx: 0, dy: inverterLado ? -1 : 1),
                dimensoes: Dimensoes(largura: 0.9, altura: 2.1, profundidade: 0)
            )
            ab.modeloPorta = porta
            ab.modeloJanela = janela
            ab.dobradicaNoFim = inverterDobradica
            plano.aberturas = [ab]

            var paleta = PaletaPlano.tela
            paleta.fundo = fundo
            let t = PlanoTransform.ajustar(CGRect(x: -1.1, y: -1.0, width: 2.2, height: 2.0), em: size, margem: 6)
            FloorPlanRenderer(plano: plano, t: t, paleta: paleta, mostrarCotas: false, mostrarAcessorios: false,
                              mostrarArea: false, mostrarNomeComodo: false, mostrarNomesObjetos: false)
                .desenhar(ctx, tamanho: size)
        }
    }
}
