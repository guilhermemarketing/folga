#!/bin/zsh
# Publishes a new version: builds the DMG, signs it for Sparkle, creates the GitHub release
# and adds it to appcast.xml.
#   1. Bump MARKETING_VERSION and BUILD_NUMBER in version.env
#   2. ./scripts/release.sh "O que mudou nesta versão"
set -euo pipefail
cd "${0:A:h}/.."
source ./version.env
NOTES=${1:?Uso: ./scripts/release.sh "notas da versão"}
REPO=guilhermemarketing/folga
ACCOUNT=marketing.gui.folga
TAG="v$MARKETING_VERSION"
DMG="dist/Folga-$MARKETING_VERSION.dmg"

grep -q "<sparkle:version>$BUILD_NUMBER</sparkle:version>" appcast.xml && { echo "Build $BUILD_NUMBER já está no appcast. Aumente BUILD_NUMBER."; exit 1; }
./scripts/fetch-sparkle-tools.sh >/dev/null
./scripts/make-dmg.sh

SIG=$(.sparkle/bin/sign_update --account "$ACCOUNT" "$DMG")   # sparkle:edSignature="…" length="…"
URL="https://github.com/$REPO/releases/download/$TAG/Folga-$MARKETING_VERSION.dmg"
DATE=$(LC_ALL=en_US.UTF-8 date -u "+%a, %d %b %Y %H:%M:%S +0000")
ITEM=$(cat <<XML
    <item>
      <title>Folga $MARKETING_VERSION</title>
      <pubDate>$DATE</pubDate>
      <sparkle:version>$BUILD_NUMBER</sparkle:version>
      <sparkle:shortVersionString>$MARKETING_VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <description><![CDATA[<p>${NOTES//$'\n'/<br>}</p>]]></description>
      <enclosure url="$URL" type="application/octet-stream" $SIG/>
    </item>
XML
)
# Newest first, right after the channel header.
python3 -c 'import sys; p="appcast.xml"; s=open(p).read(); m="<!-- items -->"; open(p,"w").write(s.replace(m, m+"\n"+sys.argv[1], 1))' "$ITEM"

gh release create "$TAG" "$DMG" --repo "$REPO" --title "Folga $MARKETING_VERSION" --notes "$NOTES"
git add appcast.xml version.env
git commit -m "Release $MARKETING_VERSION"
git push
echo "Publicado: $TAG — apps instalados recebem a atualização na próxima checagem."
