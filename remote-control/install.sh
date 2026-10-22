#!/bin/bash
# CLI Remote Control("Mac 상시")을 Mac 로그인 때마다 자동으로 띄우고, 꺼지면 다시 띄우도록 등록한다.
# 처음 한 번은 ./claude-rc.sh 를 직접 실행해 "Enable Remote Control? (y/n)" 에 y 로 답해야 한다.
# 사용법: ./install.sh            → 등록하고 바로 시작
#         ./install.sh uninstall  → 끄고 등록 해제
set -euo pipefail
cd "$(dirname "$0")"

LABEL=com.darciiiii.claude-rc
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
DOMAIN="gui/$(id -u)"

launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true

if [[ "${1:-}" == "uninstall" ]]; then
  rm -f "$PLIST"
  echo "해제 완료: $LABEL"
  exit 0
fi

mkdir -p "$HOME/Library/LaunchAgents"
cat > "$PLIST" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key><array><string>$PWD/claude-rc.sh</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>ThrottleInterval</key><integer>60</integer>
  <key>StandardOutPath</key><string>$HOME/Library/Logs/claude-rc.log</string>
  <key>StandardErrorPath</key><string>$HOME/Library/Logs/claude-rc.log</string>
</dict>
</plist>
PL
launchctl bootstrap "$DOMAIN" "$PLIST"
echo "등록 완료: $LABEL (로그: ~/Library/Logs/claude-rc.log)"
