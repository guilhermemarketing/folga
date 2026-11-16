# Folga — contexto para agentes

App de barra de menus (SwiftUI, macOS 14+, Apple silicon) que mede o disco e o espaço usado por
ChatGPT/Codex, Claude, Antigravity e ferramentas de dev (pnpm, npm, Node, uv, Bun, Docker, Hugging Face,
Playwright/Puppeteer, Whisper), limpa cache e conversas antigas, e tem "Manter acordado".
Atualizações via Sparkle 2.10.1 (appcast.xml no repo, DMG nos Releases).
Uso e instalação: `README.md`. Aprendizados: `docs/bugs-aprendizados.md`.

## Mapa
- `Sources/Folga/Catalog.swift` — onde cada IA/ferramenta guarda dados; regras de cache e conversas (`group: .ai/.dev`). Único lugar a editar para novos caminhos.
- `Shell.swift` — roda CLIs (docker, pnpm) com PATH próprio; `Docker` (df/prune).
- `Updater.swift` — Sparkle (só ativo em build empacotado, que tem `SUFeedURL`).
- `Scanner.swift` — medição (tamanho alocado + última modificação), `DiskInfo`, `FOLGA_HOME`.
- `Cleaner.swift` — cache é apagado; conversas vão para o Lixo; `isSafe` bloqueia tudo fora da home; fechar/reabrir apps.
- `Store.swift` — estado (seleção de IAs, opções, fases overview → review → confirm → cleaning → done).
- `KeepAwake.swift` — asserções IOKit (display sleep + user activity a cada 20s), contador da barra de menus.
- `Views.swift` — todas as telas. `MenuController.swift` — item de status + janela própria (NSPanel) com topo preso sob a barra; `--panel-probe` mede o vão. `Debug.swift` — flags de linha de comando.
- `README.md` bilíngue (EN para SEO + PT), `CONTRIBUTING.md`, licença MIT.

## Regras
- Build só com Command Line Tools: não usar macros do SwiftUI (`@State`, `@Observable`, `#Preview`). Estado local via `Flag` + `@StateObject`.
- Nunca rodar limpeza real nos dados do usuário para testar: use `FOLGA_HOME=<pasta falsa> .build/release/Folga --clean-test`.
- Limpeza exige seleção explícita e dupla confirmação; Enter nunca dispara a limpeza.
- Cache de app aberto não é tocado, salvo com "Fechar e reabrir".
- UI em português (pt-BR), minimalista.
- Nunca versionar `.keys/`, `.p12` ou a chave EdDSA privada. Publicar só com `scripts/release.sh` (incrementa appcast; `BUILD_NUMBER` sempre sobe).
- Modelos HF: arquivos são symlinks para `hub/blobs`; só apagar blobs referenciados por um único modelo.

## Verificar
```bash
swift build -c release
.build/release/Folga --report               # números por IA
.build/release/Folga --snapshot /tmp/folga  # PNG de todas as telas (claro/escuro)
.build/release/Folga --awake-test           # + pmset -g assertions
./scripts/build.sh && ./scripts/make-dmg.sh  # dist/Folga.app e dist/Folga-<versão>.dmg
.sparkle/bin/sign_update --verify <dmg> <assinatura> --account marketing.gui.folga
```
