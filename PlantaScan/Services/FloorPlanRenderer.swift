import SwiftUI

/// Converte coordenadas do plano (metros) em coordenadas de tela (pontos).
struct PlanoTransform {
    var escala: CGFloat
    /// Ponto do plano que fica no centro da tela.
    var origem: CGPoint
    var centroTela: CGPoint

    func tela(_ p: CGPoint) -> CGPoint {
        CGPoint(x: (p.x - origem.x) * escala + centroTela.x, y: (p.y - origem.y) * escala + centroTela.y)
    }

    func plano(_ q: CGPoint) -> CGPoint {
        CGPoint(x: (q.x - centroTela.x) / escala + origem.x, y: (q.y - centroTela.y) / escala + origem.y)
    }

    /// Escala automática para caber no tamanho, com zoom e deslocamento do usuário.
    static func ajustar(_ limites: CGRect, em tamanho: CGSize, margem: CGFloat = 44, zoom: CGFloat = 1, deslocamento: CGSize = .zero) -> PlanoTransform {
        let w = max(limites.width, 0.5)
        let h = max(limites.height, 0.5)
        let disponivelW = max(tamanho.width - 2 * margem, 40)
        let disponivelH = max(tamanho.height - 2 * margem, 40)
        let base = min(disponivelW / w, disponivelH / h)
        return PlanoTransform(
            escala: base * zoom,
            origem: CGPoint(x: limites.midX, y: limites.midY),
            centroTela: CGPoint(x: tamanho.width / 2 + deslocamento.width, y: tamanho.height / 2 + deslocamento.height)
        )
    }
}

struct PaletaPlano {
    var fundo: Color
    var parede: Color
    var piso: Color
    var objeto: Color
    var objetoFundo: Color
    var janela: Color
    var cota: Color
    var texto: Color
    var destaque: Color

    static let tela = PaletaPlano(
        fundo: Color(uiColor: .systemBackground),
        parede: Color(uiColor: .label),
        piso: Color.accentColor.opacity(0.08),
        objeto: Color(uiColor: .secondaryLabel),
        objetoFundo: Color(uiColor: .tertiarySystemFill),
        janela: Color(uiColor: .systemBlue),
        cota: Color(uiColor: .secondaryLabel),
        texto: Color(uiColor: .label),
        destaque: .orange
    )
}

/// Desenha a planta num GraphicsContext (Canvas na tela; o mesmo código servirá para PDF/PNG).
struct FloorPlanRenderer {
    var plano: FloorPlan2D
    var t: PlanoTransform
    var paleta: PaletaPlano = .tela
    var selecionado: UUID? = nil
    var titulo: String? = nil
    var mostrarCotas = true
    var mostrarAcessorios = true
    var mostrarArea = true
    var mostrarNomeComodo = true
    var mostrarNomesObjetos = true
    /// Direção do norte verdadeiro no plano (radianos); nil = não medido (a bússola não é desenhada).
    var anguloNorte: Double? = nil

    private var larguraParede: CGFloat {
        max(CGFloat(FloorPlanBuilder.espessuraPadrao) * t.escala, 3)
    }

    func desenhar(_ ctx: GraphicsContext, tamanho: CGSize) {
        desenharPisos(ctx)
        desenharObjetos(ctx)
        desenharParedes(ctx)
        desenharAberturas(ctx)
        if mostrarCotas { desenharCotas(ctx) }
        if mostrarArea || mostrarNomeComodo { desenharRotuloArea(ctx) }
        if mostrarAcessorios {
            desenharBussola(ctx, tamanho: tamanho)
            desenharEscala(ctx, tamanho: tamanho)
        }
    }

    // MARK: Auxiliares

    private func linha(_ a: CGPoint, _ b: CGPoint) -> Path {
        var p = Path()
        p.move(to: a)
        p.addLine(to: b)
        return p
    }

