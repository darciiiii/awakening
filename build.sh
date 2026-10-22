#!/bin/bash
# Awakening.app 빌드 스크립트. Xcode Command Line Tools가 필요하다 (xcode-select --install).
# 사용법: ./build.sh            → build/Awakening.app 생성
#         ./build.sh install    → 빌드 후 /Applications 에 설치
set -euo pipefail
cd "$(dirname "$0")"

APP="build/Awakening.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

swiftc -O \
  -target "$(uname -m)-apple-macos11" \
  src/main.swift \
  -o "$APP/Contents/MacOS/Awakening"

cp Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
echo "빌드 완료: $APP"

if [[ "${1:-}" == "install" ]]; then
  pkill -x Awakening 2>/dev/null || true
  sleep 1  # 바로 open 하면 종료 중인 앱과 겹쳐 -600 오류가 난다
  rm -rf /Applications/Awakening.app
  cp -R "$APP" /Applications/
  open /Applications/Awakening.app
  echo "설치 완료: /Applications/Awakening.app"
fi
