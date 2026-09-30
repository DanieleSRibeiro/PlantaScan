import CoreGraphics
import Foundation
import Observation
import RoomPlan

/// Mudança local que precisa ir para a nuvem.
enum AlteracaoLocal {
    case imovel(UUID)
    case comodo(UUID)
    case imovelApagado(UUID)
    case comodoApagado(UUID)
}

/// O que ainda falta enviar e até onde já recebemos (salvo em Documents/sync.json).
private struct EstadoSync: Codable {
    var imoveisPendentes: Set<UUID> = []
    var comodosPendentes: Set<UUID> = []
    var imoveisApagados: Set<UUID> = []
    var comodosApagados: Set<UUID> = []
    /// Cômodos cujo scan e modelo 3D já foram enviados.
    var arquivosEnviados: Set<UUID> = []
    var cursorImoveis: String?
    var cursorComodos: String?
    /// Usuário dono deste estado (troca de conta = recomeça).
    var userID: String?
}

/// Sincroniza os imóveis/cômodos locais com o Supabase (mesmo banco do site do Lovable).
/// Estratégia: envia pendências (upsert / exclusão lógica) e depois recebe o que mudou desde o último cursor.
@MainActor
@Observable
final class Sincronizador {
    let cliente = SupabaseCliente()
    private(set) var sincronizando = false
    private(set) var ultimaSincronizacao: Date?
    private(set) var ultimoErro: String?
    private(set) var logado = false
    private(set) var email: String?

    private var estado = EstadoSync()
    private weak var store: ImovelStore?
    private var agendada: Task<Void, Never>?

