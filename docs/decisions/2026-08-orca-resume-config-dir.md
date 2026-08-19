# Orca resume 시 CLAUDE_CONFIG_DIR 자동 재해석

## 상태

채택 (2026-08)

## 맥락

이 harness는 Claude 계정을 두 개 운용한다: 개인(`~/.claude`, `cc`/`ccd`)과
업무(`~/.claude-upstage`, `ccu`/`ccud`). `CLAUDE_CONFIG_DIR`은 `_cc_run()`의
서브셸 안에서만 export되므로 셸 자체에는 남지 않는다
(근거: `docs/decisions/2026-07-multi-account-claude-config.md`).

Orca(ADE)는 SSH 재연결 시 pane을 복구하면서 탭에 기록해 둔 세션 ID로
`claude --dangerously-skip-permissions --resume <id>`를 **새 셸에 타이핑**한다
(`~/.orca/sessions/*.json`의 `aiVaultTitle.sessionId`). 이때 argv는 보존되지만
원래 서브셸의 env는 보존되지 않으므로, `ccu`/`ccud`로 뜬 세션의 resume은 기본
`~/.claude/projects/`만 탐색하다 `No conversation found`로 실패한다.
훅 설치 경로의 `CLAUDE_CONFIG_DIR` 미지원
([#7740](https://github.com/stablyai/orca/issues/7740))과 같은 뿌리의 문제다.

## 결정

`shared/shell/init.sh`에 resume 계정 재해석을 추가하고, 두 실행 경로가 같은
로직을 공유하게 한다:

- `_cc_resume_session_id`: `--resume <uuid>` / `--resume=<uuid>` / `-r <uuid>`
  인자에서 세션 ID를 추출한다.
- `_cc_find_session_config_dir`: 유효 config 디렉토리 → `~/.claude` →
  `$CCU_CONFIG_DIR` 순으로 `projects/*/<uuid>.jsonl`을 찾아, 유효 디렉토리가
  아닌 곳에서 발견될 때만 그 경로를 출력한다.
- `claude()` 셸 함수 래퍼 (Orca 복구 경로): 재지정이 필요하면 **그 호출에만**
  `CLAUDE_CONFIG_DIR`을 얹어 `command claude`를 실행하고 stderr로 알린다.
- `_cc_run()` (cc/ccu/ccd/ccud 경로): 계정 export/unset 직후 같은 재해석을
  수행해, `ccd --resume <ccu세션>` 같은 교차 계정 resume도 성공시킨다.
  export는 기존과 동일하게 서브셸 안에만 머문다.
- 그 외 모든 경우(일반 실행, ID 없는 `--resume`, 미존재 세션)는 그대로
  통과시킨다.

## 검토한 대안

- **Orca 쪽 수정 대기**: 업스트림이 env 보존 또는 config-dir 인식을 구현할
  때까지 수동 `CLAUDE_CONFIG_DIR=... claude --resume`으로 버티기. 재접속마다
  반복되는 수작업이라 기각.
- **PATH 셸 스크립트 shim**: 비인터랙티브 경로까지 잡을 수 있으나, cmux의
  `claude` 래퍼 등 다른 PATH shim과의 순서 충돌 위험이 있다. Orca는 인터랙티브
  셸에 명령을 타이핑하므로 셸 함수로 충분해 기각.
- **계정 통합(단일 config 디렉토리)**: 계정 분리 결정
  (`2026-07-multi-account-claude-config.md`)을 뒤집는 것이라 기각.

## 결과

- `ccu`/`ccud` 세션도 Orca SSH 재접속 후 resume이 자동 성공한다. 반대 방향
  (ccu 셸에서 개인 세션 resume) 미스매치, 그리고 알리아스에 직접 `--resume`을
  붙이는 교차 계정 케이스(`ccd --resume <ccu세션>` 등)도 함께 해결된다.
- resume이 아닌 알리아스 실행(새 세션)은 재해석이 개입하지 않아 기존 동작
  그대로다. 래퍼·재해석은 인터랙티브 셸(init.sh 로드)에서만 존재한다.
- 한계: Orca가 셸을 거치지 않고 바이너리를 직접 spawn하는 경로가 생기면
  래퍼가 개입하지 못한다 — 그 경우 현재(수정 전)와 동일하게 동작한다.
- 증상·복구 절차는 `claude/skills/orca-relay/SKILL.md`에 문서화되어 있다.
