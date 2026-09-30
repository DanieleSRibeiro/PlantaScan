import CoreGraphics
import Foundation
import RoomPlan
import simd

/// Converte o resultado do RoomPlan (3D) em planta 2D projetando no plano XZ.
enum FloorPlanBuilder {
    /// O RoomPlan não mede a espessura das paredes; usamos um valor típico para o desenho.
    static let espessuraPadrao: Double = 0.12

    static func construir(_ room: CapturedRoom, comodo: Comodo? = nil) -> FloorPlan2D {
        var plano = construir(
            paredes: room.walls,
            portas: room.doors,
            janelas: room.windows,
            vaos: room.openings,
            objetos: room.objects,
            pisos: room.floors
        )
        if let comodo {
            aplicar(comodo, em: &plano)
        }
        return plano
    }

    static func construir(
        paredes: [CapturedRoom.Surface],
        portas: [CapturedRoom.Surface],
        janelas: [CapturedRoom.Surface],
        vaos: [CapturedRoom.Surface],
        objetos: [CapturedRoom.Object],
        pisos: [CapturedRoom.Surface]
    ) -> FloorPlan2D {
        var plano = FloorPlan2D()

        plano.paredes = paredes.map { s in
            let (a, b) = extremos(s.transform, largura: s.dimensions.x)
            var p = Parede2D(id: s.identifier, a: a, b: b, dimensoes: dimensoes(s.dimensions))
            p.yBase = base(s.transform, altura: s.dimensions.y)
            return p
        }

        // Piso: usa polygonCorners (iOS 17); senão, o polígono formado pelas paredes.
        var contornos: [[CGPoint]] = pisos.compactMap { piso in
            let cantos = piso.polygonCorners
            guard cantos.count >= 3 else { return nil }
            let pts = cantos.map { c -> CGPoint in
                let w = piso.transform * simd_float4(c.x, c.y, c.z, 1)
                return CGPoint(x: CGFloat(w.x), y: CGFloat(w.z))
            }
            return Geometria.area(pts) > 0.1 ? pts : nil
        }
        if contornos.isEmpty {
            let p = poligonoDasParedes(plano.paredes)
            if p.count >= 3 { contornos = [p] }
        }
        plano.pisos = contornos
        plano.area = contornos.reduce(0) { $0 + Geometria.area($1) }

        let pontosParedes = plano.paredes.flatMap { [$0.a, $0.b] }
        plano.centro = Geometria.media(pontosParedes + contornos.flatMap { $0 })

        let centro = plano.centro
        for i in plano.paredes.indices {
            plano.paredes[i].referencia = centro
        }
        func abertura(_ s: CapturedRoom.Surface, _ tipo: TipoAbertura) -> Abertura2D {
            let (a, b) = extremos(s.transform, largura: s.dimensions.x)
            let n = (b - a).normalizado.perpendicular
            var ab = Abertura2D(
                id: s.identifier,
                tipo: tipo,
                a: a,
                b: b,
                ladoInterno: ladoInterno(meio: CGPoint.media(a, b), normal: n, pisos: contornos, centro: centro),
                dimensoes: dimensoes(s.dimensions)
            )
            ab.yBase = base(s.transform, altura: s.dimensions.y)
            return ab
        }
        plano.aberturas = portas.map { abertura($0, .porta) }
            + janelas.map { abertura($0, .janela) }
            + vaos.map { abertura($0, .vao) }

        plano.objetos = objetos.map { o in
            let t = o.transform
            let c = CGPoint(x: CGFloat(t.columns.3.x), y: CGFloat(t.columns.3.z))
            let u = eixo(t.columns.0)
            let v = eixo(t.columns.2)
            let hx = CGFloat(o.dimensions.x) / 2
            let hz = CGFloat(o.dimensions.z) / 2
            let ux: CGVector = u * hx
            let vz: CGVector = v * hz
            let cantos: [CGPoint] = [
                c - ux - vz,
                c + ux - vz,
                c + ux + vz,
                c - ux + vz,
            ]
            return Objeto2D(id: o.identifier, nome: Rotulos.nome(o.category), cantos: cantos, centro: c, dimensoes: dimensoes(o.dimensions))
        }

        plano.limites = Geometria.limites(pontosParedes + contornos.flatMap { $0 } + plano.objetos.flatMap(\.cantos))
        return plano
    }

    // MARK: Edições do usuário

