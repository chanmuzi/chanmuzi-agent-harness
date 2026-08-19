---
name: orca-relay
description: Orca(ADE) 세션 감지·relay 문제 진단 플레이북. Orca UI에서 세션이 spinning으로 고착되거나, 세션이 미인식되거나, relay가 여러 개 떠 있거나, 재접속 후 화면이 깨질 때 사용. orca, relay, PTY, 세션 스피너, 훅 감지 관련 질문·작업 시 로드.
---

# Orca relay 진단 플레이북

## 구조 요약

Orca는 원격 세션을 **relay 데몬**(서버 상주, tmux 유사)으로 유지한다.
relay가 PTY의 master를 쥐고 있어 앱을 꺼도 세션이 살아남는다.

세션 상태(working/idle/done)는 **Claude Code 훅 → HTTP POST → relay 인메모리
상태 머신**으로 감지된다. 훅 스크립트는 `~/.orca/agent-hooks/claude-hook.sh`,
엔드포인트는 pane 환경변수(`ORCA_PANE_KEY`, `ORCA_AGENT_HOOK_ENDPOINT`)로 주입된다.
훅 엔트리는 harness `claude/settings.json`이 관리한다
(근거: `docs/decisions/2026-08-orca-agent-hooks.md`).

핵심 제약: **relay는 이벤트가 올 때만 상태를 갱신한다.** idle 세션은 이벤트를
만들지 않으므로, 한 번 잘못 굳은 상태(놓친 SubagentStop, 마지막 Stop 이후에
끝난 백그라운드 작업, session_crons 잔존)는 다음 이벤트까지 영원히 유지된다.
앱 재시작은 소용없다 — relay(와 그 메모리)는 살아남는 게 설계 목적이다.

## 증상별 진단

### 작업이 끝났는데 spinning이 계속됨 (가장 흔함)

1. 세션 자체 상태 확인: `orca-nudge` (목록 모드) — Claude가 `idle`을 보고하는데
   UI만 spinning이면 relay 메모리 고착이다.
2. `orca-nudge <pid>`로 복구. 세션이 idle일 때만 발사되도록 가드가 있다.
3. 수동 대안: 해당 pane에 아무 입력(프롬프트/ESC)을 주면 훅 이벤트가 다시 흘러
   재동기화된다.

### claude가 working 중 죽어서 spinning이 남음

- relay의 claude 핸들러가 `SessionEnd`를 소비하지 않아 구조적으로 재발하는
  케이스다 (아래 "알려진 한계" 참조). claude 프로세스가 없으니 pane env를 읽을
  대상이 사라진 것처럼 보이지만, relay가 쥔 **pane 셸**(`bash --rcfile
  ~/.orca-relay/shell-ready/...`)이 살아남아 `ORCA_PANE_KEY`와
  `ORCA_AGENT_HOOK_ENDPOINT`를 그대로 보존한다 (2026-08-19 실측).
- 복구: `orca-nudge` 목록에서 `status=dead`로 표시되는 pane 셸 PID를 찾아
  `orca-nudge <셸 pid>` — 셸 env에서 엔드포인트를 읽어 같은
  `SessionStart(resume)`를 보낸다.
- 죽은 pane 판정: relay의 자식 셸 중 `ORCA_PANE_KEY`는 있는데 claude 자손이
  없는 것. claude 자손이 살아 있으면 도구가 그 PID로 nudge하라고 안내하고,
  전송 직전에 새 claude가 떴는지 재확인 후 물러난다(`--force`로도 우회 불가).
- 자동화: `orca-nudge --sweep`을 cron에 등록하면 수동 탐지 없이 매분 자동
  복구된다 (upstage 원격 서버에는 등록됨 — `crontab -l`로 확인, 로그
  `~/logs/orca-nudge-sweep.log`, nudge-once 마커 `~/.cache/orca-nudge/`).
  근거·등록 절차: `docs/decisions/2026-08-orca-dead-pane-sweep.md`

### 닫은 pane이 프로젝트 클릭 시 부활함 / 앱이 `claude --resume`을 자동 타이핑함

- 원천: Orca 앱이 서버 원장 `~/.orca/sessions/<namespace>.json`에 프로젝트별
  tab 레이아웃을 저장하고, tab의 `aiVaultTitle.sessionId`로 pane의 세션 id를
  기억한다. pane 복구 시 이 id로 `claude --resume <id>`를 자동 타이핑한다.
- 부활 메커니즘: UI에서 pane을 닫으면 원장에서 tab은 제거되지만 **relay가
  쥔 pane 셸은 살아남는다.** 다음 접속 때 앱이 고아 PTY를 재입양해 tab을
  재생성한다 — pane을 확실히 없애려면 원장 제거(UI 닫기)와 서버 셸 종료가
  둘 다 필요하다. `--sweep`의 reap 단계가 후자를 자동화한다(위 도구 절).
- 함정 — 일회용 id 오염: transcript가 없는 id로 resume이 실패해도 Claude
  Code는 새 세션 id를 발급하고 SessionStart 훅을 실행한다(transcript는 안
  씀). relay/앱이 그 빈 id를 pane 세션으로 학습해 다음 복구도 반드시
  실패하는 루프가 된다. 세션 잔재(`session-env/<id>`, `tasks/session-<id>`)만
  있고 `projects/*/<id>.jsonl`이 없으면 이 케이스다. 진짜 대화는 해당 프로젝트
  디렉토리의 다른 jsonl에서 내용으로 식별해 수동 `--resume` 하라.

### 세션이 Orca에 아예 미인식됨

