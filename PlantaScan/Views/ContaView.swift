import SwiftUI

/// Login e status da sincronização com o site (Lovable/Supabase).
struct ContaView: View {
    @Environment(Sincronizador.self) private var sinc
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var senha = ""
    @State private var criarConta = false
    @State private var enviando = false
    @State private var erro: String?

    var body: some View {
        NavigationStack {
            Form {
                if sinc.logado {
                    logadoView
                } else {
                    loginView
                }
            }
            .navigationTitle("Conta e sincronização")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fechar") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private var loginView: some View {
        Section {
            TextField("E-mail", text: $email)
                .keyboardType(.emailAddress)
                .textContentType(.username)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            SecureField("Senha", text: $senha)
                .textContentType(criarConta ? .newPassword : .password)
            Picker("", selection: $criarConta) {
                Text("Entrar").tag(false)
                Text("Criar conta").tag(true)
            }
            .pickerStyle(.segmented)
        } footer: {
            Text("Use a mesma conta no site do PlantaScan. Os imóveis e plantas passam a ser sincronizados automaticamente entre o iPhone e o computador.")
        }

        if let erro {
            Section {
                Label(erro, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
            }
        }

        Section {
            Button {
                Task { await entrar() }
            } label: {
                HStack {
                    Spacer()
                    if enviando {
                        ProgressView()
                    } else {
                        Text(criarConta ? "Criar conta" : "Entrar").fontWeight(.semibold)
                    }
                    Spacer()
                }
            }
            .disabled(enviando || email.isEmpty || senha.count < 6)
        } footer: {
            if criarConta {
                Text("A senha precisa ter pelo menos 6 caracteres.")
            }
        }
    }

    @ViewBuilder
    private var logadoView: some View {
        Section("Conta") {
            LabeledContent("E-mail", value: sinc.email ?? "—")
        }

        Section("Sincronização") {
            LabeledContent("Situação") {
                if sinc.sincronizando {
                    HStack(spacing: 6) {
                        ProgressView()
                        Text("Sincronizando…")
                    }
                } else if sinc.pendencias > 0 {
                    Text("\(sinc.pendencias) alteração(ões) a enviar")
                } else {
                    Text("Em dia")
                }
            }
            if let data = sinc.ultimaSincronizacao {
                LabeledContent("Última", value: data.formatted(date: .abbreviated, time: .shortened))
            }
            if let erro = sinc.ultimoErro {
                Label(erro, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .font(.callout)
            }
            Button {
                Task { await sinc.sincronizar() }
            } label: {
                Label("Sincronizar agora", systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(sinc.sincronizando)
        }

        Section {
            Link(destination: SupabaseConfig.site) {
                Label("Abrir o site do PlantaScan", systemImage: "globe")
            }
        } footer: {
            Text("No computador, abra este endereço e entre com a mesma conta.")
        }

        Section {
            Button("Sair da conta", role: .destructive) {
                sinc.sair()
            }
        } footer: {
            Text("Os dados continuam no iPhone e na nuvem.")
        }
    }

    private func entrar() async {
        enviando = true
        erro = nil
        do {
            try await sinc.entrar(
                email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                senha: senha,
                criarConta: criarConta
            )
            senha = ""
        } catch {
            erro = error.localizedDescription
        }
        enviando = false
    }
}
