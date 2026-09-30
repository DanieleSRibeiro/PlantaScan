import SwiftUI
import UIKit

/// Gera o PDF do imóvel (A4 paisagem): plantas por andar em escala, cortes AA/BB e quadros.
@MainActor
enum PDFExporter {
    struct Opcoes {
        var incluirCortes = true
        var incluirQuadros = true
        var mostrarMobiliario = true
    }

    static func gerarPDF(imovel: Imovel, montagens: [MontagemAndar], opcoes: Opcoes = Opcoes()) throws -> URL {
        let info = InfoProjeto(nome: imovel.nome, endereco: imovel.endereco, eircode: imovel.eircode, data: Date())
        let codigos = codigosEsquadrias(montagens)

        // Monta a lista de folhas primeiro para saber o total.
        var folhas: [(Int, Int) -> AnyView] = []

        for m in montagens where !m.plano.vazio {
            var plano = m.plano
            if !opcoes.mostrarMobiliario { plano.objetos = [] }
            let cortes = opcoes.incluirCortes ? SecaoBuilder.cortes(para: plano) : []
            let area = FolhaA4.areaDesenho
            let util = CGSize(width: area.width - 90, height: area.height - 90)
            let escala = FolhaA4.escala(
                para: CGSize(width: plano.limites.width + 1.6, height: plano.limites.height + 1.6),
                em: util
            )
            let tituloPlanta = "PLANTA BAIXA — \(Formato.andar(m.andar).uppercased())"

            folhas.append { folha, total in
                AnyView(FolhaPDF(
                    titulo: tituloPlanta,
                    escala: "1:\(escala)",
                    folha: folha, totalFolhas: total, info: info,
                    desenho: {
                        DesenhoPlantaPDF(
                            plano: plano, escala: escala, codigos: codigos, cortes: cortes,
                            titulo: "\(tituloPlanta)   ESC. 1:\(escala)"
                        )
                    },
                    lateral: {
                        VStack(alignment: .leading, spacing: 12) {
                            LegendaPDF()
                            NorteEscalaPDF(norte: m.norte, escala: escala)
                            resumoAndar(m)
                            if m.separados {
                                Text("Obs.: há cômodos escaneados em sessões separadas, dispostos lado a lado sem a posição real.")
                                    .font(.system(size: 6))
                                    .foregroundStyle(Color(white: 0.3))
                            }
                        }
                    }
                ))
            }

            if opcoes.incluirCortes {
                let secoes = cortes.map { SecaoBuilder.secao(plano, corte: $0) }
                let meiaAltura = FolhaA4.areaDesenho.height / 2 - 40
                let larguraUtil = FolhaA4.areaDesenho.width - 90
                let maiorLargura = secoes.map { $0.xMax - $0.xMin }.max() ?? 1
                let maiorAltura = secoes.map(\.alturaMax).max() ?? 2.5
                let escalaCortes = FolhaA4.escala(
                    para: CGSize(width: maiorLargura + 1.2, height: maiorAltura + 0.6),
                    em: CGSize(width: larguraUtil, height: meiaAltura)
                )
                let tituloCortes = "CORTES AA E BB — \(Formato.andar(m.andar).uppercased())"
                folhas.append { folha, total in
                    AnyView(FolhaPDF(
                        titulo: tituloCortes,
                        escala: "1:\(escalaCortes)",
                        folha: folha, totalFolhas: total, info: info,
                        desenho: { DesenhoCortesPDF(secoes: secoes, escala: escalaCortes) },
                        lateral: {
                            VStack(alignment: .leading, spacing: 10) {
                                EscalaGraficaPDF(escala: escalaCortes)
                                Text("Cortes esquemáticos gerados a partir do scan. Espessuras de laje e piso não são medidas pelo LiDAR; alturas de paredes, portas e janelas são medidas.")
                                    .font(.system(size: 6))
                                    .foregroundStyle(Color(white: 0.3))
                            }
                        }
                    ))
                }
            }
        }

        if opcoes.incluirQuadros {
            for grupo in paginarTabelas(tabelas(imovel: imovel, montagens: montagens, codigos: codigos, mobiliario: opcoes.mostrarMobiliario)) {
                folhas.append { folha, total in
                    AnyView(FolhaPDF(
                        titulo: "QUADROS DE ÁREAS E ESQUADRIAS",
                        escala: nil,
                        folha: folha, totalFolhas: total, info: info,
                        desenho: { TabelasPDFView(tabelas: grupo) },
                        lateral: { EmptyView() }
                    ))
                }
            }
        }

        guard !folhas.isEmpty else { throw CocoaError(.fileWriteUnknown) }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(nomeArquivo(imovel.nome)) - Planta.pdf")
        try? FileManager.default.removeItem(at: url)

        var caixa = CGRect(x: 0, y: 0, width: FolhaA4.largura, height: FolhaA4.altura)
        let metadados: [String: Any] = [
            kCGPDFContextTitle as String: "\(imovel.nome) — Planta baixa",
            kCGPDFContextCreator as String: "PlantaScan",
        ]
        guard let ctx = CGContext(url as CFURL, mediaBox: &caixa, metadados as CFDictionary) else {
            throw CocoaError(.fileWriteUnknown)
        }
        for (i, folha) in folhas.enumerated() {
            let conteudo = folha(i + 1, folhas.count)
            let renderer = ImageRenderer(content: conteudo)
            renderer.proposedSize = ProposedViewSize(width: FolhaA4.largura, height: FolhaA4.altura)
            renderer.render { _, desenhar in
                ctx.beginPDFPage(nil)
                desenhar(ctx)
                ctx.endPDFPage()
            }
        }
        ctx.closePDF()
        return url
    }

