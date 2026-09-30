import ARKit
import Foundation
import Observation
import RoomPlan

@MainActor
@Observable
final class ImovelStore {
    var imoveis: [Imovel] = []
    var mensagemErro: String?
    /// Avisado a cada mudança local (usado pela sincronização).
    @ObservationIgnored var aoAlterar: ((AlteracaoLocal) -> Void)?

    init() {
        recarregar()
    }

    func recarregar() {
        imoveis = Storage.carregarImoveis()
        ordenar()
    }

    private func ordenar() {
        imoveis.sort { $0.nome.localizedStandardCompare($1.nome) == .orderedAscending }
    }

    func imovel(id: UUID) -> Imovel? {
        imoveis.first { $0.id == id }
    }

    // MARK: Imóveis

    @discardableResult
    func criarImovel(nome: String, endereco: String, eircode: String = "") -> Imovel {
        var novo = Imovel(nome: nome, endereco: endereco)
        novo.eircode = eircode.isEmpty ? nil : ImportadorPlanilha.formatarEircode(eircode)
        imoveis.append(novo)
        ordenar()
        persistir(novo)
        aoAlterar?(.imovel(novo.id))
        return novo
    }

    /// Importa imóveis de uma planilha, ignorando repetidos (mesmo nome e Eircode).
    func importar(_ itens: [ImovelImportado]) -> (importados: Int, ignorados: Int) {
        func chave(_ nome: String, _ eircode: String) -> String {
            (nome + "|" + eircode.filter { !$0.isWhitespace }).lowercased()
        }
        var existentes = Set(imoveis.map { chave($0.nome, $0.eircode ?? "") })
        var importados = 0
        var ignorados = 0
        for item in itens {
            let k = chave(item.nome, item.eircode)
            guard !existentes.contains(k) else {
                ignorados += 1
                continue
            }
            existentes.insert(k)
            var novo = Imovel(nome: item.nome, endereco: item.endereco)
            novo.eircode = item.eircode.isEmpty ? nil : item.eircode
            imoveis.append(novo)
            persistir(novo)
            aoAlterar?(.imovel(novo.id))
            importados += 1
        }
        ordenar()
        return (importados, ignorados)
    }

    func atualizar(_ imovel: Imovel) {
        guard let i = imoveis.firstIndex(where: { $0.id == imovel.id }) else { return }
        let antigo = imoveis[i]
        imoveis[i] = imovel
        if antigo.nome != imovel.nome { ordenar() }
        persistir(imovel)
        registrarDiferencas(de: antigo, para: imovel)
    }

