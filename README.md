# chanmuzi-agent-harness

Claude Code와 Codex CLI 설정을 여러 머신에서 동기화하기 위한 통합 harness.

## 포함된 파일

| 경로 | 용도 |
|------|------|
| `shared/lib/os.sh` | 크로스플랫폼 헬퍼 (sed, readlink, sound) |
| `shared/shell/init.sh` | 쉘 함수 (`claude`, `codex`, `codex-safe` 등) |
| `shared/hooks/` | 공용 hooks (block-no-verify, play-sound) |
| `claude/CLAUDE.md` | Claude Code 글로벌 지시사항 |
| `claude/settings.json` | 권한, hooks, 플러그인 설정 |
| `claude/statusline.sh` | 커스텀 상태바 |
| `claude/hooks/` | Claude 전용 hooks |
| `claude/commands/` | 커스텀 slash commands |
| `codex/AGENTS.md` | Codex 글로벌 지시사항 |
| `codex/profile.toml` | 관리형 프로필 (`[profiles.harness]`) |
| `codex/hooks.json` | Codex hook 설정 |
| `codex/hooks/` | Codex 전용 hooks |
| `codex/skills.txt` | 자동 설치할 Codex skills 목록 |
| `codex/external-skills.json` | 외부 skill repo 설치 목록 |
| `templates/AGENTS.md` | 프로젝트별 AGENTS.md 템플릿 |

`context7`는 curated skill로 설치하지 않고 `~/.agents/skills/context7`를
`~/.codex/skills/context7`에 심링크하는 방식으로 관리합니다.
새 머신에서는 이 디렉터리가 비어 있을 수 있으므로, `setup.sh`에서
`context7 not found in ~/.agents/skills/context7` 경고가 나올 수 있습니다.
이 경고는 `context7`만 빠졌다는 뜻이며 다른 설정은 계속 진행됩니다.

`dev-browser`는 Claude/Codex 공용 브라우저 자동화 도구로 취급합니다.
`setup.sh`는 `npm install -g dev-browser`와 `dev-browser install`을 실행하고,
Claude에는 실행 권한을, Codex에는 외부 skill 설치를 맞춰둡니다.

단, **Claude Code에서는 실행 권한만 전역 등록**되며 자동으로 사용하지 않습니다.
프로젝트에서 dev-browser를 활용하려면 프로젝트별 CLAUDE.md에 안내를 추가해야 합니다.
Codex는 SKILL.md가 자동 디스커버리되므로 별도 설정 없이 바로 사용 가능합니다.

## 새 머신에 세팅하기

### 1. 사전 요구사항

```bash
# Node.js (>= 18)
node --version

# Claude Code CLI
npm install -g @anthropic-ai/claude-code

# Codex CLI
npm install -g @openai/codex

# jq (hooks에서 사용)
brew install jq        # macOS
sudo apt install jq    # Ubuntu/Debian
```

`dev-browser`는 별도 수동 설치가 필요 없습니다. `./setup.sh`가 자동으로 설치/업데이트합니다.

### 2. 설치

```bash
git clone git@github.com:chanmuzi/chanmuzi-agent-harness.git ~/chanmuzi-agent-harness
cd ~/chanmuzi-agent-harness
chmod +x setup.sh check.sh
./setup.sh
```

> **클론 경로는 자유입니다.** `setup.sh`가 실행 시 현재 repo 경로를 자동 감지하여
> `CHANMUZI_AGENT_HARNESS_HOME` 환경변수를 쉘 RC에 등록합니다.
> Claude/Codex hooks는 이 환경변수를 통해 `shared/lib/os.sh` 등 공용 헬퍼를 찾으므로,
> 설치 후 **쉘을 재시작**하거나 `source ~/.zshrc` (또는 `~/.bashrc`)를 실행하세요.

### 3. 선택적 설치

```bash
./setup.sh --claude    # Claude Code만
./setup.sh --codex     # Codex CLI만
./setup.sh --install-omx  # oh-my-codex CLI만 전역 설치
./setup.sh             # 둘 다 (기본)
```

### 3-1. oh-my-codex 정책

`oh-my-codex`는 전역 CLI로 설치만 해두는 것은 괜찮습니다.
하지만 `omx setup`이 실제 설정 파일을 쓰기 시작하면 이 harness가 관리하는
전역 `~/.codex`와 충돌할 수 있습니다.

이 저장소의 기본 원칙:

- 전역 `~/.codex`는 이 harness가 관리
- `oh-my-codex`는 필요할 때만 개별 프로젝트에서 사용
- `omx setup --scope user`는 사용하지 않음
- `omx setup --scope project`만 사용

전역 설치:

```bash
./setup.sh --install-omx
```

프로젝트별 적용:

```bash
cd /path/to/project
omx setup --scope project
```

사전 점검:

```bash
cd /path/to/project
omx setup --scope project --dry-run
```

### 3-2. context7 복구

`context7`를 실제로 사용한다면 새 머신에서 별도로 채워줘야 합니다.
이 harness는 `~/.agents/skills/context7`를 `~/.codex/skills/context7`에
심링크만 하며, 원본 스킬 자체를 자동 다운로드하지는 않습니다.

가장 간단한 방법은 기존에 잘 쓰고 있는 다른 머신에서 `SKILL.md`를 복사하는 것입니다.

```bash
mkdir -p ~/.agents/skills/context7
```

다른 머신에서 현재 머신으로 복사:

