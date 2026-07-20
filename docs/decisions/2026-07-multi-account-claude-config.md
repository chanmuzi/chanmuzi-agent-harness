# 2026-07 — Claude Code 다계정: `cc` / `cc-up` 분리

## 상태

확정 (2026-07-20). 개인 계정과 업무 계정(`chanmuzi@upstage.ai`)을 **`CLAUDE_CONFIG_DIR`로 분리**하고,
두 계정이 **동일한 harness 설정을 공유**한다.

## 배경

계정 하나로만 쓰던 구조에서는 업무 계정을 쓰려면 매번 `/logout` → `/login`을 반복해야 했다.
세션 기록도 섞이고, 두 계정을 동시에 띄울 수 없었다.

## 결정한 구조

| 명령어 | 계정 | `CLAUDE_CONFIG_DIR` |
|--------|------|---------------------|
| `cc` | 개인 | (미설정 → 기본 `~/.claude`) |
| `cc-up` | 업무 `chanmuzi@upstage.ai` | `~/.claude-upstage` |

두 디렉터리 모두 `setup.sh`의 `link_claude_config()`가 **같은 레포 파일로 symlink**한다.
`settings.json`, `CLAUDE.md`, `statusline.sh`, `hooks/*`, `commands/*`가 대상이다.
따라서 계정이 달라도 훅·권한·전역 규칙은 동일하게 적용된다.

## macOS Keychain — 검증이 필요했던 지점

[공식 문서](https://code.claude.com/docs/en/env-vars)는 `CLAUDE_CONFIG_DIR`에 대해 이렇게만 말한다.

> All settings, session history, and plugins are stored under this path, as are credentials
> **on Linux and Windows; on macOS, credentials are in the system Keychain.**

즉 macOS에서는 **인증정보만 config dir 바깥(Keychain)에 있다.** 문서는 다중 계정 예시(`alias claude-work=...`)를
들면서도 **Keychain 항목이 config dir별로 분리되는지는 명시하지 않는다.** 분리되지 않는다면 새 계정 로그인이
기존 계정 토큰을 덮어써서, 이 구조 자체가 성립하지 않는다.

문서에 근거가 없으므로 **실측으로 확인했다.** 업무 계정 로그인 전 Keychain을 백업하고, 로그인 후 항목을 확인했다.

```
"svce"<blob>="Claude Code-credentials"            ← 개인 (~/.claude)
"svce"<blob>="Claude Code-credentials-f67dc77b"   ← 업무 (~/.claude-upstage)
```

**config dir에 따라 접미사가 붙어 별도 항목으로 저장되며, 기존 개인 계정 항목은 그대로 유지된다.**

이 동작은 **공식 문서에 명시되지 않은 관찰 결과**다. Claude Code 업데이트로 바뀔 수 있으므로,
계정 로그인이 갑자기 풀리는 증상이 생기면 이 지점을 먼저 의심할 것.

## 훅 경로를 config dir 상대로 바꾼 이유

`settings.json`을 두 계정이 공유하는데, 훅 커맨드가 `bash ~/.claude/hooks/*.sh`로 하드코딩돼 있었다.
그대로 두면 업무 계정이 **개인 계정 디렉터리의 훅 파일**을 참조해 두 계정이 경로로 결합된다.

```
"command": "bash \"${CLAUDE_CONFIG_DIR:-$HOME/.claude}/hooks/block-no-verify.sh\""
```

`:-` 기본값이 **반드시 필요하다.** 개인 계정은 `CLAUDE_CONFIG_DIR`을 설정하지 않으므로
(`cc`는 변수를 export하지 않는다) 기본값이 없으면 `/hooks/...`로 확장되어 **모든 훅이 조용히 깨진다.**

양쪽 확장을 실측 확인했다.

```
개인(unset): /Users/chanmuzi/.claude/hooks/block-no-verify.sh
업무(set):   /Users/chanmuzi/.claude-upstage/hooks/block-no-verify.sh
```

`check.sh`의 훅 등록 검증도 경로 완전일치에서 파일명 매칭(`test("...\\.sh")`)으로 완화했다.
경로 표현이 바뀌어도 검증이 깨지지 않게 하기 위해서다.

## 플러그인은 공유한다

`~/.claude-upstage/plugins`는 `~/.claude/plugins`를 가리키는 **디렉터리 symlink**다.

플러그인 캐시는 용량이 크고, `setup.sh`의 설치 로직 전체(마켓플레이스 등록, 캐시 배치, 매니페스트 갱신)를
계정마다 중복 실행하는 것은 비용 대비 이득이 없다고 판단했다. 두 계정이 같은 플러그인 집합을 쓰는 것이
"동일 설정 공유"라는 목표와도 일치한다.

**트레이드오프**: 개인 디렉터리를 지우면 업무 계정 플러그인도 같이 깨진다. 계정별로 다른 플러그인이
필요해지면 이 결정을 되돌려야 한다.

## 함께 제거한 것

`claude-safe`, `claude-team`, `claude-team-safe` 세 함수를 **삭제했다.** 실사용이 없었다.
`claude`라는 이름도 남기지 않았다 — `cc` / `cc-up`이 정식 명령이고, `claude`를 치면 래퍼 없는 원본 CLI가 실행된다.

## `cc` 이름과 C 컴파일러 충돌

`cc`는 macOS에서 `/usr/bin/cc`(C 컴파일러)와 이름이 겹친다. 셸 함수가 인터랙티브 셸에서 이를 가린다.

의도적으로 감수한 선택이다. 스크립트와 `make`는 셸 함수를 상속하지 않으므로 빌드는 영향받지 않고,
터미널에서 C 컴파일러를 직접 호출할 일이 없다. 필요하면 `command cc` 또는 `/usr/bin/cc`로 우회한다.
