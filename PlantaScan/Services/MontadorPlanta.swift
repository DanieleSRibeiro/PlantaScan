import CoreGraphics
import Foundation
import RoomPlan

/// Planta de um andar montada a partir dos cômodos.
struct MontagemAndar {
    var andar: Int
    var plano: FloorPlan2D
    var norte: Double?
    /// Há cômodos de sessões diferentes (postos lado a lado, sem alinhamento real).
    var separados: Bool
    var comodos: [Comodo]
    /// Planta de cada cômodo (com edições), para tabelas e totais.
    var planosPorComodo: [UUID: FloorPlan2D]
}

enum MontadorPlanta {
    static func carregarRooms(_ comodos: [Comodo], imovelID: UUID) -> [UUID: CapturedRoom] {
        var r: [UUID: CapturedRoom] = [:]
        for c in comodos {
            if let room = try? Storage.carregarScan(comodoID: c.id, imovelID: imovelID) {
                r[c.id] = room
            }
        }
        return r
    }

    /// Junta os cômodos da mesma sessão (mesmo referencial); sessões diferentes ficam lado a lado.
    static func montar(andar: Int, comodos todos: [Comodo], rooms: [UUID: CapturedRoom]) -> MontagemAndar {
        let comodos = todos.filter { $0.andarOuPadrao == andar }
        var ordem: [String] = []
        var grupos: [String: [FloorPlan2D]] = [:]
        var planosPorComodo: [UUID: FloorPlan2D] = [:]
        var norte: Double?

        for c in comodos {
            guard let room = rooms[c.id] else { continue }
            var p = FloorPlanBuilder.construir(room, comodo: c)
            p.rotulos = [RotuloComodo(ponto: p.centroRotulo, nome: c.nome, area: p.area)]
            planosPorComodo[c.id] = p
            let chave = c.sessao?.uuidString ?? c.id.uuidString
            if grupos[chave] == nil {
                ordem.append(chave)
            }
            // O norte vale para o primeiro grupo (os outros podem estar em outro referencial).
            if ordem.first == chave, norte == nil {
                norte = c.anguloNorte
            }
            grupos[chave, default: []].append(p)
        }

        var partes: [FloorPlan2D] = []
        var proximoX: CGFloat = 0
        for chave in ordem {
            var g = FloorPlan2D.combinar(grupos[chave] ?? [])
            if !partes.isEmpty {
                g.deslocar(CGVector(dx: proximoX - g.limites.minX, dy: 0))
            }
            proximoX = g.limites.maxX + 1.5
            partes.append(g)
        }

        return MontagemAndar(
            andar: andar,
            plano: FloorPlan2D.combinar(partes),
            norte: norte,
            separados: ordem.count > 1,
            comodos: comodos,
            planosPorComodo: planosPorComodo
        )
    }
}
