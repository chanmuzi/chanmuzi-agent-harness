# 2026-07 — 브라우저 자동화: dev-browser 제거, Aside 미채택

## 상태

확정 (2026-07-13). 이 하네스는 현재 **브라우저 자동화 도구를 제공하지 않는다.**

## 배경

`dev-browser` CLI가 `setup.sh`로 자동 설치되고 `check.sh`가 존재를 확인해 왔다.
Claude 쪽은 `Bash(dev-browser *)` 권한으로, Codex 쪽은 `sawyerhood/dev-browser` 외부 스킬로 노출됐다.

두 가지 문제가 겹쳤다.

- **실사용 0** — 기본 비활성 구조(프로젝트 `CLAUDE.md`에 활성화 문구를 넣어야 켜짐)였는데, 어떤 프로젝트도 그 문구를 넣지 않았다. 권한 항목만 잔재로 남아 있었다.
- **주 작업 환경에서 고장** — 실제 작업은 대부분 원격 리눅스 서버(aimp)에서 이뤄지는데, 그곳에서 dev-browser는 버전 불일치로 실행되지 않았다.

즉 되는 곳에선 안 쓰고, 쓰고 싶은 곳에선 안 됐다.

## 검토한 대안: Aside

[Aside](https://aside.com) 브라우저 에이전트를 대체재로 검토했고 **기각했다.**

기각 사유는 단 하나, **macOS 전용**이다. 설치 스크립트가 명시적으로 거부한다.

```sh
case "$(uname -s):$(uname -m)" in
  Darwin:arm64 | Darwin:aarch64) PLATFORM="darwin-arm64" ;;
  Darwin:x86_64)                 PLATFORM="darwin-x64" ;;
  *) echo "Aside CLI installer supports macOS arm64 and x64 only." >&2
```

배포된 바이너리도 `Aside CLI.app` 번들 안의 Mach-O arm64였다.
구조적으로도 맞지 않는다 — Aside는 헤드리스 엔진이 아니라 **로컬 맥에 떠 있는 Aside Browser GUI 앱에 붙는** 도구라, 원격 헤드리스 서버에는 붙을 브라우저 자체가 없다. 리눅스 빌드가 나오더라도 원격 용도로는 성격이 다르다.

주 작업 환경이 리눅스인 이상 채택해도 거의 못 쓴다.

참고로 장점은 분명했다. MCP 서버가 노출하는 툴이 **`repl` 단 하나(≈1.2k 토큰)**로, 툴 20여 개를 쏟아내는 Playwright MCP류보다 컨텍스트 비용이 훨씬 낮다. Playwright API가 통째로 든 영속 JS 샌드박스를 주는 설계다. **macOS 로컬 전용 작업이 주가 되는 상황이 오면 재검토할 가치가 있다.**

## 결정

`dev-browser`를 하네스에서 완전히 제거한다. 대체재는 두지 않는다.

- `setup.sh` — `install_dev_browser_cli()` 함수 및 호출부 제거
- `check.sh` — 존재 확인 블록 제거
- `claude/settings.json` — `Bash(dev-browser *)`, `Bash(npx dev-browser *)` 권한 제거
- `codex/external-skills.json` — `sawyerhood/dev-browser` 스킬 엔트리 제거
- `README.md` — 설치 안내 및 "프로젝트별 활성화" 섹션 제거
- `setup.sh` — 기존 설치분을 지우는 일회성 마이그레이션(`migrate_remove_dev_browser_skill`) 추가
- `check.sh` — 잔재 경고 추가

### 함정: 선언 제거만으로는 안 지워진다

`external-skills.json`에서 엔트리를 빼도 **이미 설치된 `~/.codex/skills/dev-browser`는 남는다.**
외부 스킬 설치 로직은 선언된 항목만 순회하며 설치·갱신할 뿐, MCP 서버와 달리 **미선언 항목을 프루닝하지 않기 때문**이다.

남은 `SKILL.md`는 Codex에게 브라우저 자동화 트리거를 계속 노출하고, 심지어 본문에 `npm install -g dev-browser`가 적혀 있어 **제거한 CLI를 되살리라고 안내한다.** 선언만 지웠다면 "브라우저 자동화 수단이 없다"는 이 결정이 기존 설치 환경에서 거짓이 됐을 것이다.

그래서 `setup.sh`에 일회성 마이그레이션을 넣었다. `.installed-ref` 존재 여부로 가드해 하네스가 설치한 것만 지우고, 사용자가 직접 만든 동명 스킬은 건드리지 않는다.

미선언 외부 스킬을 일반적으로 프루닝하는 로직(MCP 서버처럼)은 별도 설계 결정이라 이번 범위에서 제외했다.

## 결과 (중요)

**이 하네스에는 브라우저 자동화 수단이 없다.** 의도된 공백이다.

Claude·Codex 양쪽에서 동시에 제거했으므로 Agent Parity Policy 위반은 아니다.

향후 브라우저 자동화가 실제로 필요해지면, 판단 기준은 **어디서 돌릴 것인가**다.

- **원격 리눅스(aimp 등)** — Aside는 답이 아니다. 해당 서버에 Playwright를 직접 설치하는 별개 과제로 접근한다.
- **로컬 macOS 전용** — Aside 재검토. MCP는 프로젝트 스코프(`claude mcp add -s local`)로 붙여 팀에 의존성을 강요하지 않는다.

## 미해결 리스크 (Aside를 나중에 도입한다면)

Aside의 `repl` 툴은 `fs`(node:fs/promises)와 사용자 쿠키를 쓰는 `fetch`를 동시에 노출한다.
파일 접근을 툴 이름으로 거르는 가드 훅(예: ews-knowledge의 `guard_paths.py`가 `Write|Edit|Read|Glob|Grep`만 감시)은 **`repl` 경유 파일 접근을 잡지 못한다.**
민감 경로를 가진 레포에 도입하려면 가드 훅 matcher에 `mcp__aside__repl`을 반드시 추가해야 한다.

## 참고

레포의 `/aside` 슬래시 커맨드(`claude/commands/aside.md`)는 Aside 제품과 **무관하다.**
최초 커밋(`618a68b`)부터 있던 자작 커맨드로, "컨텍스트를 잃지 않고 곁가지 질문에 답한다"는 용도다. 이름만 우연히 같다.
