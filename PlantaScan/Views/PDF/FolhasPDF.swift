import SwiftUI

/// A4 paisagem em pontos.
enum FolhaA4 {
    static let largura: CGFloat = 842
    static let altura: CGFloat = 595
    static let margem: CGFloat = 20
    static let lateral: CGFloat = 190

    /// Área útil do desenho (à esquerda da coluna lateral).
    static var areaDesenho: CGSize {
        CGSize(width: largura - 2 * margem - lateral, height: altura - 2 * margem)
    }

    /// Escalas usuais de arquitetura.
    static let escalas: [Int] = [20, 25, 50, 75, 100, 125, 150, 200, 250, 500, 1000]

    /// Pontos por metro numa escala 1:n.
    static func pontosPorMetro(_ n: Int) -> CGFloat {
        72 / 0.0254 / CGFloat(n)
    }

    /// Menor escala (mais detalhada) em que o tamanho em metros cabe na área.
    static func escala(para metros: CGSize, em area: CGSize) -> Int {
        for n in escalas {
            let ppm = pontosPorMetro(n)
            if metros.width * ppm <= area.width && metros.height * ppm <= area.height {
                return n
            }
        }
        return escalas.last ?? 1000
    }
}

struct InfoProjeto {
    var nome: String
    var endereco: String
    var eircode: String?
    var data: Date
}

// MARK: - Moldura com coluna lateral e carimbo

struct FolhaPDF<Desenho: View, Lateral: View>: View {
    let titulo: String
    let escala: String?
    let folha: Int
    let totalFolhas: Int
    let info: InfoProjeto
    @ViewBuilder let desenho: () -> Desenho
    @ViewBuilder let lateral: () -> Lateral

    var body: some View {
        HStack(spacing: 0) {
            desenho()
                .frame(width: FolhaA4.areaDesenho.width, height: FolhaA4.areaDesenho.height)
                .clipped()
            Rectangle().fill(Color.black).frame(width: 0.8)
            VStack(alignment: .leading, spacing: 10) {
                lateral()
                Spacer(minLength: 0)
                Carimbo(titulo: titulo, escala: escala, folha: folha, totalFolhas: totalFolhas, info: info)
            }
            .padding(8)
            .frame(width: FolhaA4.lateral - 0.8)
        }
        .frame(width: FolhaA4.largura - 2 * FolhaA4.margem, height: FolhaA4.altura - 2 * FolhaA4.margem)
        .border(Color.black, width: 1.2)
        .padding(FolhaA4.margem)
        .frame(width: FolhaA4.largura, height: FolhaA4.altura)
        .background(Color.white)
        .foregroundStyle(Color.black)
        .environment(\.colorScheme, .light)
    }
}

struct Carimbo: View {
    let titulo: String
    let escala: String?
    let folha: Int
    let totalFolhas: Int
    let info: InfoProjeto

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            linha {
                VStack(alignment: .leading, spacing: 1) {
                    Text("PLANTASCAN").font(.system(size: 9, weight: .heavy)).tracking(1)
                    Text("Levantamento por LiDAR").font(.system(size: 6))
                }
            }
            linha {
                campo("IMÓVEL") {
                    Text(info.nome).font(.system(size: 9, weight: .bold)).lineLimit(2)
                }
            }
            linha {
                campo("ENDEREÇO") {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(info.endereco.isEmpty ? "—" : info.endereco).font(.system(size: 7)).lineLimit(3)
                        if let e = info.eircode, !e.isEmpty {
                            Text("Eircode: \(e)").font(.system(size: 7, weight: .semibold))
                        }
                    }
                }
            }
            linha {
                campo("DESENHO") {
                    Text(titulo).font(.system(size: 8, weight: .bold))
                }
            }
            HStack(spacing: 0) {
                linha { campo("ESCALA") { Text(escala ?? "Indicada").font(.system(size: 8, weight: .semibold)) } }
                Rectangle().fill(Color.black).frame(width: 0.6)
                linha { campo("DATA") { Text(info.data.formatted(date: .numeric, time: .omitted)).font(.system(size: 8)) } }
            }
            .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 0) {
                linha { campo("FOLHA") { Text("\(folha)/\(totalFolhas)").font(.system(size: 8, weight: .semibold)) } }
                Rectangle().fill(Color.black).frame(width: 0.6)
                linha { campo("UNIDADE") { Text("metros").font(.system(size: 8)) } }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .border(Color.black, width: 0.8)
    }

    private func linha<C: View>(@ViewBuilder _ c: () -> C) -> some View {
        c()
            .padding(4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .bottom) { Rectangle().fill(Color.black).frame(height: 0.6) }
    }

    private func campo<C: View>(_ rotulo: String, @ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(rotulo).font(.system(size: 5.5, weight: .semibold)).foregroundStyle(Color(white: 0.35))
            c()
        }
    }
}

// MARK: - Legenda, norte e escala gráfica

