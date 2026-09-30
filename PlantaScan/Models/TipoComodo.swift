import CoreGraphics
import Foundation
import RoomPlan
import simd

enum TipoComodo: String, Codable, CaseIterable, Identifiable {
    case quarto, banheiro, cozinha, salaEstar, salaJantar, lavanderia, escritorio, corredor, varanda, garagem, outro

    var id: String { rawValue }

    var nome: String {
        switch self {
        case .quarto: return "Quarto"
        case .banheiro: return "Banheiro"
        case .cozinha: return "Cozinha"
        case .salaEstar: return "Sala de estar"
        case .salaJantar: return "Sala de jantar"
        case .lavanderia: return "Lavanderia"
        case .escritorio: return "Escritório"
        case .corredor: return "Corredor"
        case .varanda: return "Varanda"
        case .garagem: return "Garagem"
        case .outro: return "Cômodo"
        }
    }

    var plural: String {
        switch self {
        case .quarto: return "quartos"
        case .banheiro: return "banheiros"
        case .cozinha: return "cozinhas"
        case .salaEstar: return "salas de estar"
        case .salaJantar: return "salas de jantar"
        case .lavanderia: return "lavanderias"
        case .escritorio: return "escritórios"
        case .corredor: return "corredores"
        case .varanda: return "varandas"
        case .garagem: return "garagens"
        case .outro: return "outros"
        }
    }

    var icone: String {
        switch self {
        case .quarto: return "bed.double"
        case .banheiro: return "shower"
        case .cozinha: return "fork.knife"
        case .salaEstar: return "sofa"
        case .salaJantar: return "table.furniture"
        case .lavanderia: return "washer"
        case .escritorio: return "desktopcomputer"
        case .corredor: return "arrow.left.and.right"
        case .varanda: return "sun.max"
        case .garagem: return "car"
        case .outro: return "square.dashed"
        }
    }

    /// Quartos, banheiros e cômodos genéricos sempre recebem número ("Quarto 1").
    var sempreNumerar: Bool {
        self == .quarto || self == .banheiro || self == .outro
    }
}

/// Identifica o tipo do cômodo pelas seções que o RoomPlan reconhece (iOS 17).
enum DetectorComodo {
    static func tipo(de label: CapturedRoom.Section.Label) -> TipoComodo {
        switch label {
        case .bedroom: return .quarto
        case .bathroom: return .banheiro
        case .kitchen: return .cozinha
        case .livingRoom: return .salaEstar
        case .diningRoom: return .salaJantar
        case .unidentified: return .outro
        @unknown default: return .outro
        }
    }

    /// Usa a seção identificada mais próxima do centro do piso.
    static func tipo(_ room: CapturedRoom, centro: CGPoint) -> TipoComodo {
        let candidatas = room.sections
            .map { (tipo(de: $0.label), $0.center) }
            .filter { $0.0 != .outro }
        guard let melhor = candidatas.min(by: { distancia($0.1, centro) < distancia($1.1, centro) }) else {
            return .outro
        }
        return melhor.0
    }

    private static func distancia(_ p: simd_float3, _ c: CGPoint) -> Double {
        hypot(Double(p.x) - Double(c.x), Double(p.z) - Double(c.y))
    }

    /// "Quarto 2", "Cozinha", "Cozinha 2"…
    static func nomeSugerido(_ tipo: TipoComodo, existentes: [Comodo], ignorando id: UUID? = nil) -> String {
        let n = existentes.filter { $0.tipo == tipo && $0.id != id }.count
        if tipo.sempreNumerar || n > 0 {
            return "\(tipo.nome) \(n + 1)"
        }
        return tipo.nome
    }
}
