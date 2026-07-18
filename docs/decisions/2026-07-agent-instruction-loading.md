# 2026-07 — 프로젝트 문서 체계: AGENTS.md 정본 + CLAUDE.md adapter

## 상태

확정 (2026-07-18). 이 저장소의 프로젝트 문서 정본은 **루트 `AGENTS.md` 하나**이며,
루트 `CLAUDE.md`는 `@AGENTS.md` 한 줄 adapter다. `templates/`의 쌍도 같은 구조를 따른다.

## 배경

기존 체계는 `shared/project-doc.md`를 정본으로 두고 `shared/render_project_docs.py`가
루트 `CLAUDE.md`와 `AGENTS.md` 두 벌을 통째로 복제 생성했으며, `check.sh`가 동기화를 검증했다.

동작에는 문제가 없었지만 구조적 비용이 있었다.

- 정본이 루트가 아닌 `shared/` 안에 숨어 있어, 에이전트와 사람 모두 "루트 문서를 직접 고치면 안 된다"는
  규칙을 별도로 알아야 했다
- 같은 내용의 파일이 저장소에 세 벌(소스 + 복제 2) 존재했다
- 렌더러·동기화 검증이라는 유지 대상이 늘 따라다녔다

EWS의 에이전트 지침 로딩 가이드(Codex/Claude 계층 로딩 규칙 비교, 2026-07-15 기준)를 검토한 결과,
복제 없이 같은 효과를 얻는 표준 패턴이 확인됐다:

- **Codex**는 프로세스 시작 시 Git 루트→cwd 체인으로 `AGENTS.md`를 자동 로드한다
- **Claude Code**는 시작 위치의 `CLAUDE.md`를 읽고, `@AGENTS.md` import를 확장한다
- 따라서 `AGENTS.md`를 정본으로 두고 `CLAUDE.md`를 한 줄 adapter로 만들면
  두 에이전트가 같은 규칙을 한 벌의 파일에서 받는다

관련 사례: 별도 저장소(git-claw)는 반대 방향의 symlink(`AGENTS.md → CLAUDE.md`)를 쓰고
있었고, 그 결과 Codex가 `# CLAUDE.md` 제목의 문서를 읽는 상태였다. 이 기록의 최초 버전은
이를 손 복제 drift로 오인했으나, 확인 결과 symlink였다 (git mode 120000). symlink 방식의
문제는 아래 '검토한 대안'의 기각 사유와 같으며, git-claw도 adapter 체계로 전환하는 별도 PR을 진행 중이다 (chanmuzi/git-claw#47).

## 결정

1. **루트 `AGENTS.md`가 유일한 프로젝트 문서 정본(SSoT)** — 직접 손으로 편집한다
2. **루트 `CLAUDE.md`는 첫 줄이 정확히 `@AGENTS.md`인 adapter** — 공유 내용을 복제하지 않는다.
   Claude 전용 프로젝트 규칙이 필요해지면 import 줄 아래에 추가한다
3. `shared/project-doc.md`와 `shared/render_project_docs.py`는 **삭제** — 렌더링 체계 폐기
4. `check.sh`의 동기화 검증은 **adapter 검증으로 교체** — 정본 존재 + adapter 첫 줄 확인
5. `templates/` 쌍도 같은 구조로 전환 — `templates/AGENTS.md`(정본) + `templates/CLAUDE.md`(adapter)
6. **세션은 저장소 루트에서 시작**하는 것을 원칙으로 한다. 디렉토리별 하위 문서와
   `AGENTS.override.md`는 이 저장소에서 사용하지 않는다

## 검토한 대안

- **기존 렌더러 체계 유지** — 동작은 했지만 위 구조적 비용이 상수로 남는다. adapter가 같은 보장을
  파일 한 벌로 제공하므로 기각
- **symlink (`CLAUDE.md → AGENTS.md`)** — Windows에서 관리자 권한/Developer Mode가 필요하고,
  `core.symlinks=false` 환경에서는 경로 문자열만 담긴 일반 파일로 checkout 된다.
  Claude 전용 내용을 덧붙일 수도 없다. EWS 가이드도 같은 이유로 기각했다

## 주의사항 (버전 종속 관찰)

EWS 가이드의 최소 재현(Claude Code 2.1.209)에서, **하위 디렉토리에서 세션을 시작**하면 상위
`CLAUDE.md` 자체는 보이지만 상위 `@AGENTS.md` include가 확장되지 않는 관찰이 있었다.
공식 계약이 아닌 특정 버전 관찰이므로 계약으로 취급하지 않되, 이 저장소는 어차피
"루트에서 시작" 원칙(결정 6)으로 해당 경로를 회피한다. 하위 시작을 위한 우회 문구를
하위 파일에 복제하는 방식은 채택하지 않는다.

## 영향

- 프로젝트 규칙 변경 절차가 "AGENTS.md 하나만 편집"으로 단순해진다
- `check.sh`의 `project docs` 검증 메시지가 동기화 확인에서 adapter 확인으로 바뀐다
- 글로벌 문서(`claude/CLAUDE.md`, `codex/AGENTS.md`)는 이 결정의 대상이 아니다 —
  Agent Parity Policy에 따라 의도적 차이가 허용되는 영역으로 남는다
- git-claw 저장소도 같은 체계로 전환한다 (별도 PR)

## 근거 자료

- EWS Agent Instruction Hierarchy 가이드 (내부 HTML, 2026-07-15):
  Codex startup chain / Claude lazy discovery / adapter vs symlink 비교
- Codex 공식: AGENTS.md 탐색 순서, override 우선순위, root→cwd 병합
- Claude Code 공식: CLAUDE.md 상향 탐색, 하위 지연 로드, `@` import