    /// PNG da folha da planta de um andar (alta resolução).
    static func gerarPNG(imovel: Imovel, montagem m: MontagemAndar) throws -> URL {
        let info = InfoProjeto(nome: imovel.nome, endereco: imovel.endereco, eircode: imovel.eircode, data: Date())
        let area = FolhaA4.areaDesenho
        let escala = FolhaA4.escala(
            para: CGSize(width: m.plano.limites.width + 1.6, height: m.plano.limites.height + 1.6),
            em: CGSize(width: area.width - 90, height: area.height - 90)
        )
        let titulo = "PLANTA BAIXA — \(Formato.andar(m.andar).uppercased())"
        let folha = FolhaPDF(
            titulo: titulo, escala: "1:\(escala)", folha: 1, totalFolhas: 1, info: info,
            desenho: {
                DesenhoPlantaPDF(plano: m.plano, escala: escala, codigos: codigosEsquadrias([m]), cortes: [],
                                 titulo: "\(titulo)   ESC. 1:\(escala)")
            },
            lateral: {
                VStack(alignment: .leading, spacing: 12) {
                    LegendaPDF()
                    NorteEscalaPDF(norte: m.norte, escala: escala)
                    resumoAndar(m)
                }
            }
        )
        let renderer = ImageRenderer(content: folha)
        renderer.scale = 3
        guard let dados = renderer.uiImage?.pngData() else { throw CocoaError(.fileWriteUnknown) }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(nomeArquivo(imovel.nome)) - \(Formato.andar(m.andar)).png")
        try dados.write(to: url, options: .atomic)
        return url
    }

    // MARK: Conteúdo

