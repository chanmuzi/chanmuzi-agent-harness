# 2026-11 Artifact 첫 게시 때 브라우저 자동 열기를 끈다

## 상태

채택 (2026-11-25)

## 맥락

Claude Code는 Artifact를 처음 게시하면 브라우저를 자동으로 연다. 이 harness는 주로 원격
서버의 Orca pane이나 여러 병렬 세션에서 쓰이므로, 자동 열기는 엉뚱한 머신에서 브라우저를
띄우려 하거나 작업 중인 화면을 가로챈다. 게시 결과는 터미널에 URL로 남으므로 필요할 때
직접 열면 된다.

## 결정

`claude/settings.json`의 `env`에 `"CLAUDE_CODE_ARTIFACT_AUTO_OPEN": "0"`을 둔다.
두 계정(`cc`, `ccu`)이 같은 파일을 symlink하므로 양쪽에 함께 적용된다.

Claude Code 2.1.332 바이너리에서 확인한 동작: 값이 `0`, `false`, `no`, `off`면 자동 열기를
건너뛴다. 이후 버전에서 이름이나 동작이 바뀔 수 있다.

## 고려한 대안

- **셸 rc에서 export**: 셸 init을 거치지 않고 뜨는 세션에는 적용되지 않는다.
  settings.json `env`는 Claude Code가 직접 읽으므로 실행 경로와 무관하다.
- **세션마다 수동으로 닫기**: 병렬 세션이 많아 반복 비용이 크다.

## 재검토 조건

- Claude Code가 이 변수를 제거하거나 이름을 바꾸면 이 항목은 no-op이 된다. 자동 열기가
  다시 보이면 바이너리에서 새 이름을 확인해 교체한다.
- Codex CLI에는 대응 기능이 없어 parity 대상이 아니다.
