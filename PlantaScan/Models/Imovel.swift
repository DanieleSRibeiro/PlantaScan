import Foundation

struct Imovel: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var nome: String
    var endereco: String
    var dataCriacao: Date = Date()
    var comodos: [Comodo] = []
}

struct Comodo: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var nome: String
    var dataScan: Date = Date()
    /// Área em m² calculada a partir do scan (cache para a lista).
    var area: Double?
    /// Ajustes feitos pelo usuário em portas/janelas/vãos, por id do elemento.
    var edicoes: [String: EdicaoAbertura]?
    /// Portas/janelas/vãos adicionados manualmente.
    var aberturasManuais: [AberturaManual]?
    /// Objetos detectados que o usuário removeu.
    var objetosRemovidos: [UUID]?
}
