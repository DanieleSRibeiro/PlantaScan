import Foundation
import RoomPlan

enum Formato {
    private static let local = Locale(identifier: "pt_BR")

    static func numero(_ v: Double) -> String {
        v.formatted(.number.precision(.fractionLength(2)).locale(local))
    }

    static func numeroCurto(_ v: Double) -> String {
        v.formatted(.number.precision(.fractionLength(0...2)).locale(local))
    }

    static func metros(_ v: Double) -> String { "\(numero(v)) m" }

    static func andar(_ n: Int) -> String { "\(n)º andar" }

    static func area(_ v: Double) -> String { "\(numero(v)) m²" }

    /// "L 0,80 × A 2,10 × P 0,05 m" (profundidade omitida quando não medida).
    static func dimensoes(_ d: Dimensoes) -> String {
        var partes = ["L \(numero(d.largura))", "A \(numero(d.altura))"]
        if d.profundidade > 0.001 {
            partes.append("P \(numero(d.profundidade))")
        }
        return partes.joined(separator: " × ") + " m"
    }
}

enum Rotulos {
    static func nome(_ categoria: CapturedRoom.Object.Category) -> String {
        switch categoria {
        case .bathtub: return "Banheira"
        case .bed: return "Cama"
        case .chair: return "Cadeira"
        case .dishwasher: return "Lava-louças"
        case .fireplace: return "Lareira"
        case .oven: return "Forno"
        case .refrigerator: return "Geladeira"
        case .sink: return "Pia"
        case .sofa: return "Sofá"
        case .stairs: return "Escada"
        case .storage: return "Armário/estante"
        case .stove: return "Fogão"
        case .table: return "Mesa"
        case .television: return "TV"
        case .toilet: return "Vaso sanitário"
        case .washerDryer: return "Máquina de lavar"
        @unknown default: return "Objeto"
        }
    }
}
