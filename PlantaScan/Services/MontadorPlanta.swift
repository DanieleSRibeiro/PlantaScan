import CoreGraphics
import Foundation
import RoomPlan

/// Planta de um andar montada a partir dos cômodos.
struct MontagemAndar {
    var andar: Int
    var plano: FloorPlan2D
    var norte: Double?
    /// Há grupos não encaixados (postos lado a lado, sem a posição real).
    var separados: Bool
    var comodos: [Comodo]
    /// Planta de cada cômodo (com edições), na posição em que aparece no desenho.
    var planosPorComodo: [UUID: FloorPlan2D]
    /// Grupo de referência (o primeiro escaneado) e a sua planta.
    var chavePrincipal: String?
    var planoPrincipal: FloorPlan2D
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

    /// Planta de um cômodo com edições e rótulo, antes de qualquer encaixe.
    static func planoBruto(_ c: Comodo, room: CapturedRoom) -> FloorPlan2D {
        var p = FloorPlanBuilder.construir(room, comodo: c)
        p.rotulos = [RotuloComodo(ponto: p.centroRotulo, nome: c.nome, area: p.area)]
        return p
    }

    /// Junta os cômodos por grupo (mesma sessão ou encaixados); grupos soltos ficam lado a lado.
    static func montar(andar: Int, comodos todos: [Comodo], rooms: [UUID: CapturedRoom]) -> MontagemAndar {
        let comodos = todos.filter { $0.andarOuPadrao == andar }
        var ordem: [String] = []
        var grupos: [String: [UUID]] = [:]
        var planos: [UUID: FloorPlan2D] = [:]
        var norte: Double?

        for c in comodos {
            guard let room = rooms[c.id] else { continue }
            var p = planoBruto(c, room: room)
            p.aplicar(c.alinhamento)
            planos[c.id] = p
            let chave = c.chaveGrupo
            if grupos[chave] == nil {
                ordem.append(chave)
            }
            grupos[chave, default: []].append(c.id)
        }
        // O norte vale para o grupo principal (cômodos dele que não foram girados).
        let chavePrincipal = ordem.first
        if let chavePrincipal {
            norte = comodos.first { $0.chaveGrupo == chavePrincipal && $0.alinhamento == nil && $0.anguloNorte != nil }?.anguloNorte
        }

        var partes: [FloorPlan2D] = []
        var principal = FloorPlan2D()
        var proximoX: CGFloat = 0
        for chave in ordem {
            let ids = grupos[chave] ?? []
            var g = FloorPlan2D.combinar(ids.compactMap { planos[$0] })
            if partes.isEmpty {
                principal = g
            } else {
                let d = CGVector(dx: proximoX - g.limites.minX, dy: 0)
                g.deslocar(d)
                for id in ids {
                    planos[id]?.deslocar(d)
                }
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
            planosPorComodo: planos,
            chavePrincipal: chavePrincipal,
            planoPrincipal: principal
        )
    }
}
