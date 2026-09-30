import Foundation

enum TipoAbertura: String, Codable, CaseIterable, Identifiable {
    case porta, janela, vao

    var id: String { rawValue }

    var nome: String {
        switch self {
        case .porta: return "Porta"
        case .janela: return "Janela"
        case .vao: return "Vão"
        }
    }
}

enum ModeloPorta: String, Codable, CaseIterable, Identifiable {
    case giro, dupla, correr, sanfonada

    var id: String { rawValue }

    var nome: String {
        switch self {
        case .giro: return "De abrir"
        case .dupla: return "Dupla"
        case .correr: return "De correr"
        case .sanfonada: return "Sanfonada"
        }
    }
}

enum ModeloJanela: String, Codable, CaseIterable, Identifiable {
    case correr, basculante, maximAr, fixa

    var id: String { rawValue }

    var nome: String {
        switch self {
        case .correr: return "De correr"
        case .basculante: return "Basculante"
        case .maximAr: return "Maxim-ar"
        case .fixa: return "Fixa"
        }
    }
}

/// Ajustes sobre uma porta/janela/vão. Campos nulos mantêm o valor escaneado.
struct EdicaoAbertura: Codable, Hashable {
    var tipo: TipoAbertura?
    var modeloPorta: ModeloPorta?
    var modeloJanela: ModeloJanela?
    var largura: Double?
    var altura: Double?
    /// Deslocamento em metros ao longo da parede.
    var deslocamento: Double?
    var inverterLado: Bool?
    var inverterDobradica: Bool?
    var removido: Bool?
}

/// Rotação + deslocamento que leva a planta de um cômodo para o referencial de outro grupo.
/// p' = R(rotacao) · p + (dx, dy)
struct Alinhamento: Codable, Hashable {
    /// Chave do grupo de referência (Comodo.chaveSessaoPropria do grupo principal).
    var referencia: String?
    var rotacao: Double
    var dx: Double
    var dy: Double
}

/// Porta/janela/vão adicionado pelo usuário numa parede escaneada.
struct AberturaManual: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var paredeID: UUID
    var tipo: TipoAbertura
    /// Distância em metros do início da parede até o centro da abertura.
    var posicao: Double
    var largura: Double
    var altura: Double
}
