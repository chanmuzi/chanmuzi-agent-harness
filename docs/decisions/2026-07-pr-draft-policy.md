# 2026-07 — background agent의 draft PR 강제를 훅으로 차단

## 상태

확정 (2026-07-25). Claude Code background agent가 항상 draft PR을 만드는 동작을
**설정으로 끄는 방법은 존재하지 않음**을 확인했고, 대신 `shared/hooks/enforce-git-claw.sh`의
PreToolUse 차단과 에이전트 전역 문서 규칙으로 처리한다.

## 배경

background job(`cc`/`ccu`가 띄우는 백그라운드 세션)이나 agent 세션에서 작업을 마치면
PR이 **항상 draft로** 생성됐다. 이 레포의 PR 컨벤션은 review-ready PR이므로 매번 손으로
`gh pr ready`를 눌러야 했다.

원인을 추적한 결과, `--draft`는 이 레포나 `git-claw` 플러그인이 아니라
**Claude Code CLI 바이너리에 하드코딩된 시스템 프롬프트 문자열**이었다.

`~/.local/share/claude/versions/2.1.220` (Mach-O 바이너리)에서 추출:

```js
bDu = "open a draft PR via `gh pr create --draft` without asking — never end "
    + "the job with uncommitted work"

wiw = ` If the task produces code changes, ship them on a feature branch and ${bDu}. ...`
Ciw = ` If the task produces code changes, shipping is part of it: commit them, push the branch, and ${bDu} ...`
```

`wiw`는 agent용, `Ciw`는 background session용 shipping 정책 문자열이다. 둘 다 `bDu`를
그대로 끼워넣는 **순수 리터럴**이며, 조건 분기나 설정 조회가 붙어 있지 않다.

## 조사한 대안과 기각 사유

| 대안 | 결과 |
| --- | --- |
| `settings.json` 설정 키 | **없음.** 바이너리 전체 문자열에서 draft 관련 설정 키는 무관한 `feedbackDrafts`뿐이고, `pullRequest*` 계열 키도 존재하지 않는다 |
| `gh` CLI 쪽 기본값 | `gh`에는 "draft로 만들지 말 것"을 강제하는 config가 없다. draft 여부는 호출 시 플래그로만 결정된다 |
| `git-claw` `/pr` 스킬 수정 | 스킬은 애초에 `--draft`를 쓰지 않는다(`skills/pr/SKILL.md`). 원인이 아니므로 고칠 대상이 아니다 |
| PreToolUse 훅의 `updatedInput`으로 플래그 제거 | Claude Code는 `updatedInput`으로 Bash 명령 재작성을 지원한다(바이너리의 PreToolUse 스키마에서 확인). 하지만 Codex 훅에는 동등한 재작성 경로가 없어 **agent 간 동작이 갈린다.** 조용한 parity 격차를 만들지 않기 위해 기각 |
| PreToolUse 훅으로 **차단**(exit 2) | **채택.** 기존 `enforce-git-claw.sh`의 차단 패턴과 동일하게 양쪽 에이전트에서 같은 방식으로 동작한다 |

## 결정한 구조

2단 구성이다.

**1. 프롬프트 레벨 (1차 방어)** — `claude/CLAUDE.md`와 `codex/AGENTS.md`의 Git 섹션에
draft 금지 규칙을 넣는다. Claude 쪽 문구는 하드코딩된 background 지침을 **명시적으로
override**한다고 적어, 두 지시가 충돌할 때 어느 쪽이 이기는지 모델이 판단할 수 있게 한다.

**2. 훅 레벨 (강제)** — `shared/hooks/enforce-git-claw.sh`에 check 4b를 추가한다.
기존 `gh pr create` 검사 블록 안에서 `--draft` / `-d` / `--draft=true`를 잡아 exit 2로 막고,
에이전트는 플래그를 뺀 채 재실행한다.

오탐 방지를 위해 두 가지를 지켰다.

- 매칭 대상은 `COMMAND_NO_BODY_NO_MSG` — gh `--body`와 git commit 메시지가 이미
  redact된 사본이다. PR 본문이나 커밋 메시지에 `--draft`라는 **텍스트**가 들어가도
  (이 문서를 커밋하는 경우가 바로 그 사례다) 플래그로 오인하지 않는다
- 매칭 범위는 `gh pr create` 세그먼트로 한정한다. `-d`는 gh의 `--draft` 단축형이지만
  `ls -d` 같은 다른 명령에서도 흔한 플래그라, 명령줄 전체를 훑으면 무관한 체인 명령을 막게 된다

`--draft=false`(gh의 명시적 opt-out)와 `--dry-run`은 통과시킨다.

## 우회 경로

사용자가 실제로 draft PR을 원할 때는 `ALLOW_DRAFT_PR=1`로 실행한다.
`ENFORCE_GIT_CLAW=0`과 같은 결의 명시적 opt-out이며, 차단 메시지에도 안내된다.

## 결과

- background agent가 `--draft`를 붙여도 PR은 review-ready로 만들어진다
- 이 동작은 CLI 버전에 종속적이다. Anthropic이 나중에 실제 설정 키를 제공하면
  훅 대신 그 키를 쓰도록 갈아탈 수 있다 — 그때 이 기록을 갱신한다
- 회귀 테스트 8건을 `shared/hooks/enforce-git-claw.test.sh`에 추가했다
  (차단 3건, 오탐 방지 5건). `bash shared/hooks/enforce-git-claw.test.sh`로 실행한다
