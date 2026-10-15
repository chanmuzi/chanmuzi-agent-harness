# 2026-10 전역 `gh pr merge --squash` deny 규칙 제거

## 결정

`claude/settings.json` 의 `permissions.deny` 에서 `Bash(gh pr merge *--squash*)` 를 제거한다.
`Bash(gh pr merge *--admin*)` deny 는 유지한다.
squash 억제는 전역 agent 문서(`claude/CLAUDE.md`, `codex/AGENTS.md`)의 행동 규칙으로만 남긴다:
"레포 관례와 사용자 지시를 따르되, 스스로 squash 를 선택하지 않는다".

## 배경

- PR #11 (2026-04) 은 `gh pr merge` 마다 permission prompt 가 떠서 생기던 마찰을 줄이려고
  `--merge`/`--rebase` 를 allow 하고, 그 대신 `--squash`/`--admin` 을 deny 로 구조적으로 막았다.
- 이후 `defaultMode: bypassPermissions` 가 기본이 되면서 allow 항목은 사실상 의미를 잃었고
  (`docs/decisions/2026-07-bypass-permissions-default-mode.md`), deny 만 남았다.
- 2026-10 에 "Merge commits are not allowed" 설정의 외부 레포(squash 만 허용)에서 사용자가 squash 를
  명시 승인했는데도 deny 가 실행을 막아, 결국 사용자가 `!` 로 직접 명령을 쳐야 했다.
  안전장치가 사용자 지시까지 막고 우회를 유도하는 상태였다.

## 검토한 대안

1. **프로젝트별 allow 로 예외** — Claude Code 는 deny 가 allow 보다 우선하므로 전역 deny 가 남아 있는 한
   동작하지 않는다. 기각.
2. **PreToolUse 훅으로 레포 설정(`gh repo view --json mergeCommitAllowed`) 을 읽어 조건부 차단** —
   동작은 하지만 네트워크 호출이 merge 마다 붙고, 결국 "사용자가 요청하면 허용" 이라는 문서 규칙을
   코드로 다시 쓰는 것이라 복잡도 대비 이득이 작다. 기각.
   네트워크 호출 없이 문자열 매칭으로 `permissionDecision: "ask"` 를 돌려주는 변형도 가능하나,
   사용자가 squash 를 레포별 선택으로 두기로 결정했으므로 함께 기각. deny 제거 후 임의 squash
   사례가 실제로 생기면 이 변형을 1순위로 재검토한다.
3. **deny 삭제 + 문서 규칙 유지** — 채택. squash 여부는 레포 설정(GitHub 이 강제)과 사용자 지시가
   결정하며, 모델이 임의로 squash 하지 않는 규칙은 문서가 담당한다.

## 유지하는 것

- `Bash(gh pr merge *--admin*)` deny: merge 스타일이 아니라 branch protection 우회라 레포마다 달라질
  이유가 없고, CI 실패를 우회하려는 유인이 있는 플래그이므로 계속 차단한다.
- `--merge`/`--rebase` allow 항목: bypass 모드에서는 무해한 죽은 항목이라 이번 범위에서 건드리지 않는다.

## 결과

- 사용자가 squash 를 명시하거나 레포가 squash 만 허용하면 에이전트가 직접 merge 할 수 있다.
- 런타임 강제 장치는 더 이상 없다. `check.sh` 의 `check_contains` 는 양쪽 문서에 규칙 문구가 남아
  있는지(parity drift)만 검증하며, 행동 자체를 보장하지 않는다.
- "레포가 squash 만 허용" 판단은 추측이 아니라 `gh repo view --json mergeCommitAllowed,...` 로 확인한다.
