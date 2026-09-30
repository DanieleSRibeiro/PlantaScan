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
}
