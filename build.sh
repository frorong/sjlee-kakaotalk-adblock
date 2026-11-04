#!/bin/zsh
# 로컬 전용 KleanTalk 빌드. 네트워크에서 아무것도 받지 않는다 (Sparkle·외부 라이브러리 없음).
# 결과: build/kleantalk-adserver, build/kleantalk-check  (이 맥 아키텍처 전용)
set -euo pipefail
cd "${0:A:h}"

ARCH=$(uname -m)
mkdir -p build
for pair in "kleantalk-adserver:adserver/main.swift" "kleantalk-check:tools/check.swift"; do
  out=${pair%%:*} src=${pair#*:}
  swiftc -O -swift-version 5 -target "$ARCH-apple-macos12.0" -o "build/$out" "$src"
  xattr -c "build/$out" 2>/dev/null || true
  codesign --force --options runtime --sign - "build/$out" >/dev/null
done
shasum -a 256 build/kleantalk-adserver build/kleantalk-check
echo "빌드됨: build/ ($ARCH)"
