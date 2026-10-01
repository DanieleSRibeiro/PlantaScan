import CoreGraphics
import Foundation
import RoomPlan
import simd

/// Um cômodo encontrado dentro do scan da casa toda.
struct RegiaoCasa {
    var contorno: [CGPoint]
    var area: Double
    var tipo: TipoComodo
}

/// Divide o scan da casa toda (um único CapturedRoom) em cômodos:
/// as paredes e as portas/vãos fecham os espaços; cada espaço fechado vira um cômodo,
/// e o nome vem da seção que o RoomPlan reconheceu dentro dele (quarto, banheiro…).
enum Segmentacao {
    /// Tamanho da célula da grade, em metros.
    private static let celula: CGFloat = 0.05
    /// Meia espessura usada para "desenhar" paredes e portas na grade.
    private static let raio: CGFloat = 0.08
    /// Espaços menores que isso são sobras entre paredes, não cômodos.
    private static let areaMinima: Double = 1.0

    static func dividir(_ room: CapturedRoom) -> [RegiaoCasa] {
        let plano = FloorPlanBuilder.construir(room)
        guard plano.paredes.count >= 4 else { return [] }
        let l = plano.limites.insetBy(dx: -0.5, dy: -0.5)
        let nx = Int((l.width / celula).rounded(.up))
        let ny = Int((l.height / celula).rounded(.up))
        guard nx > 4, ny > 4, nx * ny < 4_000_000 else { return [] }

        // Grade: 0 = livre, 1 = parede/porta, 2 = fora da casa, >= 3 = cômodo.
        var g = [Int32](repeating: 0, count: nx * ny)
        func centro(_ i: Int, _ j: Int) -> CGPoint {
            CGPoint(x: l.minX + (CGFloat(i) + 0.5) * celula, y: l.minY + (CGFloat(j) + 0.5) * celula)
        }

        // Fora do piso da casa.
        let contornoCasa = plano.pisos.isEmpty
            ? [Geometria.envoltoriaConvexa(plano.paredes.flatMap { [$0.a, $0.b] })]
            : plano.pisos
        for j in 0..<ny {
            for i in 0..<nx where !contornoCasa.contains(where: { Geometria.contem($0, centro(i, j)) }) {
                g[j * nx + i] = 2
            }
        }

        // Paredes e passagens (portas e vãos fecham o cômodo).
        let r = Int((raio / celula).rounded(.up))
        func marcar(_ a: CGPoint, _ b: CGPoint) {
            let passos = max(Int(a.distancia(b) / (celula / 2)), 1)
            for s in 0...passos {
                let t = CGFloat(s) / CGFloat(passos)
                let p = CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
                let ci = Int((p.x - l.minX) / celula)
                let cj = Int((p.y - l.minY) / celula)
                for dj in -r...r {
                    for di in -r...r {
                        let i = ci + di
                        let j = cj + dj
                        guard i >= 0, j >= 0, i < nx, j < ny else { continue }
                        if centro(i, j).distancia(p) <= raio { g[j * nx + i] = 1 }
                    }
                }
            }
        }
        for w in plano.paredes { marcar(w.a, w.b) }
        for ab in plano.aberturas where ab.tipo != .janela { marcar(ab.a, ab.b) }

        // Espaços conectados (vizinhança de 4).
        var proximo: Int32 = 3
        var tamanhos: [Int32: Int] = [:]
        var pilha: [Int] = []
        for inicio in 0..<(nx * ny) where g[inicio] == 0 {
            let rotulo = proximo
            proximo += 1
            var n = 0
            g[inicio] = rotulo
            pilha.append(inicio)
            while let k = pilha.popLast() {
                n += 1
                let i = k % nx
                let j = k / nx
                if i > 0, g[k - 1] == 0 { g[k - 1] = rotulo; pilha.append(k - 1) }
                if i < nx - 1, g[k + 1] == 0 { g[k + 1] = rotulo; pilha.append(k + 1) }
                if j > 0, g[k - nx] == 0 { g[k - nx] = rotulo; pilha.append(k - nx) }
                if j < ny - 1, g[k + nx] == 0 { g[k + nx] = rotulo; pilha.append(k + nx) }
            }
            tamanhos[rotulo] = n
        }

        let areaCelula = Double(celula * celula)
        let validos = tamanhos.filter { Double($0.value) * areaCelula >= areaMinima }.map(\.key)
        guard validos.count >= 2 else { return [] }

        // Nome de cada espaço pela seção do RoomPlan que cai dentro dele.
        var tipos: [Int32: TipoComodo] = [:]
        for secao in room.sections {
            let p = CGPoint(x: CGFloat(secao.center.x), y: CGFloat(secao.center.z))
            let i = Int((p.x - l.minX) / celula)
            let j = Int((p.y - l.minY) / celula)
            guard i >= 0, j >= 0, i < nx, j < ny else { continue }
            let rotulo = g[j * nx + i]
            guard validos.contains(rotulo) else { continue }
            let tipo = DetectorComodo.tipo(de: secao.label)
            if tipos[rotulo] == nil || tipos[rotulo] == .outro {
                tipos[rotulo] = tipo
            }
        }

        var regioes: [RegiaoCasa] = []
        for rotulo in validos {
            let contorno = contornoDe(rotulo, g: g, nx: nx, ny: ny, origem: l.origin)
            guard contorno.count >= 3 else { continue }
            regioes.append(RegiaoCasa(
                contorno: contorno,
                area: Double(tamanhos[rotulo] ?? 0) * areaCelula,
                tipo: tipos[rotulo] ?? .outro
            ))
        }
        // Maiores primeiro (sala, quartos), depois os menores.
        return regioes.sorted { $0.area > $1.area }
    }

