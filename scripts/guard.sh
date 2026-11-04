#!/bin/zsh
# kleantalk guard (root, LaunchDaemon local.kleantalk.guard)
# 부팅 시, /etc/hosts가 바뀔 때, 30분마다 실행된다. 설정이 풀렸으면 되돌리고, 맞으면 아무것도 쓰지 않는다.
#  - /etc/hosts의 KakaoAdBlock 블록
#  - lo0의 전용 주소 127.84.11.1
#  - 빈 광고 서버 LaunchDaemon 로드 상태
# 네트워크 접속은 하지 않는다.
set -u
export PATH=/usr/bin:/bin:/usr/sbin:/sbin

HOST=serv.ds.kakao.com
ADDR=127.84.11.1
DIR="/Library/Application Support/KleanTalkLocal"
SERVER_LABEL=local.kleantalk.adserver
SERVER_PLIST=/Library/LaunchDaemons/$SERVER_LABEL.plist
HOSTS=/etc/hosts

say() { logger -t kleantalk-guard "$*"; }

[[ $EUID -eq 0 ]] || { echo "root로만 실행"; exit 1; }

# 1. hosts 블록 ---------------------------------------------------------------
BLOCK="# >>> KakaoAdBlock (managed by KleanTalk local)
0.0.0.0 display.ad.daum.net
:: display.ad.daum.net
0.0.0.0 analytics.ad.daum.net
:: analytics.ad.daum.net
$ADDR $HOST
:: $HOST
# <<< KakaoAdBlock"

if [[ -s $HOSTS ]]; then
  current=$(awk '/^# >>> KakaoAdBlock/{f=1} f{print} /^# <<< KakaoAdBlock/{f=0}' $HOSTS)
  if [[ $current != "$BLOCK" ]]; then
    tmp=$(mktemp /etc/hosts.kleantalk.XXXXXX) || exit 1
    # 블록 밖 내용은 그대로 두고, 블록만 새로 붙인다
    awk '/^# >>> KakaoAdBlock/{f=1; next} f && /^# <<< KakaoAdBlock/{f=0; next} !f{print}' $HOSTS > "$tmp"
    # 블록 뒤 남은 빈 줄 정리 후 붙이기
    printf '%s\n' "$(cat "$tmp")" > "$tmp.2" && printf '\n%s\n' "$BLOCK" >> "$tmp.2"
    # 원래 내용(블록 제외)이 줄어들지 않았는지 확인한 뒤에만 덮어쓴다 (inode·권한 유지를 위해 cat)
    if [[ -s "$tmp.2" ]] && grep -q 'localhost' "$tmp.2"; then
      cat "$tmp.2" > $HOSTS
      dscacheutil -flushcache; killall -HUP mDNSResponder 2>/dev/null
      say "hosts 블록을 복구했습니다"
    else
      say "hosts 복구 중단: 결과가 비정상 (localhost 항목 없음)"
    fi
    rm -f "$tmp" "$tmp.2"
  fi
else
  say "hosts 파일이 비어 있거나 없음: 건드리지 않음"
fi

# 2. 루프백 전용 주소 -----------------------------------------------------------
if ! ifconfig lo0 | grep -q "inet $ADDR "; then
  ifconfig lo0 alias $ADDR netmask 255.255.255.255 up && say "lo0에 $ADDR 다시 붙임"
fi

# 3. 서버 데몬 -----------------------------------------------------------------
if [[ -f $SERVER_PLIST ]] && ! launchctl print system/$SERVER_LABEL >/dev/null 2>&1; then
  launchctl bootstrap system $SERVER_PLIST 2>/dev/null && say "빈 광고 서버를 다시 올림"
fi

# 4. 인증서 기한 경고 (갱신은 사용자 확인이 필요해 자동으로 하지 않음) --------------
if [[ -f $DIR/cert.pem ]] && ! openssl x509 -in "$DIR/cert.pem" -noout -checkend 2592000 >/dev/null 2>&1; then
  say "인증서가 30일 안에 만료됩니다. 설치 폴더에서 ./install.sh 를 다시 실행하세요"
fi
exit 0