    private var urlEstado: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("sync.json")
    }

    init() {
        if let data = try? Data(contentsOf: urlEstado),
           let e = try? JSONDecoder().decode(EstadoSync.self, from: data) {
            estado = e
        }
        atualizarConta()
    }

    var pendencias: Int {
        estado.imoveisPendentes.count + estado.comodosPendentes.count + estado.imoveisApagados.count + estado.comodosApagados.count
    }

    func conectar(_ store: ImovelStore) {
        self.store = store
        store.aoAlterar = { [weak self] alteracao in
            self?.registrar(alteracao)
        }
    }

    // MARK: Conta

    func entrar(email: String, senha: String, criarConta: Bool) async throws {
        if criarConta {
            try await cliente.cadastrar(email: email, senha: senha)
        } else {
            try await cliente.entrar(email: email, senha: senha)
        }
        prepararParaUsuario()
        atualizarConta()
        await sincronizar()
    }

    func sair() {
        cliente.sair()
        atualizarConta()
    }

    private func atualizarConta() {
        logado = cliente.logado
        email = cliente.email
    }

    /// Primeiro login (ou troca de conta): envia tudo que existe no aparelho e baixa tudo da nuvem.
    private func prepararParaUsuario() {
        guard let uid = cliente.userID, estado.userID != uid else { return }
        estado = EstadoSync()
        estado.userID = uid
        for imovel in store?.imoveis ?? [] {
            estado.imoveisPendentes.insert(imovel.id)
            for c in imovel.comodos {
                estado.comodosPendentes.insert(c.id)
            }
        }
        salvarEstado()
    }

    // MARK: Registro de mudanças

    private func registrar(_ alteracao: AlteracaoLocal) {
        switch alteracao {
        case .imovel(let id):
            estado.imoveisPendentes.insert(id)
        case .comodo(let id):
            estado.comodosPendentes.insert(id)
        case .imovelApagado(let id):
            estado.imoveisPendentes.remove(id)
            estado.imoveisApagados.insert(id)
        case .comodoApagado(let id):
            estado.comodosPendentes.remove(id)
            estado.comodosApagados.insert(id)
        }
        salvarEstado()
        agendar()
    }

    /// Junta várias mudanças seguidas numa sincronização só.
    func agendar(atraso: Double = 3) {
        guard cliente.logado else { return }
        agendada?.cancel()
        agendada = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(atraso * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await self?.sincronizar()
        }
    }

    private func salvarEstado() {
        if let data = try? JSONEncoder().encode(estado) {
            try? data.write(to: urlEstado, options: .atomic)
        }
    }

    // MARK: Sincronização

    func sincronizar() async {
        guard SupabaseConfig.configurado, cliente.logado, !sincronizando, let store else {
            atualizarConta()
            return
        }
        prepararParaUsuario()
        sincronizando = true
        defer {
            sincronizando = false
            atualizarConta()
        }
        do {
            try await enviar(store)
            try await receber(store)
            ultimaSincronizacao = Date()
            ultimoErro = nil
        } catch {
            ultimoErro = error.localizedDescription
        }
        salvarEstado()
    }

    private func enviar(_ store: ImovelStore) async throws {
        guard let uid = cliente.userID else { throw ErroSupabase.naoLogado }

        // Imóveis (antes dos cômodos, por causa da chave estrangeira).
        let imoveis = estado.imoveisPendentes.compactMap { store.imovel(id: $0) }
        if !imoveis.isEmpty {
            try await cliente.upsert("imoveis", linhas: imoveis.map { linhaImovel($0, uid: uid) })
        }
        estado.imoveisPendentes.subtract(imoveis.map(\.id))
        estado.imoveisPendentes = estado.imoveisPendentes.filter { store.imovel(id: $0) != nil }
        salvarEstado()

        // Cômodos.
        for id in estado.comodosPendentes {
            guard let par = localizar(id, em: store) else {
                estado.comodosPendentes.remove(id)
                continue
            }
            let (imovel, comodo) = par
            let room = try? Storage.carregarScan(comodoID: comodo.id, imovelID: imovel.id)
            let planta = room.map { PlantaJSON.objeto(FloorPlanBuilder.construir($0, comodo: comodo)) }
            try await cliente.upsert("comodos", linhas: [linhaComodo(comodo, imovelID: imovel.id, uid: uid, planta: planta)])

            if !estado.arquivosEnviados.contains(comodo.id) {
                try await enviarArquivos(comodo: comodo, imovelID: imovel.id, uid: uid)
                estado.arquivosEnviados.insert(comodo.id)
            }
            estado.comodosPendentes.remove(id)
            salvarEstado()
        }

        // Exclusões (lógicas, para os outros aparelhos saberem).
        for id in estado.comodosApagados {
            try await cliente.atualizar("comodos", id: id, campos: ["apagado": true])
            estado.comodosApagados.remove(id)
        }
        for id in estado.imoveisApagados {
            try await cliente.atualizar("imoveis", id: id, campos: ["apagado": true])
            estado.imoveisApagados.remove(id)
        }
        salvarEstado()
    }

    private func enviarArquivos(comodo: Comodo, imovelID: UUID, uid: String) async throws {
        let base = "\(uid)/\(imovelID.uuidString.lowercased())/\(comodo.id.uuidString.lowercased())"
        if let scan = try? Data(contentsOf: Storage.urlScan(comodoID: comodo.id, imovelID: imovelID)) {
            try await cliente.enviarArquivo(scan, caminho: "\(base).json", tipo: "application/json")
        }
        if let modelo = try? Data(contentsOf: Storage.urlModelo(comodoID: comodo.id, imovelID: imovelID)) {
            try await cliente.enviarArquivo(modelo, caminho: "\(base).usdz", tipo: "model/vnd.usdz+zip")
        }
    }

    /// Envia o PDF do imóvel para aparecer no site ("Baixar PDF").
    func enviarPDF(_ url: URL, imovelID: UUID) {
        guard cliente.logado, let uid = cliente.userID, let data = try? Data(contentsOf: url) else { return }
        Task {
            do {
                try await cliente.enviarArquivo(data, caminho: "\(uid)/\(imovelID.uuidString.lowercased())/planta.pdf", tipo: "application/pdf")
            } catch {
                ultimoErro = "PDF não enviado: \(error.localizedDescription)"
            }
        }
    }

    private func receber(_ store: ImovelStore) async throws {
        // Imóveis.
        while true {
            let linhas = try await cliente.selecionar("imoveis", query: consulta(cursor: estado.cursorImoveis))
            for l in linhas {
                guard let id = uuid(l["id"]) else { continue }
                if (l["apagado"] as? Bool) == true {
                    store.aplicarImovelApagadoRemoto(id: id)
                    estado.imoveisPendentes.remove(id)
                } else if !estado.imoveisPendentes.contains(id) {
                    store.aplicarImovelRemoto(
                        id: id,
                        nome: (l["nome"] as? String) ?? "Imóvel",
                        endereco: (l["endereco"] as? String) ?? "",
                        eircode: l["eircode"] as? String
                    )
                }
                if let c = l["atualizado_em"] as? String { estado.cursorImoveis = c }
            }
            salvarEstado()
            if linhas.count < 500 { break }
        }

        // Cômodos.
        while true {
            let linhas = try await cliente.selecionar("comodos", query: consulta(cursor: estado.cursorComodos))
            for l in linhas {
                guard let id = uuid(l["id"]), let imovelID = uuid(l["imovel_id"]) else { continue }
                if (l["apagado"] as? Bool) == true {
                    store.aplicarComodoApagadoRemoto(id: id, imovelID: imovelID)
                    estado.comodosPendentes.remove(id)
                } else if !estado.comodosPendentes.contains(id), store.imovel(id: imovelID) != nil {
                    var comodo = decodificarComodo(l["dados"]) ?? Comodo(nome: (l["nome"] as? String) ?? "Cômodo")
                    comodo.id = id
                    comodo.nome = (l["nome"] as? String) ?? comodo.nome
                    comodo.tipo = (l["tipo"] as? String).flatMap(TipoComodo.init(rawValue:)) ?? comodo.tipo
                    comodo.andar = (l["andar"] as? Int) ?? comodo.andar

                    // Cômodo escaneado em outro aparelho: baixa o scan.
                    if !FileManager.default.fileExists(atPath: Storage.urlScan(comodoID: id, imovelID: imovelID).path),
                       let uid = cliente.userID {
                        let caminho = "\(uid)/\(imovelID.uuidString.lowercased())/\(id.uuidString.lowercased()).json"
                        if let data = try? await cliente.baixarArquivo(caminho: caminho) {
                            try? FileManager.default.createDirectory(at: Storage.pasta(imovelID: imovelID), withIntermediateDirectories: true)
                            try? data.write(to: Storage.urlScan(comodoID: id, imovelID: imovelID), options: .atomic)
                            estado.arquivosEnviados.insert(id)
                        }
                    }
                    store.aplicarComodoRemoto(comodo, imovelID: imovelID)
                }
                if let c = l["atualizado_em"] as? String { estado.cursorComodos = c }
            }
            salvarEstado()
            if linhas.count < 500 { break }
        }
    }

    // MARK: Conversões

    private func consulta(cursor: String?) -> [URLQueryItem] {
        var q = [
            URLQueryItem(name: "select", value: "*"),
            URLQueryItem(name: "order", value: "atualizado_em.asc"),
            URLQueryItem(name: "limit", value: "500"),
        ]
        if let cursor {
            q.append(URLQueryItem(name: "atualizado_em", value: "gt.\(cursor)"))
        }
        return q
    }

    private func localizar(_ comodoID: UUID, em store: ImovelStore) -> (Imovel, Comodo)? {
        for imovel in store.imoveis {
            if let c = imovel.comodos.first(where: { $0.id == comodoID }) {
                return (imovel, c)
            }
        }
        return nil
    }

    private func uuid(_ valor: Any?) -> UUID? {
        (valor as? String).flatMap(UUID.init(uuidString:))
    }

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private func linhaImovel(_ i: Imovel, uid: String) -> [String: Any] {
        [
            "id": i.id.uuidString.lowercased(),
            "user_id": uid,
            "nome": i.nome,
            "endereco": i.endereco,
            "eircode": i.eircode ?? NSNull(),
            "criado_em": Self.iso.string(from: i.dataCriacao),
            "apagado": false,
        ]
    }

    private func linhaComodo(_ c: Comodo, imovelID: UUID, uid: String, planta: [String: Any]?) -> [String: Any] {
        let dados = (try? JSONEncoder().encode(c)).flatMap { try? JSONSerialization.jsonObject(with: $0) }
        return [
            "id": c.id.uuidString.lowercased(),
            "imovel_id": imovelID.uuidString.lowercased(),
            "user_id": uid,
            "nome": c.nome,
            "tipo": (c.tipo ?? .outro).rawValue,
            "andar": c.andarOuPadrao,
            "area": c.area.map { $0 as Any } ?? NSNull(),
            "sessao": c.sessao.map { $0.uuidString.lowercased() as Any } ?? NSNull(),
            "norte": c.anguloNorte.map { $0 as Any } ?? NSNull(),
            "planta": planta.map { $0 as Any } ?? NSNull(),
            "dados": dados ?? NSNull(),
            "data_scan": Self.iso.string(from: c.dataScan),
            "apagado": false,
        ]
    }

    private func decodificarComodo(_ valor: Any?) -> Comodo? {
        guard let valor, !(valor is NSNull),
              let data = try? JSONSerialization.data(withJSONObject: valor) else { return nil }
        return try? JSONDecoder().decode(Comodo.self, from: data)
    }
}

