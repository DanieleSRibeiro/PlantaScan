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

    func adicionarComodo(nome: String, room: CapturedRoom, imovelID: UUID, andar: Int, norte: Double?) throws {
        guard var imovel = imovel(id: imovelID) else { return }
        var comodo = Comodo(nome: nome)
        comodo.area = FloorPlanBuilder.construir(room).area
        comodo.andar = andar
        comodo.norte = norte
        try Storage.salvarScan(room, comodoID: comodo.id, imovelID: imovelID)
        imovel.comodos.append(comodo)
        atualizar(imovel)
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
