import Compression
import Foundation

struct ImovelImportado {
    var nome: String
    var endereco: String
    var eircode: String
}

enum ErroImportacao: LocalizedError {
    case arquivoIlegivel
    case planilhaVazia

    var errorDescription: String? {
        switch self {
        case .arquivoIlegivel: return "Não foi possível ler o arquivo. Use CSV ou Excel (.xlsx)."
        case .planilhaVazia: return "A planilha está vazia ou não tem linhas reconhecíveis."
        }
    }
}

/// Lê CSV (vírgula, ponto e vírgula ou tab) e Excel .xlsx e reconhece as colunas pelo cabeçalho.
enum ImportadorPlanilha {
    static func ler(url: URL) throws -> [ImovelImportado] {
        let acessou = url.startAccessingSecurityScopedResource()
        defer { if acessou { url.stopAccessingSecurityScopedResource() } }

        let data = try Data(contentsOf: url)
        let linhas: [[String]]
        if url.pathExtension.lowercased() == "xlsx" || data.starts(with: [0x50, 0x4B, 0x03, 0x04]) {
            linhas = try LeitorXLSX.linhas(de: data)
        } else {
            guard let texto = String(data: data, encoding: .utf8)
                    ?? String(data: data, encoding: .windowsCP1252)
                    ?? String(data: data, encoding: .isoLatin1) else {
                throw ErroImportacao.arquivoIlegivel
            }
            linhas = LeitorCSV.linhas(de: texto)
        }
        let itens = mapear(linhas)
        if itens.isEmpty { throw ErroImportacao.planilhaVazia }
        return itens
    }

    // MARK: Colunas

    private static func normalizar(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "pt_BR"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let chavesEircode = ["eircode", "eir code", "postcode", "post code", "postal", "cep", "zip"]
    private static let chavesEndereco = ["endereco", "address", "morada", "rua", "street", "linha", "line", "cidade", "city",
                                         "town", "county", "condado", "bairro", "locality", "localidade", "estado", "country", "pais"]
    private static let chavesNome = ["nome", "name", "casa", "house", "imovel", "property", "propriedade", "titulo", "title"]

    static func mapear(_ linhasBrutas: [[String]]) -> [ImovelImportado] {
        let linhas = linhasBrutas
            .map { $0.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) } }
            .filter { $0.contains { !$0.isEmpty } }
        guard let cabecalho = linhas.first else { return [] }

        var colNome: Int?
        var colEircode: Int?
        var colsEndereco: [Int] = []
        for (i, bruto) in cabecalho.enumerated() {
            let k = normalizar(bruto)
            if colEircode == nil, chavesEircode.contains(where: { k.contains($0) }) {
                colEircode = i
            } else if chavesEndereco.contains(where: { k.contains($0) }) {
                colsEndereco.append(i)
            } else if colNome == nil, chavesNome.contains(where: { k.contains($0) }) {
                colNome = i
            }
        }

        let temCabecalho = colNome != nil || colEircode != nil || !colsEndereco.isEmpty
        if !temCabecalho {
            // Sem cabeçalho: nome, endereço, eircode.
            colNome = 0
            if cabecalho.count > 1 { colsEndereco = [1] }
            if cabecalho.count > 2 { colEircode = 2 }
        }

        let dados = temCabecalho ? Array(linhas.dropFirst()) : linhas
        return dados.compactMap { (linha: [String]) -> ImovelImportado? in
            func valor(_ i: Int?) -> String {
                guard let i, i < linha.count else { return "" }
                return linha[i]
            }
            let endereco = colsEndereco.map { valor($0) }.filter { !$0.isEmpty }.joined(separator: ", ")
            var eircode = formatarEircode(valor(colEircode))
            if eircode.isEmpty, let achado = extrairEircode(endereco) {
                eircode = achado
            }
            var nome = valor(colNome)
            if nome.isEmpty {
                nome = endereco.components(separatedBy: ",").first?.trimmingCharacters(in: .whitespaces) ?? ""
            }
            guard !nome.isEmpty else { return nil }
            return ImovelImportado(nome: nome, endereco: endereco, eircode: eircode)
        }
    }

    // MARK: Eircode

    private static let regexEircode = try? NSRegularExpression(
        pattern: "\\b(?:[AC-FHKNPRTV-Y][0-9]{2}|D6W)\\s?[0-9AC-FHKNPRTV-Y]{4}\\b",
        options: [.caseInsensitive]
    )

    static func extrairEircode(_ texto: String) -> String? {
        guard let regex = regexEircode,
              let m = regex.firstMatch(in: texto, range: NSRange(texto.startIndex..., in: texto)),
              let r = Range(m.range, in: texto) else { return nil }
        return formatarEircode(String(texto[r]))
    }

    /// "d02x285" → "D02 X285".
    static func formatarEircode(_ s: String) -> String {
        let limpo = s.uppercased().filter { !$0.isWhitespace }
        guard limpo.count == 7 else { return s.uppercased().trimmingCharacters(in: .whitespaces) }
        return "\(limpo.prefix(3)) \(limpo.suffix(4))"
    }
}

