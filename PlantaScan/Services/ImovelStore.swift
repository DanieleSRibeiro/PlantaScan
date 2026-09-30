import ARKit
import Foundation
import Observation
import RoomPlan

@Observable
final class ImovelStore {
    var imoveis: [Imovel] = []
    var mensagemErro: String?

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
            importados += 1
        }
        ordenar()
        return (importados, ignorados)
    }

    func atualizar(_ imovel: Imovel) {
        guard let i = imoveis.firstIndex(where: { $0.id == imovel.id }) else { return }
        let renomeado = imoveis[i].nome != imovel.nome
        imoveis[i] = imovel
        if renomeado { ordenar() }
        persistir(imovel)
    }

    func apagarImovel(id: UUID) {
        do {
            try Storage.apagar(imovelID: id)
            imoveis.removeAll { $0.id == id }
        } catch {
            mensagemErro = "Não foi possível apagar o imóvel: \(error.localizedDescription)"
        }
    }

    // MARK: Cômodos

    /// Salva um cômodo escaneado, identificando o tipo e dando um nome automático ("Quarto 1").
    @discardableResult
    func adicionarComodo(room: CapturedRoom, imovelID: UUID, andar: Int, norte: Double?, sessao: UUID, mapa: ARWorldMap?) throws -> Comodo {
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
        try Storage.salvarScan(room, comodoID: comodo.id, imovelID: imovelID)
        if let mapa {
            try? Storage.salvarMapa(mapa, sessao: sessao, imovelID: imovelID)
        }
        imovel.comodos.append(comodo)
        atualizar(imovel)
        return comodo
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
        alterarComodo(comodoID, imovelID: imovelID) { c in
            c.objetosRemovidos = nil
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
