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

struct Parede2D: Identifiable {
    let id: UUID
    var a: CGPoint
    var b: CGPoint
    var dimensoes: Dimensoes
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
    let cantos: [CGPoint]
    let centro: CGPoint
    let dimensoes: Dimensoes
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
