# Orca dead pane 자동 sweep

날짜: 2026-08-19
상태: 적용됨

## 맥락

relay의 claude 핸들러는 `SessionEnd`를 소비하지 않는다
(`2026-08-orca-agent-hooks.md` 정정 항목). working 중 claude 프로세스가
종료되면 스피너가 영원히 남고, 이는 구조적으로 재발이 확정된 문제다.
2026-08-19에 `orca-nudge`의 dead pane 폴백(relay가 쥔 pane 셸의 env에서
엔드포인트를 읽어 `SessionStart(resume)` 주입)으로 수동 복구가 가능해졌지만,
발생할 때마다 사람이 탐지·실행해야 했다.

이 서버에는 이미 cron 기반 감시 패턴이 있다: `studio-web-dev-watchdog.sh`
(매분), `stale-session-reaper.sh`(매일 04:30, orca 구버전 relay 정리 단계
내장). 같은 패턴으로 자동화한다.

## 결정

- `orca-nudge --sweep` 모드 추가 (harness 관리, `shared/bin/orca-nudge`):
  모든 dead pane을 nudge하되 pane별 마커(`~/.cache/orca-nudge/`)로 한 번만
  보낸다. 마커는 셸이 죽거나 pane에 새 claude가 뜨면 해제되어, 같은 pane에서
  세션이 다시 working 중 죽는 재발도 잡는다. 조용한 실행은 무출력이고
  `.last-sweep` 하트비트만 갱신한다.
- crontab 매분 등록 (머신 로컬, harness 미관리): Orca가 도는 원격 서버에만
  의미가 있어 머신별로 수동 등록한다. 등록 예 —
  `* * * * * flock -n $HOME/.orca-nudge-sweep.lock <repo>/shared/bin/orca-nudge --sweep >> $HOME/logs/orca-nudge-sweep.log 2>&1`
- cadence 매분: 실측 1회 비용 0.7초 미만이고 steady state는 마커 덕에
  아무것도 하지 않는다. 부담이 되면 `*/5`로 낮춰도 무방.

## 검토한 대안

- **stale-session-reaper 통합**: 일 1회(04:30)라 스피너 복구 용도로는 너무
  느리고, 스크립트가 harness 밖(`~/bin`) 머신 로컬이라 관리 지점이 어긋난다.
- **relay 쪽 수정**: 근본 원인(SessionEnd 미소비, stale 상태 재조정 부재)은
  업스트림 영역([#15317](https://github.com/stablyai/orca/issues/15317)).

## auto-reap: 처음엔 보류했다가 같은 날 저녁 추가

sweep 최초 구현 시 dead pane 셸 자동 kill(auto-reap)은 보류했다:

1. claude 없이 의도적으로 띄워둔 plain 터미널 pane(잠깐 쉬는 작업, 방치
   의도)을 오탐으로 죽일 수 있다 — 당시엔 "의도"를 판정할 신호가 없었다.
2. dead pane 셸 4개를 수동 kill한 직후 앱이 접속 중이던 프로젝트에서 새
   pane 셸이 생성되는 것을 관찰 — 셸 kill 단독으로 UI 부활을 막는다는
   보장이 없어 보였다.

같은 날 저녁, 재검토 조건이던 **"UI가 버린 pane"의 결정적 판정 수단**을
찾았다: `~/.orca/sessions/<namespace>.json` — Orca 앱이 서버에 저장하는
프로젝트별 tab 레이아웃 원장. 각 tab은 `aiVaultTitle.sessionId`로 pane의
agent 세션 id를 기억하며, **앱이 자동 타이핑하는 `claude --resume <id>`가
바로 이 필드에서 나온다.** UI에서 pane을 닫으면 원장에서 tab이 제거되지만
relay의 셸은 살아남고, 다음 접속 때 앱이 고아 PTY를 재입양해 pane이
부활한다(2026-08-19 실측 정합 — solly tab을 UI에서 닫자 원장이 `[]`로
갱신되는 것 확인).

이에 sweep에 reap 단계를 추가했다. kill 조건은 전부 충족해야 한다:

- 원장이 정상(`tabsByWorktreePath` 존재)이고 pane의 tab id가 어느 원장
  파일에도 없음 — 의도적으로 남긴 pane은 원장에 있으므로 절대 매칭 안 됨,
  원장이 사라진 비정상 상태에서는 reap 전체를 거부(안전한 실패)
- 셸에 자식 프로세스가 전혀 없음 (claude 포함 무엇이든 돌고 있으면 제외)
- 셸 나이 ≥ 600초 (`ORCA_NUDGE_REAP_MIN_AGE`로 조정) — 방금 만든 pane의
  원장 기록 지연 레이스 방지

부활 루프의 부수 발견: 실패한 `--resume`도 새 세션 id를 발급하고
SessionStart 훅까지 실행하므로(transcript는 안 남음), relay/앱이 그 일회용
id를 pane 세션으로 학습해 다음 복구도 반드시 실패하는 자가 영속 루프가
된다. reap으로 pane 자체가 사라지면 루프도 끊긴다. 업스트림 보고 후보.
