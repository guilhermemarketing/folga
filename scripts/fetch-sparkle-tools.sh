#!/bin/zsh
# Downloads Sparkle's command-line tools (generate_keys, sign_update) into .sparkle/bin.
set -euo pipefail
cd "${0:A:h}/.."
VERSION=2.10.1   # keep in sync with Package.swift
[ -x .sparkle/bin/sign_update ] && { echo "Já instaladas em .sparkle/bin"; exit 0; }
TMP=$(mktemp -d)
curl -sSLf -o "$TMP/Sparkle.tar.xz" "https://github.com/sparkle-project/Sparkle/releases/download/$VERSION/Sparkle-$VERSION.tar.xz"
mkdir -p .sparkle && tar -xJf "$TMP/Sparkle.tar.xz" -C .sparkle bin
echo "Pronto: .sparkle/bin ($VERSION)"
