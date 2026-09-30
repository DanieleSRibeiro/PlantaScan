import CoreGraphics
import Foundation

/// Medidas em metros.
struct Dimensoes: Hashable {
    var largura: Double
    var altura: Double
    var profundidade: Double
}

/// Planta 2D em metros, no plano XZ do RoomPlan (vista de cima: x → direita, z → baixo).
struct FloorPlan2D {
    var paredes: [Parede2D] = []
    var aberturas: [Abertura2D] = []
    var objetos: [Objeto2D] = []
    /// Contornos do piso (um por cômodo).
    var pisos: [[CGPoint]] = []
    var area: Double = 0
    var limites: CGRect = CGRect(x: -1, y: -1, width: 2, height: 2)
    var centro: CGPoint = .zero
    var quantidadeRemovidos = 0
    /// Nomes e áreas dos cômodos (planta de vários cômodos).
    var rotulos: [RotuloComodo] = []

    var vazio: Bool { paredes.isEmpty && objetos.isEmpty }

    func contar(_ tipo: TipoAbertura) -> Int {
        aberturas.filter { $0.tipo == tipo }.count
    }

    /// Ponto para o rótulo de área: centroide do maior piso.
    var centroRotulo: CGPoint {
        guard let maior = pisos.max(by: { Geometria.area($0) < Geometria.area($1) }) else { return centro }
        return Geometria.centroidePoligono(maior)
    }
}

struct RotuloComodo {
    var ponto: CGPoint
    var nome: String
    var area: Double
}

struct Parede2D: Identifiable {
    let id: UUID
    var a: CGPoint
    var b: CGPoint
    var dimensoes: Dimensoes
    /// Centro do cômodo a que a parede pertence (para desenhar a cota do lado de fora).
    var referencia: CGPoint? = nil
}

struct Abertura2D: Identifiable {
    let id: UUID
    var tipo: TipoAbertura
    var modeloPorta: ModeloPorta = .giro
    var modeloJanela: ModeloJanela = .correr
    var a: CGPoint
    var b: CGPoint
    /// Vetor unitário perpendicular à parede, apontando para dentro do cômodo.
    var ladoInterno: CGVector
    var dobradicaNoFim = false
    var dimensoes: Dimensoes
    var manual = false

    init(id: UUID, tipo: TipoAbertura, a: CGPoint, b: CGPoint, ladoInterno: CGVector, dimensoes: Dimensoes, manual: Bool = false) {
        self.id = id
        self.tipo = tipo
        self.a = a
        self.b = b
        self.ladoInterno = ladoInterno
        self.dimensoes = dimensoes
        self.manual = manual
    }

    var descricao: String {
        switch tipo {
        case .porta: return "Porta · \(modeloPorta.nome.lowercased())"
        case .janela: return "Janela · \(modeloJanela.nome.lowercased())"
        case .vao: return "Vão"
        }
    }
}

struct Objeto2D: Identifiable {
    let id: UUID
    var nome: String
    var cantos: [CGPoint]
    var centro: CGPoint
    let dimensoes: Dimensoes
}

extension FloorPlan2D {
    /// Move toda a planta (usado para pôr lado a lado cômodos de sessões diferentes).
    mutating func deslocar(_ d: CGVector) {
        for i in paredes.indices {
            paredes[i].a = paredes[i].a + d
            paredes[i].b = paredes[i].b + d
            paredes[i].referencia = paredes[i].referencia.map { $0 + d }
        }
        for i in aberturas.indices {
            aberturas[i].a = aberturas[i].a + d
            aberturas[i].b = aberturas[i].b + d
        }
        for i in objetos.indices {
            objetos[i].cantos = objetos[i].cantos.map { $0 + d }
            objetos[i].centro = objetos[i].centro + d
        }
        pisos = pisos.map { $0.map { $0 + d } }
        for i in rotulos.indices {
            rotulos[i].ponto = rotulos[i].ponto + d
        }
        centro = centro + d
        limites = limites.offsetBy(dx: d.dx, dy: d.dy)
    }

    /// Junta várias plantas que já estão no mesmo sistema de coordenadas.
    static func combinar(_ planos: [FloorPlan2D]) -> FloorPlan2D {
        guard let primeiro = planos.first else { return FloorPlan2D() }
        var r = FloorPlan2D()
        r.paredes = planos.flatMap(\.paredes)
        r.aberturas = planos.flatMap(\.aberturas)
        r.objetos = planos.flatMap(\.objetos)
        r.pisos = planos.flatMap(\.pisos)
        r.rotulos = planos.flatMap(\.rotulos)
        r.area = planos.reduce(0) { $0 + $1.area }
        r.quantidadeRemovidos = planos.reduce(0) { $0 + $1.quantidadeRemovidos }
        r.limites = planos.dropFirst().reduce(primeiro.limites) { $0.union($1.limites) }
        r.centro = Geometria.media(planos.map(\.centro))
        return r
    }
}

/// Elemento tocado na planta.
struct ElementoPlano: Identifiable, Equatable {
    enum Tipo: Equatable {
        case parede
        case abertura(TipoAbertura)
        case objeto
    }

    let id: UUID
    let tipo: Tipo
    let nome: String
    let dimensoes: Dimensoes
}

extension FloorPlan2D {
    /// Busca o elemento sob um ponto do plano (em metros).
    func elemento(em p: CGPoint, tolerancia: CGFloat) -> ElementoPlano? {
        let aberturaProxima = aberturas
            .map { ($0, Geometria.distancia(ponto: p, a: $0.a, b: $0.b)) }
            .min { $0.1 < $1.1 }
        if let m = aberturaProxima, m.1 < tolerancia + 0.1 {
            return ElementoPlano(id: m.0.id, tipo: .abertura(m.0.tipo), nome: m.0.descricao, dimensoes: m.0.dimensoes)
        }
        if let o = objetos.first(where: { Geometria.contem($0.cantos, p) }) {
            return ElementoPlano(id: o.id, tipo: .objeto, nome: o.nome, dimensoes: o.dimensoes)
        }
        let paredeProxima = paredes
            .map { ($0, Geometria.distancia(ponto: p, a: $0.a, b: $0.b)) }
            .min { $0.1 < $1.1 }
        if let m = paredeProxima, m.1 < tolerancia + 0.08 {
            return ElementoPlano(id: m.0.id, tipo: .parede, nome: "Parede", dimensoes: m.0.dimensoes)
        }
        return nil
    }
}
