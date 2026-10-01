import ARKit
import SwiftUI
import RoomPlan

enum ModoScan {
    case umComodo
    case casaToda
}

struct ConfigScan: Identifiable {
    let id = UUID()
    let modo: ModoScan
    /// Sessão (sistema de coordenadas) em que os cômodos serão salvos.
    let sessao: UUID
    /// Mapa do ambiente para continuar uma sessão anterior.
    let mapa: ARWorldMap?
    let andar: Int
}

/// Tela de scan: um cômodo, vários cômodos seguidos (casa toda) ou continuação de uma sessão anterior.
struct RoomScanView: View {
    let config: ConfigScan
    /// Salva o cômodo e devolve o nome dado a ele.
    let aoCapturar: (_ room: CapturedRoom, _ mapa: ARWorldMap?, _ norte: Double?, _ andar: Int, _ sessao: UUID, _ video: URL?) throws -> String

    @Environment(\.dismiss) private var dismiss
    @State private var holder = ScanControllerHolder()
    @State private var fase: Fase
    @State private var proximoDepois = false
    @State private var andar: Int
    @State private var sessao: UUID
    @State private var salvos: [String] = []
    @State private var aviso: String?
    @State private var erro: String?

    private enum Fase {
        case relocalizando, escaneando, processando, fim
    }

