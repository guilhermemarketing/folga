# Bugs e aprendizados

## 2026-10-15 — `@State` não compila só com Command Line Tools
- **Problema:** `swift build` falha com `external macro implementation type 'SwiftUIMacros.StateMacro' could not be found`.
- **Causa:** no SDK atual `@State` é uma macro; o plugin `SwiftUIMacros` vem com o Xcode, não com as Command Line Tools.
- **Solução:** estado local via `@StateObject` com um `ObservableObject` mínimo (`Flag` em `Views.swift`).
- **Prevenção:** sem Xcode instalado, evitar `@State`, `@Observable`, `#Preview` e outras macros do SwiftUI.

## 2026-11-16 — Certificado autoassinado assina sem precisar de confiança
- **Contexto:** sem conta Apple Developer, mas com o Sparkle exigindo a mesma identidade entre versões.
- **Achado:** um certificado autoassinado com EKU `codeSigning`, importado com `-T /usr/bin/codesign`, assina sem prompt mesmo aparecendo como `CSSMERR_TP_NOT_TRUSTED`. O requisito designado vira `certificate root = H"<sha1>"`, estável entre builds.
- **Prevenção:** não é preciso marcar o certificado como confiável (`add-trusted-cert`). Sem o certificado no Keychain, o build sai ad-hoc e não serve como atualização.

## 2026-11-16 — Cache do Hugging Face com blobs compartilhados
- **Problema:** as pastas `models--*` mediam KB, mas o hub tinha 2,7 GB.
- **Causa:** no layout novo, os arquivos de cada modelo são symlinks para `hub/blobs/<xx>/<hash>`, que é compartilhado.
- **Solução:** seguir os symlinks e atribuir a cada modelo só os blobs que nenhum outro modelo referencia; apagar a pasta do modelo junto com esses blobs.

## 2026-11-16 — Vão entre a barra de menus e a janela do Folga
- **Problema:** depois de recolher "Desenvolvimento", a janela abria com um vão do tamanho da lista abaixo da barra de menus.
- **Causa provável:** o AppKit redimensiona janelas a partir da borda de baixo; quando o conteúdo da `MenuBarExtra(.window)` encolhe, o topo desce. Não reproduz numa `NSWindow` comum com `NSHostingController`, e clique sintético no item de status não abre a janela, então não deu para medir automaticamente.
- **Solução:** `TopAnchor` observa `didResize`/`didBecomeKey` da janela e reancora o topo sob a barra de menus.

## 2026-11-16 — Binário de `swift build` sem achar o Sparkle
- **Problema:** `.build/release/Folga --report` falhava com `Library not loaded: @rpath/Sparkle.framework`.
- **Causa:** o rpath só tinha `@executable_path/../Frameworks` (layout do `.app`); no `swift build` o framework fica ao lado do binário.
- **Solução:** adicionar também `-rpath @executable_path` no `Package.swift`.

## 2026-11-16 — codesign recusa assinar dentro do iCloud Drive
- **Problema:** `resource fork, Finder information, or similar detritus not allowed` ao assinar `dist/Folga.app`.
- **Causa:** o iCloud Drive grava atributos estendidos nos arquivos e volta a gravar mesmo depois de um `xattr -cr`.
- **Solução:** `build.sh` monta e assina o `.app` numa pasta temporária fora do iCloud e só então copia (`ditto`) para `dist/`.