struct LegendaPDF: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("LEGENDA").font(.system(size: 7, weight: .bold))
            item("Parede") { ctx, s in
                var p = Path(); p.move(to: CGPoint(x: 2, y: s.height / 2)); p.addLine(to: CGPoint(x: s.width - 2, y: s.height / 2))
                ctx.stroke(p, with: .color(.black), lineWidth: 4)
            }
            item("Porta de abrir") { ctx, s in
                var p = Path()
                p.move(to: CGPoint(x: 4, y: s.height - 2)); p.addLine(to: CGPoint(x: 4, y: 2))
                ctx.stroke(p, with: .color(.black), lineWidth: 1.2)
                var arco = Path()
                arco.addArc(center: CGPoint(x: 4, y: s.height - 2), radius: s.height - 4,
                            startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
                ctx.stroke(arco, with: .color(.black), lineWidth: 0.5)
            }
            item("Janela") { ctx, s in
                for dy in [-2.5, 0, 2.5] as [CGFloat] {
                    var p = Path(); p.move(to: CGPoint(x: 2, y: s.height / 2 + dy)); p.addLine(to: CGPoint(x: s.width - 2, y: s.height / 2 + dy))
                    ctx.stroke(p, with: .color(.black), lineWidth: 0.6)
                }
            }
            item("Vão (sem porta)") { ctx, s in
                var p = Path(); p.move(to: CGPoint(x: 2, y: s.height / 2)); p.addLine(to: CGPoint(x: s.width - 2, y: s.height / 2))
                ctx.stroke(p, with: .color(.black), style: StrokeStyle(lineWidth: 0.6, dash: [2, 2]))
            }
            item("Mobiliário") { ctx, s in
                let r = Path(CGRect(x: 4, y: 2, width: s.width - 8, height: s.height - 4))
                ctx.fill(r, with: .color(Color(white: 0.95)))
                ctx.stroke(r, with: .color(Color(white: 0.4)), lineWidth: 0.6)
            }
            item("Linha de corte") { ctx, s in
                var p = Path(); p.move(to: CGPoint(x: 2, y: s.height / 2)); p.addLine(to: CGPoint(x: s.width - 2, y: s.height / 2))
                ctx.stroke(p, with: .color(.black), style: StrokeStyle(lineWidth: 0.7, dash: [5, 2, 1, 2]))
            }
            Text("P = porta · J = janela · V = vão\nPD = pé-direito · cotas em metros")
                .font(.system(size: 6))
                .foregroundStyle(Color(white: 0.3))
        }
    }

    private func item(_ nome: String, _ desenho: @escaping (GraphicsContext, CGSize) -> Void) -> some View {
        HStack(spacing: 6) {
            Canvas { ctx, size in desenho(ctx, size) }
                .frame(width: 30, height: 14)
            Text(nome).font(.system(size: 7))
        }
    }
}

struct NorteEscalaPDF: View {
    let norte: Double?
    let escala: Int

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            if let norte {
                VStack(spacing: 2) {
                    ZStack {
                        Circle().stroke(Color.black, lineWidth: 0.6)
                        Image(systemName: "location.north.fill")
                            .font(.system(size: 16))
                            .rotationEffect(.radians(norte + .pi / 2))
                    }
                    .frame(width: 32, height: 32)
                    Text("NORTE").font(.system(size: 5.5, weight: .semibold))
                }
            }
            EscalaGraficaPDF(escala: escala)
        }
    }
}

struct EscalaGraficaPDF: View {
    let escala: Int

    private var passo: Double {
        let ppm = FolhaA4.pontosPorMetro(escala)
        // Blocos de ~15–30 pt.
        for m in [0.1, 0.2, 0.25, 0.5, 1, 2, 5, 10] where CGFloat(m) * ppm >= 15 {
            return m
        }
        return 10
    }

    var body: some View {
        let ppm = FolhaA4.pontosPorMetro(escala)
        let bloco = CGFloat(passo) * ppm
        VStack(alignment: .leading, spacing: 2) {
            Canvas { ctx, size in
                for i in 0..<4 {
                    let r = CGRect(x: CGFloat(i) * bloco, y: 0, width: bloco, height: 4)
                    if i % 2 == 0 { ctx.fill(Path(r), with: .color(.black)) }
                    ctx.stroke(Path(r), with: .color(.black), lineWidth: 0.5)
                }
            }
            .frame(width: bloco * 4, height: 4)
            HStack(spacing: 0) {
                ForEach(0..<5, id: \.self) { i in
                    Text(Formato.numeroCurto(passo * Double(i)))
                        .font(.system(size: 5.5))
                        .frame(width: i < 4 ? bloco : nil, alignment: .leading)
                }
            }
            Text("ESC. 1:\(escala) (m)").font(.system(size: 6, weight: .semibold))
        }
    }
}

// MARK: - Planta

struct DesenhoPlantaPDF: View {
    let plano: FloorPlan2D
    let escala: Int
    let codigos: [UUID: String]
    let cortes: [Corte]
    let titulo: String