    private static func resumoAndar(_ m: MontagemAndar) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("ÁREAS").font(.system(size: 7, weight: .bold))
            ForEach(m.comodos) { c in
                HStack {
                    Text(c.nome).lineLimit(1)
                    Spacer()
                    Text(Formato.area(m.planosPorComodo[c.id]?.area ?? c.area ?? 0))
                }
                .font(.system(size: 6.5))
            }
            Rectangle().fill(Color.black).frame(height: 0.5)
            HStack {
                Text("Total do andar")
                Spacer()
                Text(Formato.area(m.plano.area))
            }
            .font(.system(size: 7, weight: .bold))
        }
    }

    /// P1, P2… para portas, J1… para janelas, V1… para vãos, na ordem dos andares.
    static func codigosEsquadrias(_ montagens: [MontagemAndar]) -> [UUID: String] {
        var codigos: [UUID: String] = [:]
        var contadores: [TipoAbertura: Int] = [:]
        for m in montagens {
            for c in m.comodos {
                for ab in m.planosPorComodo[c.id]?.aberturas ?? [] {
                    let n = (contadores[ab.tipo] ?? 0) + 1
                    contadores[ab.tipo] = n
                    let prefixo: String
                    switch ab.tipo {
                    case .porta: prefixo = "P"
                    case .janela: prefixo = "J"
                    case .vao: prefixo = "V"
                    }
                    codigos[ab.id] = "\(prefixo)\(n)"
                }
            }
        }
        return codigos
    }

    private static func tabelas(imovel: Imovel, montagens: [MontagemAndar], codigos: [UUID: String], mobiliario: Bool) -> [TabelaPDF] {
        var resultado: [TabelaPDF] = []

        // Quadro de áreas.
        var linhas: [[String]] = []
        var negrito: Set<Int> = []
        var total = 0.0
        for m in montagens {
            var subtotal = 0.0
            for c in m.comodos {
                let p = m.planosPorComodo[c.id]
                let area = p?.area ?? c.area ?? 0
                subtotal += area
                linhas.append([
                    Formato.andar(m.andar),
                    c.nome,
                    (c.tipo ?? .outro).nome,
                    Formato.numero(area),
                    Formato.numero(p?.perimetro ?? 0),
                    Formato.numero(p?.peDireito ?? 0),
                    "\(p?.contar(.porta) ?? 0)",
                    "\(p?.contar(.janela) ?? 0)",
                ])
            }
            negrito.insert(linhas.count)
            linhas.append(["", "Subtotal \(Formato.andar(m.andar))", "", Formato.numero(subtotal), "", "", "", ""])
            total += subtotal
        }
        negrito.insert(linhas.count)
        linhas.append(["", "TOTAL DO IMÓVEL", Formato.contagem(montagens.flatMap(\.comodos)), Formato.numero(total), "", "", "", ""])

        resultado.append(TabelaPDF(
            titulo: "QUADRO DE ÁREAS",
            colunas: [
                ColunaTabela(titulo: "ANDAR", largura: 62),
                ColunaTabela(titulo: "CÔMODO", largura: 130),
                ColunaTabela(titulo: "TIPO", largura: 110),
                ColunaTabela(titulo: "ÁREA (m²)", largura: 60, alinhamento: .trailing),
                ColunaTabela(titulo: "PERÍM. (m)", largura: 60, alinhamento: .trailing),
                ColunaTabela(titulo: "PD (m)", largura: 50, alinhamento: .trailing),
                ColunaTabela(titulo: "PORTAS", largura: 50, alinhamento: .center),
                ColunaTabela(titulo: "JANELAS", largura: 50, alinhamento: .center),
            ],
            linhas: linhas,
            negrito: negrito
        ))

        // Quadro de esquadrias.
        var esquadrias: [[String]] = []
        for m in montagens {
            for c in m.comodos {
                guard let p = m.planosPorComodo[c.id] else { continue }
                for ab in p.aberturas {
                    let modelo: String
                    switch ab.tipo {
                    case .porta: modelo = "Porta \(ab.modeloPorta.nome.lowercased())"
                    case .janela: modelo = "Janela \(ab.modeloJanela.nome.lowercased())"
                    case .vao: modelo = "Vão"
                    }
                    let peitoril = ab.tipo == .janela ? Formato.numero(max(ab.yBase - p.nivelPiso, 0)) : "—"
                    esquadrias.append([
                        codigos[ab.id] ?? "",
                        modelo,
                        c.nome,
                        Formato.numero(ab.dimensoes.largura),
                        Formato.numero(ab.dimensoes.altura),
                        peitoril,
                    ])
                }
            }
        }
        if !esquadrias.isEmpty {
            resultado.append(TabelaPDF(
                titulo: "QUADRO DE ESQUADRIAS",
                colunas: [
                    ColunaTabela(titulo: "CÓD.", largura: 40, alinhamento: .center),
                    ColunaTabela(titulo: "TIPO / MODELO", largura: 150),
                    ColunaTabela(titulo: "CÔMODO", largura: 130),
                    ColunaTabela(titulo: "LARG. (m)", largura: 60, alinhamento: .trailing),
                    ColunaTabela(titulo: "ALT. (m)", largura: 60, alinhamento: .trailing),
                    ColunaTabela(titulo: "PEITORIL (m)", largura: 70, alinhamento: .trailing),
                ],
                linhas: esquadrias
            ))
        }

        // Mobiliário.
        if mobiliario {
            var moveis: [[String]] = []
            for m in montagens {
                for c in m.comodos {
                    for o in m.planosPorComodo[c.id]?.objetos ?? [] {
                        moveis.append([
                            c.nome,
                            o.nome,
                            Formato.numero(o.dimensoes.largura),
                            Formato.numero(o.dimensoes.profundidade),
                            Formato.numero(o.dimensoes.altura),
                        ])
                    }
                }
            }
            if !moveis.isEmpty {
                resultado.append(TabelaPDF(
                    titulo: "MOBILIÁRIO DETECTADO",
                    colunas: [
                        ColunaTabela(titulo: "CÔMODO", largura: 130),
                        ColunaTabela(titulo: "OBJETO", largura: 150),
                        ColunaTabela(titulo: "LARG. (m)", largura: 60, alinhamento: .trailing),
                        ColunaTabela(titulo: "PROF. (m)", largura: 60, alinhamento: .trailing),
                        ColunaTabela(titulo: "ALT. (m)", largura: 60, alinhamento: .trailing),
                    ],
                    linhas: moveis
                ))
            }
        }
        return resultado
    }

    /// Distribui as tabelas em folhas (repete o cabeçalho quando uma tabela continua).
    private static func paginarTabelas(_ tabelas: [TabelaPDF]) -> [[TabelaPDF]] {
        let capacidade = 30
        var paginas: [[TabelaPDF]] = []
        var atual: [TabelaPDF] = []
        var usadas = 0

        for tabela in tabelas {
            var inicio = 0
            while inicio < tabela.linhas.count || (tabela.linhas.isEmpty && inicio == 0) {
                let livres = capacidade - usadas - 3
                if livres < 4 {
                    paginas.append(atual)
                    atual = []
                    usadas = 0
                    continue
                }
                let fim = min(inicio + livres, tabela.linhas.count)
                var parte = tabela
                parte.linhas = Array(tabela.linhas[inicio..<fim])
                parte.negrito = Set(tabela.negrito.compactMap { $0 >= inicio && $0 < fim ? $0 - inicio : nil })
                if inicio > 0 { parte.titulo = (tabela.titulo ?? "") + " (continuação)" }
                atual.append(parte)
                usadas += parte.linhas.count + 3
                inicio = fim
                if tabela.linhas.isEmpty { break }
            }
        }
        if !atual.isEmpty { paginas.append(atual) }
        return paginas
    }

    static func nomeArquivo(_ nome: String) -> String {
        let invalidos = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        let limpo = nome.components(separatedBy: invalidos).joined(separator: "-")
        return limpo.isEmpty ? "Imovel" : limpo
    }
}
