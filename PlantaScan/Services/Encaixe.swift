import CoreGraphics
import Foundation

/// Encaixa um cômodo escaneado separadamente na planta existente, pela porta (ou vão) em comum.
enum Encaixe {
    /// Procura a porta/vão do cômodo `movel` que coincide com uma do `fixo` (mesma largura)
    /// e devolve a rotação + deslocamento que as sobrepõe, com os cômodos em lados opostos.
    static func porPorta(movel: FloorPlan2D, fixo: FloorPlan2D, referencia: String) -> Alinhamento? {
        let portasM = movel.aberturas.filter { $0.tipo != .janela }
        let portasF = fixo.aberturas.filter { $0.tipo != .janela }
        var melhor: (pontuacao: Double, alinhamento: Alinhamento)?

        for a in portasM {
            for b in portasF {
                let diferenca = abs(a.dimensoes.largura - b.dimensoes.largura)
                guard diferenca < 0.2 else { continue }
                let ca = CGPoint.media(a.a, a.b)
                let cb = CGPoint.media(b.a, b.b)
                // O "lado de dentro" de uma porta deve apontar para fora da outra.
                let base = Double((-b.ladoInterno).angulo - a.ladoInterno.angulo)
                for rotacao in [base, base + .pi] {
                    let c = cos(rotacao)
                    let s = sin(rotacao)
                    let rx = Double(ca.x) * c - Double(ca.y) * s
                    let ry = Double(ca.x) * s + Double(ca.y) * c
                    let candidato = Alinhamento(referencia: referencia, rotacao: rotacao, dx: Double(cb.x) - rx, dy: Double(cb.y) - ry)
                    var teste = movel
                    teste.aplicar(candidato)
                    let sobreposto = fracaoSobreposta(teste, fixo)
                    let pontuacao = sobreposto * 10 + diferenca + (rotacao == base ? 0 : 0.05)
                    // Encaixe que invade o outro cômodo (mais de 15% da área) não serve.
                    guard sobreposto < 0.15 else { continue }
                    if melhor == nil || pontuacao < melhor!.pontuacao {
                        melhor = (pontuacao, candidato)
                    }
                }
            }
        }
        return melhor?.alinhamento
    }

    /// Fração da área do cômodo movido que cai dentro de algum piso do fixo (amostragem em grade).
    static func fracaoSobreposta(_ movel: FloorPlan2D, _ fixo: FloorPlan2D) -> Double {
        var total = 0
        var dentro = 0
        for piso in movel.pisos {
            let l = Geometria.limites(piso)
            let passo = max(min(l.width, l.height) / 10, 0.1)
            var y = l.minY + passo / 2
            while y < l.maxY {
                var x = l.minX + passo / 2
                while x < l.maxX {
                    let p = CGPoint(x: x, y: y)
                    if Geometria.contem(piso, p) {
                        total += 1
                        if fixo.pisos.contains(where: { Geometria.contem($0, p) }) {
                            dentro += 1
                        }
                    }
                    x += passo
                }
                y += passo
            }
        }
        return total == 0 ? 1 : Double(dentro) / Double(total)
    }

    /// Paredes e objetos do cômodo novo que pertencem a cômodos já escaneados
    /// (capturados pela porta aberta). As plantas precisam estar no mesmo referencial.
    static func estranhos(novo: FloorPlan2D, existentes: [FloorPlan2D]) -> (paredes: [UUID], objetos: [UUID]) {
        let pisosAntigos = existentes.flatMap(\.pisos)
        guard !pisosAntigos.isEmpty else { return ([], []) }
        func noAntigo(_ p: CGPoint) -> Bool { pisosAntigos.contains { Geometria.contem($0, p) } }
        func noNovo(_ p: CGPoint) -> Bool { novo.pisos.isEmpty || novo.pisos.contains { Geometria.contem($0, p) } }
        /// Área que é só do cômodo novo.
        func proprio(_ p: CGPoint) -> Bool { noNovo(p) && !noAntigo(p) }

        var paredes: [UUID] = []
        for w in novo.paredes {
            let meio = CGPoint.media(w.a, w.b)
            let n = (w.b - w.a).normalizado.perpendicular
            let lado1 = meio + n * 0.25
            let lado2 = meio - n * 0.25
            // A parede comum tem um lado no cômodo novo; a parede de outro cômodo não tem.
            if !proprio(lado1) && !proprio(lado2) && (noAntigo(lado1) || noAntigo(lado2)) {
                paredes.append(w.id)
            }
        }
        let objetos = novo.objetos.filter { noAntigo($0.centro) }.map(\.id)
        return (paredes, objetos)
    }

    /// Gira o alinhamento em torno de um ponto (coordenadas já alinhadas).
    static func girar(_ a: Alinhamento, por delta: Double, em centro: CGPoint) -> Alinhamento {
        let c = cos(delta)
        let s = sin(delta)
        let tx = a.dx - Double(centro.x)
        let ty = a.dy - Double(centro.y)
        return Alinhamento(
            referencia: a.referencia,
            rotacao: a.rotacao + delta,
            dx: tx * c - ty * s + Double(centro.x),
            dy: tx * s + ty * c + Double(centro.y)
        )
    }
}
