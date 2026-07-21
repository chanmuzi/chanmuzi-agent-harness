# 2026-07 — agent teams 권한 상속과 cmux 훅: `cc`/`ccu` = agents, `ccd`/`ccud` = 일반 세션

## 상태

확정 (2026-07-22). 로컬 cmux 환경에서 `cc agents`의 티메이트가 권한을 상속받지 못하던 문제의
**진짜 원인은 cmux 래퍼의 훅 주입**이었다. `cc`/`ccu`를 background agents 모드(cmux 훅 off)로,
기존 일반 세션은 `ccd`/`ccud`(cmux 훅 on)로 분리한다.

## 배경 — 증상과 오진

`cc`/`ccu`는 `--dangerously-skip-permissions`로 뜬다. 단일 세션에선 프롬프트가 없다.
그런데 `cc agents`(= `claude … agents`, background agents 서브커맨드)를 쓰면 **티메이트가
매 명령마다 권한을 물었다.**

첫 진단은 "CLI 플래그가 데몬 스폰 티메이트에 전파되지 않는다"였고, 그 해결로
`settings.json`에 `permissions.defaultMode: "bypassPermissions"`를 추가했다
(`2026-07-bypass-permissions-default-mode.md`). 하지만 **fresh 워커로 재시작해도 티메이트는
계속 프롬프트**했다 — settings의 defaultMode로는 안 잡혔다.

## 배경 — 진짜 원인 (cmux)

결정적 단서는 사용자의 관찰이었다: **같은 cmux에서 SSH로 원격(aimp) 접속하면 `cc agents`
티메이트가 정상 상속**한다. 로컬만 안 된다.

로컬 `claude`는 순정 바이너리가 아니라 **cmux 래퍼 스크립트**
(`/Applications/cmux.app/Contents/Resources/bin/claude`)다. 래퍼 주석 그대로:

> When running inside a cmux terminal (`CMUX_SURFACE_ID` is set), this wrapper intercepts
> `claude` invocations to inject `--session-id` and `--settings` flags so that Claude Code
> hooks fire back into cmux. **Outside cmux, it passes through to the real claude unchanged.**

주입되는 `--settings`에는 **`PermissionRequest` 훅**(cmux로 권한요청 라우팅, 125s SYNC)이 들어있다.

- **리드**: `--dangerously-skip-permissions` 플래그로 완전 bypass → 애초에 권한요청이 안 생겨
  cmux 훅이 발동하지 않음 → 정상.
- **티메이트**: 데몬이 플래그 없이 스폰 → 순정 Claude라면 리드 bypass를 상속하지만, cmux 환경에선
  티메이트의 권한요청이 **cmux가 주입한 PermissionRequest 훅에 걸려** 프롬프트가 뜬다.
- **aimp(SSH)**: `CMUX_SURFACE_ID`는 로컬 env라 SSH 너머로 전파되지 않는다. 원격 claude는 순정
  pass-through → 주입 없음 → 티메이트 정상 상속. 이래서 원격만 됐던 것.

즉 harness가 아니라 **cmux의 훅 주입**이 원인이었고, `defaultMode`는 그 위에 얹힌 cmux 훅을
막지 못했다.

## 결정한 구조

cmux 래퍼는 `CMUX_CLAUDE_HOOKS_DISABLED=1`이면 주입 없이 순정 claude로 pass-through한다
(래퍼 라인 142/150에서 확인). 이를 background agents 모드에서만 켠다.

| 명령 | 실행 | cmux 훅 | 용도 |
|------|------|---------|------|
| `cc` / `ccu` | `claude --dangerously-skip-permissions agents` | **off** | background agents (티메이트 bypass 상속) |
| `ccd` / `ccud` | `claude --dangerously-skip-permissions` | on | 일반 세션 (cmux 알림/상태 연동 유지) |

`cc`/`ccu`가 자주 쓰는 기본이므로 짧은 이름을 갖고, 옛 일반 세션은 `ccd`/`ccud`로 남긴다.

`CMUX_CLAUDE_HOOKS_DISABLED=1`은 `_cc_run`의 **서브셸 `( … )` 안에서만 export**한다.
방금 띄운 claude 프로세스 하나에만 적용되고, **호출한 셸이나 다른 터미널·cmux 패인에 전파되지
않는다** (각자 별도 프로세스·env). `.zshrc` 전역 export가 아니라 호출 시점 스코프다.

## 안전장치는 유지된다

`CMUX_CLAUDE_HOOKS_DISABLED=1`은 **cmux의 UI 연동 훅만** 끈다. harness 자체 훅
(`block-no-verify`, `guard-destructive-git`, `enforce-git-claw`, `quality-gate` 등)은
config dir의 `settings.json`에 있어 claude가 항상 로드하므로 **agents 모드에서도 그대로 작동**한다.
잃는 것은 cmux의 알림/사이드바 feed 연동뿐이다.

## 검증 (2026-07-22)

stub `claude`(env·args 출력)로 bash·zsh 양쪽에서 대조:

| 명령 | `CMUX_CLAUDE_HOOKS_DISABLED` | `CLAUDE_CONFIG_DIR` | args |
|------|------|------|------|
| `cc` | `1` | (기본) | `… agents` |
| `ccu` | `1` | `~/.claude-upstage` | `… agents` |
| `ccd` | (없음) | (기본) | `…` |
| `ccud` | (없음) | `~/.claude-upstage` | `…` |

호출 후 부모 셸의 `CMUX_CLAUDE_HOOKS_DISABLED`은 빈 값(누수 0)임도 확인.

## 트레이드오프 / 관련 결정

- **agents 모드는 cmux UI 연동을 잃는다.** 알림/사이드바 feed가 필요하면 `ccd`/`ccud`(일반 세션)를
  쓴다. 단일 세션에선 티메이트가 없어 상속 문제가 없으므로 훅을 켜둬도 무방하다.
- `2026-07-bypass-permissions-default-mode.md`의 `defaultMode` 추가는 이 증상의 해결책이
  **아니었다** (진짜 원인은 cmux). 다만 순정/원격 환경에서 persistent bypass를 보장하는
  무해한 하드닝이라 되돌리지 않고 유지한다.
- 근본적으로는 cmux 쪽 이슈다 — PermissionRequest 훅이 bypass 세션의 티메이트까지 잡는다.
  cmux가 bypass 세션에선 훅을 건너뛰도록 고치면 이 우회가 불필요해진다.
