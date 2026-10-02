# 2026-10 — npm global prefix가 root 소유면 `~/.npm-global`로 전환한다

## 상태

채택 (2026-10-02)

## 맥락

공용 GPU 서버(Ubuntu 20.04, apt로 설치한 Node)에서 `./setup.sh`가 안내하는
`npm install -g @anthropic-ai/claude-code`가 다음 오류로 실패했다:

```
npm error code EACCES
npm error path /usr/lib/node_modules/@anthropic-ai
```

시스템 Node의 npm global prefix는 `/usr`이고 `/usr/lib/node_modules`는 `root:root 755`다.
일반 계정은 쓸 수 없고 `sudo`도 보통 없다. 그래서 `claude`가 설치되지 않았고,
`ccud`/`ccu`는 `claude: command not found`로 끝났다.

## 결정

- `shared/lib/npm.sh`의 `ensure_npm_user_prefix`를 `setup.sh`가 매번 실행한다.
  - 현재 prefix의 `lib/node_modules`(없으면 가장 가까운 상위 디렉토리)에 쓰기 권한이 있으면
    아무것도 바꾸지 않는다. macOS Homebrew, nvm, 이미 설정된 user prefix가 여기에 해당한다.
  - 쓰기 권한이 없을 때만 `npm config set prefix ~/.npm-global`(→ `~/.npmrc`)을 실행한다.
- `shared/shell/init.sh`가 `~/.npm-global/bin`이 있으면 PATH 앞에 추가한다.
  rc 파일에 직접 줄을 추가하지 않으므로, harness 블록 하나로 관리된다.
- `_cc_run`(`cc`/`ccu`/`ccd`/`ccud`)은 `claude` 바이너리가 없으면 설치 안내를 출력하고
  127로 종료한다. `claude()` 래퍼 함수가 이름을 가리므로 함수를 unset한 서브셸에서 확인한다.
- `check.sh`는 npm global prefix에 쓰기 권한이 없으면 경고한다.

## 고려한 대안

- **`sudo npm install -g`** — 공용 서버에서 대부분 불가능하다. 가능해도 root 소유 파일이
  남아 이후 자동 업데이트가 같은 EACCES로 실패한다.
- **Claude Code 네이티브 설치(`curl ... | bash`)만 안내** — Claude는 해결되지만 Codex,
  oh-my-codex는 여전히 npm이 필요하다. 한 가지 방식으로 세 CLI를 모두 덮기 위해 npm prefix를 고친다.
- **CLI 자동 설치** — 계정 로그인이 따로 필요하고 설치 시점을 사용자가 정해야 하므로
  이번 범위에서 제외했다. `setup.sh`는 계속 설치 명령을 안내만 한다.

## 결과

- 쓰기 권한이 없는 머신에서 `./setup.sh` 한 번이면 이후 `npm install -g`가 root 없이 동작하고,
  새 셸에서 `claude`, `codex`, `ccud`가 바로 잡힌다.
- `~/.npmrc`의 `prefix`는 nvm과 충돌한다(nvm이 경고를 띄운다). 쓰기 권한이 있는 prefix에서는
  설정하지 않으므로 nvm 사용 머신은 영향이 없지만, 홈 디렉토리를 여러 머신이 공유하고 그중
  일부가 nvm을 쓰면 `~/.npmrc`의 `prefix`를 직접 지워야 한다.