// MARK: - CSV

enum LeitorCSV {
    static func linhas(de textoOriginal: String) -> [[String]] {
        var texto = textoOriginal
        if texto.hasPrefix("\u{FEFF}") { texto.removeFirst() }

        let primeira = texto.prefix { $0 != "\n" && $0 != "\r" && $0 != "\r\n" }
        let candidatos: [Character] = [",", ";", "\t"]
        var separador: Character = ","
        var melhor = 0
        for c in candidatos {
            let n = primeira.filter { $0 == c }.count
            if n > melhor {
                melhor = n
                separador = c
            }
        }

        var linhas: [[String]] = []
        var linha: [String] = []
        var campo = ""
        var aspas = false
        let chars = Array(texto)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if aspas {
                if c == "\"" {
                    if i + 1 < chars.count && chars[i + 1] == "\"" {
                        campo.append("\"")
                        i += 1
                    } else {
                        aspas = false
                    }
                } else {
                    campo.append(c)
                }
            } else if c == "\"" {
                aspas = true
            } else if c == separador {
                linha.append(campo)
                campo = ""
            } else if c == "\n" || c == "\r" || c == "\r\n" {
                linha.append(campo)
                campo = ""
                linhas.append(linha)
                linha = []
            } else {
                campo.append(c)
            }
            i += 1
        }
        if !campo.isEmpty || !linha.isEmpty {
            linha.append(campo)
            linhas.append(linha)
        }
        return linhas
    }
}

// MARK: - XLSX (zip + XML, sem dependências)

enum LeitorXLSX {
    static func linhas(de data: Data) throws -> [[String]] {
        let zip = try LeitorZip(data)
        let compartilhadas = zip.arquivo("xl/sharedStrings.xml").map { ParserTextosCompartilhados.ler($0) } ?? []
        let planilhas = zip.nomes
            .filter { $0.hasPrefix("xl/worksheets/sheet") && $0.hasSuffix(".xml") }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        guard let nome = planilhas.first, let xml = zip.arquivo(nome) else {
            throw ErroImportacao.planilhaVazia
        }
        return ParserPlanilha.ler(xml, compartilhadas: compartilhadas)
    }
}

struct LeitorZip {
    private struct Entrada {
        let metodo: UInt16
        let tamanhoComprimido: Int
        let tamanho: Int
        let offset: Int
    }

    private let bytes: [UInt8]
    private var entradas: [String: Entrada] = [:]

    var nomes: [String] { Array(entradas.keys) }

    init(_ data: Data) throws {
        bytes = [UInt8](data)
        guard bytes.count >= 22 else { throw ErroImportacao.arquivoIlegivel }

        // Registro "End of Central Directory".
        var eocd = -1
        var i = bytes.count - 22
        let limite = max(0, bytes.count - 22 - 65_535)
        while i >= limite {
            if u32(i) == 0x0605_4b50 {
                eocd = i
                break
            }
            i -= 1
        }
        guard eocd >= 0 else { throw ErroImportacao.arquivoIlegivel }

        let total = Int(u16(eocd + 10))
        var p = Int(u32(eocd + 16))
        for _ in 0..<total {
            guard p + 46 <= bytes.count, u32(p) == 0x0201_4b50 else { break }
            let n = Int(u16(p + 28))
            let extra = Int(u16(p + 30))
            let comentario = Int(u16(p + 32))
            guard p + 46 + n <= bytes.count else { break }
            let nome = String(decoding: bytes[(p + 46)..<(p + 46 + n)], as: UTF8.self)
            entradas[nome] = Entrada(
                metodo: u16(p + 10),
                tamanhoComprimido: Int(u32(p + 20)),
                tamanho: Int(u32(p + 24)),
                offset: Int(u32(p + 42))
            )
            p += 46 + n + extra + comentario
        }
    }

    func arquivo(_ nome: String) -> Data? {
        guard let e = entradas[nome] else { return nil }
        let o = e.offset
        guard o + 30 <= bytes.count, u32(o) == 0x0403_4b50 else { return nil }
        let inicio = o + 30 + Int(u16(o + 26)) + Int(u16(o + 28))
        guard inicio + e.tamanhoComprimido <= bytes.count else { return nil }
        let bruto = Array(bytes[inicio..<(inicio + e.tamanhoComprimido)])
        switch e.metodo {
        case 0: return Data(bruto)
        case 8: return inflar(bruto, tamanho: e.tamanho)
        default: return nil
        }
    }