- 훅 미등록이 원인. `CLAUDE_CONFIG_DIR`을 쓰는 세션은 Orca 설치기가 훅을 넣어주지
  않는다(업스트림 [#7740](https://github.com/stablyai/orca/issues/7740)) —
  harness가 병합으로 우회 중. `check.sh`로 symlink를 확인하라.
- 훅은 세션 시작 시점에 로드되므로, 설정 병합 이전에 뜬 세션은 재시작해야 한다.

### relay가 2개 이상 떠 있음

- `ps aux | grep 'relay.js --detached'`로 확인. **PTY 자식이 있는 relay가 진짜다**
  (`pgrep -P <relay-pid>`). 자식 없는 relay는 빈 연결 정체성으로, 무해할 수 있다.
- 버전 업데이트 후 구 relay가 PTY를 쥔 채 고아화되는 케이스는 업스트림
  [#8585](https://github.com/stablyai/orca/issues/8585) /
  [#13852](https://github.com/stablyai/orca/issues/13852). 세션이 달린 relay를
  먼저 kill하지 말 것 — PTY가 함께 죽는다.

### SSH 재접속 후 resume이 "No conversation found" 실패

- Orca는 pane 복구 시 새 셸에 `claude --resume <id>`를 타이핑하는데, 원래
  세션이 `ccu`/`ccud`(=`CLAUDE_CONFIG_DIR=~/.claude-upstage`)로 떴다면 그
  env가 유실되어 기본 `~/.claude`에서만 세션을 찾다 실패한다.
- harness의 `claude()` 셸 함수(init.sh)가 자동 우회한다: `--resume <uuid>`
  감지 시 알려진 config 디렉토리들에서 `projects/*/<uuid>.jsonl`을 찾아 해당
  계정으로 `CLAUDE_CONFIG_DIR`을 재지정해 실행한다 (해당 호출에만 적용).
  `cc`/`ccu`/`ccd`/`ccud`에 `--resume`을 붙이는 교차 계정 resume도 `_cc_run`이
  같은 로직으로 처리한다.
- 래퍼가 없는 환경(init.sh 미로드 셸)에서는 수동으로:
  `CLAUDE_CONFIG_DIR=~/.claude-upstage claude --dangerously-skip-permissions --resume <id>`
- 근거: `docs/decisions/2026-08-orca-resume-config-dir.md`

### 재접속 후 화면이 깨져 보임

- detached PTY 재접속(tmux attach와 동일) 특성. 세션은 정상이고 표시만 밀린 것.
- 해당 pane에서 아무 키나 누르거나 창 크기를 바꾸면 TUI가 전체 리드로우한다.

## 도구

실행 경로: 셸 함수 `orca-nudge`(init.sh가 로드된 인터랙티브 셸), 비인터랙티브
셸/에이전트 Bash에서는 `"$CHANMUZI_AGENT_HARNESS_HOME/shared/bin/orca-nudge"`
절대경로를 사용하라.

- `orca-nudge` — orca pane에서 도는 Claude 세션 목록 + 자체 보고 상태.
  claude가 죽고 셸만 남은 pane은 `status=dead`(pane 셸 PID)로 함께 표시된다.
- `orca-nudge <pid>` — 해당 pane에 `SessionStart(resume)` 이벤트를 주입해 relay
  상태 리셋 (idle 가드 내장, `--force`로 우회). 살아있는 claude PID가 기본
  대상이고, 죽은 pane은 목록의 pane 셸 PID를 넘기면 폴백 경로로 처리된다.
- `orca-nudge --sweep` — cron 모드, 2단계 정리: **UI에서 이미 닫힌** dead
  pane(원장 `~/.orca/sessions/*.json`에 tab 없음 + 셸에 자식 없음 + 10분
  이상 경과)은 셸을 reap해 부활을 차단하고, UI에 아직 있는 dead pane은 한
  번씩 nudge한다. pane별 마커로 재전송을 막고, pane에 새 claude가 뜨면
  마커를 해제해 재발도 잡는다. 조용할 땐 출력이 없다(cron 로그 오염 방지).
- Orca의 비공개 훅 API 형식에 의존하므로 Orca 업데이트 후 4xx가 나오면 형식
  변경을 의심하라 (세션에 해는 없음).

도구의 한계:

- **죽은 세션 복구는 pane 셸 생존에 의존** — pane 키/엔드포인트를 대상
  프로세스의 환경에서 읽는 구조라, relay가 pane 셸까지 회수한 경우(pane 닫힘
  등)에는 읽을 env가 없어 복구할 수 없다. 셸이 남아 있는 통상 케이스는 위
  dead pane 폴백으로 처리된다. 폴백 경로에서도 endpoint.env는 data로만
  파싱한다(소싱 금지 원칙 동일 적용).
- **idle 확인과 전송 사이 잔여 경쟁** — 전송 직전 재확인으로 창을 줄였지만
  원자성은 없다. 잘못 눌린 상태는 세션의 다음 훅 이벤트에서 자가 복구된다.
  dead pane 폴백도 같은 방식으로 전송 직전 "claude 자손 없음"을 재확인한다.

## 알려진 한계 / 업스트림

- 근본 원인(stale 상태 재조정 부재)은 Orca 쪽 코드라 harness에서 못 고친다.
- relay의 claude 핸들러는 `SessionEnd`를 소비하지 않는다(2026-08 기준, devin 등
  다른 핸들러 전용). working 중 프로세스가 종료되면 스피너가 남는 것은 이 때문.
  harness 쪽 완화책이 위의 dead pane 폴백이다.
- 추적: [#7740](https://github.com/stablyai/orca/issues/7740)(훅 설치 경로),
  [#8585](https://github.com/stablyai/orca/issues/8585)/[#13852](https://github.com/stablyai/orca/issues/13852)(relay 수명주기),
  [#15317](https://github.com/stablyai/orca/issues/15317)(stale 상태 재조정 부재).