    /// Contorno externo de um espaço da grade, simplificado.
    private static func contornoDe(_ rotulo: Int32, g: [Int32], nx: Int, ny: Int, origem: CGPoint) -> [CGPoint] {
        func dentro(_ i: Int, _ j: Int) -> Bool {
            i >= 0 && j >= 0 && i < nx && j < ny && g[j * nx + i] == rotulo
        }
        func chave(_ i: Int, _ j: Int) -> Int { j * (nx + 1) + i }

        // Arestas da borda, com o espaço sempre à esquerda.
        var saidas: [Int: [Int]] = [:]
        for j in 0..<ny {
            for i in 0..<nx where g[j * nx + i] == rotulo {
                if !dentro(i, j - 1) { saidas[chave(i, j), default: []].append(chave(i + 1, j)) }
                if !dentro(i + 1, j) { saidas[chave(i + 1, j), default: []].append(chave(i + 1, j + 1)) }
                if !dentro(i, j + 1) { saidas[chave(i + 1, j + 1), default: []].append(chave(i, j + 1)) }
                if !dentro(i - 1, j) { saidas[chave(i, j + 1), default: []].append(chave(i, j)) }
            }
        }

        // Encadeia as arestas em laços; fica com o maior.
        var melhor: [Int] = []
        while let inicio = saidas.first(where: { !$0.value.isEmpty })?.key {
            var laco: [Int] = [inicio]
            var atual = inicio
            while var lista = saidas[atual], let seguinte = lista.popLast() {
                saidas[atual] = lista
                if seguinte == inicio { break }
                laco.append(seguinte)
                atual = seguinte
                if laco.count > nx * ny * 4 { break }
            }
            if laco.count > melhor.count { melhor = laco }
            saidas = saidas.filter { !$0.value.isEmpty }
        }

        let pontos = melhor.map { k -> CGPoint in
            let i = k % (nx + 1)
            let j = k / (nx + 1)
            return CGPoint(x: origem.x + CGFloat(i) * celula, y: origem.y + CGFloat(j) * celula)
        }
        return simplificar(pontos, tolerancia: celula * 0.9)
    }

    /// Douglas-Peucker para polígono fechado.
    private static func simplificar(_ p: [CGPoint], tolerancia: CGFloat) -> [CGPoint] {
        guard p.count > 4 else { return p }
        func dp(_ pts: ArraySlice<CGPoint>) -> [CGPoint] {
            guard let a = pts.first, let b = pts.last, pts.count > 2 else { return Array(pts) }
            var maior: CGFloat = 0
            var indice = pts.startIndex
            for k in pts.indices.dropFirst().dropLast() {
                let d = Geometria.distancia(ponto: pts[k], a: a, b: b)
                if d > maior {
                    maior = d
                    indice = k
                }
            }
            guard maior > tolerancia else { return [a, b] }
            let esquerda = dp(pts[pts.startIndex...indice])
            let direita = dp(pts[indice...pts.endIndex - 1])
            return Array(esquerda.dropLast()) + direita
        }
        // Divide no ponto mais distante do primeiro, para tratar o laço fechado.
        let a = p[0]
        let longe = p.indices.max { a.distancia(p[$0]) < a.distancia(p[$1]) } ?? p.count / 2
        let ida = dp(p[0...longe])
        let volta = dp((p[longe...] + [a])[...])
        let resultado = Array(ida.dropLast() + volta.dropLast())
        return resultado.count >= 3 ? resultado : p
    }
}
