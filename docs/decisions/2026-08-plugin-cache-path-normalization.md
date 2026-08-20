# 플러그인 캐시 경로 비교의 물리 경로 정규화

## 상태

채택 (2026-08)

## 맥락

`setup.sh`의 플러그인 캐시 prune은 `plugins/cache/<marketplace>/<plugin>/<version>/`
를 순회하면서 `installed_plugins.json`의 `installPath` 목록에 없는 디렉토리를
`rm -rf` 한다. `check.sh`도 같은 비교로 stale 캐시를 경고한다.

두 곳 모두 `grep -qxF`로 **문자열 완전일치**를 검사했다. 그런데 이 harness는
멀티 계정 구성상 `~/.claude-upstage/plugins`를 `~/.claude/plugins`로 향하는
디렉토리 symlink로 만든다(`docs/decisions/2026-07-multi-account-claude-config.md`).
그 결과 같은 디렉토리가 두 가지 표기로 기록된다:

- 순회 대상은 항상 `CLAUDE_DIR="$HOME/.claude"` 기준 경로
- `installPath`는 CLI 세션이 쓰던 config dir 기준이라, `ccu`(work) 세션에서
  설치·갱신한 플러그인은 `~/.claude-upstage/plugins/cache/...`로 기록됨

두 경로는 같은 실체지만 문자열이 달라, **로드되어 있는 캐시가 stale로 판정되어
삭제됐다.** 실제로 `omc`, `ui-ux-pro-max`, `git-claw` 캐시가 지워져 해당 스킬이
Claude Code에서 통째로 사라졌고, `installPath`가 구 경로로 남아 있던
`codex`만 살아남았다. `check.sh` 역시 같은 세 항목을 stale로 경고하며
"run ./setup.sh"를 권해, 사용자를 재발로 유도했다.

## 결정

캐시 경로 비교는 항상 **물리 경로**로 한다.

- `shared/lib/plugins.sh`를 추가하고, `plugin_cache_realpath` /
  `plugin_active_cache_paths` / `plugin_cache_is_active`를 `setup.sh`와
  `check.sh`가 공유한다. 정규화는 기존 `resolve_path()`(`shared/lib/os.sh`)로
  하므로 macOS/Linux 모두 동작한다.
- prune은 삭제 전에 분류 단계를 먼저 돌고, **살아있는 항목이 하나도 없으면
  중단**한다. 캐시 전체가 manifest와 어긋나는 상황은 지울 캐시가 아니라 이쪽
  로직의 버그이기 때문이다.
- 존재하지 않는 `installPath`는 활성 목록에서 제외한다. 어차피 디스크의
  디렉토리와 매칭될 수 없고, 남겨두면 위의 "전부 불일치" 가드가 무력해진다.

## 검토한 대안

- **`CLAUDE_DIR`을 `${CLAUDE_CONFIG_DIR:-$HOME/.claude}`로 변경**: 단독으로는
  불충분하다. manifest에 두 표기가 섞여 있어 어느 쪽 기준을 골라도 반대편
  표기의 항목이 stale로 잡힌다. 정규화가 있으면 이 변경 없이도 두 계정 모두
  올바르게 동작하므로 기각.
- **prune 기능 제거**: 캐시가 무한히 쌓이고, 로드되지 않는 옛 버전을 OMC 패치
  단계가 계속 스캔한다. 원래 목적이 유효하므로 기각.

## 결과

- `ccu`(work) 세션에서 설치·갱신한 플러그인이 `./setup.sh` 실행으로 삭제되지
  않는다. `./check.sh`의 허위 stale 경고도 사라진다.
- 이번 사고의 2차 요인이었던 `known_marketplaces.json`의 `installLocation`
  구 경로 문제는 이 수정 범위 밖이다. Claude Code CLI가 접두사 비교로
  "corrupted installLocation"을 판정해 마켓플레이스 갱신을 거부하는 동작이며,
  해당 파일은 이미 수동 교정되었다. harness는 이 파일의 경로 표기를 관리하지
  않는다.
- 한계: 정규화는 경로가 실제로 존재할 때만 가능하다. manifest가 이미 지워진
  디렉토리를 가리키면 그 항목은 조용히 무시된다(캐시 삭제로 이어지지 않음).
