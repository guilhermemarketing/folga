#!/bin/zsh
# Packs dist/Folga.app into dist/Folga-<version>.dmg (drag-to-Applications).
set -euo pipefail
cd "${0:A:h}/.."

./scripts/build.sh
source ./version.env; VERSION=$MARKETING_VERSION
DMG="dist/Folga-$VERSION.dmg"
STAGE=$(mktemp -d)/Folga

mkdir -p "$STAGE"
cp -R dist/Folga.app "$STAGE/"
ln -s /Applications "$STAGE/Aplicativos"
cat > "$STAGE/Como abrir.txt" <<TXT
Folga $VERSION — Apple silicon, macOS 14 ou mais novo

1. Arraste o Folga para a pasta Aplicativos.
2. Abra o Folga. Na primeira vez, o macOS avisa que não pode verificar o desenvolvedor
   (o app não tem assinatura paga da Apple).
3. Vá em Ajustes do Sistema > Privacidade e Segurança, role até o fim e clique em
   "Abrir Mesmo Assim" ao lado do Folga. Confirme com sua senha ou Touch ID.

Alternativa pelo Terminal (faz o mesmo que o passo 3):
   xattr -dr com.apple.quarantine /Applications/Folga.app

O Folga aparece na barra de menus (ícone de disco), não no Dock.
Para abrir junto com o Mac: ⚙︎ > Abrir ao iniciar sessão.
TXT

rm -f "$DMG"
hdiutil create -volname "Folga" -srcfolder "$STAGE" -fs HFS+ -format UDZO -imagekey zlib-level=9 -ov "$DMG" >/dev/null
codesign --force --sign - "$DMG"
echo "Pronto: $DMG ($(du -h "$DMG" | cut -f1))"
