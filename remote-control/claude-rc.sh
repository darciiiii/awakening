#!/bin/bash
# 데스크톱 앱 로그인과 별개로, 터미널(CLI) 로그인으로 Remote Control을 상시 띄운다.
# 앱이 주입하는 환경 변수를 물려받지 않도록 깨끗한 환경에서 실행한다.
cd "$HOME"
exec env -i HOME="$HOME" USER="$USER" \
  PATH="$HOME/.local/bin:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin" \
  TERM=xterm-256color LANG=en_US.UTF-8 \
  "$HOME/.local/bin/claude" remote-control --name "Mac 상시" --spawn=same-dir
