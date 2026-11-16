# Folga

Medidor de disco na barra de menus do macOS (Apple silicon, macOS 14+) para o que as IAs e as
ferramentas de desenvolvimento ocupam. Mostra o espaço livre e quanto cada uma pesa, e libera espaço
com seleção explícita e dupla confirmação. Também tem um "Manter acordado" com cronômetro.

- **IAs:** ChatGPT/Codex, Claude e Antigravity
- **Desenvolvimento:** pnpm, npm, Node, Python (uv + pip), Bun, Docker, modelos Hugging Face,
  Playwright + Puppeteer e Whisper

## Instalar

Baixe o `.dmg` mais recente em [Releases](https://github.com/guilhermemarketing/folga/releases),
arraste o Folga para Aplicativos e abra. O app não tem assinatura paga da Apple, então, na primeira vez,
vá em **Ajustes do Sistema → Privacidade e Segurança → Abrir Mesmo Assim** (ou rode
`xattr -dr com.apple.quarantine /Applications/Folga.app`).

Depois disso, as atualizações chegam sozinhas pelo [Sparkle](https://sparkle-project.org)
(checagem diária; ⚙︎ → **Procurar atualizações…** força uma checagem agora).
Em ⚙︎ também dá para ligar **Abrir ao iniciar sessão** e escolher o que conta como conversa antiga (7, 30 ou 90 dias).

## O que ele limpa

Clique nos itens da tela principal (o círculo vira ✓), toque em **Revisar limpeza**, escolha cache
e/ou conversas, **Continuar** e, na segunda tela, **Limpar agora**. Enter nunca dispara a limpeza.

| Item | O que sai | Como sai |
|---|---|---|
| ChatGPT, Claude, Antigravity: cache | Caches do Chromium/Electron, `~/Library/Caches/<app>`, logs, versões antigas do Claude Code, updates pendentes | Apagado (os apps recriam) |
| ChatGPT, Claude, Antigravity: conversas | Sessões do Codex, do Claude Code (menos `memory/`) e do Antigravity sem uso há N dias | Lixo (recuperável) |
| pnpm | Cache de metadados e stores de versões antigas; depois roda `pnpm store prune` | Apagado |
| npm | `_cacache`, logs e pacotes do npx parados há 7+ dias (servidores MCP rodam de lá) | Apagado |
| Node | Headers do node-gyp, cache do Corepack e do nvm | Apagado |
| Python (uv) | Cache do uv e do pip (ambientes e Pythons instalados ficam) | Apagado |
| Bun | Cache de pacotes | Apagado |
| Docker | `docker system prune -a` + `builder prune` (volumes nunca) — precisa do Docker aberto | Removido pelo Docker |
| Hugging Face | Modelos e datasets baixados (exceto Whisper); blobs compartilhados entre modelos ficam | Apagado |
| Playwright + Puppeteer | Versões antigas dos navegadores; a mais nova de cada fica | Apagado |
| Whisper | Modelos Whisper do Hugging Face e do openai-whisper | Apagado |

O cache de um app aberto não é tocado (o Folga pode fechar, limpar e reabrir, se você pedir).
Configurações, login, cookies, memórias e imagens geradas nunca são tocados. Todos os caminhos
ficam em [`Sources/Folga/Catalog.swift`](Sources/Folga/Catalog.swift).

## Manter acordado

Liga/desliga, de 30 min a 24 h. Enquanto ligado, a tela não apaga, a proteção de tela não entra e a
sessão não bloqueia por inatividade (⌃⌘Q continua funcionando). **+30 min** soma meia hora (desligado,
liga por 30 min); **↺** volta para 30 min contando de agora. A barra de menus mostra o tempo restante
(`2h15`, `29m`, `40s`).

## Desenvolvimento

Só precisa das Command Line Tools (`xcode-select --install`).

```bash
swift build -c release
.build/release/Folga --report                 # o que o app enxerga, em texto
.build/release/Folga --snapshot /tmp/folga    # renderiza as telas em PNG (claro e escuro)
.build/release/Folga --awake-test             # liga por 6s; confira com: pmset -g assertions
FOLGA_HOME=/tmp/casa-falsa .build/release/Folga --clean-test   # limpeza só numa home falsa
./scripts/build.sh                            # dist/Folga.app
./scripts/make-dmg.sh                         # dist/Folga-<versão>.dmg
```

### Publicar uma versão

1. Aumente `MARKETING_VERSION` e `BUILD_NUMBER` em `version.env`.
2. `./scripts/release.sh "O que mudou"` — gera e assina o DMG, cria o release no GitHub,
   adiciona a versão ao `appcast.xml` e faz push.

Isso precisa, no Mac que publica:

- **Chave EdDSA do Sparkle** no Keychain, conta `marketing.gui.folga`
  (para importar do backup: `.sparkle/bin/generate_keys --account marketing.gui.folga -f backup.txt`).
  A chave pública está em `scripts/build.sh`. Sem a privada, nenhuma atualização pode ser publicada.
- **Certificado "Folga Local Signing"** no Keychain (importe o `.p12`). Ele mantém a mesma identidade
  de assinatura entre versões, e o Sparkle exige isso para aceitar a atualização. Sem ele, o build
  sai ad-hoc e não serve como atualização.
