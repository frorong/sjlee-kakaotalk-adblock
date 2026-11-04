#!/bin/zsh
# install.sh 가 sudo로 부르는 관리자 권한 부분. 직접 부르지 않는다.
# 사용: install-root.sh <빌드 폴더> <스크립트 폴더> <사용자 uid> <옛 인증서 보관 경로>
set -euo pipefail
export PATH=/usr/bin:/bin:/usr/sbin:/sbin
[[ $EUID -eq 0 ]] || { echo "root로만 실행"; exit 1; }

BUILD=$1 SCRIPTS=$2 USER_UID=$3 OLD_CERT_OUT=$4
USER_HOME=$(dscl . -read "/Users/$(id -un "$USER_UID")" NFSHomeDirectory | awk '{print $2}')
HOST=serv.ds.kakao.com
DIR="/Library/Application Support/KleanTalkLocal"
SERVER_LABEL=local.kleantalk.adserver
GUARD_LABEL=local.kleantalk.guard

# 0. upstream KleanTalk(자동 업데이트 포함 앱) 걷어내기 -------------------------------
OLD_LABEL=com.myungchul.kleantalk
OLD_DIR="/Library/Application Support/KleanTalk/AdServer"
launchctl bootout "gui/$USER_UID/$OLD_LABEL" 2>/dev/null || true
pkill -x KleanTalk 2>/dev/null || true
rm -f "$USER_HOME/Library/LaunchAgents/$OLD_LABEL.plist"
launchctl bootout system/$OLD_LABEL.adserver 2>/dev/null || true
rm -f /Library/LaunchDaemons/$OLD_LABEL.adserver.plist
if [[ -f $OLD_DIR/cert.pem ]]; then
  # 옛 인증서 신뢰는 사용자 권한으로 지워야 해서 install.sh 쪽에 넘긴다
  install -o "$USER_UID" -m 644 "$OLD_DIR/cert.pem" "$OLD_CERT_OUT"
fi
rm -rf "/Library/Application Support/KleanTalk"
if [[ -d /Applications/KleanTalk.app ]]; then
  dest="$USER_HOME/.Trash/KleanTalk.app"
  [[ -e $dest ]] && dest="$USER_HOME/.Trash/KleanTalk $(date +%H%M%S).app"
  mv /Applications/KleanTalk.app "$dest" && chown -R "$USER_UID" "$dest"
  echo "  upstream KleanTalk.app → 휴지통"
fi

# 1. 파일 ----------------------------------------------------------------------
launchctl bootout system/$SERVER_LABEL 2>/dev/null || true
launchctl bootout system/$GUARD_LABEL 2>/dev/null || true
mkdir -p "$DIR"
chown root:wheel "$DIR"; chmod 755 "$DIR"
install -o root -g wheel -m 755 "$BUILD/kleantalk-adserver" "$DIR/kleantalk-adserver"
install -o root -g wheel -m 755 "$BUILD/kleantalk-check" "$DIR/kleantalk-check"
install -o root -g wheel -m 755 "$SCRIPTS/guard.sh" "$DIR/guard.sh"
install -o root -g wheel -m 755 "$SCRIPTS/uninstall.sh" "$DIR/uninstall.sh"
install -o root -g wheel -m 755 "$SCRIPTS/status.sh" "$DIR/status.sh"

# 2. 인증서·키: 30일 넘게 남았으면 그대로 쓴다 (신뢰 재등록 불필요) -------------------
if [[ -f $DIR/cert.pem && -f $DIR/key.der ]] && openssl x509 -in "$DIR/cert.pem" -noout -checkend 2592000 >/dev/null 2>&1; then
  echo "  인증서 재사용 (만료: $(openssl x509 -in "$DIR/cert.pem" -noout -enddate | cut -d= -f2))"
else
  TMP=$(mktemp -d); chmod 700 "$TMP"
  trap 'rm -rf "${TMP:?}"' EXIT
  cat > "$TMP/req.cnf" <<CNF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $HOST
O = KleanTalk local (this Mac only)
[ext]
subjectAltName = DNS:$HOST
basicConstraints = critical,CA:FALSE
keyUsage = critical,digitalSignature,keyEncipherment
extendedKeyUsage = serverAuth
CNF
  (umask 077; openssl genrsa -out "$TMP/key.pem" 2048 2>/dev/null)
  openssl req -new -x509 -sha256 -key "$TMP/key.pem" -days 825 -config "$TMP/req.cnf" -out "$TMP/cert.pem" 2>/dev/null
  install -o root -g wheel -m 600 /dev/null "$DIR/key.der"
  openssl rsa -in "$TMP/key.pem" -outform DER -out "$DIR/key.der" 2>/dev/null
  install -o root -g wheel -m 644 "$TMP/cert.pem" "$DIR/cert.pem"
  openssl x509 -in "$DIR/cert.pem" -outform DER -out "$DIR/cert.der"
  chmod 644 "$DIR/cert.der"
  rm -rf "${TMP:?}"
  echo "  새 인증서 생성 (CA 아님, $HOST 전용, 825일)"
fi

# 3. LaunchDaemon 두 개: 빈 광고 서버 + 감시 -------------------------------------
write_plist() {  # write_plist <label> <body>
  local p=/Library/LaunchDaemons/$1.plist
  cat > "$p" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key><string>$1</string>
$2
</dict>
</plist>
EOF
  chown root:wheel "$p"; chmod 644 "$p"
  plutil -lint "$p" >/dev/null
}

write_plist $SERVER_LABEL "	<key>ProgramArguments</key>
	<array>
		<string>$DIR/kleantalk-adserver</string>
		<string>$DIR/cert.der</string>
		<string>$DIR/key.der</string>
	</array>
	<key>RunAtLoad</key><true/>
	<key>KeepAlive</key><true/>
	<key>ThrottleInterval</key><integer>10</integer>
	<key>ProcessType</key><string>Interactive</string>"

write_plist $GUARD_LABEL "	<key>ProgramArguments</key>
	<array>
		<string>/bin/zsh</string>
		<string>$DIR/guard.sh</string>
	</array>
	<key>RunAtLoad</key><true/>
	<key>WatchPaths</key>
	<array><string>/etc/hosts</string></array>
	<key>StartInterval</key><integer>1800</integer>
	<key>ThrottleInterval</key><integer>15</integer>
	<key>ProcessType</key><string>Background</string>"

launchctl bootstrap system /Library/LaunchDaemons/$SERVER_LABEL.plist
# guard는 RunAtLoad로 바로 한 번 돌며 hosts 블록·루프백 주소를 맞춘다
/bin/zsh "$DIR/guard.sh"
launchctl bootstrap system /Library/LaunchDaemons/$GUARD_LABEL.plist
echo "  LaunchDaemon 등록: $SERVER_LABEL, $GUARD_LABEL"
