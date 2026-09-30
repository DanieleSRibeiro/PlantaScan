import Foundation

struct Imovel: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var nome: String
    var endereco: String
    var dataCriacao: Date = Date()
    var comodos: [Comodo] = []
    var eircode: String? = nil

    /// Soma das áreas dos cômodos já calculadas.
    var areaTotal: Double {
        comodos.reduce(0) { $0 + ($1.area ?? 0) }
    }

    var andares: [Int] {
        Array(Set(comodos.map(\.andarOuPadrao))).sorted()
    }
}

struct Comodo: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var nome: String
    var dataScan: Date = Date()
    /// Área em m² calculada a partir do scan (cache para a lista).
    var area: Double?
    /// Andar (1 = 1º andar).
    var andar: Int?
    var tipo: TipoComodo?
    /// Cômodos da mesma sessão de scan compartilham o sistema de coordenadas (planta alinhada).
    var sessao: UUID?
    /// Ajustes feitos pelo usuário em portas/janelas/vãos, por id do elemento.
    var edicoes: [String: EdicaoAbertura]?
    /// Portas/janelas/vãos adicionados manualmente.
    var aberturasManuais: [AberturaManual]?
    /// Objetos detectados que o usuário removeu.
    var objetosRemovidos: [UUID]?
    /// Nomes personalizados de objetos, por id.
    var nomesObjetos: [String: String]?
    /// Direção do norte verdadeiro no plano XZ do scan (radianos, medida pela bússola durante o scan).
    var norte: Double?
    /// Correção manual do norte, em graus.
    var ajusteNorte: Double?

    /// Posição deste cômodo na planta de outro grupo (encaixe pela porta ou manual).
    var alinhamento: Alinhamento?

    var andarOuPadrao: Int { andar ?? 1 }

    /// Grupo de cômodos que se movem juntos (mesma sessão de scan).
    var chaveSessaoPropria: String { (sessao ?? id).uuidString }

    /// Grupo em cujo sistema de coordenadas o cômodo é desenhado (depois do encaixe).
    var chaveGrupo: String { alinhamento?.referencia ?? chaveSessaoPropria }

    /// Ângulo final do norte na planta (radianos), ou nil se não foi medido nem ajustado.
    var anguloNorte: Double? {
        guard norte != nil || ajusteNorte != nil else { return nil }
        return (norte ?? -Double.pi / 2) + (ajusteNorte ?? 0) * Double.pi / 180
    }
}
