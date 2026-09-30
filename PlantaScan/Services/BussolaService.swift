import CoreLocation
import CoreMotion
import Foundation
import simd

/// Mede para onde fica o norte verdadeiro no sistema de coordenadas do scan.
///
/// Combina a orientação do aparelho em relação ao norte magnético (Core Motion) com a
/// posição da câmera no ARKit, e corrige a declinação magnética com o CLHeading.
final class BussolaService: NSObject, CLLocationManagerDelegate {
    private let movimento = CMMotionManager()
    private let localizacao = CLLocationManager()
    /// Norte verdadeiro − norte magnético, em graus.
    private var declinacao: Double?
    private var somaSen: Double = 0
    private var somaCos: Double = 0
    private var amostras = 0

    func iniciar() {
        if movimento.isDeviceMotionAvailable,
           CMMotionManager.availableAttitudeReferenceFrames().contains(.xMagneticNorthZVertical) {
            movimento.deviceMotionUpdateInterval = 1.0 / 30
            movimento.startDeviceMotionUpdates(using: .xMagneticNorthZVertical)
        }
        localizacao.delegate = self
        if localizacao.authorizationStatus == .notDetermined {
            localizacao.requestWhenInUseAuthorization()
        }
        if CLLocationManager.headingAvailable() {
            localizacao.startUpdatingHeading()
        }
    }

    func parar() {
        movimento.stopDeviceMotionUpdates()
        localizacao.stopUpdatingHeading()
    }

    /// Registra uma amostra usando a pose atual da câmera do ARKit.
    func registrarAmostra(camera: simd_float4x4) {
        guard let angulo = anguloNorte(camera: camera) else { return }
        somaSen += sin(angulo)
        somaCos += cos(angulo)
        amostras += 1
    }

    /// Média circular das amostras (radianos no plano XZ), ou nil se não houve medição.
    var resultado: Double? {
        guard amostras >= 3, hypot(somaSen, somaCos) / Double(amostras) > 0.5 else { return nil }
        return atan2(somaSen, somaCos)
    }

    private func anguloNorte(camera: simd_float4x4) -> Double? {
        guard let dm = movimento.deviceMotion else { return nil }
        let r = dm.attitude.rotationMatrix
        let m = simd_double3x3(rows: [
            simd_double3(r.m11, r.m12, r.m13),
            simd_double3(r.m21, r.m22, r.m23),
            simd_double3(r.m31, r.m32, r.m33),
        ])
        // Descobre o sentido da matriz comparando com a gravidade medida no aparelho.
        let gravidadeAparelho = simd_double3(dm.gravity.x, dm.gravity.y, dm.gravity.z)
        let gravidadeReferencia = simd_double3(0, 0, -1)
        let referenciaParaAparelho = simd_dot(m * gravidadeReferencia, gravidadeAparelho)
            >= simd_dot(m.transpose * gravidadeReferencia, gravidadeAparelho)
        let aparelhoParaReferencia = referenciaParaAparelho ? m.transpose : m

        // Direção da câmera traseira (−Z do aparelho) no referencial X = norte magnético, Z = cima.
        let frente = aparelhoParaReferencia * simd_double3(0, 0, -1)
        guard hypot(frente.x, frente.y) > 0.3 else { return nil }
        // Azimute horário a partir do norte (Y do referencial aponta para oeste).
        var azimute = atan2(-frente.y, frente.x)
        if let d = declinacao {
            azimute += d * .pi / 180
        }

        // Mesma direção no mundo do ARKit (−Z da câmera), projetada no plano XZ.
        let frenteAR = -camera.columns.2
        guard hypot(Double(frenteAR.x), Double(frenteAR.z)) > 0.3 else { return nil }
        let anguloFrente = atan2(Double(frenteAR.z), Double(frenteAR.x))
        // Na vista de cima (x → direita, z → baixo) os ângulos crescem no sentido horário, como o azimute.
        return anguloFrente - azimute
    }

    // MARK: CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didUpdateHeading novo: CLHeading) {
        guard novo.trueHeading >= 0, novo.headingAccuracy >= 0 else { return }
        var d = novo.trueHeading - novo.magneticHeading
        while d > 180 { d -= 360 }
        while d < -180 { d += 360 }
        declinacao = d
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if CLLocationManager.headingAvailable() {
            manager.startUpdatingHeading()
        }
    }
}
