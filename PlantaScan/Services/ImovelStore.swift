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
        let comodo = Comodo(nome: nome)
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

    private func persistir(_ imovel: Imovel) {
        do {
            try Storage.salvar(imovel)
        } catch {
            mensagemErro = "Não foi possível salvar: \(error.localizedDescription)"
        }
    }
}
