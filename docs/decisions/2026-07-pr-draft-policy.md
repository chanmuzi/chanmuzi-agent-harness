# 2026-07 — background agent의 draft PR 강제를 훅으로 차단

## 상태

확정 (2026-07-25). Claude Code background agent가 항상 draft PR을 만드는 동작을
**설정으로 끄는 방법은 존재하지 않음**을 확인했고, 대신 `shared/hooks/enforce-git-claw.sh`의
PreToolUse 차단 **한 겹으로만** 처리한다. 에이전트 전역 문서(`claude/CLAUDE.md`,
`codex/AGENTS.md`)에 규칙을 넣는 방식은 검토했으나 기각했다.

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
| 에이전트 전역 문서에 draft 금지 규칙 추가 | **기각.** 아래 "프롬프트 레벨을 쓰지 않는 이유" 참고 |
| PreToolUse 훅으로 **차단**(exit 2) | **채택.** 기존 `enforce-git-claw.sh`의 차단 패턴과 동일하게 양쪽 에이전트에서 같은 방식으로 동작한다 |

## 프롬프트 레벨을 쓰지 않는 이유

초안에서는 훅 차단과 함께 `claude/CLAUDE.md` / `codex/AGENTS.md`에도 draft 금지 규칙을
넣어 훅에 걸리기 전에 미리 막으려 했다. 리뷰에서 기각했다.

**1. 전역 비용, 국소 효용.** 이 문서들은 PR과 아무 상관 없는 세션에서도 매번 전부 읽힌다.
이 규칙이 의미를 갖는 순간은 `gh pr create`를 실제로 실행할 때뿐인데, 프롬프트에 넣으면
비용은 항상 내고 효용은 가끔 본다. 훅은 정반대로 해당 명령이 실행될 때만 동작한다.

**2. Claude Code 내부 구현에 결합된다.** 초안 문구는 "background-session 지침을
override한다"고 적어 CLI에 하드코딩된 프롬프트를 **명시적으로 참조**했다. 그 프롬프트가
바뀌거나 사라지면 존재하지 않는 것을 가리키는 문장이 전역 문서에 남는다.

반면 훅이 강제하는 명제는 "`gh pr create`에 draft 플래그를 붙이지 않는다"로,
**gh CLI의 공개 인터페이스에만** 의존한다. Claude Code가 프롬프트를 바꾸든 나중에 설정 키를
내놓든 훅은 그대로 유효하다(설정 키가 생기면 중복될 뿐 깨지지 않는다).

대가는 에이전트가 draft로 시도했다가 차단당해 한 번 재실행하는 왕복 1회다.
이 비용은 실제로 PR을 만들 때만 지불되므로 받아들인다.

## 결정한 구조

`shared/hooks/enforce-git-claw.sh`에 check 4b를 추가한다. 기존 `gh pr create` 검사 블록
안에서 `--draft` / `-d` / `--draft=true`를 잡아 exit 2로 막고, 에이전트는 플래그를 뺀 채
재실행한다. 강제 지점은 이 훅 하나뿐이다.

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
- CLI 버전에 종속적인 것은 **이 결정의 동기**(하드코딩된 프롬프트, 설정 키 부재)이지
  강제 수단이 아니다. 위에 적은 대로 훅은 gh CLI 인터페이스에만 의존하므로,
  Anthropic이 프롬프트를 바꾸거나 설정 키를 제공해도 훅을 고칠 필요는 없다.
  설정 키가 생기면 그때 훅이 중복인지 판단해 이 기록을 갱신한다
- 에이전트 전역 문서는 건드리지 않았다. PR과 무관한 세션이 영향받지 않는다
- 회귀 테스트 8건을 `shared/hooks/enforce-git-claw.test.sh`에 추가했다
  (차단 3건, 오탐 방지 5건). `bash shared/hooks/enforce-git-claw.test.sh`로 실행한다
