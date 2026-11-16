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
