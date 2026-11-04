#!/bin/zsh
# 로컬 전용 KleanTalk 제거 (sudo 없이 실행. 관리자 암호를 묻는다)
# 서버·감시 데몬, hosts 블록, 루프백 주소, 인증서·키, 인증서 신뢰를 모두 되돌린다.
set -uo pipefail
export PATH=/usr/bin:/bin:/usr/sbin:/sbin
[[ $EUID -ne 0 ]] || { echo "sudo 없이 실행하세요 (인증서 신뢰 제거는 사용자 권한이 필요)"; exit 1; }
DIR="/Library/Application Support/KleanTalkLocal"
WORK=$(mktemp -d); trap 'rm -rf "${WORK:?}"' EXIT
[[ -f $DIR/cert.pem ]] && cp "$DIR/cert.pem" "$WORK/cert.pem"

sudo /bin/zsh -c '
  set -u
  for l in local.kleantalk.guard local.kleantalk.adserver; do
    launchctl bootout system/$l 2>/dev/null; rm -f /Library/LaunchDaemons/$l.plist
  done
  awk "/^# >>> KakaoAdBlock/{f=1; next} f && /^# <<< KakaoAdBlock/{f=0; next} !f{print}" /etc/hosts > /etc/hosts.kleantalk.tmp \
    && grep -q localhost /etc/hosts.kleantalk.tmp && cat /etc/hosts.kleantalk.tmp > /etc/hosts
  rm -f /etc/hosts.kleantalk.tmp
  dscacheutil -flushcache; killall -HUP mDNSResponder 2>/dev/null
  ifconfig lo0 -alias 127.84.11.1 2>/dev/null
  rm -rf "/Library/Application Support/KleanTalkLocal"
' || { echo "관리자 권한 단계 실패"; exit 1; }

if [[ -f $WORK/cert.pem ]]; then
  security remove-trusted-cert "$WORK/cert.pem" 2>/dev/null
  FP=$(openssl x509 -in "$WORK/cert.pem" -noout -fingerprint -sha1 | cut -d= -f2 | tr -d :)
  security delete-certificate -Z "$FP" 2>/dev/null
fi
echo "로컬 전용 KleanTalk을 모두 제거했습니다. 카카오톡을 다시 시작하면 원래대로 돌아옵니다."
