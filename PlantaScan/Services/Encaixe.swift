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
                    let pontuacao = Double(sobreposicao(teste, fixo)) * 10 + diferenca + (rotacao == base ? 0 : 0.05)
                    if melhor == nil || pontuacao < melhor!.pontuacao {
                        melhor = (pontuacao, candidato)
                    }
                }
            }
        }
        // Encaixe que invade o outro cômodo não serve.
        guard let m = melhor, m.pontuacao < 10 else { return nil }
        return m.alinhamento
    }

    /// Quantos pontos do piso do cômodo movido caem dentro do piso do fixo.
    private static func sobreposicao(_ movel: FloorPlan2D, _ fixo: FloorPlan2D) -> Int {
        var n = 0
        for piso in movel.pisos {
            let centro = Geometria.centroidePoligono(piso)
            // Pontos puxados 20% para o centro, para não contar os cantos encostados na parede comum.
            let amostras = piso.map { q in CGPoint(x: centro.x + (q.x - centro.x) * 0.8, y: centro.y + (q.y - centro.y) * 0.8) } + [centro]
            for p in amostras where fixo.pisos.contains(where: { Geometria.contem($0, p) }) {
                n += 1
            }
        }
        return n
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
