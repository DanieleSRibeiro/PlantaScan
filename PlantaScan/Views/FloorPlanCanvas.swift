import SwiftUI

/// Planta desenhada com Canvas: pinça para zoom, arrasto para mover, toque para selecionar.
struct FloorPlanCanvas: View {
    let plano: FloorPlan2D
    var titulo: String?
    @Binding var selecionado: ElementoPlano?
    var mostrarNomeComodo = true
    var mostrarNomesObjetos = true
    var anguloNorte: Double?
    /// Limites fixos (para a escala não mudar enquanto um cômodo é arrastado).
    var limites: CGRect? = nil
    /// Se definido, o toque devolve o ponto (em metros) em vez de selecionar um elemento.
    var aoTocar: ((CGPoint) -> Void)? = nil
    /// Se definido, arrastar move algo (delta em metros) em vez de mover a vista.
    var aoArrastar: ((CGVector) -> Void)? = nil

    @State private var zoom: CGFloat = 1
    @State private var zoomBase: CGFloat = 1
    @State private var desloc: CGSize = .zero
    @State private var deslocBase: CGSize = .zero
    @State private var ultimaTranslacao: CGSize = .zero

    var body: some View {
        GeometryReader { geo in
            let t = PlanoTransform.ajustar(limites ?? plano.limites, em: geo.size, zoom: zoom, deslocamento: desloc)
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
                                if let aoArrastar {
                                    let dx = v.translation.width - ultimaTranslacao.width
                                    let dy = v.translation.height - ultimaTranslacao.height
                                    ultimaTranslacao = v.translation
                                    aoArrastar(CGVector(dx: dx / t.escala, dy: dy / t.escala))
                                } else {
                                    desloc = CGSize(width: deslocBase.width + v.translation.width,
                                                    height: deslocBase.height + v.translation.height)
                                }
                            }
                            .onEnded { _ in
                                ultimaTranslacao = .zero
                                if aoArrastar == nil { deslocBase = desloc }
                            }
                    )
            )
            .simultaneousGesture(
                SpatialTapGesture().onEnded { v in
                    let p = t.plano(v.location)
                    if let aoTocar {
                        aoTocar(p)
                    } else {
                        selecionado = plano.elemento(em: p, tolerancia: 12 / t.escala)
                    }
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
