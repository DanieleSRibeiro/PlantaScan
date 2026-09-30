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
