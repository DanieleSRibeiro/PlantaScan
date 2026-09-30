import CoreGraphics
import SwiftUI

/// Linha de corte na planta.
struct Corte {
    /// "A" ou "B".
    var letra: String
    /// Ponto de referência e direção da linha (em metros, plano XZ).
    var origem: CGPoint
    var direcao: CGVector
    /// Direção para onde o observador olha (perpendicular à linha).
    var vista: CGVector
    var inicio: CGPoint
    var fim: CGPoint
}

/// Elemento do corte em coordenadas (posição ao longo da linha × altura acima do piso), em metros.
struct ElementoCorte {
    enum Tipo {
        case paredeCortada, paredeVista
        case portaCortada, janelaCortada, vaoCortado
        case portaVista, janelaVista, vaoVisto
    }

    var tipo: Tipo
    var x0: Double
    var x1: Double
    var y0: Double
    var y1: Double
}

struct Secao2D {
    var letra: String
    var elementos: [ElementoCorte]
    var xMin: Double
    var xMax: Double
    var alturaMax: Double

    var vazia: Bool { elementos.isEmpty }
}

/// Gera cortes esquemáticos a partir da planta 2D e das alturas medidas pelo RoomPlan.
/// Espessura de laje e de piso não são medidas: o corte mostra paredes, vãos e pé-direito.
enum SecaoBuilder {
    /// Corte AA (horizontal na planta, olhando para cima) e BB (vertical, olhando para a esquerda),
    /// posicionados para passar pelo maior número de portas e janelas.
    static func cortes(para plano: FloorPlan2D) -> [Corte] {
        let l = plano.limites
        let folga: CGFloat = 0.8

        let zA = melhorPosicao(plano, horizontal: true, padrao: l.midY)
        let a = Corte(
            letra: "A",
            origem: CGPoint(x: l.minX - folga, y: zA),
            direcao: CGVector(dx: 1, dy: 0),
            vista: CGVector(dx: 0, dy: -1),
            inicio: CGPoint(x: l.minX - folga, y: zA),
            fim: CGPoint(x: l.maxX + folga, y: zA)
        )

        let xB = melhorPosicao(plano, horizontal: false, padrao: l.midX)
        let b = Corte(
            letra: "B",
            origem: CGPoint(x: xB, y: l.maxY + folga),
            direcao: CGVector(dx: 0, dy: -1),
            vista: CGVector(dx: -1, dy: 0),
            inicio: CGPoint(x: xB, y: l.maxY + folga),
            fim: CGPoint(x: xB, y: l.minY - folga)
        )
        return [a, b]
    }

    private static func melhorPosicao(_ plano: FloorPlan2D, horizontal: Bool, padrao: CGFloat) -> CGFloat {
        func coord(_ p: CGPoint) -> CGFloat { horizontal ? p.y : p.x }
        var candidatos: [CGFloat] = [padrao]
        for ab in plano.aberturas {
            let u = (ab.b - ab.a).normalizado
            // A abertura precisa cruzar a linha: direção quase perpendicular a ela.
            let componente = horizontal ? abs(u.dy) : abs(u.dx)
            if componente > 0.7 {
                candidatos.append(coord(CGPoint.media(ab.a, ab.b)))
            }
        }
        func pontuacao(_ c: CGFloat) -> Int {
            plano.aberturas.filter { ab in
                let da = coord(ab.a) - c
                let db = coord(ab.b) - c
                return da * db < 0
            }.count
        }
        return candidatos.max { x, y in
            let px = pontuacao(x)
            let py = pontuacao(y)
            if px != py { return px < py }
            return abs(x - padrao) > abs(y - padrao)
        } ?? padrao
    }

