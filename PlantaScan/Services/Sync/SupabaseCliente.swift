import Foundation
import Security

/// Sessão do usuário no Supabase (guardada no Keychain).
struct SessaoSupabase: Codable {
    var accessToken: String
    var refreshToken: String
    var expiraEm: Date
    var userID: String
    var email: String
}

enum ErroSupabase: LocalizedError {
    case naoLogado
    case confirmarEmail
    case servidor(String)

    var errorDescription: String? {
        switch self {
        case .naoLogado: return "Entre na sua conta para sincronizar."
        case .confirmarEmail: return "Conta criada. Confirme o e-mail e depois entre."
        case .servidor(let msg): return msg
        }
    }
}

/// Cliente mínimo da API REST do Supabase (auth, banco e storage) usando só URLSession.
@MainActor
final class SupabaseCliente {
    private(set) var sessao: SessaoSupabase?
    private let contaChaveiro = "sessao-supabase"

    var logado: Bool { sessao != nil }
    var email: String? { sessao?.email }
    var userID: String? { sessao?.userID.lowercased() }

    init() {
        if let data = Chaveiro.ler(conta: contaChaveiro) {
            sessao = try? JSONDecoder().decode(SessaoSupabase.self, from: data)
        }
    }

    // MARK: Autenticação

    func entrar(email: String, senha: String) async throws {
        let corpo = try JSONSerialization.data(withJSONObject: ["email": email, "password": senha])
        let data = try await chamar("POST", "auth/v1/token", query: [URLQueryItem(name: "grant_type", value: "password")], corpo: corpo, autenticado: false)
        try guardarSessao(data, email: email)
    }

    func cadastrar(email: String, senha: String) async throws {
        let corpo = try JSONSerialization.data(withJSONObject: ["email": email, "password": senha])
        let data = try await chamar("POST", "auth/v1/signup", corpo: corpo, autenticado: false)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        guard json?["access_token"] != nil else { throw ErroSupabase.confirmarEmail }
        try guardarSessao(data, email: email)
    }

    func sair() {
        sessao = nil
        Chaveiro.apagar(conta: contaChaveiro)
    }

    private func guardarSessao(_ data: Data, email: String) throws {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let access = json["access_token"] as? String,
              let refresh = json["refresh_token"] as? String else {
            throw ErroSupabase.servidor("Resposta de login inválida.")
        }
        let expira = (json["expires_in"] as? Double) ?? 3600
        let usuario = json["user"] as? [String: Any]
        let id = (usuario?["id"] as? String) ?? sessao?.userID ?? ""
        let mail = (usuario?["email"] as? String) ?? email
        let nova = SessaoSupabase(accessToken: access, refreshToken: refresh,
                                  expiraEm: Date().addingTimeInterval(expira), userID: id, email: mail)
        sessao = nova
        if let dados = try? JSONEncoder().encode(nova) {
            Chaveiro.salvar(dados, conta: contaChaveiro)
        }
    }

    private func tokenValido() async throws -> String {
        guard let s = sessao else { throw ErroSupabase.naoLogado }
        if s.expiraEm.timeIntervalSinceNow > 60 { return s.accessToken }
        let corpo = try JSONSerialization.data(withJSONObject: ["refresh_token": s.refreshToken])
        do {
            let data = try await chamar("POST", "auth/v1/token", query: [URLQueryItem(name: "grant_type", value: "refresh_token")], corpo: corpo, autenticado: false)
            try guardarSessao(data, email: s.email)
        } catch {
            sair()
            throw ErroSupabase.naoLogado
        }
        return sessao?.accessToken ?? ""
    }

    // MARK: Banco (PostgREST)

