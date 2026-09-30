import Foundation
import RoomPlan

/// Persistência em arquivos: Documents/Imoveis/<imovelID>/
///   imovel.json          – metadados do imóvel e lista de cômodos
///   <comodoID>.json      – CapturedRoom (Codable)
///   <comodoID>.usdz      – modelo 3D paramétrico
enum Storage {
    private static var fm: FileManager { .default }

    static var raiz: URL {
        fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Imoveis", isDirectory: true)
    }

    static func pasta(imovelID: UUID) -> URL {
        raiz.appendingPathComponent(imovelID.uuidString, isDirectory: true)
    }

    static func urlImovel(_ imovelID: UUID) -> URL {
        pasta(imovelID: imovelID).appendingPathComponent("imovel.json")
    }

    static func urlScan(comodoID: UUID, imovelID: UUID) -> URL {
        pasta(imovelID: imovelID).appendingPathComponent("\(comodoID.uuidString).json")
    }

    static func urlModelo(comodoID: UUID, imovelID: UUID) -> URL {
        pasta(imovelID: imovelID).appendingPathComponent("\(comodoID.uuidString).usdz")
    }

    private static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }

    private static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    // MARK: Imóveis

    static func carregarImoveis() -> [Imovel] {
        guard let pastas = try? fm.contentsOfDirectory(at: raiz, includingPropertiesForKeys: nil) else {
            return []
        }
        let dec = decoder()
        return pastas.compactMap { pasta in
            guard let data = try? Data(contentsOf: pasta.appendingPathComponent("imovel.json")) else { return nil }
            return try? dec.decode(Imovel.self, from: data)
        }
    }

    static func salvar(_ imovel: Imovel) throws {
        try fm.createDirectory(at: pasta(imovelID: imovel.id), withIntermediateDirectories: true)
        let data = try encoder().encode(imovel)
        try data.write(to: urlImovel(imovel.id), options: .atomic)
    }

    static func apagar(imovelID: UUID) throws {
        let p = pasta(imovelID: imovelID)
        if fm.fileExists(atPath: p.path) {
            try fm.removeItem(at: p)
        }
    }

    // MARK: Scans

    static func salvarScan(_ room: CapturedRoom, comodoID: UUID, imovelID: UUID) throws {
        try fm.createDirectory(at: pasta(imovelID: imovelID), withIntermediateDirectories: true)

        let data = try JSONEncoder().encode(room)
        try data.write(to: urlScan(comodoID: comodoID, imovelID: imovelID), options: .atomic)

        let usdz = urlModelo(comodoID: comodoID, imovelID: imovelID)
        if fm.fileExists(atPath: usdz.path) {
            try fm.removeItem(at: usdz)
        }
        try room.export(to: usdz, exportOptions: .parametric)
    }

    static func carregarScan(comodoID: UUID, imovelID: UUID) throws -> CapturedRoom {
        let data = try Data(contentsOf: urlScan(comodoID: comodoID, imovelID: imovelID))
        return try JSONDecoder().decode(CapturedRoom.self, from: data)
    }

    static func apagarScan(comodoID: UUID, imovelID: UUID) {
        try? fm.removeItem(at: urlScan(comodoID: comodoID, imovelID: imovelID))
        try? fm.removeItem(at: urlModelo(comodoID: comodoID, imovelID: imovelID))
    }
}