```bash
scp ~/.agents/skills/context7/SKILL.md \
  <user>@<host>:~/.agents/skills/context7/SKILL.md
```

복사 후 다시 실행:

```bash
./setup.sh --codex
./check.sh
```

확인 포인트:

- `~/.agents/skills/context7/SKILL.md`가 존재해야 합니다.
- `~/.codex/skills/context7`는 `setup.sh`가 만든 심링크여야 합니다.
- `setup.sh`에서 `context7` 경고가 사라져야 합니다.

### 4. 검증

```bash
./check.sh
```

`check.sh`는 전역 `~/.codex`에 `oh-my-codex` user-scope 설정 흔적이 있으면
경고를 출력합니다. 이 경우 전역 설정 공존이 아니라 충돌 가능성으로 봐야 합니다.
또한 `dev-browser` CLI가 없으면 경고를 출력합니다.

### 4-1. dev-browser 확인

```bash
dev-browser --help
```

확인 포인트:

- Claude Code에서는 `Bash(dev-browser *)` 권한이 이미 등록되어 있어야 합니다.
- Codex에서는 `~/.codex/skills/dev-browser`가 설치되어 있어야 합니다.
- `dev-browser --help` 출력에 LLM usage guide와 API 레퍼런스가 포함되어 있어야 합니다.

간단한 사용 예시:

```bash
dev-browser --headless
# 또는 Claude/Codex에 "use dev-browser"라고 지시
```

### 4-2. dev-browser 프로젝트별 활성화

dev-browser는 **기본 비활성** 상태입니다.
실행 권한은 전역으로 등록되어 있지만, 에이전트가 자발적으로 사용하지는 않습니다.
프로젝트에서 브라우저 자동화가 필요할 때 아래처럼 활성화합니다.

**Claude Code** — 프로젝트 루트 `CLAUDE.md`에 추가:

```markdown
## Browser Automation
브라우저 자동화가 필요하면 `dev-browser` CLI를 사용하라.
사용법: `dev-browser --help` 참고.
```

**Codex CLI** — 별도 설정 불필요 (SKILL.md 자동 디스커버리)

## 쉘 명령어

### Claude Code

| 명령어 | 설명 |
|--------|------|
| `claude` | 권한 스킵 (hooks가 안전장치) |
| `claude-safe` | 기본 권한 모드 |
| `claude-team [name]` | tmux 세션에서 실행 |
| `claude-team-safe [name]` | tmux + 기본 권한 |

### Codex CLI

| 명령어 | 설명 |
|--------|------|
| `codex` | 승인/샌드박스 바이패스 (hooks가 안전장치) |
| `codex-safe` | 승인 있음 + 샌드박스 (`-a on-request -s workspace-write`) |

`./setup.sh --codex`는 현재 harness 저장소 경로를 `~/.codex/config.toml`의
`[projects."<repo path>"]`에 `trust_level = "trusted"`로 등록합니다.
이 trust 설정은 approval/sandbox 옵션과 별개입니다.

### oh-my-codex

| 명령어 | 설명 |
|--------|------|
| `./setup.sh --install-omx` | `oh-my-codex` CLI만 전역 설치/업데이트 |
| `omx setup --scope project` | 현재 프로젝트에만 OMX 적용 |
| `omx setup --scope project --dry-run` | 실제 쓰기 전 프로젝트 적용 범위 확인 |

`oh-my-codex`는 Codex 전용 워크플로우 레이어입니다.
Claude Code 설정에는 적용되지 않습니다.

## 업데이트

```bash
cd ~/chanmuzi-agent-harness
git pull
./setup.sh
```

## 설정 관리 방식

| 도구 | 방식 | 이유 |
|------|------|------|
| Claude Code | 심링크 (전체 교체) | `settings.json`이 100% 공통 설정 |
| Codex CLI | 심링크 + config.toml patch | `config.toml`에 머신별 설정(projects, MCP)이 섞여 있음 |

Codex의 `config.toml`에서 harness가 관리하는 영역은 `[profiles.harness]` 블록과
현재 harness 저장소의 `projects."<repo path>".trust_level` 엔트리뿐이며,
다른 `projects.*`, `mcp_servers.*`, `plugins.*`는 건드리지 않습니다.

`oh-my-codex`를 함께 사용할 때도 이 원칙은 유지합니다.
따라서 OMX는 전역 `user` scope가 아니라 프로젝트 로컬 `project` scope로만 사용하는 것을 권장합니다.

## 실제 적용 테스트

전역 CLI 설치 확인:

```bash
./setup.sh --install-omx
omx --version
./check.sh
```

기대 결과:

- `omx --version`이 출력됩니다.
- `./check.sh`에서 전역 `~/.codex` 관련 오류가 없어야 합니다.
- 전역 OMX 흔적 경고가 없어야 합니다.

프로젝트 단위 안전 테스트:

```bash
cd /path/to/scratch-project
omx setup --scope project --dry-run
omx setup --scope project
```

확인 포인트:

- 프로젝트 루트에 `./.codex/`가 생깁니다.
- 프로젝트 루트에 `./.omx/`가 생깁니다.
- 전역 `~/.codex/AGENTS.md`와 `~/.codex/hooks.json`은 그대로 유지됩니다.
- 이 harness 저장소에서 `./check.sh`를 다시 돌렸을 때 전역 설정 drift가 없어야 합니다.

피해야 할 테스트:

```bash
omx setup --scope user
```

이 명령은 전역 `~/.codex`를 건드리므로 이 harness와 충돌할 수 있습니다.