    func selecionar(_ tabela: String, query: [URLQueryItem]) async throws -> [[String: Any]] {
        let data = try await chamar("GET", "rest/v1/\(tabela)", query: query)
        return (try JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? []
    }

    func upsert(_ tabela: String, linhas: [[String: Any]]) async throws {
        guard !linhas.isEmpty else { return }
        let corpo = try JSONSerialization.data(withJSONObject: linhas)
        _ = try await chamar("POST", "rest/v1/\(tabela)", query: [URLQueryItem(name: "on_conflict", value: "id")], corpo: corpo,
                             cabecalhos: ["Prefer": "resolution=merge-duplicates,return=minimal"])
    }

    func atualizar(_ tabela: String, id: UUID, campos: [String: Any]) async throws {
        let corpo = try JSONSerialization.data(withJSONObject: campos)
        _ = try await chamar("PATCH", "rest/v1/\(tabela)", query: [URLQueryItem(name: "id", value: "eq.\(id.uuidString.lowercased())")],
                             corpo: corpo, cabecalhos: ["Prefer": "return=minimal"])
    }

    // MARK: Storage

    func enviarArquivo(_ data: Data, caminho: String, tipo: String) async throws {
        _ = try await chamar("POST", "storage/v1/object/\(SupabaseConfig.bucket)/\(caminho)", corpo: data,
                             cabecalhos: ["Content-Type": tipo, "x-upsert": "true"])
    }

    func baixarArquivo(caminho: String) async throws -> Data {
        try await chamar("GET", "storage/v1/object/authenticated/\(SupabaseConfig.bucket)/\(caminho)")
    }

    // MARK: HTTP

    private func chamar(
        _ metodo: String,
        _ caminho: String,
        query: [URLQueryItem] = [],
        corpo: Data? = nil,
        cabecalhos: [String: String] = [:],
        autenticado: Bool = true
    ) async throws -> Data {
        var componentes = URLComponents(url: SupabaseConfig.url.appendingPathComponent(caminho), resolvingAgainstBaseURL: false)
        if !query.isEmpty {
            componentes?.queryItems = query
            // "+" do fuso horário precisa ser codificado para o PostgREST.
            componentes?.percentEncodedQuery = componentes?.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        }
        guard let url = componentes?.url else { throw ErroSupabase.servidor("URL inválida.") }

        var req = URLRequest(url: url)
        req.httpMethod = metodo
        req.httpBody = corpo
        req.timeoutInterval = 60
        req.setValue(SupabaseConfig.chavePublica, forHTTPHeaderField: "apikey")
        if corpo != nil {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        for (k, v) in cabecalhos {
            req.setValue(v, forHTTPHeaderField: k)
        }
        if autenticado {
            req.setValue("Bearer \(try await tokenValido())", forHTTPHeaderField: "Authorization")
        }

        let (data, resposta) = try await URLSession.shared.data(for: req)
        let status = (resposta as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let msg = (json?["error_description"] as? String)
                ?? (json?["msg"] as? String)
                ?? (json?["message"] as? String)
                ?? (json?["error"] as? String)
                ?? "Erro \(status) no servidor."
            throw ErroSupabase.servidor(traduzir(msg))
        }
        return data
    }

    private func traduzir(_ msg: String) -> String {
        switch msg {
        case "Invalid login credentials": return "E-mail ou senha incorretos."
        case "User already registered": return "Este e-mail já tem conta. Use \"Entrar\"."
        case "Email not confirmed": return "Confirme o e-mail antes de entrar."
        default: return msg
        }
    }
}

/// Acesso simples ao Keychain (senhas genéricas).
enum Chaveiro {
    private static let servico = "com.dribeiro.plantascan"

    static func salvar(_ dados: Data, conta: String) {
        apagar(conta: conta)
        let item: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: servico,
            kSecAttrAccount as String: conta,
            kSecValueData as String: dados,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        SecItemAdd(item as CFDictionary, nil)
    }

    static func ler(conta: String) -> Data? {
        let consulta: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: servico,
            kSecAttrAccount as String: conta,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var resultado: CFTypeRef?
        guard SecItemCopyMatching(consulta as CFDictionary, &resultado) == errSecSuccess else { return nil }
        return resultado as? Data
    }

    static func apagar(conta: String) {
        let consulta: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: servico,
            kSecAttrAccount as String: conta,
        ]
        SecItemDelete(consulta as CFDictionary)
    }
}
