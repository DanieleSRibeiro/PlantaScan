import ARKit
import AVFoundation

/// Grava em vídeo (H.264, sem áudio) as imagens da câmera durante o scan de um cômodo.
/// Usa os quadros da própria ARSession, então não precisa de outra câmera nem de permissão extra.
final class GravadorScan {
    private var writer: AVAssetWriter?
    private var input: AVAssetWriterInput?
    private var adaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var inicio: TimeInterval?
    private var ultimo: TimeInterval = 0
    private var url: URL?

    var gravando: Bool { writer != nil }

    func iniciar() {
        cancelar()
        let destino = FileManager.default.temporaryDirectory
            .appendingPathComponent("scan-\(UUID().uuidString).mp4")
        guard let w = try? AVAssetWriter(outputURL: destino, fileType: .mp4) else { return }
        let configuracao: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            // ~15 MB por minuto: cabe no limite de 50 MB por arquivo do storage (cômodos de até ~3 min).
            AVVideoWidthKey: 960,
            AVVideoHeightKey: 720,
            AVVideoScalingModeKey: AVVideoScalingModeResizeAspectFill,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 2_000_000,
                AVVideoMaxKeyFrameIntervalKey: 60,
            ],
        ]
        let i = AVAssetWriterInput(mediaType: .video, outputSettings: configuracao)
        i.expectsMediaDataInRealTime = true
        // A imagem da câmera vem deitada; o vídeo fica em pé, como o iPhone é segurado no scan.
        i.transform = CGAffineTransform(rotationAngle: .pi / 2)
        guard w.canAdd(i) else { return }
        w.add(i)
        writer = w
        input = i
        adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: i, sourcePixelBufferAttributes: nil)
        url = destino
        inicio = nil
        ultimo = 0
    }

    func adicionar(_ frame: ARFrame) {
        guard let w = writer, let i = input, let a = adaptor else { return }
        let t = frame.timestamp
        if inicio == nil {
            guard w.startWriting() else {
                cancelar()
                return
            }
            w.startSession(atSourceTime: .zero)
            inicio = t
        }
        guard let inicio, t > ultimo, i.isReadyForMoreMediaData else { return }
        ultimo = t
        a.append(frame.capturedImage, withPresentationTime: CMTime(seconds: t - inicio, preferredTimescale: 600))
    }

    /// Fecha o arquivo; devolve a URL do vídeo (ou nil se nada foi gravado).
    func finalizar(_ fim: @escaping (URL?) -> Void) {
        guard let w = writer, inicio != nil, w.status == .writing else {
            cancelar()
            fim(nil)
            return
        }
        let destino = url
        input?.markAsFinished()
        writer = nil
        input = nil
        adaptor = nil
        w.finishWriting {
            DispatchQueue.main.async {
                fim(w.status == .completed ? destino : nil)
            }
        }
    }

    func cancelar() {
        if let w = writer, w.status == .writing {
            w.cancelWriting()
        }
        if let url {
            try? FileManager.default.removeItem(at: url)
        }
        writer = nil
        input = nil
        adaptor = nil
        url = nil
        inicio = nil
    }
}
