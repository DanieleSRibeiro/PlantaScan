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
        imoveis = Storage.carregarImoveis().sorted { $0.dataCriacao > $1.dataCriacao }
    }

    func imovel(id: UUID) -> Imovel? {
        imoveis.first { $0.id == id }
    }

    // MARK: Imóveis

    @discardableResult
    func criarImovel(nome: String, endereco: String) -> Imovel {
        let novo = Imovel(nome: nome, endereco: endereco)
        imoveis.insert(novo, at: 0)
        persistir(novo)
        return novo
    }

    func atualizar(_ imovel: Imovel) {
        guard let i = imoveis.firstIndex(where: { $0.id == imovel.id }) else { return }
        imoveis[i] = imovel
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

    func adicionarComodo(nome: String, room: CapturedRoom, imovelID: UUID) throws {
        guard var imovel = imovel(id: imovelID) else { return }
        var comodo = Comodo(nome: nome)
        comodo.area = FloorPlanBuilder.construir(room).area
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

    func apagarComodos(at offsets: IndexSet, imovelID: UUID) {
        guard var imovel = imovel(id: imovelID) else { return }
        for i in offsets.sorted(by: >) {
            Storage.apagarScan(comodoID: imovel.comodos[i].id, imovelID: imovelID)
            imovel.comodos.remove(at: i)
        }
        atualizar(imovel)
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
