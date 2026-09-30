import SafariServices
import SwiftUI

/// Página do site aberta dentro do app (Safari embutido: câmera, login salvo, compartilhar).
struct LinkWeb: Identifiable {
    let url: URL
    var id: String { url.absoluteString }

    /// Módulo Pro do site. Com `imovelID`, abre direto a página do imóvel.
    static func pro(imovelID: UUID? = nil) -> LinkWeb {
        var caminho = "pro"
        if let imovelID {
            caminho += "/imovel/\(imovelID.uuidString.lowercased())"
        }
        return LinkWeb(url: SupabaseConfig.site.appendingPathComponent(caminho))
    }
}

struct PaginaWeb: UIViewControllerRepresentable {
    let url: URL
    let aoFechar: () -> Void

    func makeCoordinator() -> Coordenador {
        Coordenador(aoFechar: aoFechar)
    }

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let configuracao = SFSafariViewController.Configuration()
        configuracao.entersReaderIfAvailable = false
        configuracao.barCollapsingEnabled = true
        let vc = SFSafariViewController(url: url, configuration: configuracao)
        vc.dismissButtonStyle = .close
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}

    final class Coordenador: NSObject, SFSafariViewControllerDelegate {
        let aoFechar: () -> Void

        init(aoFechar: @escaping () -> Void) {
            self.aoFechar = aoFechar
        }

        func safariViewControllerDidFinish(_ controller: SFSafariViewController) {
            aoFechar()
        }
    }
}

extension View {
    /// Apresenta uma página do site em tela cheia.
    func paginaWeb(_ link: Binding<LinkWeb?>) -> some View {
        fullScreenCover(item: link) { l in
            PaginaWeb(url: l.url) { link.wrappedValue = nil }
                .ignoresSafeArea()
        }
    }
}
