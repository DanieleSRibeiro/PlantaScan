# PlantaScan

App de iPhone que escaneia cômodos com o LiDAR (Apple RoomPlan) e gera a planta baixa 2D, com PDF profissional, cortes e sincronização com o site PlantaScan Web.

## O que o app faz

- **Imóveis**: cadastro com nome, endereço e Eircode, pesquisa por palavra-chave/Eircode, importação de planilha CSV ou Excel (.xlsx).
- **Scan**: um cômodo, a casa toda (vários cômodos seguidos, alinhados) ou continuar um scan anterior (relocalização pelo mapa do ambiente). Tipo do cômodo detectado automaticamente (Quarto 1, Banheiro 1, Cozinha…), andar escolhido antes do scan e norte verdadeiro medido pela bússola.
- **Planta 2D**: paredes com cotas, portas (de abrir, dupla, de correr, sanfonada), janelas (de correr, basculante, maxim-ar, fixa), vãos, móveis, área em m². Toque para ver medidas; edite modelos, medidas e posição de portas/janelas, adicione ou remova elementos, renomeie objetos.
- **Planta do andar**: todos os cômodos juntos, com nome e área, contagem por tipo e área total.
- **Exportação**: PDF A4 com planta em escala, legenda, carimbo, cortes AA/BB e quadros de áreas, esquadrias e mobiliário; PNG da planta; modelo 3D (USDZ).
- **Sincronização**: entre com sua conta (ícone de nuvem na tela inicial) para sincronizar com o site PlantaScan Web no computador.

## Instalação no iPhone (sem conta paga da Apple)

1. No Windows, instale o **iTunes** e o **iCloud** baixados do **site da Apple** (não da Microsoft Store) e depois o **Sideloadly** (sideloadly.io).
2. Conecte o iPhone pelo cabo (precisa ser um cabo que **transfere dados**, não só carrega) e toque em **"Confiar neste computador"**.
3. Baixe o `PlantaScan.ipa` da última Release: https://github.com/DanieleSRibeiro/PlantaScan/releases/latest (abra no **computador**).
4. Abra o Sideloadly, arraste o `.ipa`, informe seu Apple ID e clique em **Start**.
5. No iPhone: **Ajustes → Privacidade e Segurança → Modo de Desenvolvedor → Ativar** (o iPhone reinicia).
6. **Ajustes → Geral → VPN e Gerenciamento de Dispositivos** → confie no seu Apple ID.
7. O app vale por **7 dias**. Depois, repita o passo 4. Os dados salvos no app são mantidos se o bundle ID (`com.dribeiro.plantascan`) não mudar — e, com a conta conectada, também ficam guardados na nuvem.

## Como gerar uma nova versão

Não é preciso Mac: toda compilação acontece no GitHub Actions.

1. Faça as alterações no código e envie para a branch `main`:
   ```
   git add -A
   git commit -m "Descrição da mudança"
   git push
   ```
2. O workflow **Build** (`.github/workflows/build.yml`) roda sozinho num Mac do GitHub: gera o projeto com XcodeGen, compila sem assinatura e cria o `PlantaScan.ipa`.
3. Acompanhe com `gh run watch` (ou na aba **Actions** do GitHub). Se falhar, veja o erro com `gh run view --log-failed`.
4. Quando terminar, o `.ipa` aparece numa nova **Release** (`build-N`). Instale com o Sideloadly como acima.

Também dá para disparar um build manualmente: aba **Actions → Build → Run workflow**.

## Estrutura

```
project.yml                  Projeto XcodeGen (iOS 17+, sem dependências externas)
PlantaScan/
  App/                       Entrada do app
  Models/                    Imóvel, cômodo, edições, tipos, planta 2D
  Services/                  Armazenamento, planta 2D, desenho, cortes, PDF,
                             importação de planilhas, bússola
  Services/Sync/             Cliente Supabase e sincronização
  Views/                     Telas (SwiftUI) e folhas do PDF
.github/workflows/build.yml  Build no GitHub Actions + Release
```