    private func poligono(_ pts: [CGPoint]) -> Path {
        var p = Path()
        guard let primeiro = pts.first else { return p }
        p.move(to: primeiro)
        for q in pts.dropFirst() { p.addLine(to: q) }
        p.closeSubpath()
        return p
    }

    // MARK: Camadas

    private func desenharPisos(_ ctx: GraphicsContext) {
        for piso in plano.pisos {
            ctx.fill(poligono(piso.map { t.tela($0) }), with: .color(paleta.piso))
        }
    }

    private func desenharObjetos(_ ctx: GraphicsContext) {
        for o in plano.objetos {
            let pts = o.cantos.map { t.tela($0) }
            let path = poligono(pts)
            let sel = o.id == selecionado
            ctx.fill(path, with: .color(sel ? paleta.destaque.opacity(0.25) : paleta.objetoFundo))
            ctx.stroke(path, with: .color(sel ? paleta.destaque : paleta.objeto), lineWidth: sel ? 2 : 1)
            guard mostrarNomesObjetos, pts.count == 4 else { continue }
            let lado = min(pts[0].distancia(pts[1]), pts[1].distancia(pts[2]))
            if lado > 26 {
                let fonte = min(max(lado / 5, 8), 12)
                ctx.draw(
                    Text(o.nome).font(.system(size: fonte)).foregroundStyle(paleta.objeto),
                    at: t.tela(o.centro)
                )
            }
        }
    }

    private func desenharParedes(_ ctx: GraphicsContext) {
        for p in plano.paredes {
            let sel = p.id == selecionado
            ctx.stroke(
                linha(t.tela(p.a), t.tela(p.b)),
                with: .color(sel ? paleta.destaque : paleta.parede),
                style: StrokeStyle(lineWidth: larguraParede, lineCap: .square)
            )
        }
    }

