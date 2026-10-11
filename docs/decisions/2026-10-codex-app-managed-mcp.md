# 2026-10 — Codex 앱이 관리하는 MCP 서버는 정리 대상에서 제외한다

## 상태

채택 (2026-10-11)

## 맥락

`setup.sh`의 `sync_codex_mcp_servers`는 `codex/mcp-servers.json`에 선언되지 않은
`[mcp_servers.*]` 섹션을 `~/.codex/config.toml`에서 모두 지운다. 하네스가 넣지 않은 MCP 서버가
쌓이는 것을 막기 위한 규칙이다.

그런데 Codex 데스크톱 앱(ChatGPT.app)이 같은 파일에 직접 써넣는 서버가 있다:

- `node_repl`(+ `node_repl.env`): 번들 플러그인 `browser@openai-bundled`와
  `chrome@openai-bundled`의 훅(Stop, SubagentStop, Interrupt)이 이 이름의 서버를 호출한다.
  두 플러그인은 서버를 직접 정의하지 않고, 앱이 `config.toml`에 써 둔 정의에 의존한다.
- `computer-use`: 앱이 `enabled = false`로 써 두는 항목이다.

로컬 macOS에서 `./setup.sh`를 실행하자 이 섹션들이 "unmanaged"로 지워졌고,
`CODEX_HOME=~/.codex codex mcp list`에서 `node_repl`이 사라졌다. 지워지기 직전 블록에 적힌
앱 버전이 설치된 앱 버전과 같았으므로 앱이 이 블록을 주기적으로 다시 쓰는 것으로 보이지만,
그 시점(앱 재시작인지 업데이트인지)은 확인하지 못했다. 그 사이에는 브라우저·Chrome 제어가
서버 없이 남는다.

## 결정

- `codex/mcp-app-managed.json`에 앱이 관리하는 서버 이름을 나열한다(현재 `node_repl`,
  `computer-use`).
- `setup.sh`는 이 목록의 서버와 그 하위 테이블(`<name>.env` 등)을 지우지 않는다.
- `check.sh`는 이 목록의 서버를 "선언되지 않은 MCP 서버" 경고에서 제외한다.
- 그 밖의 선언되지 않은 `mcp_servers.*`는 지금처럼 정리한다.

## 고려한 대안

- **정리 로직 자체를 없앤다**: 앱 서버는 보존되지만, 다른 도구가 넣은 MCP 서버가 조용히
  쌓이는 원래 문제가 돌아온다.
- **`codex/mcp-servers.json`에 앱 서버를 선언한다**: 이 파일은 하네스가 등록·검증하는
  `streamable_http` 서버 스키마다. 앱 서버는 stdio이고 경로·버전·해시를 앱이 갱신하므로
  하네스가 값을 소유할 수 없다.
- **앱이 다시 써 주기를 기다린다**: 복구 시점이 보장되지 않고, `setup.sh`를 돌릴 때마다 같은
  공백이 반복된다.

## 결과

- 앱이 새 서버 이름을 추가하면 `setup.sh`가 다시 지우고 `check.sh`가 경고한다. 그때는
  이 목록에 이름을 추가한다.
- 목록의 값은 이름뿐이다. 서버의 명령·환경 변수는 앱이 소유하며 하네스는 읽지도 쓰지도 않는다.
- Orca 계정 셸은 별도 `CODEX_HOME`을 쓰므로 이 정리 로직의 영향을 받지 않는다
  (`2026-08-codex-skills-home.md` 참고).