    static func secao(_ plano: FloorPlan2D, corte: Corte) -> Secao2D {
        let piso = plano.nivelPiso
        let esp = FloorPlanBuilder.espessuraPadrao
        let d = corte.direcao
        let v = corte.vista

        func ao(_ p: CGPoint) -> Double { Double((p - corte.origem).dot(d)) }
        func prof(_ p: CGPoint) -> Double { Double((p - corte.origem).dot(v)) }

        /// Ponto onde o segmento cruza a linha de corte.
        func cruzamento(_ a: CGPoint, _ b: CGPoint) -> CGPoint? {
            let da = prof(a)
            let db = prof(b)
            guard da * db <= 0, da != db else { return nil }
            let t = CGFloat(da / (da - db))
            return a + (b - a) * t
        }

        /// Visível: nenhuma outra parede entre o elemento e a linha de corte.
        func visivel(_ m: CGPoint, ignorando: (Parede2D) -> Bool) -> Bool {
            let distancia = CGFloat(prof(m))
            let inicio = m - v * 0.05
            let fim = m - v * distancia
            return !plano.paredes.contains { p in
                !ignorando(p) && Geometria.cruzam(inicio, fim, p.a, p.b)
            }
        }

        var elementos: [ElementoCorte] = []

        for p in plano.paredes {
            let y0 = p.yBase - piso
            let y1 = y0 + p.dimensoes.altura
            let u = (p.b - p.a).normalizado
            if let x = cruzamento(p.a, p.b).map(ao) {
                let seno = max(abs(Double(u.dot(v))), 0.33)
                let meia = esp / seno / 2
                elementos.append(ElementoCorte(tipo: .paredeCortada, x0: x - meia, x1: x + meia, y0: y0, y1: y1))
            } else if prof(p.a) > 0, prof(p.b) > 0, abs(u.dot(d)) > 0.5 {
                let m = CGPoint.media(p.a, p.b)
                if visivel(m, ignorando: { $0.id == p.id }) {
                    let xa = ao(p.a)
                    let xb = ao(p.b)
                    elementos.append(ElementoCorte(tipo: .paredeVista, x0: min(xa, xb), x1: max(xa, xb), y0: y0, y1: y1))
                }
            }
        }

        for ab in plano.aberturas {
            let y0 = ab.yBase - piso
            let y1 = y0 + ab.dimensoes.altura
            let u = (ab.b - ab.a).normalizado
            if let x = cruzamento(ab.a, ab.b).map(ao) {
                let seno = max(abs(Double(u.dot(v))), 0.33)
                let meia = esp / seno / 2 + 0.01
                let tipo: ElementoCorte.Tipo
                switch ab.tipo {
                case .porta: tipo = .portaCortada
                case .janela: tipo = .janelaCortada
                case .vao: tipo = .vaoCortado
                }
                elementos.append(ElementoCorte(tipo: tipo, x0: x - meia, x1: x + meia, y0: y0, y1: y1))
            } else if prof(ab.a) > 0, prof(ab.b) > 0, abs(u.dot(d)) > 0.5 {
                let m = CGPoint.media(ab.a, ab.b)
                // Ignora a própria parede onde a abertura está.
                let naParede: (Parede2D) -> Bool = { Geometria.distancia(ponto: m, a: $0.a, b: $0.b) < 0.15 }
                if visivel(m, ignorando: naParede) {
                    let xa = ao(ab.a)
                    let xb = ao(ab.b)
                    let tipo: ElementoCorte.Tipo
                    switch ab.tipo {
                    case .porta: tipo = .portaVista
                    case .janela: tipo = .janelaVista
                    case .vao: tipo = .vaoVisto
                    }
                    elementos.append(ElementoCorte(tipo: tipo, x0: min(xa, xb), x1: max(xa, xb), y0: y0, y1: y1))
                }
            }
        }

        let xs = elementos.flatMap { [$0.x0, $0.x1] }
        return Secao2D(
            letra: corte.letra,
            elementos: elementos,
            xMin: xs.min() ?? 0,
            xMax: xs.max() ?? 1,
            alturaMax: elementos.map(\.y1).max() ?? 2.5
        )
    }
}

/// Desenha um corte num GraphicsContext.
struct SecaoRenderer {
    var secao: Secao2D
    /// Pontos por metro.
    var escala: CGFloat
    /// Canto inferior esquerdo do desenho (nível do piso, início do corte).
    var origem: CGPoint
    var escalaTexto: CGFloat = 0.8

    private func p(_ x: Double, _ y: Double) -> CGPoint {
        CGPoint(x: origem.x + CGFloat(x - secao.xMin) * escala, y: origem.y - CGFloat(y) * escala)
    }

    private func retangulo(_ e: ElementoCorte) -> Path {
        let a = p(e.x0, e.y1)
        let b = p(e.x1, e.y0)
        return Path(CGRect(x: a.x, y: a.y, width: b.x - a.x, height: b.y - a.y))
    }

