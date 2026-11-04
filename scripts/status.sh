#!/bin/zsh
# 로컬 전용 KleanTalk 상태 확인 (sudo 불필요, 외부 접속 없음)
export PATH=/usr/bin:/bin:/usr/sbin:/sbin
DIR="/Library/Application Support/KleanTalkLocal"
ADDR=127.84.11.1
fail=0
row() { printf '  %-14s %s\n' "$1" "$2"; }

for l in local.kleantalk.adserver local.kleantalk.guard; do
  if launchctl print system/$l >/dev/null 2>&1; then row "${l#local.kleantalk.}" "등록됨"; else row "${l#local.kleantalk.}" "없음"; fail=1; fi
done
pid=$(pgrep -f "$DIR/kleantalk-adserver")
if [[ -n $pid ]]; then row "서버 프로세스" "pid $pid, 사용자 $(ps -o user= -p $pid)"; else row "서버 프로세스" "실행 안 됨"; fail=1; fi
grep -q "^$ADDR serv.ds.kakao.com" /etc/hosts && row "hosts" "적용됨" || { row "hosts" "블록 없음"; fail=1; }
ifconfig lo0 | grep -q "inet $ADDR " && row "lo0 주소" "$ADDR" || { row "lo0 주소" "없음"; fail=1; }
if [[ -f $DIR/cert.pem ]]; then
  end=$(openssl x509 -in "$DIR/cert.pem" -noout -enddate | cut -d= -f2)
  openssl x509 -in "$DIR/cert.pem" -noout -checkend 2592000 >/dev/null && row "인증서 만료" "$end" || { row "인증서 만료" "$end (30일 안 → install.sh 다시 실행)"; fail=1; }
fi
[[ -d /Applications/KleanTalk.app ]] && { row "upstream 앱" "남아 있음 (자동 업데이트 가능성)"; fail=1; }
printf '  %-14s ' "접속 시험"; "$DIR/kleantalk-check" || fail=1
exit $fail