    var body: some View {
        Canvas { ctx, size in
            let ppm = FolhaA4.pontosPorMetro(escala)
            let t = PlanoTransform(
                escala: ppm,
                origem: CGPoint(x: plano.limites.midX, y: plano.limites.midY),
                centroTela: CGPoint(x: size.width / 2, y: size.height / 2 - 6)
            )
            FloorPlanRenderer(
                plano: plano, t: t, paleta: .impressao,
                mostrarAcessorios: false,
                escalaTexto: 0.72,
                codigos: codigos
            )
            .desenhar(ctx, tamanho: size)

            for corte in cortes {
                desenharCorte(ctx, corte: corte, t: t)
            }

            ctx.draw(
                Text(titulo).font(.system(size: 9, weight: .bold)).foregroundStyle(Color.black),
                at: CGPoint(x: 12, y: size.height - 12),
                anchor: .leading
            )
        }
    }

    private func desenharCorte(_ ctx: GraphicsContext, corte: Corte, t: PlanoTransform) {
        let a = t.tela(corte.inicio)
        let b = t.tela(corte.fim)
        var linha = Path()
        linha.move(to: a)
        linha.addLine(to: b)
        ctx.stroke(linha, with: .color(.black), style: StrokeStyle(lineWidth: 0.7, dash: [8, 3, 2, 3]))

        let r: CGFloat = 7
        for ponta in [a, b] {
            let circulo = Path(ellipseIn: CGRect(x: ponta.x - r, y: ponta.y - r, width: 2 * r, height: 2 * r))
            ctx.fill(circulo, with: .color(.white))
            ctx.stroke(circulo, with: .color(.black), lineWidth: 0.8)
            ctx.draw(Text(corte.letra).font(.system(size: 7, weight: .bold)).foregroundStyle(Color.black), at: ponta)
            // Seta indicando para onde o corte olha.
            let v = corte.vista
            let base = ponta + v * (r + 1)
            let perp = v.perpendicular
            var seta = Path()
            seta.move(to: base + v * 6)
            seta.addLine(to: base + perp * 4)
            seta.addLine(to: base - perp * 4)
            seta.closeSubpath()
            ctx.fill(seta, with: .color(.black))
        }
    }
}

// MARK: - Cortes

struct DesenhoCortesPDF: View {
    let secoes: [Secao2D]
    let escala: Int

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(secoes.enumerated()), id: \.offset) { i, s in
                Canvas { ctx, size in
                    let ppm = FolhaA4.pontosPorMetro(escala)
                    let largura = CGFloat(s.xMax - s.xMin) * ppm
                    let alturaDesenho = CGFloat(s.alturaMax) * ppm
                    let origem = CGPoint(
                        x: (size.width - largura) / 2,
                        y: (size.height + alturaDesenho) / 2 + 4
                    )
                    if s.vazia {
                        ctx.draw(Text("Corte sem elementos").font(.system(size: 8)).foregroundStyle(Color.gray),
                                 at: CGPoint(x: size.width / 2, y: size.height / 2))
                    } else {
                        SecaoRenderer(secao: s, escala: ppm, origem: origem).desenhar(ctx)
                    }
                    ctx.draw(
                        Text("CORTE \(s.letra)\(s.letra)   ESC. 1:\(escala)")
                            .font(.system(size: 9, weight: .bold)).foregroundStyle(Color.black),
                        at: CGPoint(x: 12, y: size.height - 12),
                        anchor: .leading
                    )
                }
                if i < secoes.count - 1 {
                    Rectangle().fill(Color(white: 0.7)).frame(height: 0.5)
                }
            }
        }
    }
}

// MARK: - Tabelas

struct ColunaTabela {
    var titulo: String
    var largura: CGFloat
    var alinhamento: Alignment = .leading
}

struct TabelaPDF: Identifiable {
    let id = UUID()
    var titulo: String?
    var colunas: [ColunaTabela]
    var linhas: [[String]]
    /// Linhas destacadas (totais).
    var negrito: Set<Int> = []
}

struct TabelasPDFView: View {
    let tabelas: [TabelaPDF]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(tabelas) { tabela in
                VStack(alignment: .leading, spacing: 0) {
                    if let titulo = tabela.titulo {
                        Text(titulo).font(.system(size: 9, weight: .bold)).padding(.bottom, 4)
                    }
                    linha(tabela.colunas.map(\.titulo), colunas: tabela.colunas, cabecalho: true, negrito: true)
                    ForEach(Array(tabela.linhas.enumerated()), id: \.offset) { i, valores in
                        linha(valores, colunas: tabela.colunas, cabecalho: false, negrito: tabela.negrito.contains(i))
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func linha(_ valores: [String], colunas: [ColunaTabela], cabecalho: Bool, negrito: Bool) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(colunas.enumerated()), id: \.offset) { i, col in
                Text(i < valores.count ? valores[i] : "")
                    .font(.system(size: cabecalho ? 6.5 : 7.5, weight: negrito ? .bold : .regular))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, 3)
                    .frame(width: col.largura, height: 14, alignment: col.alinhamento)
                    .overlay(alignment: .trailing) { Rectangle().fill(Color(white: 0.6)).frame(width: 0.4) }
            }
        }
        .background(cabecalho ? Color(white: 0.9) : Color.white)
        .overlay(alignment: .bottom) { Rectangle().fill(Color(white: 0.6)).frame(height: 0.4) }
    }
}