    init(config: ConfigScan, aoCapturar: @escaping (CapturedRoom, ARWorldMap?, Double?, Int, UUID, URL?) throws -> String) {
        self.config = config
        self.aoCapturar = aoCapturar
        _fase = State(initialValue: config.mapa == nil ? .escaneando : .relocalizando)
        _andar = State(initialValue: config.andar)
        _sessao = State(initialValue: config.sessao)
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
            RoomCaptureRepresentable(
                holder: holder,
                mapaInicial: config.mapa,
                aoTerminar: { tratar($0) },
                aoRelocalizar: { fase = .escaneando }
            )
            .ignoresSafeArea()

            VStack(spacing: 12) {
                barraSuperior
                if let aviso {
                    Text(aviso)
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.regularMaterial, in: Capsule())
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                Spacer()
                barraInferior
            }
            .padding()
            .animation(.snappy, value: aviso)
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

    private var barraSuperior: some View {
        HStack {
            Button(salvos.isEmpty ? "Cancelar" : "Sair") {
                holder.controller?.encerrar()
                dismiss()
            }
            .buttonStyle(.bordered)

            Spacer()

            Menu {
                ForEach(Formato.faixaAndares, id: \.self) { n in
                    Button(Formato.andar(n)) { andar = n }
                }
            } label: {
                Label(Formato.andar(andar), systemImage: "stairs")
            }
            .buttonStyle(.bordered)
        }
        .controlSize(.large)
    }

    @ViewBuilder
    private var barraInferior: some View {
        switch fase {
        case .relocalizando:
            VStack(spacing: 10) {
                ProgressView()
                Text("Reconhecendo o local…")
                    .font(.headline)
                Text("Aponte o iPhone para uma parte que já foi escaneada (por exemplo, a porta por onde você vai entrar) e mova devagar.")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Button("Começar como scan separado") {
                    sessao = UUID()
                    holder.controller?.iniciarCaptura()
                    fase = .escaneando
                }
                .font(.footnote)
            }
            .padding()
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        case .escaneando:
            VStack(spacing: 8) {
                if !salvos.isEmpty {
                    Text("Salvos: \(salvos.joined(separator: ", "))")
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(.regularMaterial, in: Capsule())
                }
                if config.modo == .casaToda && salvos.isEmpty {
                    Text("Ande pela casa toda sem parar, com as portas abertas, passando por todos os cômodos. Toque em Concluir só no fim.")
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .padding(10)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
                HStack {
                    Button {
                        finalizarComodo(continuar: false)
                    } label: {
                        Label("Concluir", systemImage: "checkmark.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .controlSize(.large)
            }
        case .processando:
            Label("Processando o cômodo…", systemImage: "hourglass")
                .padding(12)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        case .fim:
            EmptyView()
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

    private func finalizarComodo(continuar: Bool) {
        proximoDepois = continuar
        fase = .processando
        holder.controller?.finalizarComodo()
    }

    private func tratar(_ r: Result<(CapturedRoom, ARWorldMap?), Error>) {
        switch r {
        case .success(let (room, mapa)):
            if room.walls.isEmpty {
                mostrarAviso("Nenhuma parede detectada — cômodo descartado")
            } else {
                do {
                    let nome = try aoCapturar(room, mapa, holder.controller?.norteMedido, andar, sessao, holder.controller?.ultimoVideo)
                    salvos.append(nome)
                    mostrarAviso("✓ \(nome) salvo")
                } catch {
                    erro = "Não foi possível salvar o cômodo: \(error.localizedDescription)"
                    return
                }
            }
            if proximoDepois {
                holder.controller?.iniciarCaptura()
                fase = .escaneando
            } else {
                fase = .fim
                holder.controller?.encerrar()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { dismiss() }
            }
        case .failure(let e):
            erro = "Falha ao processar o scan: \(e.localizedDescription)"
        }
    }

    private func mostrarAviso(_ texto: String) {
        aviso = texto
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            if aviso == texto { aviso = nil }
        }
    }
}

// MARK: - UIKit

final class ScanControllerHolder {
    weak var controller: ScanController?
}

struct RoomCaptureRepresentable: UIViewControllerRepresentable {
    let holder: ScanControllerHolder
    let mapaInicial: ARWorldMap?
    let aoTerminar: (Result<(CapturedRoom, ARWorldMap?), Error>) -> Void
    let aoRelocalizar: () -> Void

    func makeUIViewController(context: Context) -> ScanController {
        let controller = ScanController(mapaInicial: mapaInicial)
        controller.aoTerminar = aoTerminar
        controller.aoRelocalizar = aoRelocalizar
        holder.controller = controller
        return controller
    }

    func updateUIViewController(_ uiViewController: ScanController, context: Context) {
        uiViewController.aoTerminar = aoTerminar
        uiViewController.aoRelocalizar = aoRelocalizar
    }
}

/// Controla a RoomCaptureView com uma ARSession própria, para poder:
/// - escanear vários cômodos seguidos no mesmo referencial (stop(pauseARSession: false));
/// - salvar o mapa do ambiente (ARWorldMap) e relocalizar nele para continuar depois.
/// O delegate do RoomCaptureView precisa ser NSCoding; um UIViewController já é.
final class ScanController: UIViewController, RoomCaptureViewDelegate {
    var aoTerminar: ((Result<(CapturedRoom, ARWorldMap?), Error>) -> Void)?
    var aoRelocalizar: (() -> Void)?

    private let mapaInicial: ARWorldMap?
    private let sessaoAR = ARSession()
    private var captureView: RoomCaptureView?
    private var capturando = false
    private var aguardandoRelocalizacao = false
    private var iniciou = false
    private var comodosCapturados = 0
    private let bussola = BussolaService()
    private var timer: Timer?
    private let gravador = GravadorScan()
    private var linkGravacao: CADisplayLink?
    private var videoPendente: DispatchGroup?

    /// Direção do norte verdadeiro no plano do scan (radianos), se foi possível medir.
    var norteMedido: Double? { bussola.resultado }
    /// Vídeo do último cômodo capturado (arquivo temporário).
    private(set) var ultimoVideo: URL?

    init(mapaInicial: ARWorldMap?) {
        self.mapaInicial = mapaInicial
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) não é suportado")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        let cv = RoomCaptureView(frame: view.bounds, arSession: sessaoAR)
        cv.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        cv.delegate = self
        view.addSubview(cv)
        captureView = cv
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !iniciou else { return }
        iniciou = true

        bussola.iniciar()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.tick()
        }

        if let mapa = mapaInicial {
            let configuracao = ARWorldTrackingConfiguration()
            configuracao.initialWorldMap = mapa
            sessaoAR.run(configuracao, options: [.resetTracking, .removeExistingAnchors])
            aguardandoRelocalizacao = true
        } else {
            iniciarCaptura()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        encerrar()
    }

    private func tick() {
        guard let frame = sessaoAR.currentFrame else { return }
        if aguardandoRelocalizacao, case .normal = frame.camera.trackingState {
            aguardandoRelocalizacao = false
            iniciarCaptura()
            aoRelocalizar?()
        }
        if capturando {
            bussola.registrarAmostra(camera: frame.camera.transform)
        }
    }

    func iniciarCaptura() {
        aguardandoRelocalizacao = false
        guard !capturando else { return }
        // Reaproveitar a mesma RoomCaptureView depois de um cômodo pronto deixava a tela preta
        // no terceiro cômodo: cada cômodo ganha uma vista nova, na mesma ARSession (mesmo referencial).
        if comodosCapturados > 0 {
            recriarCaptureView()
        }
        guard let cv = captureView else { return }
        cv.captureSession.run(configuration: RoomCaptureSession.Configuration())
        capturando = true

        // Grava a filmagem do cômodo (30 quadros por segundo).
        ultimoVideo = nil
        gravador.iniciar()
        let link = CADisplayLink(target: self, selector: #selector(gravarQuadro))
        link.preferredFramesPerSecond = 30
        link.add(to: .main, forMode: .common)
        linkGravacao = link
    }

    @objc private func gravarQuadro() {
        guard capturando, let frame = sessaoAR.currentFrame else { return }
        gravador.adicionar(frame)
    }

    private func pararGravacao() {
        linkGravacao?.invalidate()
        linkGravacao = nil
        guard gravador.gravando else { return }
        let grupo = DispatchGroup()
        grupo.enter()
        videoPendente = grupo
        gravador.finalizar { [weak self] url in
            self?.ultimoVideo = url
            grupo.leave()
        }
    }

    private func recriarCaptureView() {
        captureView?.delegate = nil
        captureView?.removeFromSuperview()
        let cv = RoomCaptureView(frame: view.bounds, arSession: sessaoAR)
        cv.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        cv.delegate = self
        view.insertSubview(cv, at: 0)
        captureView = cv
    }

    /// Termina o cômodo atual mantendo a ARSession ativa (para o próximo cômodo ficar alinhado).
    func finalizarComodo() {
        guard capturando else { return }
        capturando = false
        pararGravacao()
        captureView?.captureSession.stop(pauseARSession: false)
    }

    func encerrar() {
        timer?.invalidate()
        timer = nil
        bussola.parar()
        linkGravacao?.invalidate()
        linkGravacao = nil
        gravador.cancelar()
        if capturando {
            captureView?.captureSession.stop()
            capturando = false
        }
        sessaoAR.pause()
    }

    // MARK: RoomCaptureViewDelegate

    func captureView(shouldPresent roomDataForProcessing: CapturedRoomData, error: Error?) -> Bool {
        true
    }

    func captureView(didPresent processedResult: CapturedRoom, error: Error?) {
        if let error {
            aoTerminar?(.failure(error))
            return
        }
        comodosCapturados += 1
        // Guarda o mapa do ambiente para poder continuar esta sessão depois.
        sessaoAR.getCurrentWorldMap { [weak self] mapa, _ in
            DispatchQueue.main.async {
                // Espera o vídeo do cômodo terminar de ser gravado.
                let grupo = self?.videoPendente ?? DispatchGroup()
                grupo.notify(queue: .main) {
                    self?.videoPendente = nil
                    self?.aoTerminar?(.success((processedResult, mapa)))
                }
            }
        }
    }
}