    /// Descompacta DEFLATE bruto (o COMPRESSION_ZLIB da Apple é DEFLATE sem cabeçalho).
    private func inflar(_ origem: [UInt8], tamanho: Int) -> Data? {
        guard tamanho > 0, !origem.isEmpty else { return Data() }
        var destino = [UInt8](repeating: 0, count: tamanho)
        let n = destino.withUnsafeMutableBufferPointer { d in
            origem.withUnsafeBufferPointer { s in
                compression_decode_buffer(d.baseAddress!, tamanho, s.baseAddress!, s.count, nil, COMPRESSION_ZLIB)
            }
        }
        return n > 0 ? Data(destino[0..<n]) : nil
    }

    private func u16(_ o: Int) -> UInt16 {
        let b0 = UInt16(bytes[o])
        let b1 = UInt16(bytes[o + 1])
        return b0 | (b1 << 8)
    }

    private func u32(_ o: Int) -> UInt32 {
        let b0 = UInt32(bytes[o])
        let b1 = UInt32(bytes[o + 1]) << 8
        let b2 = UInt32(bytes[o + 2]) << 16
        let b3 = UInt32(bytes[o + 3]) << 24
        return b0 | b1 | b2 | b3
    }
}

private func nomeLocal(_ elemento: String) -> String {
    elemento.split(separator: ":").last.map(String.init) ?? elemento
}

final class ParserTextosCompartilhados: NSObject, XMLParserDelegate {
    private var textos: [String] = []
    private var atual = ""
    private var dentroSI = false
    private var dentroT = false
    private var dentroFonetica = false

    static func ler(_ data: Data) -> [String] {
        let delegado = ParserTextosCompartilhados()
        let parser = XMLParser(data: data)
        parser.delegate = delegado
        parser.parse()
        return delegado.textos
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        switch nomeLocal(elementName) {
        case "si": dentroSI = true; atual = ""
        case "t": dentroT = true
        case "rPh": dentroFonetica = true
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if dentroSI && dentroT && !dentroFonetica { atual += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        switch nomeLocal(elementName) {
        case "si": textos.append(atual); dentroSI = false
        case "t": dentroT = false
        case "rPh": dentroFonetica = false
        default: break
        }
    }
}

final class ParserPlanilha: NSObject, XMLParserDelegate {
    private let compartilhadas: [String]
    private var celulas: [Int: [Int: String]] = [:]
    private var linhaAtual = 1
    private var proximaLinha = 1
    private var colunaAtual = 0
    private var proximaColuna = 0
    private var tipoAtual = ""
    private var valor = ""
    private var capturando = false

    private init(compartilhadas: [String]) {
        self.compartilhadas = compartilhadas
    }

    static func ler(_ data: Data, compartilhadas: [String]) -> [[String]] {
        let delegado = ParserPlanilha(compartilhadas: compartilhadas)
        let parser = XMLParser(data: data)
        parser.delegate = delegado
        parser.parse()
        return delegado.resultado()
    }

    private func resultado() -> [[String]] {
        celulas.keys.sorted().map { l in
            let linha = celulas[l] ?? [:]
            let maxCol = linha.keys.max() ?? -1
            guard maxCol >= 0 else { return [] }
            return (0...maxCol).map { linha[$0] ?? "" }
        }
    }

    /// "C12" → 2
    private func coluna(_ ref: String) -> Int {
        var n = 0
        for ch in ref.uppercased() {
            guard let a = ch.asciiValue, a >= 65, a <= 90 else { break }
            n = n * 26 + Int(a - 64)
        }
        return max(n - 1, 0)
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        switch nomeLocal(elementName) {
        case "row":
            linhaAtual = attributeDict["r"].flatMap { Int($0) } ?? proximaLinha
            proximaLinha = linhaAtual + 1
            proximaColuna = 0
        case "c":
            colunaAtual = attributeDict["r"].map { coluna($0) } ?? proximaColuna
            proximaColuna = colunaAtual + 1
            tipoAtual = attributeDict["t"] ?? ""
            valor = ""
        case "v", "t":
            capturando = true
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if capturando { valor += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        switch nomeLocal(elementName) {
        case "v", "t":
            capturando = false
        case "c":
            var texto = valor
            if tipoAtual == "s", let i = Int(valor.trimmingCharacters(in: .whitespaces)), i >= 0, i < compartilhadas.count {
                texto = compartilhadas[i]
            }
            if !texto.isEmpty {
                celulas[linhaAtual, default: [:]][colunaAtual] = texto
            }
        default:
            break
        }
    }
}