    private func texto(_ s: String, _ tamanho: CGFloat = 8, peso: Font.Weight = .regular) -> Text {
        Text(s).font(.system(size: tamanho * escalaTexto, weight: peso)).foregroundStyle(Color.black)
    }

    func desenhar(_ ctx: GraphicsContext) {
        let fina = Color(white: 0.45)

        // Elementos vistos (ao fundo), em linha fina.
        for e in secao.elementos {
            switch e.tipo {
            case .paredeVista:
                ctx.stroke(retangulo(e), with: .color(fina), lineWidth: 0.5)
            case .portaVista, .vaoVisto:
                ctx.fill(retangulo(e), with: .color(.white))
                ctx.stroke(retangulo(e), with: .color(fina), lineWidth: 0.6)
            case .janelaVista:
                ctx.fill(retangulo(e), with: .color(.white))
                ctx.stroke(retangulo(e), with: .color(fina), lineWidth: 0.6)
                var meio = Path()
                meio.move(to: p((e.x0 + e.x1) / 2, e.y0))
                meio.addLine(to: p((e.x0 + e.x1) / 2, e.y1))
                ctx.stroke(meio, with: .color(fina), lineWidth: 0.4)
            default:
                break
            }
        }

        // Piso.
        var piso = Path()
        piso.move(to: p(secao.xMin - 0.3, 0))
        piso.addLine(to: p(secao.xMax + 0.3, 0))
        ctx.stroke(piso, with: .color(.black), lineWidth: 1.8)

        // Paredes cortadas (preenchidas).
        let cortadas = secao.elementos.filter { $0.tipo == .paredeCortada }
        for e in cortadas {
            ctx.fill(retangulo(e), with: .color(.black))
        }

        // Laje/forro: linha no topo das paredes cortadas.
        if let xi = cortadas.map(\.x0).min(), let xf = cortadas.map(\.x1).max() {
            let topo = cortadas.map(\.y1).max() ?? secao.alturaMax
            var forro = Path()
            forro.move(to: p(xi, topo))
            forro.addLine(to: p(xf, topo))
            ctx.stroke(forro, with: .color(.black), lineWidth: 1.4)

            // Cota do pé-direito à esquerda.
            let xCota = xi - 0.45
            var cota = Path()
            cota.move(to: p(xCota, 0))
            cota.addLine(to: p(xCota, topo))
            cota.move(to: p(xCota - 0.08, 0))
            cota.addLine(to: p(xCota + 0.08, 0))
            cota.move(to: p(xCota - 0.08, topo))
            cota.addLine(to: p(xCota + 0.08, topo))
            ctx.stroke(cota, with: .color(.black), lineWidth: 0.5)
            var g = ctx
            let meio = p(xCota - 0.15, topo / 2)
            g.translateBy(x: meio.x, y: meio.y)
            g.rotate(by: .degrees(-90))
            g.draw(texto("PD \(Formato.numero(topo))"), at: .zero)

            ctx.draw(texto("±0,00"), at: p(xi - 0.45, -0.18))
        }

        // Aberturas cortadas: recortam a parede.
        for e in secao.elementos {
            switch e.tipo {
            case .portaCortada, .vaoCortado:
                ctx.fill(retangulo(e), with: .color(.white))
                var batentes = Path()
                batentes.move(to: p(e.x0, e.y1))
                batentes.addLine(to: p(e.x1, e.y1))
                ctx.stroke(batentes, with: .color(.black), lineWidth: 0.8)
                ctx.draw(texto("h \(Formato.numero(e.y1 - e.y0))", 7), at: p((e.x0 + e.x1) / 2, e.y1 + 0.12))
            case .janelaCortada:
                ctx.fill(retangulo(e), with: .color(.white))
                ctx.stroke(retangulo(e), with: .color(.black), lineWidth: 0.6)
                var vidro = Path()
                vidro.move(to: p((e.x0 + e.x1) / 2, e.y0))
                vidro.addLine(to: p((e.x0 + e.x1) / 2, e.y1))
                ctx.stroke(vidro, with: .color(.black), lineWidth: 0.6)
                ctx.draw(texto("peitoril \(Formato.numero(e.y0))", 7), at: p(e.x1 + 0.35, e.y0 / 2))
            default:
                break
            }
        }
    }
}
