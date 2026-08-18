# 2026-08 — Orca 에이전트 훅을 harness가 직접 관리

## 상태

확정 (2026-08-18). Orca(ADE, [stablyai/orca](https://github.com/stablyai/orca))의 Claude Code
세션 인식 훅을 **harness의 `claude/settings.json`에 직접 병합**해서 개인/업무 두 계정이 공유한다.

## 배경

Orca는 Claude 세션을 훅으로 인식한다. 세션에서 SessionStart/Stop 등 이벤트가 발생하면
settings.json에 심어둔 훅이 `~/.orca/agent-hooks/claude-hook.sh`를 실행하고, 이 스크립트가
pane 환경변수(`ORCA_PANE_KEY`, `ORCA_AGENT_HOOK_ENDPOINT`)를 이용해 Orca 런타임의 HTTP
엔드포인트로 이벤트를 POST한다. 이 훅이 안 돌면 Orca UI에서 세션이 인식되지 않는다.

문제는 Orca가 이 훅을 **`~/.claude/settings.json`에만 설치**한다는 것.
[2026-07 다계정 결정](2026-07-multi-account-claude-config.md)에 따라 업무 계정(`ccu`)은
`CLAUDE_CONFIG_DIR=~/.claude-upstage`로 뜨므로 설정을 그쪽에서만 읽고, Orca 훅은 영원히
로드되지 않는다. 원격 서버(aimp-slurm-login)에서 업무 세션이 전부 미인식되던 원인이었다.

## 결정

Orca가 `~/.claude/settings.json`에 설치한 훅 엔트리(커맨드에 `orca` 경로 포함, 11개 이벤트:
SessionStart, UserPromptSubmit, Stop, StopFailure, SubagentStart, SubagentStop, TeammateIdle,
PreToolUse, PostToolUse, PostToolUseFailure, PermissionRequest)를 harness의
`claude/settings.json`에 병합한다. 두 계정이 같은 파일을 symlink하므로 양쪽 모두 훅을 얻는다.

안전한 이유:

- 훅 커맨드는 **버전 독립 래퍼**다. `$HOME/.orca/agent-hooks/claude-hook.sh`를 런타임에
  찾아 실행하고, 엔드포인트 정보는 Orca가 pane 환경변수로 주입한다. Orca가 업데이트돼도
  settings.json 쪽 엔트리는 그대로 동작한다.
- Orca가 없는 머신에서는 스크립트가 존재하지 않아 **훅이 즉시 no-op으로 종료**한다
  (stdin을 비우고 exit 0). 부작용 없음.
- 훅은 claude **시작 시점에 로드**되므로, 병합 후 떠 있던 세션은 재시작해야 인식된다.

## 주의: Orca 설치기가 symlink를 끊는다

Orca는 훅을 (재)설치할 때 `~/.claude/settings.json`을 **파일 교체 방식으로 재작성**한다.
harness가 걸어둔 symlink가 이때 끊기고 독립 사본이 남는다 (2026-08-16 원격 서버에서 실측 —
파일 mtime이 Orca relay 설치 시각과 정확히 일치). `check.sh`가 symlink 검증으로 잡아주므로,
Orca 업데이트 후 `check.sh`에서 `settings.json exists but is NOT a symlink`가 뜨면
내용 diff 확인 후 재링크하면 된다. 업스트림에 근본 수정을 제안하기 전까지 반복될 수 있다.

## 재검토 조건 (제거 판단 기준)

이 훅 엔트리는 업스트림 [#7740](https://github.com/stablyai/orca/issues/7740)
(`CLAUDE_CONFIG_DIR` 미지원)이 해결되더라도 **제거하면 안 된다**. 커밋된 엔트리는 세션
인식 외에, Orca 설치기가 훅 부재를 감지하고 settings.json을 재작성(= symlink 파괴)하는
것을 막는 방패 역할을 겸한다 — 설치기는 커맨드 문자열로 자기 훅의 존재를 확인하고, 이미
있으면 파일을 건드리지 않는다. #7740만 고쳐진 상태에서 엔트리를 제거하면 Orca가 두 계정의
settings.json **모두**에 재설치를 시도해 symlink가 양쪽 다 끊긴다.

제거를 재검토할 수 있는 조건은 하나뿐이다: Orca가 settings.json을 직접 편집하지 않는
훅 설치 방식(관리형 훅 디렉토리 등)으로 전환했을 때. 그 전까지 유지 비용은 0에 가깝다 —
훅 커맨드는 버전 독립 래퍼이고, Orca가 없는 머신에서는 즉시 no-op으로 종료한다.

## 함께 발견한 Orca 버그 (업스트림 추적)

- **업데이트 시 구버전 relay 고아화**: 원격 relay는 버전별 디렉터리+소켓을 쓰는데, 업데이트
  후 구 relay가 `--grace-time 0`으로 PTY들을 쥔 채 영원히 남는다. 세션 6개(claude 4개)가
  UI에서 사라진 채 살아있었다. 증상 시 `ps aux | grep 'relay.js --detached'`로 relay가
  2개인지 확인하고, 산하 claude의 resume ID를 확보한 뒤(자식 MCP 프로세스
  `/proc/<pid>/environ`의 `CLAUDE_CODE_SESSION_ID`) 구 relay에 SIGTERM.
  업스트림: [#8585](https://github.com/stablyai/orca/issues/8585),
  [#13852](https://github.com/stablyai/orca/issues/13852)
- **`CLAUDE_CONFIG_DIR` 미지원** (이 문서의 본 건): 업스트림
  [#7740](https://github.com/stablyai/orca/issues/7740). 관련 PR
  [#6956](https://github.com/stablyai/orca/pull/6956)은 Orca 관리 계정의 config dir만
  다루고, 셸 env로 export된 사용자 config dir + 원격 relay 설치 경로는 범위 밖.
- **`workspace.changed` 12KB 초과 시 무통보 드랍**: relay 로그에
  `Dropped workspace.changed (13798B > producer frame capacity 12288B)`. 세션 목록이
  낡은 채 남는 원인 후보.

## 다른 머신 적용 절차

1. harness pull 후 `./setup.sh` (symlink 복원 포함) → `./check.sh`로 확인
2. 떠 있는 claude 세션 재시작 (`claude --resume <id>` 또는 `--continue`)
3. 원격 서버라면 위의 구버전 relay 고아화 여부 확인
