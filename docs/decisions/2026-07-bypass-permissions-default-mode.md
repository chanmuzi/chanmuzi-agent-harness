# 2026-07 — 권한 스킵을 `settings.json`의 `defaultMode`로 이전

## 상태

확정 (2026-07-21). 권한 스킵을 `cc` / `ccu` 런처의 `--dangerously-skip-permissions`
**CLI 플래그에만 의존**하던 구조에서, `claude/settings.json`의
`permissions.defaultMode: "bypassPermissions"`로 **영구 설정화**한다.

## 배경

`cc` / `ccu`는 `--dangerously-skip-permissions`로 Claude Code를 띄운다
(`shared/shell/init.sh`의 `_cc_run`). 단일 에이전트 세션에서는 프롬프트가 뜨지 않아
문제가 없었다.

그러나 agent teams(`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`, `settings.json`의 `env`에 설정됨)를
쓰면 **매 명령마다 권한 프롬프트가 떴다.** 원인은 CLI 플래그의 적용 범위다.

`--dangerously-skip-permissions`는 **네가 직접 실행한 포그라운드 프로세스 하나에만** 적용된다.
반면 티메이트는 데몬이 새로 스폰하는 **별도 프로세스**(`claude daemon run`, `claude bg-spare`,
`claude bg-pty-host`)에서 돌아가며, 이 프로세스들은 플래그를 상속받지 못한다.

실측으로 확인했다 — 실행 중인 모든 `claude` 프로세스의 플래그 유무 대조:

```
--session-id ...   ✅ SKIP     ← cc 로 직접 띄운 포그라운드 세션
bg-spare           ❌ NO-SKIP  ← 데몬이 스폰한 티메이트/백그라운드 워커
bg-pty-host        ❌ NO-SKIP
daemon run         ❌ NO-SKIP
```

포그라운드 세션에만 플래그가 있고, 데몬 스폰 워커에는 전부 없다. 티메이트는 플래그 없는
기본(ask) 모드로 시작되므로 명령마다 승인을 요구한 것이다. **agent teams 기능 자체의 버그가 아니라
스킵을 CLI 플래그로만 걸어둔 구성의 한계다.**

## 결정한 구조

`claude/settings.json`의 `permissions`에 한 줄 추가한다.

```json
"permissions": {
  "defaultMode": "bypassPermissions",
  "allow": [ ... ],
  "deny": [ ... ]
}
```

`settings.json`은 **메인 세션과 데몬이 스폰하는 티메이트를 포함해 모든 프로세스가 로드**한다.
따라서 스킵이 티메이트까지 상속되어, agent teams 전 구성원이 프롬프트 없이 동작한다.
CLI 플래그와 달리 프로세스 스폰 경로와 무관하게 적용되는 것이 핵심이다.

`bypassPermissions`는 [공식 문서](https://code.claude.com/docs/en/permission-modes)가
`defaultMode`의 유효값으로 명시한 6개 모드 중 하나이며, settings로 영구 지정하는 것이
공식 지원 방식이다.

## 안전장치는 유지된다

bypass 모드에서도 하네스의 가드는 그대로 작동한다. 이는 새로 도입하는 위험이 아니라,
이미 `--dangerously-skip-permissions`로 돌던 메인 세션에서 검증된 현재 동작이다.

- **PreToolUse 훅** — `block-no-verify.sh`, `guard-destructive-git.sh`, `enforce-git-claw.sh`는
  권한 모드와 독립적으로 실행된다. `init.sh` 주석의 *"hooks provide the safety guardrails"*
  설계 의도 그대로다.
- **`deny` 리스트** — `gh pr merge --squash` / `--admin` 차단은 bypass 모드에서도 유지된다.

즉 이번 변경은 **안전 정책을 바꾸는 게 아니라**, 이미 메인 세션에 적용되던 "권한 스킵 + 훅 가드"
조합을 티메이트까지 일관되게 확장하는 것이다.

## 트레이드오프

- `cc` / `ccu`의 `--dangerously-skip-permissions` 플래그는 이제 **사실상 redundant**다.
  settings가 이미 bypass를 걸므로 기능상 중복이지만, 명시적 의도를 드러내는 값이라 그대로 둔다.
  (플래그를 제거해도 동작은 동일하다.)
- bypass가 **전역 기본**이 되므로 안전은 전적으로 훅과 `deny`에 의존한다. 새 위험 명령을 막으려면
  프롬프트가 아니라 `deny` 규칙이나 PreToolUse 훅으로 대응해야 한다.
- 두 계정(`cc` / `ccu`)이 같은 `settings.json`을 symlink로 공유하므로, 이 변경은 개인·업무
  양쪽에 동일하게 적용된다.
