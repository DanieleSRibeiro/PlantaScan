import SwiftUI
import RoomPlan

/// Tela de scan: RoomCaptureView (com as instruções do próprio RoomPlan) + botões Concluir/Cancelar.
struct RoomScanView: View {
    let aoSalvar: (String, CapturedRoom) throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var holder = ScanControllerHolder()
    @State private var fase: Fase = .escaneando
    @State private var resultado: CapturedRoom?
    @State private var pedindoNome = false
    @State private var nome = ""
    @State private var erro: String?

    private enum Fase {
        case escaneando, processando, pronto
    }

    var body: some View {
        if RoomCaptureSession.isSupported {
            scanner
        } else {
            naoSuportado
        }
    }

    private var scanner: some View {
        ZStack {
            RoomCaptureRepresentable(holder: holder) { resultado in
                tratar(resultado)
            }
            .ignoresSafeArea()

            VStack {
                HStack {
                    Button("Cancelar") {
                        holder.controller?.parar()
                        dismiss()
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    switch fase {
                    case .escaneando:
                        Button("Concluir") {
                            fase = .processando
                            holder.controller?.parar()
                        }
                        .buttonStyle(.borderedProminent)
                    case .processando:
                        ProgressView()
                            .padding(8)
                            .background(.regularMaterial, in: Capsule())
                    case .pronto:
                        Button("Salvar") {
                            pedindoNome = true
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .controlSize(.large)
                .padding()

                Spacer()

                if fase == .processando {
                    Text("Processando o scan…")
                        .padding(12)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                        .padding(.bottom, 40)
                }
            }
        }
        .alert("Nome do cômodo", isPresented: $pedindoNome) {
            TextField("Ex.: Sala, Quarto 1", text: $nome)
            Button("Salvar") { salvar() }
            Button("Agora não", role: .cancel) {}
        } message: {
            Text("Dê um nome para identificar este cômodo.")
        }
        .alert(
            "Erro",
            isPresented: Binding(get: { erro != nil }, set: { if !$0 { erro = nil } })
        ) {
            Button("OK") { dismiss() }
        } message: {
            Text(erro ?? "")
        }
    }

    private var naoSuportado: some View {
        NavigationStack {
            ContentUnavailableView(
                "Scan não suportado",
                systemImage: "exclamationmark.triangle",
                description: Text("Este aparelho não suporta o RoomPlan. É necessário um iPhone ou iPad com sensor LiDAR.")
            )
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fechar") { dismiss() }
                }
            }
        }
    }

    private func tratar(_ r: Result<CapturedRoom, Error>) {
        switch r {
        case .success(let room):
            resultado = room
            fase = .pronto
            pedindoNome = true
        case .failure(let e):
            erro = "Falha ao processar o scan: \(e.localizedDescription)"
        }
    }

    private func salvar() {
        guard let room = resultado else { return }
        let limpo = nome.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try aoSalvar(limpo.isEmpty ? "Cômodo" : limpo, room)
            dismiss()
        } catch {
            erro = "Não foi possível salvar o cômodo: \(error.localizedDescription)"
        }
    }
}

// MARK: - UIKit

final class ScanControllerHolder {
    weak var controller: ScanController?
}

struct RoomCaptureRepresentable: UIViewControllerRepresentable {
    let holder: ScanControllerHolder
    let aoTerminar: (Result<CapturedRoom, Error>) -> Void

    func makeUIViewController(context: Context) -> ScanController {
        let controller = ScanController()
        controller.aoTerminar = aoTerminar
        holder.controller = controller
        return controller
    }

    func updateUIViewController(_ uiViewController: ScanController, context: Context) {
        uiViewController.aoTerminar = aoTerminar
    }
}

/// O delegate do RoomCaptureView precisa ser NSCoding; um UIViewController já é.
final class ScanController: UIViewController, RoomCaptureViewDelegate {
    var aoTerminar: ((Result<CapturedRoom, Error>) -> Void)?

    private var captureView: RoomCaptureView?
    private var rodando = false

    init() {
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) não é suportado")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        let cv = RoomCaptureView(frame: view.bounds)
        cv.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        cv.delegate = self
        view.addSubview(cv)
        captureView = cv
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        iniciar()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        parar()
    }

    func iniciar() {
        guard !rodando, let cv = captureView else { return }
        cv.captureSession.run(configuration: RoomCaptureSession.Configuration())
        rodando = true
    }

    func parar() {
        guard rodando else { return }
        captureView?.captureSession.stop()
        rodando = false
    }

    // MARK: RoomCaptureViewDelegate

    func captureView(shouldPresent roomDataForProcessing: CapturedRoomData, error: Error?) -> Bool {
        true
    }

    func captureView(didPresent processedResult: CapturedRoom, error: Error?) {
        if let error {
            aoTerminar?(.failure(error))
        } else {
            aoTerminar?(.success(processedResult))
        }
    }
}
