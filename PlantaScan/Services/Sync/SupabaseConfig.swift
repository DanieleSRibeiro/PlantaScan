import Foundation

/// Backend do site PlantaScan Web (Lovable Cloud / Supabase).
/// A chave pública ("publishable/anon") pode ficar no app: o acesso aos dados é protegido
/// pelas regras de segurança (RLS) do banco — cada usuário só vê os próprios imóveis.
enum SupabaseConfig {
    static let url = URL(string: "https://configurar.supabase.co")!
    static let chavePublica = ""
    static let bucket = "plantascan"
    /// Endereço do site para abrir no computador.
    static let site = URL(string: "https://id-preview--109a893c-077e-4b38-9974-a0300726fd09.lovable.app")!

    static var configurado: Bool { !chavePublica.isEmpty }
}