/// Converte a planta 2D no formato JSON combinado com o site (campo `planta`).
enum PlantaJSON {
    static func objeto(_ p: FloorPlan2D) -> [String: Any] {
        func pt(_ c: CGPoint) -> [Double] { [finito(Double(c.x)), finito(Double(c.y))] }
        func finito(_ v: Double) -> Double { v.isFinite ? (v * 1000).rounded() / 1000 : 0 }
        let piso = p.nivelPiso

        let paredes: [[String: Any]] = p.paredes.map {
            [
                "id": $0.id.uuidString.lowercased(),
                "a": pt($0.a), "b": pt($0.b),
                "largura": finito($0.dimensoes.largura),
                "altura": finito($0.dimensoes.altura),
            ]
        }
        let aberturas: [[String: Any]] = p.aberturas.map { ab in
            let modelo: String
            switch ab.tipo {
            case .porta: modelo = ab.modeloPorta.rawValue
            case .janela: modelo = ab.modeloJanela.rawValue
            case .vao: modelo = ""
            }
            return [
                "id": ab.id.uuidString.lowercased(),
                "tipo": ab.tipo.rawValue,
                "modelo": modelo,
                "a": pt(ab.a), "b": pt(ab.b),
                "ladoInterno": [finito(Double(ab.ladoInterno.dx)), finito(Double(ab.ladoInterno.dy))],
                "dobradicaNoFim": ab.dobradicaNoFim,
                "largura": finito(ab.dimensoes.largura),
                "altura": finito(ab.dimensoes.altura),
                "peitoril": ab.tipo == .janela ? finito(max(ab.yBase - piso, 0)) : 0,
            ]
        }
        let objetos: [[String: Any]] = p.objetos.map {
            [
                "id": $0.id.uuidString.lowercased(),
                "nome": $0.nome,
                "cantos": $0.cantos.map(pt),
                "largura": finito($0.dimensoes.largura),
                "altura": finito($0.dimensoes.altura),
                "profundidade": finito($0.dimensoes.profundidade),
            ]
        }
        return [
            "versao": 1,
            "paredes": paredes,
            "aberturas": aberturas,
            "objetos": objetos,
            "pisos": p.pisos.map { $0.map(pt) },
            "area": finito(p.area),
        ]
    }
}
