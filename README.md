# KleanTalk local

upstream [KleanTalk](https://github.com/showmeyourway-sketch/KleanTalk) 1.11(MIT, `LICENSE-upstream`)의 빈 광고 서버만 가져와 이 맥 전용으로 만든 버전.
앱·Sparkle 자동 업데이트·GitHub 접속 없음. 부팅하면 LaunchDaemon으로 알아서 동작.

## 설치 / 확인 / 제거

```bash
./install.sh                                                   # sudo 없이. 관리자 암호 1번 + 인증서 신뢰 확인 창 1번
"/Library/Application Support/KleanTalkLocal/status.sh"        # 상태
"/Library/Application Support/KleanTalkLocal/uninstall.sh"     # 전부 되돌리기
```

install.sh는 upstream KleanTalk(앱, 로그인 항목, 서버, 인증서 신뢰)을 먼저 걷어낸다. 앱은 휴지통으로 옮긴다.

## 구성

| 항목 | 위치 |
|---|---|
| 빈 광고 서버 (root로 443 연 뒤 nobody) | `local.kleantalk.adserver` LaunchDaemon |
| 감시: 부팅 시 / hosts 변경 시 / 30분마다 hosts 블록·lo0 주소·서버 복구 | `local.kleantalk.guard` LaunchDaemon |
| 실행 파일·인증서·키(root 전용) | `/Library/Application Support/KleanTalkLocal/` |
| hosts | `/etc/hosts`의 `# >>> KakaoAdBlock` 블록 |

## upstream 대비 변경점

- 앱·Sparkle 제거 → 자동 업데이트, 외부 다운로드, GitHub 접속 없음. 빌드도 로컬 소스만 사용
- 권한 낮출 때 root 보조 그룹(wheel/admin/kmem 등)까지 버림 (upstream은 setgid/setuid만 해서 보조 그룹이 남음) + root 복귀 불가 확인
- 연결당 10초 제한, 동시 연결 64개 제한, 헤더 8KB 제한, GET 외 405
- root 실행 시 주소·포트 환경 변수 무시, 루프백 외 주소 거부
- 감시 데몬: macOS 업데이트 등으로 hosts가 풀려도 자동 복구 (upstream은 6시간마다 확인 후 창만 띄움)
- 인증서 새로 생성 (CA 아님, serv.ds.kakao.com 전용, 825일). 만료 30일 전부터 status.sh·시스템 로그에 경고 → install.sh 다시 실행

## 시스템 로그

```bash
log show --last 1d --predicate 'subsystem == "local.kleantalk.adserver" OR process == "logger"' | grep -i kleantalk
```
