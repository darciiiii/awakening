# Awakening

macOS 메뉴바에서 시스템 휴면을 제어하는 앱입니다. 스마트폰으로 Claude Code를 원격 조작(Remote Control)할 때 Mac이 잠들지 않게 붙잡아 둡니다.

- 전원 설정은 건드리지 않습니다. IOKit 전원 어서션만 사용하므로 앱을 끄면 바로 원래 휴면 동작으로 돌아갑니다.
- 화면은 평소처럼 꺼지고, 시스템(네트워크·프로세스)만 깨어 있습니다.

## 기능

| 메뉴 | 동작 |
| --- | --- |
| 수동으로 깨어있기 | 켜두는 동안 계속 휴면 방지 |
| claude 실행 중일 때 자동 유지 | `claude` 프로세스가 돌고 있을 때만 휴면 방지 (5초마다 확인, 기본 ON) |

메뉴바 아이콘: ☀︎ 깨어있음 / ☾ 휴면 허용

## 빌드 및 설치

Xcode Command Line Tools가 필요합니다 (`xcode-select --install`).

```bash
./build.sh            # build/Awakening.app 생성
./build.sh install    # 빌드 후 /Applications 에 설치하고 실행
```

## 확인

```bash
pmset -g assertions | grep Awakening
```

## 참고

- MacBook은 덮개를 닫으면 이 앱과 상관없이 잠듭니다(외부 모니터·전원 연결 시의 클램쉘 모드는 예외).
