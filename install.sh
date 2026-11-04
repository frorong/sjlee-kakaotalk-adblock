#!/bin/zsh
# 로컬 전용 KleanTalk 설치 (sudo 없이 실행. 관리자 암호는 중간에 한 번 묻는다)
#  1. 빌드 (외부 다운로드 없음)
#  2. 관리자 권한: upstream KleanTalk 앱·자동 업데이트·로그인 항목 제거, 서버·감시 데몬 설치
#  3. 사용자 권한: 옛 인증서 신뢰 제거, 새 인증서 신뢰 등록 (macOS 확인 창)
#  4. 카카오톡 다시 시작, 상태 확인
set -euo pipefail
# 시스템 도구만 쓴다 (conda·Homebrew의 openssl 등이 먼저 잡히지 않게)
export PATH=/usr/bin:/bin:/usr/sbin:/sbin
cd "${0:A:h}"
[[ $EUID -ne 0 ]] || { echo "sudo 없이 ./install.sh 로 실행하세요 (인증서 신뢰는 사용자 권한이 필요)"; exit 1; }

HOST=serv.ds.kakao.com
DIR="/Library/Application Support/KleanTalkLocal"

echo "[1/4] 빌드"
./build.sh

echo "[2/4] 관리자 권한 설치 (암호 입력)"
WORK=$(mktemp -d); trap 'rm -rf "${WORK:?}"' EXIT
sudo /bin/zsh "$PWD/scripts/install-root.sh" "$PWD/build" "$PWD/scripts" "$(id -u)" "$WORK/old-cert.pem"

echo "[3/4] 인증서 신뢰"
if [[ -f $WORK/old-cert.pem ]]; then
  security remove-trusted-cert "$WORK/old-cert.pem" 2>/dev/null && echo "  upstream 인증서 신뢰 제거" || true
  OLD_FP=$(openssl x509 -in "$WORK/old-cert.pem" -noout -fingerprint -sha1 | cut -d= -f2 | tr -d :)
  security delete-certificate -Z "$OLD_FP" 2>/dev/null || true
fi
NEW_FP=$(openssl x509 -in "$DIR/cert.pem" -noout -fingerprint -sha1 | cut -d= -f2 | tr -d :)
if "$DIR/kleantalk-check" >/dev/null 2>&1; then
  echo "  이미 신뢰됨"
else
  echo "  macOS 확인 창이 뜨면 로그인 암호로 허용하세요"
  security add-trusted-cert -r trustRoot -p ssl -s $HOST "$DIR/cert.pem"
fi

echo "[4/4] 확인"
dscacheutil -flushcache 2>/dev/null || true
sleep 1
"$DIR/status.sh" || true

if pgrep -x KakaoTalk >/dev/null; then
  read -q "?카카오톡을 다시 시작할까요? [y/N] " && {
    echo; osascript -e 'quit app "KakaoTalk"'; sleep 2; open -a KakaoTalk; } || echo
fi
echo "완료. 제거: \"$DIR/uninstall.sh\""