    private func desenharAberturas(_ ctx: GraphicsContext) {
        let h = larguraParede / 2
        for ab in plano.aberturas {
            var a = t.tela(ab.a)
            var b = t.tela(ab.b)
            if ab.dobradicaNoFim { swap(&a, &b) }
            let n = ab.ladoInterno
            let sel = ab.id == selecionado
            let cor: Color = sel ? paleta.destaque : paleta.parede

            // Abre o vão na parede.
            ctx.stroke(linha(a, b), with: .color(paleta.fundo), style: StrokeStyle(lineWidth: larguraParede + 2, lineCap: .butt))
            // Batentes.
            ctx.stroke(linha(a - n * h, a + n * h), with: .color(cor), lineWidth: 1.5)
            ctx.stroke(linha(b - n * h, b + n * h), with: .color(cor), lineWidth: 1.5)

            switch ab.tipo {
            case .vao:
                ctx.stroke(linha(a, b), with: .color(cor.opacity(0.6)), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            case .janela:
                desenharJanela(ctx, ab, a: a, b: b, n: n, h: h, cor: cor, corVidro: sel ? paleta.destaque : paleta.janela)
            case .porta:
                desenharPorta(ctx, ab, a: a, b: b, n: n, h: h, cor: cor)
            }
        }
    }

    private func desenharJanela(_ ctx: GraphicsContext, _ ab: Abertura2D, a: CGPoint, b: CGPoint, n: CGVector, h: CGFloat, cor: Color, corVidro: Color) {
        // Faces da parede.
        ctx.stroke(linha(a + n * h, b + n * h), with: .color(cor), lineWidth: 1)
        ctx.stroke(linha(a - n * h, b - n * h), with: .color(cor), lineWidth: 1)

        let u = (b - a).normalizado
        let w = a.distancia(b)
        let meio = CGPoint.media(a, b)

        switch ab.modeloJanela {
        case .correr:
            let sobre = w * 0.06
            let o = h * 0.35
            ctx.stroke(linha(a + n * o, meio + u * sobre + n * o), with: .color(corVidro), lineWidth: 2)
            ctx.stroke(linha(meio - u * sobre - n * o, b - n * o), with: .color(corVidro), lineWidth: 2)
        case .fixa:
            ctx.stroke(linha(a, b), with: .color(corVidro), lineWidth: 2)
        case .basculante, .maximAr:
            let o = h * 0.3
            ctx.stroke(linha(a + n * o, b + n * o), with: .color(corVidro), lineWidth: 1.2)
            ctx.stroke(linha(a - n * o, b - n * o), with: .color(corVidro), lineWidth: 1.2)
            // Projeção da folha: basculante para dentro, maxim-ar para fora.
            let lado: CGFloat = ab.modeloJanela == .basculante ? 1 : -1
            let base = n * (lado * h)
            let ponta = meio + n * (lado * (h + w * 0.18))
            var p = Path()
            p.move(to: a + base)
            p.addLine(to: ponta)
            p.addLine(to: b + base)
            ctx.stroke(p, with: .color(corVidro), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
        }
    }

    private func desenharPorta(_ ctx: GraphicsContext, _ ab: Abertura2D, a: CGPoint, b: CGPoint, n: CGVector, h: CGFloat, cor: Color) {
        let u = (b - a).normalizado
        let w = a.distancia(b)
        let meio = CGPoint.media(a, b)

        switch ab.modeloPorta {
        case .giro:
            folhaEArco(ctx, dobradica: a, fim: b, n: n, raio: w, cor: cor)
        case .dupla:
            folhaEArco(ctx, dobradica: a, fim: meio, n: n, raio: w / 2, cor: cor)
            folhaEArco(ctx, dobradica: b, fim: meio, n: n, raio: w / 2, cor: cor)
        case .correr:
            let sobre = w * 0.08
            let o = h * 0.45
            ctx.stroke(linha(a + n * o, meio + u * sobre + n * o), with: .color(cor), lineWidth: 3)
            ctx.stroke(linha(meio - u * sobre - n * o, b - n * o), with: .color(cor), lineWidth: 3)
        case .sanfonada:
            let partes = 6
            let amplitude = w / 7
            var p = Path()
            p.move(to: a)
            for i in 1...partes {
                let f = CGFloat(i) / CGFloat(partes)
                let base = a + u * (w * f)
                p.addLine(to: i % 2 == 1 ? base + n * amplitude : base)
            }
            ctx.stroke(p, with: .color(cor), lineWidth: 1.5)
        }
    }

    private func folhaEArco(_ ctx: GraphicsContext, dobradica d: CGPoint, fim: CGPoint, n: CGVector, raio r: CGFloat, cor: Color) {
        ctx.stroke(linha(d, d + n * r), with: .color(cor), lineWidth: 2)
        let a0 = n.angulo
        var delta = (fim - d).angulo - a0
        while delta > .pi { delta -= 2 * .pi }
        while delta < -.pi { delta += 2 * .pi }
        var arco = Path()
        let passos = 24
        for i in 0...passos {
            let ang = a0 + delta * CGFloat(i) / CGFloat(passos)
            let pt = CGPoint(x: d.x + cos(ang) * r, y: d.y + sin(ang) * r)
            if i == 0 { arco.move(to: pt) } else { arco.addLine(to: pt) }
        }
        ctx.stroke(arco, with: .color(cor.opacity(0.7)), lineWidth: 1)
    }

    private func desenharCotas(_ ctx: GraphicsContext) {
        let centroTela = t.tela(plano.centro)
        for p in plano.paredes {
            let a = t.tela(p.a)
            let b = t.tela(p.b)
            guard a.distancia(b) > 30 else { continue }
            let u = (b - a).normalizado
            var n = u.perpendicular
            let meio = CGPoint.media(a, b)
            if (meio - centroTela).dot(n) < 0 { n = -n }

            let off = larguraParede / 2 + 10
            let a2 = a + n * off
            let b2 = b + n * off
            var cota = linha(a2, b2)
            cota.addPath(linha(a2 - n * 4, a2 + n * 4))
            cota.addPath(linha(b2 - n * 4, b2 + n * 4))
            ctx.stroke(cota, with: .color(paleta.cota), lineWidth: 0.8)

            var ang = u.angulo
            if ang > .pi / 2 { ang -= .pi } else if ang < -.pi / 2 { ang += .pi }
            let pos = CGPoint.media(a2, b2) + n * 9
            var c = ctx
            c.translateBy(x: pos.x, y: pos.y)
            c.rotate(by: .radians(Double(ang)))
            c.draw(
                Text(Formato.metros(p.dimensoes.largura))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(paleta.cota),
                at: .zero
            )
        }
    }

    private func desenharRotuloArea(_ ctx: GraphicsContext) {
        guard plano.area > 0 else { return }
        let c = t.tela(plano.centroRotulo)
        let nome = mostrarNomeComodo ? (titulo ?? "") : ""
        let area = Text(Formato.area(plano.area)).font(.system(size: 12)).foregroundStyle(paleta.cota)
        let textoNome = Text(nome).font(.system(size: 14, weight: .semibold)).foregroundStyle(paleta.texto)
        switch (nome.isEmpty, mostrarArea) {
        case (false, true):
            ctx.draw(textoNome, at: CGPoint(x: c.x, y: c.y - 9))
            ctx.draw(area, at: CGPoint(x: c.x, y: c.y + 9))
        case (false, false):
            ctx.draw(textoNome, at: c)
        case (true, true):
            ctx.draw(area, at: c)
        case (true, false):
            break
        }
    }

    private func desenharBussola(_ ctx: GraphicsContext, tamanho: CGSize) {
        guard let norte = anguloNorte else { return }
        let c = CGPoint(x: tamanho.width - 32, y: 44)
        let r: CGFloat = 15
        ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)), with: .color(paleta.cota), lineWidth: 1)

