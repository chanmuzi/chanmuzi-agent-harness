# Codex 스킬 경로의 CODEX_HOME 추종

## 상태

채택 (2026-08)

## 맥락

`setup.sh`/`check.sh`는 Codex 스킬 상태(존재 확인, `.installed-ref` 기록,
업데이트 시 `rm -rf`, context7 symlink)를 `CODEX_DIR="$HOME/.codex"` 아래
`skills/`에서 관리해 왔다. 그러나 실제 설치를 수행하는 codex의 skill-installer
(`install-skill-from-github.py`)는 목적지를
`os.environ.get("CODEX_HOME", "~/.codex")`로 해석한다.

Orca(ADE)는 codex 계정 셸에 `CODEX_HOME`을 계정 홈
(`~/Library/Application Support/orca/codex-accounts/<uuid>/home` 등)으로
지정하므로, Orca 터미널에서 `./setup.sh`를 실행하면 split-brain이 생긴다:

- 상태 추적은 `~/.codex/skills`에서, 실제 설치는 `$CODEX_HOME/skills`에서
  일어난다.
- 이미 설치된 스킬이 `~/.codex/skills`에 없으면 매번 "installing"을 시도하고
  installer의 `Destination already exists` 오류로 끝난다.
- `~/.codex/skills`에 잔존 사본이 있으면 "updating" 경로가 그 사본을
  `rm -rf`로 지우고, 설치는 다른 곳에 되며, `.installed-ref` 기록은
  `No such file or directory`로 실패한다.

## 결정

스킬 관련 경로만 installer와 동일한 해석을 따르게 한다:

- `setup.sh`/`check.sh`에 `CODEX_SKILLS_DIR="${CODEX_HOME:-$CODEX_DIR}/skills"`
  를 도입하고, 스킬 설치·업데이트·검증·symlink·dev-browser 마이그레이션 등
  모든 스킬 경로 참조를 이 변수로 통일한다.
- 스킬이 아닌 관리 대상(`config.toml` 패치, hooks, `AGENTS.md` 등)은 기존대로
  `~/.codex`를 유지한다.

`CODEX_HOME`이 없는 환경(일반 셸, Linux 원격)에서는 값이 `~/.codex/skills`로
동일하므로 동작 변화가 없다.

## 검토한 대안

- **`CODEX_DIR` 자체를 `${CODEX_HOME:-$HOME/.codex}`로 변경**: config 패치와
  symlink까지 Orca 계정 홈을 대상으로 하게 되어 영향 범위가 스킬 설치 오류보다
  훨씬 넓다. Orca 계정 홈의 config를 harness가 관리해야 하는지는 별도 결정이
  필요해 기각(필요해지면 이 기록을 대체하는 새 기록으로 다룬다).
- **Orca 터미널에서 setup.sh 실행 금지 안내**: 실수 방지가 안 되고, Orca
  환경의 codex 계정에 스킬을 정상 설치하는 경로 자체를 잃는다. 기각.

## 결과

- Orca 터미널에서 실행해도 스킬의 존재 확인·설치·ref 기록·삭제가 전부 codex가
  실제로 읽는 디렉토리에서 일어난다. 반복되던
  `Destination already exists` / `.installed-ref: No such file or directory`
  경고가 사라진다.
- 기존에 orca 계정 홈에 ref 없이 설치돼 있던 스킬은 다음 실행에서
  "updating (no ref tracked)" 경로로 한 번 재설치되며 ref가 채워진다.
- 한계: `CODEX_HOME`이 설정된 셸과 아닌 셸에서 번갈아 실행하면 각 홈에 별도
  사본이 유지된다(각자 자기 홈 기준으로는 일관됨). 과거 split-brain이 남긴
  `~/.codex/skills`의 잔존 사본은 이 수정이 정리해 주지 않으므로 수동 삭제
  대상이다.