    static func aplicar(_ comodo: Comodo, em plano: inout FloorPlan2D) {
        var removidos = 0

        // Paredes removidas (e as aberturas que estavam nelas); o piso é refeito pelas paredes que ficaram.
        let paredesRemovidas = Set(comodo.paredesRemovidas ?? [])
        if !paredesRemovidas.isEmpty {
            let removidas = plano.paredes.filter { paredesRemovidas.contains($0.id) }
            plano.paredes.removeAll { paredesRemovidas.contains($0.id) }
            plano.aberturas.removeAll { ab in
                let meio = CGPoint.media(ab.a, ab.b)
                return removidas.contains { Geometria.distancia(ponto: meio, a: $0.a, b: $0.b) < 0.15 }
            }
            removidos += removidas.count
            let contorno = poligonoDasParedes(plano.paredes)
            if contorno.count >= 3 {
                plano.pisos = [contorno]
                plano.area = Geometria.area(contorno)
                plano.centro = Geometria.media(plano.paredes.flatMap { [$0.a, $0.b] })
            }
        }

        for m in comodo.aberturasManuais ?? [] {
            guard let parede = plano.paredes.first(where: { $0.id == m.paredeID }) else { continue }
            let u = (parede.b - parede.a).normalizado
            let meio = parede.a + u * CGFloat(m.posicao)
            let meia = CGFloat(m.largura) / 2
            var ab = Abertura2D(
                id: m.id,
                tipo: m.tipo,
                a: meio - u * meia,
                b: meio + u * meia,
                ladoInterno: ladoInterno(meio: meio, normal: u.perpendicular, pisos: plano.pisos, centro: plano.centro),
                dimensoes: Dimensoes(largura: m.largura, altura: m.altura, profundidade: 0),
                manual: true
            )
            // Janelas manuais: peitoril padrão de 1,00 m.
            ab.yBase = parede.yBase + (m.tipo == .janela ? 1.0 : 0)
            plano.aberturas.append(ab)
        }

        let edicoes = comodo.edicoes ?? [:]
        plano.aberturas = plano.aberturas.compactMap { ab in
            guard let e = edicoes[ab.id.uuidString] else { return ab }
            if e.removido == true {
                removidos += 1
                return nil
            }
            var r = ab
            if let t = e.tipo { r.tipo = t }
            if let m = e.modeloPorta { r.modeloPorta = m }
            if let m = e.modeloJanela { r.modeloJanela = m }
            let u = (ab.b - ab.a).normalizado
            var meio = CGPoint.media(ab.a, ab.b)
            if let d = e.deslocamento { meio = meio + u * CGFloat(d) }
            let largura = e.largura ?? ab.dimensoes.largura
            let meia = CGFloat(largura) / 2
            r.a = meio - u * meia
            r.b = meio + u * meia
            r.dimensoes.largura = largura
            if let h = e.altura { r.dimensoes.altura = h }
            if e.inverterLado == true { r.ladoInterno = -ab.ladoInterno }
            if e.inverterDobradica == true { r.dobradicaNoFim = true }
            return r
        }

        if let nomes = comodo.nomesObjetos, !nomes.isEmpty {
            for i in plano.objetos.indices {
                if let nome = nomes[plano.objetos[i].id.uuidString], !nome.isEmpty {
                    plano.objetos[i].nome = nome
                }
            }
        }

        let objetosRemovidos = Set(comodo.objetosRemovidos ?? [])
        if !objetosRemovidos.isEmpty {
            let antes = plano.objetos.count
            plano.objetos.removeAll { objetosRemovidos.contains($0.id) }
            removidos += antes - plano.objetos.count
        }
        plano.quantidadeRemovidos = removidos
    }

    // MARK: Auxiliares

    private static func extremos(_ t: simd_float4x4, largura: Float) -> (CGPoint, CGPoint) {
        let c = CGPoint(x: CGFloat(t.columns.3.x), y: CGFloat(t.columns.3.z))
        let u = eixo(t.columns.0)
        let m = CGFloat(largura) / 2
        return (c - u * m, c + u * m)
    }

    private static func base(_ t: simd_float4x4, altura: Float) -> Double {
        Double(t.columns.3.y) - Double(altura) / 2
    }

    private static func eixo(_ v: simd_float4) -> CGVector {
        CGVector(dx: CGFloat(v.x), dy: CGFloat(v.z)).normalizado
    }

    private static func dimensoes(_ d: simd_float3) -> Dimensoes {
        Dimensoes(largura: Double(d.x), altura: Double(d.y), profundidade: Double(d.z))
    }

    /// Escolhe o lado da parede que fica dentro do piso (para onde a porta abre).
    static func ladoInterno(meio: CGPoint, normal n: CGVector, pisos: [[CGPoint]], centro: CGPoint) -> CGVector {
        let frente = meio + n * 0.3
        let tras = meio - n * 0.3
        for piso in pisos {
            let f = Geometria.contem(piso, frente)
            let t = Geometria.contem(piso, tras)
            if f != t { return f ? n : -n }
        }
        return (centro - meio).dot(n) >= 0 ? n : -n
    }

    /// Encadeia as paredes pelas pontas mais próximas; se não fechar, usa a envoltória convexa.
    static func poligonoDasParedes(_ paredes: [Parede2D]) -> [CGPoint] {
        guard paredes.count >= 3 else { return [] }
        var restantes = paredes
        let primeira = restantes.removeFirst()
        var poligono = [primeira.a, primeira.b]
        var atual = primeira.b
        while !restantes.isEmpty {
            var melhor: (indice: Int, inverter: Bool, distancia: CGFloat)?
            for (i, p) in restantes.enumerated() {
                let da = atual.distancia(p.a)
                let db = atual.distancia(p.b)
                let d = min(da, db)
                if melhor == nil || d < melhor!.distancia {
                    melhor = (i, db < da, d)
                }
            }
            guard let m = melhor, m.distancia < 0.6 else { break }
            let p = restantes.remove(at: m.indice)
            let proximo = m.inverter ? p.a : p.b
            poligono.append(proximo)
            atual = proximo
        }
        if restantes.isEmpty {
            if poligono.count >= 4, let f = poligono.first, let l = poligono.last, f.distancia(l) < 0.6 {
                poligono.removeLast()
            }
            return poligono
        }
        return Geometria.envoltoriaConvexa(paredes.flatMap { [$0.a, $0.b] })
    }
}