        // A seta é desenhada apontando para cima (−π/2) e girada até o norte.
        var g = ctx
        g.translateBy(x: c.x, y: c.y)
        g.rotate(by: .radians(norte + .pi / 2))
        var seta = Path()
        seta.move(to: CGPoint(x: 0, y: -r + 3))
        seta.addLine(to: CGPoint(x: 5, y: 6))
        seta.addLine(to: CGPoint(x: 0, y: 2))
        seta.addLine(to: CGPoint(x: -5, y: 6))
        seta.closeSubpath()
        g.fill(seta, with: .color(paleta.texto))

        let pontaN = CGPoint(x: cos(norte) * (r + 9), y: sin(norte) * (r + 9))
        ctx.draw(
            Text("N").font(.system(size: 10, weight: .bold)).foregroundStyle(paleta.texto),
            at: CGPoint(x: c.x + pontaN.x, y: c.y + pontaN.y)
        )
    }

    private func desenharEscala(_ ctx: GraphicsContext, tamanho: CGSize) {
        let opcoes: [Double] = [0.1, 0.2, 0.25, 0.5, 1, 2, 5, 10, 20, 50]
        let alvo = 100 / Double(t.escala)
        let metros = opcoes.min { abs($0 - alvo) < abs($1 - alvo) } ?? 1
        let comp = CGFloat(metros) * t.escala
        let x0: CGFloat = 16
        let y: CGFloat = tamanho.height - 22
        var p = Path()
        p.move(to: CGPoint(x: x0, y: y - 5))
        p.addLine(to: CGPoint(x: x0, y: y))
        p.addLine(to: CGPoint(x: x0 + comp, y: y))
        p.addLine(to: CGPoint(x: x0 + comp, y: y - 5))
        ctx.stroke(p, with: .color(paleta.texto), lineWidth: 1.5)
        let rotulo = metros < 1 ? "\(Int((metros * 100).rounded())) cm" : "\(Formato.numeroCurto(metros)) m"
        ctx.draw(
            Text(rotulo).font(.system(size: 11, weight: .medium)).foregroundStyle(paleta.texto),
            at: CGPoint(x: x0 + comp / 2, y: y - 12)
        )
    }
}