    /// Descobre o que mudou para a sincronização enviar só isso.
    private func registrarDiferencas(de antigo: Imovel, para novo: Imovel) {
        guard let aoAlterar else { return }
        if antigo.nome != novo.nome || antigo.endereco != novo.endereco || antigo.eircode != novo.eircode {
            aoAlterar(.imovel(novo.id))
        }
        let anteriores = Dictionary(antigo.comodos.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for c in novo.comodos where anteriores[c.id] != c {
            aoAlterar(.comodo(c.id))
        }
        let atuais = Set(novo.comodos.map(\.id))
        for c in antigo.comodos where !atuais.contains(c.id) {
            aoAlterar(.comodoApagado(c.id))
        }
    }

    func apagarImovel(id: UUID) {
        do {
            try Storage.apagar(imovelID: id)
            imoveis.removeAll { $0.id == id }
            aoAlterar?(.imovelApagado(id))
        } catch {
            mensagemErro = "Não foi possível apagar o imóvel: \(error.localizedDescription)"
        }
    }

    // MARK: Mudanças vindas da nuvem (não geram novo envio)

    func aplicarImovelRemoto(id: UUID, nome: String, endereco: String, eircode: String?) {
        if let i = imoveis.firstIndex(where: { $0.id == id }) {
            guard imoveis[i].nome != nome || imoveis[i].endereco != endereco || imoveis[i].eircode != eircode else { return }
            imoveis[i].nome = nome
            imoveis[i].endereco = endereco
            imoveis[i].eircode = eircode
            persistir(imoveis[i])
        } else {
            var novo = Imovel(nome: nome, endereco: endereco)
            novo.id = id
            novo.eircode = eircode
            imoveis.append(novo)
            persistir(novo)
        }
        ordenar()
    }

    func aplicarImovelApagadoRemoto(id: UUID) {
        guard imoveis.contains(where: { $0.id == id }) else { return }
        try? Storage.apagar(imovelID: id)
        imoveis.removeAll { $0.id == id }
    }

    func aplicarComodoRemoto(_ comodo: Comodo, imovelID: UUID) {
        guard let i = imoveis.firstIndex(where: { $0.id == imovelID }) else { return }
        if let j = imoveis[i].comodos.firstIndex(where: { $0.id == comodo.id }) {
            guard imoveis[i].comodos[j] != comodo else { return }
            imoveis[i].comodos[j] = comodo
        } else {
            imoveis[i].comodos.append(comodo)
        }
        persistir(imoveis[i])
    }

    func aplicarComodoApagadoRemoto(id: UUID, imovelID: UUID) {
        guard let i = imoveis.firstIndex(where: { $0.id == imovelID }),
              imoveis[i].comodos.contains(where: { $0.id == id }) else { return }
        Storage.apagarScan(comodoID: id, imovelID: imovelID)
        imoveis[i].comodos.removeAll { $0.id == id }
        persistir(imoveis[i])
    }

    // MARK: Cômodos

    /// Salva um cômodo escaneado, identificando o tipo e dando um nome automático ("Quarto 1").
    @discardableResult
    func adicionarComodo(room: CapturedRoom, imovelID: UUID, andar: Int, norte: Double?, sessao: UUID, mapa: ARWorldMap?, video: URL? = nil) throws -> Comodo {
        guard var imovel = imovel(id: imovelID) else {
            throw CocoaError(.fileNoSuchFile)
        }
        let plano = FloorPlanBuilder.construir(room)
        let tipo = DetectorComodo.tipo(room, centro: plano.centroRotulo)
        var comodo = Comodo(nome: DetectorComodo.nomeSugerido(tipo, existentes: imovel.comodos))
        comodo.tipo = tipo
        comodo.area = plano.area
        comodo.andar = andar
        comodo.sessao = sessao
        // Cômodos da mesma sessão compartilham o referencial, então o norte também vale para eles.
        comodo.norte = norte ?? imovel.comodos.first { $0.sessao == sessao && $0.norte != nil }?.norte
        comodo.alinhamento = encaixeAutomatico(para: comodo, room: room, em: imovel)
        limparVizinhos(&comodo, room: room, em: imovel)
        try Storage.salvarScan(room, comodoID: comodo.id, imovelID: imovelID)
        if let mapa {
            try? Storage.salvarMapa(mapa, sessao: sessao, imovelID: imovelID)
        }
        if let video {
            let destino = Storage.urlVideo(comodoID: comodo.id, imovelID: imovelID)
            try? FileManager.default.removeItem(at: destino)
            try? FileManager.default.moveItem(at: video, to: destino)
        }
        imovel.comodos.append(comodo)
        atualizar(imovel)
        return comodo
    }

    /// Cômodo de uma sessão nova num andar que já tem cômodos: tenta encaixar pela porta em comum.
    /// Cômodos seguintes da mesma sessão herdam o mesmo encaixe (mesmo referencial).
    private func encaixeAutomatico(para comodo: Comodo, room: CapturedRoom, em imovel: Imovel) -> Alinhamento? {
        let doAndar = imovel.comodos.filter { $0.andarOuPadrao == comodo.andarOuPadrao }
        if let irmao = doAndar.first(where: { $0.chaveSessaoPropria == comodo.chaveSessaoPropria }) {
            return irmao.alinhamento
        }
        guard !doAndar.isEmpty else { return nil }
        let rooms = MontadorPlanta.carregarRooms(doAndar, imovelID: imovel.id)
        let montagem = MontadorPlanta.montar(andar: comodo.andarOuPadrao, comodos: doAndar, rooms: rooms)
        guard let chave = montagem.chavePrincipal else { return nil }
        return Encaixe.porPorta(
            movel: MontadorPlanta.planoBruto(comodo, room: room),
            fixo: montagem.planoPrincipal,
            referencia: chave
        )
    }

    /// Remove do cômodo novo as paredes e objetos que são de cômodos já escaneados no mesmo
    /// referencial (vistos pela porta aberta) e recalcula a área.
    private func limparVizinhos(_ comodo: inout Comodo, room: CapturedRoom, em imovel: Imovel) {
        let vizinhos = imovel.comodos.filter {
            $0.andarOuPadrao == comodo.andarOuPadrao && $0.chaveGrupo == comodo.chaveGrupo
        }
        guard !vizinhos.isEmpty else { return }
        let rooms = MontadorPlanta.carregarRooms(vizinhos, imovelID: imovel.id)
        let existentes: [FloorPlan2D] = vizinhos.compactMap { v in
            guard let r = rooms[v.id] else { return nil }
            var p = MontadorPlanta.planoBruto(v, room: r)
            p.aplicar(v.alinhamento)
            return p
        }
        var novo = MontadorPlanta.planoBruto(comodo, room: room)
        novo.aplicar(comodo.alinhamento)
        let (paredes, objetos) = Encaixe.estranhos(novo: novo, existentes: existentes)
        guard !paredes.isEmpty || !objetos.isEmpty else { return }
        if !paredes.isEmpty { comodo.paredesRemovidas = paredes }
        if !objetos.isEmpty { comodo.objetosRemovidos = objetos }
        comodo.area = FloorPlanBuilder.construir(room, comodo: comodo).area
    }

    func removerParede(id: UUID, comodoID: UUID, imovelID: UUID) {
        alterarComodo(comodoID, imovelID: imovelID) { c in
            c.paredesRemovidas = (c.paredesRemovidas ?? []) + [id]
        }
        recalcularArea(comodoID: comodoID, imovelID: imovelID)
    }

    /// Área do cômodo com as edições (paredes removidas mudam o piso).
    private func recalcularArea(comodoID: UUID, imovelID: UUID) {
        guard let c = imovel(id: imovelID)?.comodos.first(where: { $0.id == comodoID }),
              let room = try? Storage.carregarScan(comodoID: comodoID, imovelID: imovelID) else { return }
        definirArea(FloorPlanBuilder.construir(room, comodo: c).area, comodoID: comodoID, imovelID: imovelID)
    }

    /// Define o encaixe de todos os cômodos de um grupo (mesma sessão) de uma vez.
    func definirAlinhamento(_ alinhamento: Alinhamento?, grupo: String, imovelID: UUID) {
        guard var imovel = imovel(id: imovelID) else { return }
        for i in imovel.comodos.indices where imovel.comodos[i].chaveSessaoPropria == grupo {
            imovel.comodos[i].alinhamento = alinhamento
        }
        atualizar(imovel)
    }

    func atualizarComodo(id: UUID, nome: String, tipo: TipoComodo, andar: Int, imovelID: UUID) {
        alterarComodo(id, imovelID: imovelID) { c in
            c.nome = nome
            c.tipo = tipo
            c.andar = andar
        }
    }

    /// Última sessão de scan que pode ser continuada (tem mapa do ambiente salvo).
    func sessaoParaContinuar(imovelID: UUID) -> (sessao: UUID, comodo: Comodo)? {
        guard let imovel = imovel(id: imovelID) else { return nil }
        for c in imovel.comodos.reversed() {
            if let s = c.sessao, Storage.existeMapa(sessao: s, imovelID: imovelID) {
                return (s, c)
            }
        }
        return nil
    }

    func renomearComodo(id: UUID, para nome: String, imovelID: UUID) {
        guard var imovel = imovel(id: imovelID),
              let i = imovel.comodos.firstIndex(where: { $0.id == id }) else { return }
        imovel.comodos[i].nome = nome
        atualizar(imovel)
    }

    func apagarComodos(ids: [UUID], imovelID: UUID) {
        guard var imovel = imovel(id: imovelID) else { return }
        for id in ids {
            Storage.apagarScan(comodoID: id, imovelID: imovelID)
        }
        imovel.comodos.removeAll { ids.contains($0.id) }
        atualizar(imovel)
    }

    func moverComodo(id: UUID, paraAndar andar: Int, imovelID: UUID) {
        alterarComodo(id, imovelID: imovelID) { $0.andar = andar }
    }

    func renomearObjeto(id: UUID, para nome: String, comodoID: UUID, imovelID: UUID) {
        alterarComodo(comodoID, imovelID: imovelID) { c in
            var nomes = c.nomesObjetos ?? [:]
            nomes[id.uuidString] = nome.isEmpty ? nil : nome
            c.nomesObjetos = nomes
        }
    }

    /// Ajuste manual do norte, em graus.
    func ajustarNorte(_ graus: Double, comodoID: UUID, imovelID: UUID) {
        alterarComodo(comodoID, imovelID: imovelID) { $0.ajusteNorte = graus == 0 ? nil : graus }
    }

    // MARK: Edições da planta

    func definirArea(_ area: Double, comodoID: UUID, imovelID: UUID) {
        guard let atual = imovel(id: imovelID)?.comodos.first(where: { $0.id == comodoID }),
              atual.area.map({ abs($0 - area) > 0.001 }) ?? true else { return }
        alterarComodo(comodoID, imovelID: imovelID) { $0.area = area }
    }

    /// Salva ajustes de uma porta/janela/vão; `nil` volta ao que foi escaneado.
    func salvarEdicao(_ edicao: EdicaoAbertura?, elementoID: UUID, comodoID: UUID, imovelID: UUID) {
        alterarComodo(comodoID, imovelID: imovelID) { c in
            var edicoes = c.edicoes ?? [:]
            edicoes[elementoID.uuidString] = edicao
            c.edicoes = edicoes
        }
    }

    func adicionarAbertura(_ abertura: AberturaManual, comodoID: UUID, imovelID: UUID) {
        alterarComodo(comodoID, imovelID: imovelID) { c in
            c.aberturasManuais = (c.aberturasManuais ?? []) + [abertura]
        }
    }

    func removerAberturaManual(id: UUID, comodoID: UUID, imovelID: UUID) {
        alterarComodo(comodoID, imovelID: imovelID) { c in
            c.aberturasManuais?.removeAll { $0.id == id }
            c.edicoes?[id.uuidString] = nil
        }
    }

    func removerObjeto(id: UUID, comodoID: UUID, imovelID: UUID) {
        alterarComodo(comodoID, imovelID: imovelID) { c in
            c.objetosRemovidos = (c.objetosRemovidos ?? []) + [id]
        }
    }

    func restaurarRemovidos(comodoID: UUID, imovelID: UUID) {
        defer { recalcularArea(comodoID: comodoID, imovelID: imovelID) }
        alterarComodo(comodoID, imovelID: imovelID) { c in
            c.objetosRemovidos = nil
            c.paredesRemovidas = nil
            if var edicoes = c.edicoes {
                for (chave, e) in edicoes where e.removido == true {
                    edicoes[chave]?.removido = nil
                }
                c.edicoes = edicoes
            }
        }
    }

    private func alterarComodo(_ comodoID: UUID, imovelID: UUID, _ mudanca: (inout Comodo) -> Void) {
        guard var imovel = imovel(id: imovelID),
              let i = imovel.comodos.firstIndex(where: { $0.id == comodoID }) else { return }
        mudanca(&imovel.comodos[i])
        atualizar(imovel)
    }

    private func persistir(_ imovel: Imovel) {
        do {
            try Storage.salvar(imovel)
        } catch {
            mensagemErro = "Não foi possível salvar: \(error.localizedDescription)"
        }
    }
}
